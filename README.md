# KabadiConnect

**Fair prices and safe, recorded handovers for India's informal e-waste collectors.**

KabadiConnect is an Android app that connects *kabadiwalas* (informal e-waste collectors) with authorized recyclers. It shows collectors what their scrap is worth, matches them to nearby recyclers and records every handover. It's built for people with low literacy and patchy internet: it speaks Hindi, Marathi and English, reads prices aloud and keeps working offline.

It's built around India's **E-Waste (Management) Rules, 2022** and its Extended Producer Responsibility (EPR) framework.


---

## The problem

Most of India's e-waste is collected by informal workers who:
- don't know the fair market price of what they collect,
- sell to whoever is nearest, often unsafe and unauthorized dismantlers,
- have no record of what they sold, to whom or for how much.

Formal recycling usually adds paperwork instead of helping them. KabadiConnect aims to make the formal route the easier one.

## Features

**For collectors**
- **AI scanner:** point the camera at an item and the on-device model suggests its e-waste category, live, like Google Lens
- **Price board:** current scrap rates with price trends, read aloud with text-to-speech
- **Instant price estimate:** works fully offline using an on-device pricing model
- **Recycler matching:** nearby authorized recyclers ranked by distance and price
- **Handover record:** GPS location, photo and QR code captured at every handover
- **Earnings ledger:** a clear history of what was sold, to whom and for how much
- **Safety guidance:** narrated advice on handling hazardous e-waste safely
- **Voice AI assistant:** ask questions by voice, in your language

**For recyclers**
- Inbox of incoming lots, handover confirmation by QR and payment recording

**Built-in checks**
- **Anomaly detection** flags prices that look unusual, so data-entry mistakes and unfair quotes get reviewed
- **Offline-first:** everything works without internet and syncs later, including photo uploads

---

## How it works

One Flutter app serves both collectors and recyclers; the user picks a role during onboarding. Data lives in **Firebase** (Firestore, Auth, Storage).

- **Offline support:** Firestore's offline persistence handles records, and a custom local queue handles photo uploads, which Firestore doesn't queue on its own.
- **Image classification:** a **MobileNetV2** model, fine-tuned with transfer learning and exported to **TensorFlow Lite**, runs on the phone. No internet needed.
- **Price estimation:** a regression model trained in Python, turned into a compact lookup table that ships inside the app for instant offline estimates.
- **Live prices:** a scheduled GitHub Actions job syncs current scrap rates from MetalMandi every 3 hours.
- **AI assistant:** optional Google Gemini integration for the voice assistant and item questions (the key is supplied at build time, never stored in the code).

## Tech stack

| Area | Technology |
|---|---|
| Mobile app | Flutter (Dart) |
| Backend | Firebase: Firestore, Authentication, Storage |
| On-device ML | TensorFlow Lite (MobileNetV2) |
| ML training | Python, TensorFlow, scikit-learn, pandas |
| AI assistant | Google Gemini API |
| Automation | GitHub Actions (price sync) |
| Languages | Hindi, Marathi, English, with text-to-speech |

## Project structure

```text
app/        Flutter app (collector + recycler roles in one codebase)
ml/         Python ML pipeline: image classifier, price model, price sync
data/       Datasets: materials, prices, recyclers, transactions, traceability, collectors
firebase/   Firebase emulator config and security rules
docs/       Dataset documentation and unit-economics analysis
releases/   Version history (CHANGELOG.md)
```

---


## Run it locally

**Requirements:** Flutter SDK, Node.js (for `firebase-tools`), Java (for the Firestore emulator). Python 3.12 is only needed if you want to retrain the models.

```bash
# 1. Start the local Firebase backend
npm install -g firebase-tools
cd firebase
firebase emulators:start --project demo-kabadiconnect

# 2. In a new terminal, run the app
cd app
flutter pub get
flutter run            # on a connected Android phone or emulator
flutter run -d chrome  # quick preview in the browser
```

On first run, the app fills the local database with the sample data from `data/` automatically.

To enable the AI assistant, pass your own Gemini key at build time:

```bash
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

### Retrain the models (optional)

The trained models are already included in `app/assets/ml/`.

```bash
cd ml
python3.12 -m venv .venv
./.venv/bin/pip install tensorflow pillow pandas numpy scikit-learn joblib
./.venv/bin/python generate_datasets.py
./.venv/bin/python train_classifier.py    # -> app/assets/ml/classifier.tflite
./.venv/bin/python train_price_model.py   # -> app/assets/ml/price_table.json
```

---

## Data: what's real and what's sample

To be upfront about it:

- **Real and working:** the full app, the Firestore data model, the trained image classifier, the price model, live price sync, offline queueing, localization and text-to-speech.
- **Sample data for now:** the recycler directory is fictional but follows real CPCB/SPCB record formats; most collector profiles are generated; part of the training images and price history are generated, not collected in the field.

Replacing these with real field data (collector interviews, a verified recycler list, more real item photos) is the main next step. See [`docs/dataset_documentation.md`](docs/dataset_documentation.md) for details on every dataset, and [`docs/unit_economics.md`](docs/unit_economics.md) for the collector-earnings and sustainability analysis.

## Before a real deployment

- Tighten `firebase/firestore.rules` and `firebase/storage.rules`; they're open for local testing.
- Restrict every Google/Firebase API key in Google Cloud Console to this app's package name and signing certificate.
- Sign the APK with a proper release key.

---

## Author

**Archit Kumar**, B.Tech Information Technology, Thakur College of Engineering and Technology, Mumbai
GitHub: [@SaltyGravy](https://github.com/SaltyGravy)
