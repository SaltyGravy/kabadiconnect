"""
KabadiConnect - Seed dataset generator.

Generates the six structured datasets described in the problem brief:
materials, prices, recyclers, transactions, traceability, collectors.

IMPORTANT / HONESTY NOTE:
This is SYNTHETIC seed data for pipeline demonstration and app bootstrapping.
- Recycler names/registration numbers are FICTIONAL, modeled on the *format*
  of real CPCB/SPCB EPR-authorization records, not real facilities.
- Price ranges are grounded in publicly reported informal e-waste market
  price bands (copper, PCB, battery scrap etc. commonly cited in Indian
  e-waste sector reports) but are illustrative, not live market data.
- Collector profiles include TWO marked as `is_field_research: true` with
  placeholder fields the team MUST replace with real interview data before
  submission (see docs/dataset_documentation.md).
- Transactions/traceability are simulated to give the app and ML pipeline
  realistic-shaped data to run against.

Outputs CSVs to ../data/ and a combined seed.json (for Firestore emulator import).
"""
import csv
import json
import random
import uuid
from datetime import datetime, timedelta
from pathlib import Path

random.seed(42)

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
DATA_DIR.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# Reference domain data
# ---------------------------------------------------------------------------

CATEGORIES = {
    "CRT": {
        "sub_categories": ["CRT TV", "CRT Monitor"],
        "unit": "per piece",
        "price_range": (150, 450),
    },
    "LCD_LED": {
        "sub_categories": ["LCD Panel", "LED TV Panel", "Laptop Screen"],
        "unit": "per piece",
        "price_range": (100, 600),
    },
    "PCB": {
        "sub_categories": ["Mobile PCB", "Computer Motherboard", "TV/Appliance PCB"],
        "unit": "per kg",
        "price_range": (180, 950),
    },
    "CABLES": {
        "sub_categories": ["Copper Wire", "Mixed Cable", "USB/Data Cable"],
        "unit": "per kg",
        "price_range": (220, 520),
    },
    "BATTERIES": {
        "sub_categories": ["Li-ion (Mobile/Laptop)", "Lead-Acid", "Ni-Cd/Ni-MH"],
        "unit": "per kg",
        "price_range": (40, 180),
    },
    "MOTORS_MAGNETS": {
        "sub_categories": ["AC/DC Motor", "Speaker Magnet", "HDD Magnet Assembly"],
        "unit": "per kg",
        "price_range": (150, 400),
    },
    "MIXED_PLASTICS": {
        "sub_categories": ["ABS Casing", "Mixed E-plastic"],
        "unit": "per kg",
        "price_range": (12, 45),
    },
    "MIXED_OTHER": {
        "sub_categories": ["Mixed/Unsorted E-waste"],
        "unit": "per kg",
        "price_range": (20, 90),
    },
}

LOCATIONS = [
    {"name": "Pune", "state": "Maharashtra", "lat": 18.5204, "lng": 73.8567},
    {"name": "Mumbai", "state": "Maharashtra", "lat": 19.0760, "lng": 72.8777},
    {"name": "Nagpur", "state": "Maharashtra", "lat": 21.1458, "lng": 79.0882},
    {"name": "Nashik", "state": "Maharashtra", "lat": 19.9975, "lng": 73.7898},
    {"name": "Chhatrapati Sambhajinagar", "state": "Maharashtra", "lat": 19.8762, "lng": 75.3433},
    {"name": "Pimpri-Chinchwad", "state": "Maharashtra", "lat": 18.6298, "lng": 73.7997},
]

CONDITIONS = ["intact", "partially_damaged", "burnt/tampered", "mixed_lot"]
SOURCE_TYPES = ["household", "repair_shop", "office_itad", "street_collection", "small_industrial"]

RECYCLER_NAMES = [
    "GreenLoop E-Recyclers", "EcoReborn Waste Solutions", "Vidharbha Metal Recovery",
    "Sahyadri E-Waste Processors", "Nirmal Circuits Recovery", "Prakruti Recyclers Pvt Ltd",
    "Deccan Urban Mining Co.", "Suraksha E-Waste Handlers", "Bhoomi Green Recyclers",
    "Konkan Coast Recycling", "Vidyut Metal & Plastics Recovery", "Sanchay E-Waste Aggregators",
]


def rand_date(days_back=365):
    return datetime.now() - timedelta(days=random.randint(0, days_back))


def lot_id():
    return f"KC-{datetime.now().strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}"


def ref_number():
    return f"HR-{uuid.uuid4().hex[:8].upper()}"


# ---------------------------------------------------------------------------
# 1. Materials reference dataset (catalogue-level, not per-transaction)
# ---------------------------------------------------------------------------

def gen_materials():
    rows = []
    mid = 1
    for cat, info in CATEGORIES.items():
        for sub in info["sub_categories"]:
            for cond in CONDITIONS:
                low, high = info["price_range"]
                rows.append({
                    "material_id": f"MAT-{mid:04d}",
                    "material_category": cat,
                    "sub_category": sub,
                    "material_description": f"{sub} ({cond.replace('_', ' ')})",
                    "image_ref": f"assets/material_icons/{cat.lower()}.png",
                    "typical_weight_kg": round(random.uniform(0.2, 25.0), 2),
                    "condition": cond,
                    "source_type": random.choice(SOURCE_TYPES),
                    "estimated_value_per_unit": round(random.uniform(low, high), 2),
                    "unit": info["unit"],
                })
                mid += 1
    return rows


# ---------------------------------------------------------------------------
# 2. Price history dataset
# ---------------------------------------------------------------------------

def gen_prices(recyclers, months=9):
    rows = []
    pid = 1
    for cat, info in CATEGORIES.items():
        low, high = info["price_range"]
        base = random.uniform(low, high)
        for loc in LOCATIONS:
            trend = random.uniform(-0.15, 0.25)  # overall drift over the window
            price = base * random.uniform(0.85, 1.15)
            for week in range(months * 4):
                date = datetime.now() - timedelta(weeks=(months * 4 - week))
                drift = trend * (week / (months * 4))
                noise = random.uniform(-0.06, 0.06)
                buying_price = max(1.0, price * (1 + drift + noise))
                market_low = buying_price * random.uniform(0.85, 0.95)
                market_high = buying_price * random.uniform(1.05, 1.2)
                recycler = random.choice([r for r in recyclers if cat in r["materials_accepted"]] or recyclers)
                recycler_offer = buying_price * random.uniform(1.02, 1.15)  # formal channel premium
                rows.append({
                    "price_id": f"PRC-{pid:05d}",
                    "material_category": cat,
                    "sub_category": random.choice(info["sub_categories"]),
                    "location": loc["name"],
                    "state": loc["state"],
                    "date": date.strftime("%Y-%m-%d"),
                    "unit": info["unit"],
                    "informal_buying_price": round(buying_price, 2),
                    "market_range_low": round(market_low, 2),
                    "market_range_high": round(market_high, 2),
                    "recycler_offered_price": round(recycler_offer, 2),
                    "recycler_id": recycler["recycler_id"],
                })
                pid += 1
    return rows


# ---------------------------------------------------------------------------
# 3. Recycler / aggregator dataset
# ---------------------------------------------------------------------------

def gen_recyclers():
    rows = []
    for i, name in enumerate(RECYCLER_NAMES, start=1):
        loc = random.choice(LOCATIONS)
        accepted = random.sample(list(CATEGORIES.keys()), k=random.randint(3, len(CATEGORIES)))
        status = random.choices(["active", "active", "active", "pending_renewal", "expired"], weights=[6, 6, 6, 1, 1])[0]
        rows.append({
            "recycler_id": f"REC-{i:03d}",
            "name": name,
            "facility_location": f"{loc['name']}, {loc['state']}",
            "lat": loc["lat"] + random.uniform(-0.05, 0.05),
            "lng": loc["lng"] + random.uniform(-0.05, 0.05),
            "materials_accepted": accepted,
            "authorization_type": "CPCB EPR-Authorized Dismantler/Recycler",
            "registration_number": f"CPCB/EPR/{loc['state'][:2].upper()}/{2021+i%4}/{1000+i*17}",
            "authorization_status": status,
            # Clean E.164 format (no separators) so it matches Firebase Phone
            # Auth's normalized number when a recycler logs in.
            "contact_phone": f"+919{random.randint(100000000,999999999)}",
            "contact_email": f"contact@{name.lower().split()[0]}.example.in",
            # Set once a recycler logs in via phone auth and claims this
            # pre-registered facility -- see firestore.rules.
            "linked_auth_uid": None,
            "offered_rates": {
                cat: round(random.uniform(*CATEGORIES[cat]["price_range"]) * random.uniform(1.02, 1.12), 2)
                for cat in accepted
            },
            "pickup_available": random.random() > 0.3,
            "service_area_km": random.choice([15, 25, 40, 60]),
            "rating": round(random.uniform(3.4, 4.9), 1),
        })
    return rows


# ---------------------------------------------------------------------------
# 4 & 5. Transactions + Traceability
# ---------------------------------------------------------------------------

def gen_transactions_and_traceability(collectors, recyclers, n=220):
    tx_rows, trace_rows = [], []
    statuses_flow = ["created", "matched", "in_transit", "handed_over", "confirmed", "paid", "completed"]
    for i in range(n):
        cat = random.choice(list(CATEGORIES.keys()))
        info = CATEGORIES[cat]
        collector = random.choice(collectors)
        candidates = [r for r in recyclers if cat in r["materials_accepted"] and r["authorization_status"] == "active"]
        recycler = random.choice(candidates or recyclers)
        loc = random.choice(LOCATIONS)
        date = rand_date(240)
        weight = round(random.uniform(0.5, 40.0), 2)
        low, high = info["price_range"]
        unit_price = random.uniform(low, high)
        quoted = round(unit_price * weight * random.uniform(0.95, 1.05), 2)
        status = random.choices(statuses_flow, weights=[2, 3, 4, 5, 8, 8, 20])[0]
        final = round(quoted * random.uniform(0.9, 1.1), 2) if status in ("confirmed", "paid", "completed") else None
        # inject a handful of deliberate anomalies for the anomaly-detection feature to catch
        is_anomaly = random.random() < 0.04
        if is_anomaly and final:
            final = round(final * random.choice([0.35, 2.6]), 2)

        lid = lot_id()
        payment_status = "paid" if status in ("paid", "completed") else ("partial" if status == "confirmed" else "pending")

        tx_rows.append({
            "lot_id": lid,
            "collector_id": collector["collector_id"],
            "material_category": cat,
            "weight_kg": weight,
            "quoted_price": quoted,
            "final_price": final if final else "",
            "recycler_id": recycler["recycler_id"],
            "collection_location": f"{loc['name']}, {loc['state']}",
            "handover_location": f"{recycler['facility_location']}",
            "date_time": date.isoformat(timespec="seconds"),
            "payment_status": payment_status,
            "transaction_status": status,
            "is_flagged_anomaly": is_anomaly,
        })

        if status in ("handed_over", "confirmed", "paid", "completed"):
            trace_rows.append({
                "lot_id": lid,
                "photo_refs": [f"lots/{lid}/photo_1.jpg"],
                "weight_kg": weight,
                "timestamp": (date + timedelta(hours=random.randint(1, 48))).isoformat(timespec="seconds"),
                "gps_lat": loc["lat"] + random.uniform(-0.02, 0.02),
                "gps_lng": loc["lng"] + random.uniform(-0.02, 0.02),
                "handover_reference_number": ref_number(),
                "recycler_confirmation": status in ("confirmed", "paid", "completed"),
                "subsequent_status": status,
            })
    return tx_rows, trace_rows


# ---------------------------------------------------------------------------
# 6. Collector dataset (minimal profile; 2 marked as real field-research seats)
# ---------------------------------------------------------------------------

def gen_collectors():
    rows = [
        {
            "collector_id": "COL-001",
            "display_name": "Collector A (FIELD RESEARCH - REPLACE)",
            "phone_last4": "TODO",
            "preferred_language": "mr",
            "operating_location": "TODO: village/area, district",
            "years_active": "TODO",
            "typical_materials": "TODO e.g. cables, PCB, batteries",
            "is_field_research": True,
            "notes": "Placeholder — team must replace with real interview data from a working scrap collector before submission.",
        },
        {
            "collector_id": "COL-002",
            "display_name": "Collector B (FIELD RESEARCH - REPLACE)",
            "phone_last4": "TODO",
            "preferred_language": "hi",
            "operating_location": "TODO: village/area, district",
            "years_active": "TODO",
            "typical_materials": "TODO",
            "is_field_research": True,
            "notes": "Placeholder — team must replace with real interview data from a working scrap collector/aggregator before submission.",
        },
    ]
    first_names = ["Ramesh", "Sunita", "Iqbal", "Vithal", "Meena", "Ganesh", "Farida", "Anil", "Kavita", "Suresh"]
    for i in range(3, 23):
        loc = random.choice(LOCATIONS)
        rows.append({
            "collector_id": f"COL-{i:03d}",
            "display_name": f"{random.choice(first_names)} ({loc['name']})",
            "phone_last4": f"{random.randint(1000,9999)}",
            "preferred_language": random.choice(["mr", "hi", "en"]),
            "operating_location": loc["name"],
            "years_active": random.randint(1, 15),
            "typical_materials": ", ".join(random.sample(list(CATEGORIES.keys()), k=random.randint(1, 3))),
            "is_field_research": False,
            "notes": "",
        })
    return rows


# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------

def write_csv(rows, filename, fieldnames=None):
    path = DATA_DIR / filename
    fieldnames = fieldnames or list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            row = row.copy()
            for k, v in row.items():
                if isinstance(v, (list, dict)):
                    row[k] = json.dumps(v)
            writer.writerow(row)
    print(f"wrote {len(rows)} rows -> {path.relative_to(ROOT)}")


def main():
    collectors = gen_collectors()
    recyclers = gen_recyclers()
    materials = gen_materials()
    prices = gen_prices(recyclers)
    transactions, traceability = gen_transactions_and_traceability(collectors, recyclers)

    write_csv(materials, "materials_dataset.csv")
    write_csv(prices, "price_dataset.csv")
    write_csv(recyclers, "recyclers_dataset.csv")
    write_csv(transactions, "transactions_dataset.csv")
    write_csv(traceability, "traceability_dataset.csv")
    write_csv(collectors, "collectors_dataset.csv")

    seed = {
        "materials": materials,
        "prices": prices,
        "recyclers": recyclers,
        "transactions": transactions,
        "traceability": traceability,
        "collectors": collectors,
    }
    with open(DATA_DIR / "seed.json", "w", encoding="utf-8") as f:
        json.dump(seed, f, indent=2, default=str)
    print(f"wrote combined seed -> {(DATA_DIR / 'seed.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
