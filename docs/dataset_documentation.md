# KabadiConnect — Dataset Documentation

This project treats its six datasets as a live pipeline (generate → store →
validate → update → serve), not a static CSV dump. This document says, for
each dataset: where it comes from, how good it is, how big it is, its known
limitations, and where it lives at runtime.

## Where each dataset lives

| Dataset (brief's term) | Generator | Static file | Live store | Consumed by |
|---|---|---|---|---|
| Material | `ml/generate_datasets.py` | `data/materials_dataset.csv` | fields embedded per-document in Firestore `lots/{lotId}` | `Lot` model, Create-Lot screen |
| Price | `ml/generate_datasets.py`, distilled by `ml/train_price_model.py` | `data/price_dataset.csv` | Firestore `price_history/{id}`; on-device snapshot at `app/assets/ml/price_table.json` | `PricingService`, Price Board, valuation, anomaly detection |
| Recycler | `ml/generate_datasets.py` | `data/recyclers_dataset.csv` | Firestore `recyclers/{recyclerId}` | `RecyclerMatchingService`, matching screen, recycler profile |
| Transaction | `ml/generate_datasets.py` (seed) + app writes at runtime | `data/transactions_dataset.csv` | Firestore `lots/{lotId}` (transaction fields) | Earnings ledger, recycler inbox |
| Traceability | `ml/generate_datasets.py` (seed) + app writes at handover | `data/traceability_dataset.csv` | Firestore `traceability/{lotId}` | Lot detail (QR/reference), recycler confirmation |
| Collector | `ml/generate_datasets.py` (seed) + app writes at onboarding | `data/collectors_dataset.csv` | Firestore `collectors/{collectorId}` | Profile, earnings ledger |

**Generated → stored → validated → updated → used, concretely:**
1. `ml/generate_datasets.py` *generates* the six CSVs (+ combined `data/seed.json`) from
   modeled distributions, not scraped from a live source (see limitations below).
2. `SeedDataService` (`app/lib/core/services/seed_data_service.dart`) *stores* a
   trimmed copy of that seed into Firestore the first time the app runs against
   an empty backend — this is real application code, not a manual import script.
3. Firestore's schema-on-write plus the Dart model classes' `fromMap`/`toMap`
   (with explicit type casts and fallbacks) act as the *validation* layer today;
   see "Known gaps" below for what's missing (schema enforcement, deduplication).
4. The dataset is *updated* continuously by normal app use: every new lot,
   handover, confirmation, and payment is a write against the same collections
   the seed data lives in — there is no separate "production" dataset the app
   doesn't see.
5. It's *used* by: the Price Board and valuation (`PricingService`), recycler
   ranking (`RecyclerMatchingService`), anomaly flagging
   (`AnomalyDetectionService`), and the material image classifier
   (`ml/train_classifier.py` → `ClassifierService`).

## Per-dataset detail

### Material dataset
- **Source**: procedurally generated catalogue (8 categories × 2–3 sub-categories
  × 4 conditions = 80 rows) grounded in the brief's own material list.
- **Quality**: internally consistent, but `typical_weight_kg` and
  `estimated_value_per_unit` are modeled ranges, not measured items.
- **Size**: 80 catalogue rows; real per-lot material records grow unbounded as
  collectors create lots.
- **Limitation**: no real photographs behind any of it (see AI/ML dataset below).

### Price dataset
- **Source**: synthetic 9-month weekly time series per category × location,
  built with a trend + noise model, banded within illustrative min/max ranges
  loosely consistent with publicly discussed informal e-waste price ranges
  (e.g. copper-bearing cable scrap trading in the low-hundreds-of-rupees-per-kg
  range, PCB scrap considerably higher per kg than mixed plastics). **These are
  not scraped or live-sourced prices.**
- **Quality**: statistically well-formed (trained regression achieves R²=0.996,
  MAE≈₹11 on held-out rows — see `ml/artifacts/price_model_metrics.json`) *for
  its own synthetic generating process*. That number says the model learned the
  synthetic pattern; it says nothing about real-market accuracy.
- **Size**: 1,728 rows full history (`data/price_dataset.csv`); 480 rows bundled
  into the app (last 10 points per category×location, for fast first-run seed).
- **Limitation**: must be replaced by real recorded transaction prices as the
  platform operates — the schema and pipeline are ready for that swap
  (`train_price_model.py` re-run against `price_history` Firestore exports
  would retrain on real data with no code changes).

### Recycler dataset
- **Source**: 12 fictional facilities, modeled on the *format* of real CPCB/SPCB
  EPR-authorization records (registration-number pattern, authorization status
  values, service-area/pickup fields) — **names, registration numbers, and
  contact details are fabricated for this build**, not real facilities.
- **Quality**: internally consistent; authorization status distribution
  deliberately includes a couple of `pending_renewal`/`expired` rows so the
  "prefer authorized" ranking logic has something to actually filter out.
- **Size**: 12 rows.
- **Limitation**: before any pilot, this must be replaced with real recycler
  onboarding (verified against actual CPCB/SPCB EPR authorization records) —
  the recycler-side profile screen and matching logic are written against the
  same schema, so swapping in real vetted recyclers requires no code change.

### Transaction & Traceability datasets
- **Source**: synthetic transactions (220 generated, 60 bundled into the app
  seed) simulating the lot lifecycle, with a deliberate ~4% injected anomaly
  rate (final value 2.6× or 0.35× the expected band) so the anomaly detector
  has real positives to catch.
- **Quality/size**: internally consistent state machine (`created → matched →
  in_transit → handed_over → confirmed → paid → completed`), 220/182 rows.
- **Limitation**: entirely synthetic; real traceability records only start
  accumulating once collectors and recyclers actually use the app.

### Collector dataset
- **Source**: 22 rows total. **Two rows (`COL-001`, `COL-002`) are explicit
  placeholders** (`is_field_research: true`, fields marked `TODO`) that the team
  must replace with real interview data from the two working scrap
  collectors/aggregators the brief requires as field research — this was not
  performed as part of this build session (no ability to conduct in-person
  interviews in India from this environment). The remaining 20 rows are
  synthetic personas for demo volume.
- **Design choice**: deliberately minimal fields (no address, no ID documents)
  per the brief's "avoid unnecessary personal information" instruction.

### AI/ML training dataset (material image classifier)
- **Source**: `ml/generate_seed_images.py` procedurally draws 680 synthetic
  160×160 images (8 categories × 85 images) — shapes/colors/textures loosely
  evocative of each material category (green PCB-like traces, cylindrical
  battery-like bands, cable-like colored curves, etc.) — **not photographs**.
- **Quality**: the trained MobileNetV2-transfer-learning model reaches 85%
  validation accuracy (`ml/artifacts/classifier_metrics.json`) on this synthetic
  set. That number reflects the separability of the procedurally generated
  shapes, **not real-world photo classification accuracy**.
- **Size**: 680 images (70 train + 15 val per category).
- **Limitation — the most important one in this whole project**: this model has
  never seen a real piece of e-waste. It exists to prove the training →
  TFLite-export → on-device-inference pipeline works end-to-end (it does — see
  `app/assets/ml/classifier.tflite`, 2.4MB, running live via `tflite_flutter`
  on Android/iOS/desktop, with a labeled heuristic fallback on Flutter Web).
  Before relying on its suggestions, it must be retrained on real field photos,
  ideally captured by the two field-research collectors as part of their normal
  lot-creation flow (the app already stores every lot photo, so the retraining
  corpus grows automatically once real usage starts).

## Known gaps / next steps
- No schema validation layer beyond Dart's type casts (a Cloud Function or
  Firestore security-rule-based schema check would harden this).
- No deduplication/anomaly check on the *price* dataset itself (only on
  transaction final values) — a bad manual price entry would flow straight
  through today.
- Firestore security rules are wide open for the emulator demo (see
  `firebase/firestore.rules`) and must be scoped to authenticated
  collector/recycler identities before any real deployment.
