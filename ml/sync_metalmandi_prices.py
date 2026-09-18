"""
KabadiConnect - live scrap price sync from metalmandi.in.

Fetches area-wise scrap rates from MetalMandi's site (an undocumented,
internal proxy API their Next.js frontend calls -- see the module docstring
caveat below) and writes them into Firestore's `live_scrap_prices`
collection, one document per (service location, material category). The
app reads that collection with a real-time Firestore listener, so prices
update live without an app release; assets/ml/price_table.json remains the
offline/fallback baseline and is untouched by this script.

Run on a schedule by .github/workflows/sync-metalmandi-prices.yml (GitHub
Actions cron), authenticating as a dedicated Firebase Auth "price bot"
account (provisioned once via provision_price_bot.py) so Firestore's
security rules can allow this specific account to write while everyone
else gets read-only access.

IMPORTANT CAVEAT: `/api/crm-proxy?path=...` is not a documented public API
-- it's MetalMandi's own frontend calling their backend, reachable
directly. It works today (verified 2026-09-19) but could change or be
blocked without notice, and reusing a third party's proprietary pricing
data like this may run against their site's terms of service. Treat this
as a best-effort integration, not a guaranteed data source.
"""
import json
import os
import sys
from datetime import datetime, timezone

import requests

METALMANDI_BASE = "https://www.metalmandi.in/api/crm-proxy"

FIREBASE_API_KEY = os.environ.get("FIREBASE_API_KEY", "AIzaSyDCeXojMVR3z4FaS0MB0mjjFFoKSSITrlQ")
FIREBASE_PROJECT_ID = "kabadiconnect"
PRICEBOT_EMAIL = os.environ.get("PRICEBOT_EMAIL")
PRICEBOT_PASSWORD = os.environ.get("PRICEBOT_PASSWORD")

# service location (as used throughout the app, see app/lib/core/constants.dart
# serviceLocations) -> MetalMandi's district-level cityId. Pimpri-Chinchwad and
# Pune share a district in MetalMandi's data, so they share a cityId; MetalMandi
# still calls the renamed city "Aurangabad" (its pre-2023 name).
CITY_IDS = {
    "Pune": 533,
    "Pimpri-Chinchwad": 533,
    "Mumbai": 446,
    "Nagpur": 460,
    "Nashik": 473,
    "Chhatrapati Sambhajinagar": 36,
}

# our MaterialCategory key -> (MetalMandi top-level category name, optional
# list of specific subcategory names to average; None = average every
# subcategory under that category). MIXED_PLASTICS has no reasonable match
# on MetalMandi (it's a metal-scrap-focused site) and is intentionally
# left out -- the app keeps using its static/offline price for that one.
CATEGORY_MAP = {
    "CRT": ("Display", ["CRT TV"]),
    "LCD_LED": ("Display", ["LCD", "LED"]),
    "PCB": ("PCB", None),
    "CABLES": ("Wire", None),
    "BATTERIES": ("Li-ion Battery", None),
    "MOTORS_MAGNETS": ("Magnet", None),
    "MIXED_OTHER": ("E-waste", None),
}


def fetch_pricing(city_id: int) -> dict:
    """category_name -> {subcategory_name: rate_per_kg}."""
    res = requests.get(f"{METALMANDI_BASE}?path=/pricing?cityId={city_id}", timeout=15)
    res.raise_for_status()
    body = res.json()
    by_category: dict[str, dict[str, float]] = {}
    for cat in body["data"]["dashboardMaterialPricing"]:
        rates = {}
        for sub in cat["subcategories"]:
            rate = sub.get("has_only_high_price_in_kgs")
            if rate:
                rates[sub["subcategory_name"]] = float(rate)
        by_category[cat["category_name"]] = rates
    return by_category


def derive_rates(by_category: dict[str, dict[str, float]]) -> dict[str, tuple[float, int]]:
    """our category key -> (average_rate_per_kg, num_subcategories_averaged)."""
    out = {}
    for our_key, (mm_category, subcats) in CATEGORY_MAP.items():
        rates_by_sub = by_category.get(mm_category, {})
        if subcats is None:
            values = list(rates_by_sub.values())
        else:
            values = [rates_by_sub[s] for s in subcats if s in rates_by_sub]
        if values:
            out[our_key] = (sum(values) / len(values), len(values))
    return out


def sign_in() -> str:
    if not PRICEBOT_EMAIL or not PRICEBOT_PASSWORD:
        print("PRICEBOT_EMAIL / PRICEBOT_PASSWORD not set", file=sys.stderr)
        sys.exit(1)
    res = requests.post(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={FIREBASE_API_KEY}",
        json={"email": PRICEBOT_EMAIL, "password": PRICEBOT_PASSWORD, "returnSecureToken": True},
        timeout=15,
    )
    res.raise_for_status()
    return res.json()["idToken"]


def firestore_write(id_token: str, doc_id: str, fields: dict):
    url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/live_scrap_prices/{doc_id}"

    def wrap(v):
        if isinstance(v, str):
            return {"stringValue": v}
        if isinstance(v, bool):
            return {"booleanValue": v}
        if isinstance(v, (int, float)):
            return {"doubleValue": float(v)}
        raise TypeError(type(v))

    body = {"fields": {k: wrap(v) for k, v in fields.items()}}
    res = requests.patch(url, json=body, headers={"Authorization": f"Bearer {id_token}"}, timeout=15)
    res.raise_for_status()


def slugify(location: str) -> str:
    return location.replace(" ", "_").replace("-", "_")


def main():
    id_token = sign_in()
    now = datetime.now(timezone.utc).isoformat()

    fetched_by_city_id: dict[int, dict] = {}
    written = 0
    for location, city_id in CITY_IDS.items():
        if city_id not in fetched_by_city_id:
            print(f"fetching cityId={city_id} ...")
            fetched_by_city_id[city_id] = fetch_pricing(city_id)
        rates = derive_rates(fetched_by_city_id[city_id])
        for category, (rate, sample_size) in rates.items():
            doc_id = f"{slugify(location)}__{category}"
            mm_category = CATEGORY_MAP[category][0]
            firestore_write(
                id_token,
                doc_id,
                {
                    "location": location,
                    "category": category,
                    "rate_per_kg": round(rate, 2),
                    "source": "metalmandi.in",
                    "source_category": mm_category,
                    "sample_size": sample_size,
                    "fetched_at": now,
                },
            )
            written += 1
            print(f"  {location:28s} {category:16s} -> Rs.{rate:.0f}/kg (avg of {sample_size})")

    print(f"wrote {written} documents to live_scrap_prices")


if __name__ == "__main__":
    main()
