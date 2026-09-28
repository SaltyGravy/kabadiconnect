# KabadiConnect — Release History

Each version gets its own folder here (`releases/vX.Y.Z/`) with the built
APKs. Install `kabadiconnect-vX.Y.Z-arm64.apk` on virtually any Android
phone from the last ~8 years; use the `armeabi-v7a` one only for very old
32-bit devices. Built with debug signing (see README.md) -- Android may
warn on install; that's expected for a non-Play-Store build, not a sign of
a problem.

## v1.9.1 (2026-09-28)

Fixed the AI Copilot chat input being hidden behind the keyboard. The
sheet's root container had a fixed height of 85% of the FULL screen
height, computed without ever subtracting the keyboard's height -- so
when the keyboard opened, the sheet kept demanding that same height
instead of shrinking to fit the space actually left above the keyboard,
pushing the bottom of the sheet (where the text field lives) down
behind it. The sheet now sizes itself to `screen height - keyboard
height` whenever the keyboard is open, so the input field always ends
up sitting right above it.

## v1.9.0 (2026-09-27)

Real app icon and logo, replacing Flutter's default icon and the
`Icons.recycling` placeholder.
- Android launcher icon (all mipmap densities + adaptive icon, generated
  via `flutter_launcher_icons`) now uses the KabadiConnect mark (leaf +
  heart pin + handshake) cropped from the provided logo -- deliberately
  without the "KabadiConnect" wordmark baked in, since embedded text
  becomes illegible at launcher-icon sizes and gets inconsistently
  cropped by different launchers' adaptive-icon masks.
- The language-select screen (the app's actual first screen) now shows
  the full logo badge (mark + wordmark + tagline) instead of a generic
  Material recycling icon and separate text label.

## v1.8.4 (2026-09-27)

Found the actual root causes behind the persistent "stretched" and
"controls in the middle of the screen" reports on the continuous scanner,
confirmed via live device testing:

- **Stretched preview**: `CameraPreview` already wraps itself in its own
  orientation-aware `AspectRatio` internally (using the raw aspect ratio
  in landscape, `1/aspectRatio` in portrait -- see the `camera` package's
  `CameraPreview.build()`). Every previous fix attempt wrapped it in a
  SECOND, independently-computed `AspectRatio` using the raw, un-inverted
  ratio -- in portrait (the normal case here) that constrained it to a
  landscape-shaped box before `CameraPreview`'s own correct internal
  sizing logic ever got a chance to run, which is what actually stretched
  the texture. Removed the outer `AspectRatio` entirely; the crop-to-fill
  `Transform.scale` now uses the same orientation-corrected ratio
  `CameraPreview` uses internally, computed from `deviceOrientation`.
- **Top bar landing in the screen's vertical middle**: the top action bar
  (back / "AI Continuous Lens" pill / flash / camera-switch) is a
  non-positioned child of a `Stack(fit: StackFit.expand)`, which forces
  it to fill the FULL screen height -- and a bare `Row`'s default
  `CrossAxisAlignment.center` then centers its buttons in the middle of
  that full-height box instead of pinning them to the top. (The bottom
  control cluster didn't have this problem because it already used
  `Column(mainAxisAlignment: MainAxisAlignment.end)`, which compensates.)
  Wrapped the top bar in `Align(alignment: Alignment.topCenter)`.

## v1.8.3 (2026-09-20)

No device or emulator was available to test v1.8.2 on directly, so
instead of just asserting it was fine, did a full line-by-line audit of
the scanner's camera lifecycle code against the actual installed
`camera`/`image` package sources. Found and fixed two real bugs:
- After switching cameras (front/back toggle), the live HUD would
  silently stop updating: `_switchCamera()` disposed the old
  `CameraController` and built a new one, but never reset the
  `_isStreaming` flag, so `_startContinuousScanning()`'s re-entrancy
  guard saw a stale "already streaming" state and skipped starting the
  new controller's stream. Fixed by resetting the flag in `_initCamera()`
  and explicitly stopping the stream before disposing in `_switchCamera()`.
- The controller was requesting `ImageFormatGroup.jpeg` for
  `startImageStream()`, a less universally-supported streaming format
  across Android devices/plugin versions than the default YUV420.
  `takePicture()`'s still-capture output is unaffected by this setting
  (always JPEG on Android regardless), so there was no reason to take
  that risk -- switched to `ImageFormatGroup.yuv420`.

## v1.8.2 (2026-09-20)

Went back at the continuous scanner's lag after another report that it was
still happening. The v1.7.0 fix (switching the live HUD to the on-device
classifier) removed the network round-trip from the loop, but every tick
was still calling `takePicture()` every 2 seconds -- and `takePicture()`
is a full still-capture pipeline (AE/AF lock, sensor readout, JPEG encode,
disk write, disk read back) regardless of resolution, which is far too
heavy to call repeatedly and was the real remaining cause of the visible
lag/stutter.
- Replaced it with `startImageStream()`, which hands the app raw preview
  frames already in memory -- no capture pipeline, no disk I/O, no shutter
  hardware involved. Frames are throttled in Dart (processing at most one
  every ~2s, dropping the rest immediately) so this doesn't burn CPU on
  every frame, just the ones the HUD actually needs.
- Handles both frame formats the camera plugin may deliver (an
  already-encoded single plane, or raw YUV420 3-plane) with a manual
  YUV->RGB conversion for the latter, downsampled during conversion since
  the classifier only needs ~224px.
- Still capture (the shutter button) now explicitly stops the image
  stream first and restarts it after -- concurrent image-stream +
  takePicture() isn't reliably supported on all devices.

On the "still stretched/misaligned" report: the aspect-ratio-correcting
preview fix has been in place since v1.7.0, and this is the *only* screen
in the codebase that uses `CameraPreview`/`CameraController` -- there's no
second/stale camera screen it could be hitting instead. Sideloaded APKs
don't auto-update on Android, so if this is still showing stretched after
installing this build, the most likely explanation is a stale APK still
on the device from before v1.7.0 -- worth fully uninstalling the old one
and reinstalling this one to rule that out.

## v1.8.1 (2026-09-20)

Safety Guidance screen: each tip's audio narration now has real play/pause
and replay controls instead of a single one-shot "Listen" button.
- Since on-device TTS engines don't support true mid-utterance
  pause-and-resume, narration is spoken one sentence at a time -- Pause
  stops after the current sentence and remembers which one it was, so
  Play resumes there instead of restarting from the top. A small counter
  ("2/4") shows progress while playing or paused.
- Added a separate Replay button that jumps back to the first sentence
  and starts over, distinct from Pause/Play.

## v1.8.0 (2026-09-20)

Online AI is now live out of the box, and the classifier crossed the 80%
accuracy bar.

- **Bundled Gemini API key**: the app now ships with a Gemini API key
  built into the release binary via `--dart-define` (see
  `scripts/build_release.sh` / `app/secrets.local.env.example`) -- never
  hardcoded in a committed source file. A collector's own key, pasted via
  Settings, still always takes priority over this default. The key is
  restricted to the Generative Language API only and has a hard request
  quota set on its GCP project, since anything baked into a distributed
  APK should be treated as effectively public no matter how it's built.
- Fixed a real bug found while wiring this up: the app was calling
  `gemini-1.5-flash`, which has since been deprecated and was silently
  404ing on every online request, always falling back to the on-device
  model. Switched to `gemini-flash-latest` -- a Google-maintained alias
  that tracks their current recommended fast model, so this can't
  silently break the same way again.
- **Classifier accuracy: 79.8% -> 83.3%** validation accuracy (target was
  80%+). Pulled a fourth, more targeted round of training photos aimed at
  the single biggest confusion pair from the last confusion matrix (8 of
  48 NON_COLLECTIBLE validation images were being misclassified as
  MIXED_PLASTICS -- plastic bottles vs. plastic e-waste casings look
  similar to the model) -- sharpened the search queries on both sides of
  that pair, growing the dataset to ~3,000 images. Recall is now 72-94%
  across all 9 classes; NON_COLLECTIBLE precision is 97.7%, so it's now
  quite reliable at not accepting ordinary garbage.

## v1.7.1 (2026-09-20)

Pushed the on-device model further, in response to a request for much
higher accuracy. Worth being straight about the ceiling here: a small
MobileNetV2 classifier trained on free web photos cannot realistically hit
99% on arbitrary real-world items -- that kind of number only comes from
models trained on millions of labeled images per class, evaluated on
curated test sets, not an open-world "point at anything" scenario. What
this update does deliver, honestly measured:
- Pulled three more rounds of real, appropriately-licensed photos from
  Wikimedia Commons/Openverse (added query diversity + pagination), taking
  the training set from ~1,500 to ~2,300 images and narrowing the
  per-category imbalance from a 15x range (10 to 156 images) down to about
  2.5x (122 to 316).
- Bumped the classifier to MobileNetV2's native 224x224 input (was 160x160
  -- a resolution mismatch that would have silently broken on-device
  inference had it shipped without the matching Dart-side fix), increased
  training epochs with early stopping, and fine-tuned a larger slice of
  the backbone (top 60 layers instead of 35) now that there's more data to
  support it without overfitting.
- Validation accuracy: 72.2% -> **79.8%**, with recall now in the
  71-89% range across every one of the 9 classes (previously as low as
  ~30-50% on the weakest ones). Detector composite-scene decision accuracy:
  70.0% -> 83.3%.
- For genuinely high accuracy on real, messy scrap piles, the app's
  existing online Gemini analysis path (used on shutter press when
  internet + an API key are available) will outperform this on-device
  model by a wide margin -- that's the realistic route to near-human
  accuracy, with the on-device model serving as the fast, fully-offline
  fallback for the live scanning HUD.

## v1.7.0 (2026-09-20)

Continuous AI Lens scanner overhaul, fixing four reported problems at once:

- **Lag**: the live preview loop was calling `takePicture()` (full-res
  still capture) plus the same possibly-online `EwasteAiService.analyzeImage()`
  used for shutter presses, every 1.5s -- if a Gemini API key was ever set,
  every tick could trigger a full network round-trip. The live HUD now
  calls the on-device `ClassifierService` directly (no network, ever), at
  medium camera resolution instead of high, on a slightly longer 2s tick.
  The full (possibly online) analysis still runs, but only once, on shutter
  press -- where the extra latency is expected and acceptable.
- **Stretched/distorted preview**: `CameraPreview` was wrapped in
  `Stack(fit: StackFit.expand)` with no aspect-ratio correction, so the
  live image was squashed/stretched to fill the screen. Replaced with the
  standard Flutter camera-preview idiom (`Transform.scale` + `AspectRatio`)
  that crops-to-fill instead of distorting.
  Also wrapped the bottom shutter/HUD controls in a bottom `SafeArea` --
  they weren't previously, so on phones with a gesture-nav bar the shutter
  button could sit under the system bar.
- **Multi-item lot flow was broken**: confirming an item's weight used to
  jump straight to checkout with just that one item; "Add More Items" left
  the scanner for a different screen. Now: confirming an item's weight adds
  it to this scan session's accumulating lot and returns to the live
  scanner so you can keep pointing at more items -- a persistent "N items
  in this lot · ₹total · Checkout" bar appears once you've added at least
  one, and tapping it is the only thing that proceeds to checkout (with a
  confirm step). Leaving the scanner with unsaved items now asks first.
- **Model accuracy**: the classifier's training set was badly imbalanced
  (some categories had 150+ images, MIXED_OTHER had 10). Pulled several
  hundred more real, appropriately-licensed photos from Wikimedia
  Commons/Openverse focused on the weakest categories (MIXED_OTHER
  10→52, CRT 61→121, LCD_LED 46→95, MOTORS_MAGNETS 41→91, MIXED_PLASTICS
  32→74 training images), added inverse-frequency class weighting to the
  training loop, and retrained both the classifier and the detector.
  Validation accuracy: 68.6% → 72.2%, with the biggest gains on the
  previously-starved categories (e.g. MOTORS_MAGNETS recall 0.88,
  MIXED_OTHER recall 0.82, CRT recall 0.85).

## v1.6.1 (2026-09-19)

Fixed a real layout bug: titles in the E-Waste Guide's Categories tab and
the AI Copilot sheet's header were rendering one character per line in a
tall narrow column (e.g. "Printed Circuit Boards (PCBs)" as a vertical
strip). Root cause: a `Row` had one non-flexible sibling with a long,
unbounded-width string (the "₹250 - ₹900/kg (graded by gold/component
density)" price pill; the Voice/Chat mode toggle + 2 icon buttons in the
Copilot header) next to the `Expanded` title -- Flutter measures
non-flexible children at their natural width first, so a long enough
sibling squeezes `Expanded` down to near-zero width, and text wraps after
every 1-2 characters instead of overflowing normally.
- Guide screen: moved the price-range badge onto its own line below the
  title instead of squeezing it into the header row.
- Copilot header: the Voice/Chat toggle now shows its label only for the
  currently-selected mode (icon-only when inactive), freeing up room for
  the title; trimmed the two trailing icon buttons' padding too.
- Added `maxLines`/`overflow: ellipsis` as a defensive backstop on every
  title Text in both screens, so even an unexpectedly long string (some
  CPCB Schedule I item names are genuinely very long) truncates cleanly
  instead of collapsing into the vertical-wrap bug again.

## v1.6.0 (2026-09-19)

**Continuous "Google Lens"-style scanner.** Tap the camera button in the
bottom bar (or "Scan" from Create Lot) to open a fullscreen live scanner:
camera preview with a laser-sweep reticle, continuously re-analyzing what
it's pointed at every ~1.5s and showing a live floating pill with the
identified item, confidence, and current rate/kg. Tapping the shutter
freezes the frame, runs a full analysis, and immediately pops up a bottom
sheet asking for weight (stepper + quick-add chips + condition), with a
live running payout estimate -- "Confirm & Create Lot" goes straight to
checkout with that single item, or "Add More Items" hands off to the full
Create Lot screen with this as the first row.

**Internet-grounded e-waste knowledge base.** A new
`ewaste_knowledge_base.json` (bundled asset) encodes India's E-Waste
(Management) Rules 2022 / CPCB Schedule I taxonomy -- all 8 collection
categories plus a prohibited/rejected-items list -- researched from the
official CPCB gazette notification. A new in-app "Accepted Scrap Guide"
screen surfaces it directly to collectors.

**AI now rejects non-e-waste and explains itself.** `EwasteAiService`
combines the on-device classifier/detector with this knowledge base to
decide whether a photographed item is actually collectible under the
Rules; if not (ordinary trash, food waste, non-electronic items), it's
rejected with a plain-language reason instead of being forced into one of
the 8 categories. When an item IS accepted, the AI also surfaces
which components it likely breaks down into and any relevant safety/
hazard warning (e.g. lead in CRT glass) inline.

**Both on-device models retrained on real internet photographs**
(Wikimedia Commons + Openverse, CC-licensed), not just user-supplied field
photos:
- Classifier: added a 9th class, `NON_COLLECTIBLE`, trained explicitly to
  reject non-e-waste; two-stage fine-tuning (frozen-backbone warmup, then
  unfreezing MobileNetV2's top 35 layers at a low learning rate).
  69% validation accuracy across all 9 classes -- a real number now, not a
  synthetic-data artifact.
- Detector: the synthetic composite generator now also injects
  `NON_COLLECTIBLE` patches as unannotated negative distractors in ~35% of
  training images, explicitly teaching the detector to leave non-scrap
  objects unboxed rather than force-labelling everything in frame.

**Voice/chat AI assistant.** A new floating assistant button (and bottom
sheet) accepts spoken or typed input in English, Hindi, and Marathi --
including colloquial phrasing and Hindi fraction words ("dedh", "dhai") --
to add lot items, query rates, or ask what's accepted, hands-free. Backed
by a real NLP parser with its own test suite (10 passing unit tests
covering all three languages plus mixed Hinglish).

## v1.5.0 (2026-09-19)

**Live, area-wise scrap prices.** A new backend job
(`ml/sync_metalmandi_prices.py`, run every 3 hours by a GitHub Actions
cron -- see the new `kabadiconnect` GitHub repo) pulls real scrap rates
from metalmandi.in per city and writes them into a new Firestore
collection (`live_scrap_prices`). The app layers these over the static
offline price table via a real-time listener, so both the Rate List and
the home dashboard's rate preview update automatically as new data lands
-- no app update needed. A small "LIVE" tag marks rows backed by this feed.

Category mapping (MetalMandi doesn't use our exact taxonomy):
CRT<-Display/CRT TV, LCD_LED<-Display/LCD+LED, PCB<-PCB, CABLES<-Wire,
BATTERIES<-Li-ion Battery, MOTORS_MAGNETS<-Magnet, MIXED_OTHER<-E-waste.
**Mixed Plastics has no live source** -- MetalMandi is metal-scrap-focused
and doesn't cover plastics, so that category keeps using the static
offline price only.

Locations map to MetalMandi's district-level city IDs (Pune, Mumbai,
Nagpur, Nashik all direct matches; Pimpri-Chinchwad reuses Pune's district;
Chhatrapati Sambhajinagar matches under MetalMandi's still-used pre-2023
name "Aurangabad").

Important caveat: MetalMandi's `/api/crm-proxy` is not a documented public
API -- it's their own frontend's internal backend call, reachable
directly. It works today (verified 2026-09-19) but could change or be
blocked without notice, and this is best-effort reuse of a third party's
data, not a guaranteed integration.

## v1.4.0 (2026-09-19)

**Collector home screen redesign**, built from a hand-drawn mockup:
- The whole collector experience is now a persistent bottom-tab shell
  (My Lots / Rate List / Wallet / Profile) with a centre-docked camera
  button for starting a new lot -- tapping any tab keeps the bar visible,
  instead of the old grid-of-cards that pushed a full-screen route per tile.
- Home tab: personalized "Welcome, {name}!" greeting, a swipeable safety-tip
  carousel (taps into full Safety guidance), and a live "Today's Rates"
  preview grid for 4 categories (Cables, PCB, Batteries, Motors & Magnets)
  pulled from the same pricing data as the full Rate List.
  a quick health-and-safety icon jumps straight to Safety guidance.
  A gear icon in the top bar jumps to the Profile tab; the globe icon keeps
  the existing language picker.
  Each non-home tab (My Lots, Rate List, Wallet, Profile) got a small home
  icon in its own app bar to jump back to the dashboard, since it's no
  longer reachable by "going back" once tabs are true persistent state.
- No change to branding -- still KabadiConnect throughout.
- The other 4 categories from the full price table (CRT, LCD/LED, Mixed
  Plastics, Mixed/Other) aren't in the home teaser grid, only in the full
  Rate List tab -- picked 4 representative ones to keep the dashboard glanceable.

## v1.3.1 (2026-09-17)

Each material row on the Create Lot page now shows its own small copy of
the photo with *only that row's* box marked (the other detected boxes are
hidden) -- so confirming "yes, item 2 is this part of the photo" doesn't
require squinting at the shared photo up top with every box overlapping.
Verified live on-device: each row's thumbnail correctly shows just its own
numbered box.

## v1.3.0 (2026-09-17)

**Real multi-item object detection.** Taking one photo no longer just
classifies "the one dominant material" -- a new on-device detector (see
`ml/train_detector.py`) finds each distinct item in the photo, draws a
numbered, colour-coded box around it, and creates one editable row per
detection automatically. This replaces the old single-classification flow
for photos where anything is confidently found; if nothing is, it falls
back to the old single-suggestion behaviour so there's always a starting
point. Every row -- detected or manually added -- still starts at 0 kg,
requiring a real weight before checkout.

How it was built, and its real limits (read this before relying on it):
- There are no real photos of mixed e-waste piles with per-item bounding
  boxes anywhere in this project, so the detector was trained on a
  *synthetic* dataset: your real single-item photos pasted at random
  non-overlapping positions onto generated backgrounds (see
  `ml/generate_detection_dataset.py`). It genuinely learned to localize and
  classify multiple items in one image, but there's a real domain gap
  between "photos of collages" and "photos of an actual messy pile."
- Verified live on a real device: taking a photo reliably produces
  multiple numbered/coloured boxes with matching editable rows, and the
  whole flow (detect -> rows -> weights -> checkout) works without
  crashing.
- Known rough edges: category confusion is common (e.g. a car engine
  photographed for the composite dataset getting boxed as "Batteries"
  instead of "Motors & Magnets") -- localization (finding *that* something
  is there) is more reliable than classification (naming *what* it is) at
  this stage. Large objects can also occasionally produce two overlapping
  boxes for the same item, since a big item can make more than one grid
  cell "claim" it; basic overlap + same-class-center de-duplication is
  in place but doesn't catch every case. "Not correct?" on any row lets
  the collector fix a wrong category by hand.
- Getting meaningfully better accuracy from here needs real photos of
  actual mixed piles with real bounding-box annotations, not more
  synthetic composites -- a data collection task, not a code change.

## v1.2.3 (2026-09-17)

Bug fixes found while testing v1.2.1 live on a real device:
- Fixed a pricing bug: for "per piece" priced categories (e.g. LCD/LED
  panels), the instant value estimate showed a nonzero amount even at the
  new 0 kg default (it was treating an unset weight as "at least one
  piece"). Now 0 kg always means ₹0, for every category.
- Fixed a state bug in Create Lot: if you reopened a material row's
  category picker (tapped "Not correct?"/"Change material") and then
  removed an *earlier* row, the picker you had open would silently close
  instead of staying open -- confirmed and reproduced live, then fixed by
  correctly shifting the "currently editing" row index when a row before it
  is removed.
- Renamed the confusing "Back" link on a manually-added material row to
  "Change material" (it reopens the category picker, it doesn't navigate
  back).
- The "+ Add another material" button no longer appears while the first
  row's AI detection is still running, avoiding an odd half-loaded state.

## v1.2.1 (2026-09-17)

**Create Lot rewritten: every material is now its own row on the same
page**, instead of a single "draft" slot you filled in and tapped "Add to
Lot" one at a time:
- Taking a photo still auto-detects the first material via AI, but it now
  shows up immediately as Row 1 on the page rather than a separate
  "detected" card you had to confirm first.
- "+ Add another material" adds a new row right there on the page (pick its
  category from the icon grid) -- you can have as many rows as needed, all
  visible together, each numbered and colour-coded so it's clear which row
  is which material.
- **Every row's weight defaults to 0 kg**, including the AI-suggested one --
  the collector must type a real weight into every row before "Review &
  Checkout" enables. A row with 0 kg shows an inline hint ("Enter a weight
  for every material to continue") instead of silently letting a fake
  default weight through.
- Each row shows its own live value estimate as you edit it.

Note on scope: the on-device AI classifier is a single-label model (it
picks the one best-matching category for the whole photo) -- it cannot
detect and separate multiple physical objects within one image on its own.
"Multiple items from one photo" here means the collector adds each
material they can see in that one photo as its own row on this same page;
it is not automatic multi-object detection.

## v1.2.0 (2026-09-17)

**Checkout page** — creating a lot no longer saves it straight away. After
adding materials, the collector now goes through a Checkout screen first:
- Full breakdown of every item in the lot (numbered, with icon/colour per
  category so a multi-material photo is unambiguous about "which one is
  what"), total weight, and materials subtotal.
- **Carbon credit cashback**: estimated CO2 saved (kg) for this lot, plus a
  real "Green Bonus" cashback amount added on top of the materials price --
  a KabadiConnect incentive, not something deducted from the recycler's own
  payment. Per-category CO2-per-kg factors live in
  `assets/ml/carbon_factors.json`; clearly labelled as an estimate, not a
  certified/tradeable carbon credit.
- **Logistics choice**: "I'll handle it myself" (free) vs "Let
  KabadiConnect handle it" (a nominal weight-based pickup fee, deducted from
  the payout). Choosing platform pickup also nudges recycler matching
  toward facilities that support pickup.
- Bottom line: an "Estimated total you'll receive" combining materials +
  green bonus - logistics fee, before the lot is ever created.
- Only confirming on this screen actually writes the lot and moves on to
  recycler matching.

**Receipt** — once a recycler confirms receiving a handed-over lot, both
sides get a "View Receipt" button (on the collector's Lot Detail screen and
the recycler's Lot Review screen) showing a single itemized summary: every
material + weight, materials price, CO2 saved + green bonus, logistics fee,
net total, recycler name, and the handover reference number/GPS.

Lot Detail and Lot Review screens also now show the green bonus, logistics
fee, and a computed total payout inline, and the recycler review screen
flags when a collector has requested platform-arranged pickup.

## v1.1.1 (2026-09-15)

**Real photos in the material classifier** — the on-device AI classifier was
trained entirely on procedurally-generated placeholder shapes until now
(never real photos). Replaced its training data with real field photos for
7 of the 8 categories:
- BATTERIES, CABLES, PCB, LCD_LED, MIXED_PLASTICS, MOTORS_MAGNETS, CRT now
  train on real photos (deduped, junk-filtered, including photos that had
  been pasted into Word docs rather than saved as loose image files).
- MIXED_OTHER has no real photos supplied yet, so it still falls back to the
  synthetic placeholder set -- treat that one category as unproven until
  real photos are added for it too.
- Validation accuracy on the real-photo set is ~76% (vs. the old ~99% on
  synthetic shapes, which never meant anything about real-world accuracy --
  this number is the first real signal we have).
- No app code changed in this release, only the bundled model
  (`classifier.tflite`) and its labels -- same UI, same features as v1.1.0.

## v1.1.0 (2026-09-13)

**Multi-item lots** — a lot can now bundle several distinct materials from
one photo instead of forcing one category per lot:
- "Add to Lot" flow in Create Lot: AI detects the first material, then add
  more manually (category + weight + condition each), with a running list
  and running total value.
- Recycler matching ranks by category *coverage* ("covers 2/3 materials")
  instead of requiring one exact category match.
- Quoted price sums each material against the chosen recycler's own rate.
- Anomaly detection compares the recycler's lump-sum final price against
  the *summed* expected baseline across all materials.
- Detail screens show the full itemized breakdown; list screens show "+N
  more" for multi-item lots.
- Old single-category lots already in the live database still read fine
  (backward-compatible parsing).

**Bug fixes bundled into this release:**
- Fixed a login-flash bug: the wrong screen (profile setup, or "not an
  authorized recycler") would flash for a frame after every login, because
  Firebase's own sign-in state updated before the app had loaded the actual
  profile. Now gated behind an explicit "still resolving" flag.
- Fixed 7 `TextEditingController` instances across 6 screens that were
  never disposed (memory leak).
- Fixed the Price Board defaulting to an arbitrary city's prices instead of
  the collector's own area -- a mismatch left over from adding Places
  address search (raw formatted address vs. the six known price-table city
  keys).
- Fixed a missing Firestore composite index that made the recycler's
  "Incoming Lots" and the collector's "My Lots" screens spin forever on the
  real (non-emulator) project.
- Fixed a `WriteBatch`-reuse-after-commit bug in the seed script that had
  silently dropped 92 of 480 price records from the live database;
  backfilled the missing records.
- Removed a dead, permission-rejected cross-role Firestore write in the
  "mark lot as paid" flow (recycler trying to write to the collector's
  profile, which security rules correctly block; the earnings ledger never
  actually depended on it).

## v1.0.0 (2026-09-05 – 2026-09-12, untagged builds)

Initial build: collector + recycler roles, phone+password auth (see
docs/dataset_documentation.md for why not OTP), lot creation with on-device
AI material classification, price board with trends + TTS, GPS-tracked
recycler matching, QR-based handover records, earnings ledger, safety
guidance, Hindi/Marathi/English localization, offline-first Firestore sync,
Places API address search. Structured datasets in `data/`. See root
README.md for the full picture and known gaps.
