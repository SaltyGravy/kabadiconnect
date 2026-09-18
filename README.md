# KabadiConnect

A vernacular, low-literacy, offline-tolerant mobile platform connecting informal
e-waste collectors in India to authorized recyclers — price transparency,
documented handovers, and a usable earnings ledger, without turning formal
recycling into a compliance burden for the collector.

Built against the SIH-style brief on informal e-waste collection under India's
E-Waste (Management) Rules, 2022 EPR framework.

## What's here

```
app/    Flutter app (collector + recycler roles, one codebase)
ml/     Python ML pipeline: image classifier + price valuation model
data/   Structured datasets (materials, prices, recyclers, transactions,
        traceability, collectors) as CSV + combined seed.json
firebase/  Local Emulator Suite config (Firestore/Auth/Storage rules)
docs/   Dataset documentation & unit-economics assessment
```

Read **`docs/dataset_documentation.md` first** — it's blunt about what's real
(a fully working app + pipeline + schema) versus what's a labeled synthetic
placeholder pending real field data (the ML training images, the recycler
directory, the price history, and 20 of the 22 collector profiles).

## Architecture in one paragraph

One Flutter app serves both collector and recycler roles (role chosen at
onboarding), backed by Firebase (Firestore + Storage + Auth), run here against
the **Local Emulator Suite** with a `demo-` project id so the whole stack runs
with zero real cloud credentials. Firestore's own offline persistence handles
the "core activities work offline, sync later" requirement for documents;
`LocalQueueService`/`StorageService` add an explicit local queue for the one
thing Firestore doesn't queue offline — photo uploads. Material classification
runs a real MobileNetV2-transfer-learning TFLite model on-device on
Android/iOS/desktop, falling back to a labeled heuristic on Flutter Web (which
can't run `dart:ffi`-based TFLite). Price valuation is a regression trained
offline in Python and shipped as a compact on-device lookup table for
instant, fully-offline estimates.

## Running the demo

Prerequisites: Flutter SDK, Node (for `firebase-tools`), Java (for the
Firestore emulator), Python 3.12 (for the ML pipeline, optional if you don't
need to retrain).

```bash
# 1. Start the local Firebase backend (Firestore + Auth + Storage emulators)
npm install -g firebase-tools   # once
cd firebase && firebase emulators:start --project demo-kabadiconnect

# 2. Run the app (this repo builds/runs on Flutter Web in this sandbox because
#    no Android SDK cmdline-tools / full Xcode are installed here; the same
#    Dart code targets Android normally once you `flutter run` on a real
#    device or emulator with the Android toolchain set up)
cd app
flutter pub get
flutter run -d chrome   # or: flutter run  (on a connected Android device)
```

The app self-seeds the emulator's Firestore with the datasets in `data/` on
first run (see `SeedDataService`) — no manual import step.

To retrain the ML pipeline (optional; pretrained artifacts are already
committed under `app/assets/ml/`):

```bash
cd ml
python3.12 -m venv .venv && ./.venv/bin/pip install tensorflow pillow pandas numpy scikit-learn joblib
./.venv/bin/python generate_datasets.py      # structured datasets -> ../data
./.venv/bin/python generate_seed_images.py   # synthetic seed images -> seed_dataset/
./.venv/bin/python train_classifier.py       # -> ../app/assets/ml/classifier.tflite
./.venv/bin/python train_price_model.py      # -> ../app/assets/ml/price_table.json
```

## Deploying against a real Firebase project

Run `flutterfire configure` from `app/` (needs `firebase login`), then set
`useEmulators = false` in `app/lib/firebase_options.dart`. Tighten
`firebase/firestore.rules` and `firebase/storage.rules` first — they're wide
open for the local emulator demo (see the comments in those files for what a
real deployment needs).

## What's genuinely real vs. what's a labeled placeholder

- **Real**: the full app (onboarding, lot creation with AI-suggested category,
  price board with trend + TTS, recycler ranking, GPS+photo+QR handover
  record, recycler confirmation + payment, earnings ledger, safety guidance,
  anomaly detection, offline queueing), the Firestore schema, the trained
  MobileNetV2 classifier and its TFLite export, the trained price-regression
  model and its distilled on-device table (R²=0.996 on held-out synthetic
  data), Hindi/Marathi/English localization with text-to-speech.
- **Labeled placeholder, by necessity of this build environment**: the
  training images (procedurally generated, not photographed), the recycler
  directory (fictional facilities modeled on real CPCB/SPCB record formats),
  the price history (modeled, not scraped/live), and 20 of 22 collector
  profiles (2 are explicit `TODO` slots for the two required field-research
  interviews, which need an in-person visit this environment can't do).

See `docs/dataset_documentation.md` for the full per-dataset breakdown and
`docs/unit_economics.md` for the collector-earnings and platform-sustainability
analysis.
