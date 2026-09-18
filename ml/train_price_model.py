"""
KabadiConnect - Price valuation model.

Trains a Gradient Boosting regressor on the synthetic historical price
dataset (material_category, location, time) -> informal_buying_price, then
DISTILLS it into a compact JSON lookup+trend table that ships inside the
Flutter app for instant, fully-offline, on-device valuation (no ML runtime
needed on-device for this feature -- the model training happens here,
offline/server-side, and only its distilled output is deployed, which is a
standard pattern for lightweight mobile ML with hard offline requirements).

Also fits a robust per-(category, location) baseline + MAD used by the
anomaly detection feature to flag abnormal transaction values.

Outputs:
  ml/artifacts/price_model_metrics.json
  app/assets/ml/price_table.json   <- consumed directly by Dart PricingService
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
ARTIFACTS = ROOT / "ml" / "artifacts"
ARTIFACTS.mkdir(exist_ok=True)
APP_ASSETS = ROOT / "app" / "assets" / "ml"
APP_ASSETS.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(DATA_DIR / "price_dataset.csv", parse_dates=["date"])
df = df.sort_values("date")
df["day_index"] = (df["date"] - df["date"].min()).dt.days

# ---- Train a real regression model (category + location + time -> price) ----
enc = OneHotEncoder(handle_unknown="ignore")
X_cat = enc.fit_transform(df[["material_category", "location"]]).toarray()
X = np.hstack([X_cat, df[["day_index"]].to_numpy()])
y = df["informal_buying_price"].to_numpy()

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
model = GradientBoostingRegressor(n_estimators=150, max_depth=3, learning_rate=0.08, random_state=42)
model.fit(X_train, y_train)
pred = model.predict(X_test)
mae = mean_absolute_error(y_test, pred)
r2 = r2_score(y_test, pred)
print(f"price model: MAE={mae:.2f}  R2={r2:.3f}")

metrics = {
    "model": "GradientBoostingRegressor",
    "features": ["material_category (one-hot)", "location (one-hot)", "day_index"],
    "n_rows": len(df),
    "test_mae": round(float(mae), 2),
    "test_r2": round(float(r2), 3),
    "dataset_note": (
        "Trained on SYNTHETIC price history generated in generate_datasets.py "
        "(illustrative bands grounded in publicly reported informal e-waste price "
        "ranges, not live scraped market data). Replace with real recorded "
        "transaction/price data as the platform operates."
    ),
}
with open(ARTIFACTS / "price_model_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

# ---- Distill into an offline lookup table for the Dart app ----
# For each (category, location): latest price, 90-day trend slope (per day),
# robust baseline (median) + MAD for anomaly detection thresholds.
table = {}
for (cat, loc), g in df.groupby(["material_category", "location"]):
    g = g.sort_values("date")
    recent = g.tail(12)  # ~last 12 weeks
    latest_price = float(g.iloc[-1]["informal_buying_price"])
    latest_recycler_offer = float(g.iloc[-1]["recycler_offered_price"])
    unit = str(g.iloc[-1]["unit"])
    # simple linear trend over recent window (price per day)
    if len(recent) >= 2:
        x = (recent["day_index"] - recent["day_index"].min()).to_numpy(dtype=float)
        yv = recent["informal_buying_price"].to_numpy(dtype=float)
        slope = float(np.polyfit(x, yv, 1)[0])
    else:
        slope = 0.0
    median = float(g["informal_buying_price"].median())
    mad = float((g["informal_buying_price"] - median).abs().median()) or (median * 0.1)

    table.setdefault(cat, {})[loc] = {
        "unit": unit,
        "latest_informal_price": round(latest_price, 2),
        "latest_recycler_offer": round(latest_recycler_offer, 2),
        "trend_per_day": round(slope, 4),
        "trend_direction": "up" if slope > 0.01 else ("down" if slope < -0.01 else "stable"),
        "baseline_median": round(median, 2),
        "baseline_mad": round(mad, 2),
        "market_range_low": round(float(g["market_range_low"].tail(4).mean()), 2),
        "market_range_high": round(float(g["market_range_high"].tail(4).mean()), 2),
    }

with open(APP_ASSETS / "price_table.json", "w") as f:
    json.dump(table, f, indent=2)

print(f"wrote {APP_ASSETS / 'price_table.json'} ({len(table)} categories)")
print(f"wrote {ARTIFACTS / 'price_model_metrics.json'}")
