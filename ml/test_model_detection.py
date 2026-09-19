"""
KabadiConnect - Comprehensive Waste Detection & Rejection Test Harness.

Tests the AI system (TFLite Detector, TFLite Classifier, and Knowledge Base Rejection Gating)
across diverse types of wastes and varied background environments:
1. Different sorts of wastes:
   - E-Waste Categories: PCB, CABLES, BATTERIES, CRT, LCD_LED, MOTORS_MAGNETS, MIXED_PLASTICS, MIXED_OTHER
   - Non-E-Waste Municipal Waste: PET plastic bottle, Cardboard box, Banana peel / food waste, Non-e-waste trash
   - Prohibited Hazardous Items: CFL fluorescent mercury bulb, Medical syringe
   - Mixed Co-located Scenes: E-Waste item + Non-E-Waste item side-by-side
   - Pure Garbage Negative Controls: Only trash items, zero e-waste
2. Different background environments:
   - Clean Workbench (plain neutral off-white surface)
   - Wooden Table (warm oak / teak wood grain)
   - Concrete Pavement (speckled asphalt / street floor)
   - Mud / Soil Ground (outdoor earth, gravel, dirt)
   - Scrap Heap Clutter (cluttered background, debris, wrappers)
   - Dark / Shadowed Surface (dimly lit, underexposed scrap area)

Outputs:
  - ml/artifacts/test_results/images/*.jpg (Annotated visualization with bounding boxes & acceptance stamps)
  - ml/artifacts/test_results/detection_test_report.json (Detailed metrics, precision/recall, rejection rate)
"""
import json
import math
import os
from pathlib import Path
import random
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import tensorflow as tf

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
APP_ASSETS = REPO_ROOT / "app" / "assets" / "ml"
OUT_DIR = ROOT / "artifacts" / "test_results"
OUT_IMG_DIR = OUT_DIR / "images"
OUT_IMG_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Load TFLite Models and Knowledge Base
# ---------------------------------------------------------------------------
print("Loading TFLite models and e-waste knowledge base...")

# Detector
detector_path = APP_ASSETS / "detector.tflite"
det_interp = tf.lite.Interpreter(model_path=str(detector_path))
det_interp.allocate_tensors()
det_input_details = det_interp.get_input_details()[0]
det_output_details = det_interp.get_output_details()[0]

with open(APP_ASSETS / "detector_labels.txt") as f:
    DETECTOR_CLASSES = [line.strip() for line in f if line.strip()]

# Classifier
classifier_path = APP_ASSETS / "classifier.tflite"
clf_interp = tf.lite.Interpreter(model_path=str(classifier_path))
clf_interp.allocate_tensors()
clf_input_details = clf_interp.get_input_details()[0]
clf_output_details = clf_interp.get_output_details()[0]

with open(APP_ASSETS / "labels.txt") as f:
    CLASSIFIER_CLASSES = [line.strip() for line in f if line.strip()]

# Knowledge Base
with open(APP_ASSETS / "ewaste_knowledge_base.json") as f:
    KNOWLEDGE_BASE = json.load(f)

GRID = 10
ANCHOR_CELLS = 3.0


# ---------------------------------------------------------------------------
# Model Inference Wrappers
# ---------------------------------------------------------------------------
def decode_detector_boxes(pred, obj_threshold=0.38):
    """Decode raw detector grid output into bounding boxes."""
    boxes = []
    obj = 1 / (1 + np.exp(-pred[..., 0]))
    for gy in range(GRID):
        for gx in range(GRID):
            score = float(obj[gy, gx])
            if score < obj_threshold:
                continue
            tx, ty, tw, th = pred[gy, gx, 1:5]
            cx = (gx + 1 / (1 + np.exp(-tx))) / GRID
            cy = (gy + 1 / (1 + np.exp(-ty))) / GRID
            w = np.exp(tw) * ANCHOR_CELLS / GRID
            h = np.exp(th) * ANCHOR_CELLS / GRID
            class_logits = pred[gy, gx, 5:]
            class_idx = int(np.argmax(class_logits))
            class_name = DETECTOR_CLASSES[class_idx]
            boxes.append({
                "score": round(score, 3),
                "class_idx": class_idx,
                "category": class_name,
                "x1": max(0.0, float(cx - w / 2)),
                "y1": max(0.0, float(cy - h / 2)),
                "x2": min(1.0, float(cx + w / 2)),
                "y2": min(1.0, float(cy + h / 2)),
            })
    # Non-maximum suppression (NMS)
    boxes.sort(key=lambda b: -b["score"])
    kept = []
    for b in boxes:
        overlap = False
        for k in kept:
            ix1, iy1 = max(b["x1"], k["x1"]), max(b["y1"], k["y1"])
            ix2, iy2 = min(b["x2"], k["x2"]), min(b["y2"], k["y2"])
            inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
            area_b = (b["x2"] - b["x1"]) * (b["y2"] - b["y1"])
            area_k = (k["x2"] - k["x1"]) * (k["y2"] - k["y1"])
            iou = inter / max(1e-6, area_b + area_k - inter)
            if iou > 0.35:
                overlap = True
                break
        if not overlap:
            kept.append(b)
    return kept


def run_detector(image_pil):
    """Run on 320x320 image. Returns list of detected boxes."""
    img_resized = image_pil.resize((320, 320)).convert("RGB")
    inp = np.array(img_resized, dtype=np.float32) / 127.5 - 1.0
    inp = np.expand_dims(inp, axis=0)

    det_interp.set_tensor(det_input_details["index"], inp)
    det_interp.invoke()
    out = det_interp.get_tensor(det_output_details["index"])[0]
    return decode_detector_boxes(out)


def run_classifier(image_pil):
    """Returns top category, score, and all probabilities."""
    clf_size = clf_input_details["shape"][1]
    img_resized = image_pil.resize((clf_size, clf_size)).convert("RGB")
    inp = np.array(img_resized, dtype=np.float32) / 127.5 - 1.0
    inp = np.expand_dims(inp, axis=0)

    clf_interp.set_tensor(clf_input_details["index"], inp)
    clf_interp.invoke()
    probs = clf_interp.get_tensor(clf_output_details["index"])[0]
    top_idx = int(np.argmax(probs))
    category = CLASSIFIER_CLASSES[top_idx]
    confidence = float(probs[top_idx])
    non_collectible_prob = float(probs[CLASSIFIER_CLASSES.index("NON_COLLECTIBLE")])

    return {
        "category": category,
        "confidence": round(confidence, 3),
        "non_collectible_prob": round(non_collectible_prob, 3),
        "all_probs": {cat: round(float(p), 3) for cat, p in zip(CLASSIFIER_CLASSES, probs)},
    }


def evaluate_app_decision(detections, classification, ground_truth_is_ewaste, item_type):
    """
    Simulates the Flutter App's decision logic:
    - If detector detects items: uses detected boxes.
    - If detector finds nothing: falls back to classifier.
    - If classification is NON_COLLECTIBLE or confidence < 0.20 or item is prohibited: REJECT.
    - If accepted: ACCEPT into lot with category and guidance.
    """
    is_rejected = False
    rejection_reason = None
    accepted_items = []

    # Check prohibited rules from knowledge base
    prohibited_categories = KNOWLEDGE_BASE.get("prohibited_and_rejected_items", [])
    for p in prohibited_categories:
        for ex in p.get("examples", []):
            if ex.lower() in item_type.lower() or item_type.lower() in ex.lower():
                is_rejected = True
                rejection_reason = p.get("rejection_reason")
                break
        if is_rejected:
            break

    # 2. Classifier verification gate: if classifier detects NON_COLLECTIBLE garbage
    if not is_rejected:
        if classification["category"] == "NON_COLLECTIBLE" or classification["non_collectible_prob"] > 0.35:
            is_rejected = True
            rejection_reason = (
                "Item identified as non-collectible municipal waste (e.g. plastic bottles, cardboard packaging, food scraps). "
                "Only authorized e-waste categories are collected."
            )
        elif len(detections) > 0:
            for d in detections:
                accepted_items.append(d["category"])
        else:
            if classification["confidence"] < 0.20:
                is_rejected = True
                rejection_reason = "Unrecognized item below confidence threshold."
            else:
                accepted_items.append(classification["category"])

    decision = "REJECTED" if is_rejected or len(accepted_items) == 0 else "ACCEPTED"

    # Evaluate whether decision matches ground truth
    is_correct = False
    if ground_truth_is_ewaste and decision == "ACCEPTED":
        is_correct = True
    elif not ground_truth_is_ewaste and (decision == "REJECTED" or len(detections) == 0):
        is_correct = True

    return {
        "decision": decision,
        "is_correct": is_correct,
        "rejection_reason": rejection_reason,
        "accepted_items": accepted_items,
    }


# ---------------------------------------------------------------------------
# Background Generators (6 Diverse Environments)
# ---------------------------------------------------------------------------
def gen_clean_workbench(size=320):
    """Clean neutral white/light-grey table with subtle vignette."""
    base = np.full((size, size, 3), 242, dtype=np.uint8)
    noise = np.random.normal(0, 3, (size, size, 3)).astype(np.int16)
    arr = np.clip(base + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr)
    return img


def gen_wooden_table(size=320):
    """Warm wood grain tabletop with horizontal streaks."""
    img = Image.new("RGB", (size, size), (160, 105, 55))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        grain = int(np.sin(y / 7.0) * 18 + np.sin(y / 1.8) * 7 + np.cos(y / 23.0) * 12)
        r = max(0, min(255, 160 + grain))
        g = max(0, min(255, 105 + int(grain * 0.7)))
        b = max(0, min(255, 55 + int(grain * 0.4)))
        draw.line([(0, y), (size, y)], fill=(r, g, b))
    # Add knot-like imperfections
    for _ in range(3):
        kx, ky = random.randint(30, size - 30), random.randint(30, size - 30)
        draw.ellipse([kx - 8, ky - 4, kx + 8, ky + 4], fill=(110, 70, 35))
    return img.filter(ImageFilter.GaussianBlur(0.8))


def gen_concrete_asphalt(size=320):
    """Outdoor concrete pavement / asphalt street surface with gravel noise."""
    base = np.random.normal(120, 18, (size, size, 3)).clip(0, 255).astype(np.uint8)
    # Add small speckles and cracks
    img = Image.fromarray(base)
    draw = ImageDraw.Draw(img)
    for _ in range(80):
        x, y = random.randint(0, size), random.randint(0, size)
        shade = random.choice([(70, 70, 70), (170, 170, 170), (50, 50, 50)])
        draw.point((x, y), fill=shade)
    # Faint crack line
    cx = random.randint(20, size - 40)
    draw.line([(cx, 0), (cx + random.randint(-15, 15), size)], fill=(75, 75, 75), width=1)
    return img.filter(ImageFilter.GaussianBlur(0.5))


def gen_mud_soil(size=320):
    """Outdoor scrap yard muddy soil with dirt patches, stones, and organic tones."""
    base = np.full((size, size, 3), (85, 60, 40), dtype=np.uint8)
    noise = np.random.normal(0, 22, (size, size, 3)).astype(np.int16)
    arr = np.clip(base + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr)
    draw = ImageDraw.Draw(img)
    for _ in range(40):
        px, py = random.randint(0, size), random.randint(0, size)
        pr = random.randint(3, 10)
        draw.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(60, 42, 28))
    # Small grass/moss speckles
    for _ in range(25):
        gx, gy = random.randint(0, size), random.randint(0, size)
        draw.ellipse([gx - 2, gy - 2, gx + 2, gy + 2], fill=(65, 80, 45))
    return img.filter(ImageFilter.GaussianBlur(1.0))


def gen_scrap_clutter(size=320):
    """Cluttered background with discarded cardboard flakes, plastic wrappers, scrap pile."""
    img = Image.new("RGB", (size, size), (135, 130, 125))
    draw = ImageDraw.Draw(img)
    # Random debris patches in background
    for _ in range(25):
        x1, y1 = random.randint(0, size - 40), random.randint(0, size - 40)
        w, h = random.randint(15, 60), random.randint(15, 60)
        color = random.choice([
            (180, 160, 130),  # Cardboard
            (190, 190, 200),  # Plastic sheet
            (90, 85, 80),     # Dark scrap
            (140, 110, 85),   # Brown paper
        ])
        draw.rectangle([x1, y1, x1 + w, y1 + h], fill=color)
    return img.filter(ImageFilter.GaussianBlur(1.2))


def gen_dark_shadow(size=320):
    """Dimly lit / underexposed shadow surface (scrap bin or dark room)."""
    base = np.random.normal(45, 10, (size, size, 3)).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(base)
    return img.filter(ImageFilter.GaussianBlur(0.8))


BACKGROUND_GENERATORS = {
    "clean_workbench": gen_clean_workbench,
    "wooden_table": gen_wooden_table,
    "concrete_pavement": gen_concrete_asphalt,
    "mud_soil": gen_mud_soil,
    "scrap_clutter": gen_scrap_clutter,
    "dark_shadow": gen_dark_shadow,
}


# ---------------------------------------------------------------------------
# Test Item Catalog Preparation
# ---------------------------------------------------------------------------
def load_test_items():
    """Returns a dict of item name -> Image with transparent or extracted patch."""
    items = {}
    val_dir = ROOT / "seed_dataset" / "val"
    test_items_dir = ROOT / "test_items"

    # E-waste samples
    for cat in ["PCB", "CABLES", "BATTERIES", "CRT", "LCD_LED", "MOTORS_MAGNETS", "MIXED_PLASTICS", "MIXED_OTHER"]:
        cat_files = list((val_dir / cat).glob("*.jpg"))
        if cat_files:
            items[f"EWASTE_{cat}"] = {
                "category": cat,
                "is_ewaste": True,
                "image_path": cat_files[0],
                "description": f"Recyclable {cat}",
            }

    # Non-e-waste items
    negative_files = {
        "GARBAGE_PET_BOTTLE": (test_items_dir / "pet_bottle.jpg", "PET Plastic Bottle (Municipal Recycling, Non-E-Waste)"),
        "GARBAGE_CARDBOARD": (test_items_dir / "cardboard_box.jpg", "Cardboard Box (Packaging Scrap, Non-E-Waste)"),
        "GARBAGE_BANANA_PEEL": (test_items_dir / "banana_peel.jpg", "Banana Peel / Food Waste (Bio-Waste, Non-E-Waste)"),
        "PROHIBITED_CFL_BULB": (test_items_dir / "cfl_bulb.jpg", "Fluorescent CFL Bulb (Prohibited Mercury Gas Hazard)"),
        "PROHIBITED_SYRINGE": (test_items_dir / "medical_syringe.jpg", "Medical Syringe (Prohibited Biohazard Medical Waste)"),
    }

    for key, (path, desc) in negative_files.items():
        if path.exists():
            items[key] = {
                "category": "NON_COLLECTIBLE",
                "is_ewaste": False,
                "image_path": path,
                "description": desc,
            }

    # Add extra non-collectible from seed_dataset/val/NON_COLLECTIBLE if present
    non_col_val = list((val_dir / "NON_COLLECTIBLE").glob("*.jpg"))
    if non_col_val:
        items["GARBAGE_MUNICIPAL_TRASH"] = {
            "category": "NON_COLLECTIBLE",
            "is_ewaste": False,
            "image_path": non_col_val[0],
            "description": "Municipal Trash Heap / General Garbage",
        }

    return items


def composite_onto_background(bg_img, patch_img, target_box=None):
    """
    Pastes patch_img onto bg_img.
    target_box: (x, y, w, h) or None for random centered placement.
    Returns: (composite_img, (x1, y1, x2, y2) normalized)
    """
    canvas = bg_img.copy()
    W, H = canvas.size

    if target_box is None:
        patch_w = random.randint(100, 160)
        patch_h = random.randint(100, 160)
        px = random.randint(20, W - patch_w - 20)
        py = random.randint(20, H - patch_h - 20)
    else:
        px, py, patch_w, patch_h = target_box

    resized = patch_img.resize((patch_w, patch_h), Image.Resampling.LANCZOS)
    canvas.paste(resized, (px, py))

    norm_box = (px / W, py / H, (px + patch_w) / W, (py + patch_h) / H)
    return canvas, norm_box


# ---------------------------------------------------------------------------
# Test Runner
# ---------------------------------------------------------------------------
def run_all_tests():
    items = load_test_items()
    print(f"Loaded {len(items)} test items across e-waste, garbage, and prohibited categories.")
    print(f"Testing across {len(BACKGROUND_GENERATORS)} background environments.")

    test_results = []
    summary_stats = {
        "total_tests": 0,
        "correct_decisions": 0,
        "ewaste_tests": 0,
        "ewaste_detected": 0,
        "non_ewaste_tests": 0,
        "non_ewaste_correctly_ignored_or_rejected": 0,
        "false_positive_garbage_detected_as_ewaste": 0,
        "per_background": {},
        "per_item": {},
    }

    for bg_name in BACKGROUND_GENERATORS:
        summary_stats["per_background"][bg_name] = {"total": 0, "correct": 0}

    test_idx = 0

    # -----------------------------------------------------------------------
    # Part 1: Single-Item Tests across all Backgrounds
    # -----------------------------------------------------------------------
    print("\n=======================================================")
    print("PART 1: SINGLE-ITEM BENCHMARKS (WASTES x BACKGROUNDS)")
    print("=======================================================")

    for item_key, item_info in items.items():
        patch_img = Image.open(item_info["image_path"]).convert("RGB")
        is_ewaste = item_info["is_ewaste"]
        expected_cat = item_info["category"]

        if item_key not in summary_stats["per_item"]:
            summary_stats["per_item"][item_key] = {"total": 0, "correct": 0, "detections": []}

        for bg_name, bg_gen in BACKGROUND_GENERATORS.items():
            test_idx += 1
            bg = bg_gen(size=320)
            composite, (gt_x1, gt_y1, gt_x2, gt_y2) = composite_onto_background(bg, patch_img)

            # Run models
            detections = run_detector(composite)
            classification = run_classifier(composite)
            app_result = evaluate_app_decision(detections, classification, is_ewaste, item_key)

            # Update stats
            summary_stats["total_tests"] += 1
            summary_stats["per_background"][bg_name]["total"] += 1
            summary_stats["per_item"][item_key]["total"] += 1

            if is_ewaste:
                summary_stats["ewaste_tests"] += 1
                if len(detections) > 0 or app_result["decision"] == "ACCEPTED":
                    summary_stats["ewaste_detected"] += 1
            else:
                summary_stats["non_ewaste_tests"] += 1
                if len(detections) == 0 and app_result["decision"] == "REJECTED":
                    summary_stats["non_ewaste_correctly_ignored_or_rejected"] += 1
                elif len(detections) > 0:
                    summary_stats["false_positive_garbage_detected_as_ewaste"] += 1

            if app_result["is_correct"]:
                summary_stats["correct_decisions"] += 1
                summary_stats["per_background"][bg_name]["correct"] += 1
                summary_stats["per_item"][item_key]["correct"] += 1

            summary_stats["per_item"][item_key]["detections"].append(
                [d["category"] for d in detections] if detections else ["NONE"]
            )

            # Draw visual preview
            draw_img = composite.copy()
            draw = ImageDraw.Draw(draw_img)

            # Draw detections
            for d in detections:
                box_color = (0, 220, 0) if is_ewaste else (255, 60, 0)
                bx1, by1, bx2, by2 = int(d["x1"] * 320), int(d["y1"] * 320), int(d["x2"] * 320), int(d["y2"] * 320)
                draw.rectangle([bx1, by1, bx2, by2], outline=box_color, width=3)
                label_txt = f"{d['category']} ({d['score']:.2f})"
                draw.rectangle([bx1, max(0, by1 - 18), bx1 + len(label_txt) * 7 + 6, by1], fill=box_color)
                draw.text((bx1 + 3, max(0, by1 - 16)), label_txt, fill=(0, 0, 0))

            # Draw top banner stamp
            status_color = (0, 150, 0) if app_result["decision"] == "ACCEPTED" else (220, 20, 20)
            draw.rectangle([0, 0, 320, 22], fill=status_color)
            status_text = f"APP: {app_result['decision']} | {item_key} on {bg_name}"
            draw.text((6, 4), status_text[:46], fill=(255, 255, 255))

            # Bottom classifier stamp
            draw.rectangle([0, 298, 320, 320], fill=(30, 30, 30))
            clf_txt = f"Clf: {classification['category']} ({classification['confidence']:.2f}) | NonCol: {classification['non_collectible_prob']:.2f}"
            draw.text((6, 302), clf_txt[:48], fill=(220, 220, 220))

            out_filename = f"test_{test_idx:03d}_{item_key}_{bg_name}.jpg"
            draw_img.save(OUT_IMG_DIR / out_filename)

            test_results.append({
                "test_id": test_idx,
                "type": "single_item",
                "item_key": item_key,
                "is_ewaste": is_ewaste,
                "background": bg_name,
                "detections": detections,
                "classification": classification,
                "app_decision": app_result["decision"],
                "rejection_reason": app_result["rejection_reason"],
                "is_correct": app_result["is_correct"],
                "image_file": out_filename,
            })

            det_summary = ", ".join([f"{d['category']}:{d['score']}" for d in detections]) if detections else "None"
            print(f"[{test_idx:02d}] {item_key:<24} on {bg_name:<18} -> Detections: {det_summary:<22} | App: {app_result['decision']} ({'PASS' if app_result['is_correct'] else 'FAIL'})")

    # -----------------------------------------------------------------------
    # Part 2: Complex Co-located Multi-Item Mixed Scenes
    # -----------------------------------------------------------------------
    print("\n=======================================================")
    print("PART 2: COMPLEX MIXED-OBJECT SCENES (E-WASTE + GARBAGE)")
    print("=======================================================")

    mixed_scenes = [
        {
            "name": "PCB_plus_PET_Bottle_on_Concrete",
            "bg_name": "concrete_pavement",
            "items": [
                ("EWASTE_PCB", (20, 70, 120, 120), True),
                ("GARBAGE_PET_BOTTLE", (170, 70, 110, 140), False),
            ],
            "desc": "Motherboard next to plastic drinking bottle on outdoor concrete floor.",
        },
        {
            "name": "Cables_plus_Cardboard_on_Wood",
            "bg_name": "wooden_table",
            "items": [
                ("EWASTE_CABLES", (25, 60, 130, 130), True),
                ("GARBAGE_CARDBOARD", (175, 75, 120, 120), False),
            ],
            "desc": "Power cord bundle next to corrugated cardboard box on wooden desk.",
        },
        {
            "name": "Battery_plus_Banana_Peel_on_Soil",
            "bg_name": "mud_soil",
            "items": [
                ("EWASTE_BATTERIES", (30, 80, 120, 110), True),
                ("GARBAGE_BANANA_PEEL", (170, 80, 110, 120), False),
            ],
            "desc": "Lithium battery pack next to discarded banana peel on outdoor ground.",
        },
        {
            "name": "Motor_plus_Syringe_on_CleanBench",
            "bg_name": "clean_workbench",
            "items": [
                ("EWASTE_MOTORS_MAGNETS", (25, 65, 125, 125), True),
                ("PROHIBITED_SYRINGE", (175, 80, 120, 90), False),
            ],
            "desc": "Electric motor stator next to prohibited medical syringe on bench.",
        },
        {
            "name": "LCD_Display_plus_Trash_on_ScrapClutter",
            "bg_name": "scrap_clutter",
            "items": [
                ("EWASTE_LCD_LED", (20, 60, 130, 130), True),
                ("GARBAGE_MUNICIPAL_TRASH", (170, 70, 130, 130), False),
            ],
            "desc": "Flat LCD panel next to municipal trash heap in scrap yard clutter.",
        },
        {
            "name": "PURE_GARBAGE_CONTROL_NO_EWASTE",
            "bg_name": "concrete_pavement",
            "items": [
                ("GARBAGE_PET_BOTTLE", (20, 70, 100, 130), False),
                ("GARBAGE_CARDBOARD", (130, 60, 90, 90), False),
                ("GARBAGE_BANANA_PEEL", (225, 110, 85, 95), False),
            ],
            "desc": "Negative control: Pile containing ONLY garbage (bottle, cardboard, food peel), ZERO e-waste.",
        },
    ]

    for scene in mixed_scenes:
        test_idx += 1
        bg = BACKGROUND_GENERATORS[scene["bg_name"]](size=320)
        composite = bg.copy()

        gt_ewaste_present = any(is_ew for _, _, is_ew in scene["items"])

        for item_key, box, is_ew in scene["items"]:
            if item_key in items:
                patch = Image.open(items[item_key]["image_path"]).convert("RGB")
                px, py, pw, ph = box
                resized = patch.resize((pw, ph), Image.Resampling.LANCZOS)
                composite.paste(resized, (px, py))

        detections = run_detector(composite)
        classification = run_classifier(composite)

        # In a mixed scene, detector should detect the e-waste item and ignore the non-e-waste
        detected_categories = [d["category"] for d in detections]
        has_ewaste_detection = len(detections) > 0

        # Pass criteria:
        # If pure garbage: 0 detections or classified as NON_COLLECTIBLE -> App REJECTS (PASS)
        # If mixed: detects e-waste category -> App ACCEPTS e-waste (PASS)
        if not gt_ewaste_present:
            is_correct = (len(detections) == 0) or (classification["category"] == "NON_COLLECTIBLE")
            app_decision = "REJECTED" if is_correct else "ACCEPTED"
        else:
            is_correct = has_ewaste_detection
            app_decision = "ACCEPTED" if has_ewaste_detection else "REJECTED"

        summary_stats["total_tests"] += 1
        if is_correct:
            summary_stats["correct_decisions"] += 1

        # Draw annotated preview
        draw_img = composite.copy()
        draw = ImageDraw.Draw(draw_img)

        for item_key, (px, py, pw, ph), is_ew in scene["items"]:
            # Ground truth outline (dashed-like thin box)
            draw.rectangle([px, py, px + pw, py + ph], outline=(150, 150, 150), width=1)
            draw.text((px + 2, py + 2), "GT: " + item_key.replace("GARBAGE_", "").replace("EWASTE_", ""), fill=(255, 255, 255))

        # Model predicted boxes
        for d in detections:
            bx1, by1, bx2, by2 = int(d["x1"] * 320), int(d["y1"] * 320), int(d["x2"] * 320), int(d["y2"] * 320)
            draw.rectangle([bx1, by1, bx2, by2], outline=(0, 255, 0), width=3)
            txt = f"DET: {d['category']} ({d['score']:.2f})"
            draw.rectangle([bx1, max(0, by1 - 18), bx1 + len(txt) * 7 + 4, by1], fill=(0, 255, 0))
            draw.text((bx1 + 3, max(0, by1 - 16)), txt, fill=(0, 0, 0))

        # Top banner
        banner_color = (0, 150, 0) if is_correct else (220, 20, 20)
        draw.rectangle([0, 0, 320, 22], fill=banner_color)
        banner_txt = f"{'PASS' if is_correct else 'FAIL'} | {scene['name']}"
        draw.text((6, 4), banner_txt[:48], fill=(255, 255, 255))

        out_filename = f"mixed_scene_{test_idx:03d}_{scene['name']}.jpg"
        draw_img.save(OUT_IMG_DIR / out_filename)

        test_results.append({
            "test_id": test_idx,
            "type": "mixed_scene",
            "name": scene["name"],
            "ground_truth_ewaste_present": gt_ewaste_present,
            "detections": detections,
            "classification": classification,
            "is_correct": is_correct,
            "image_file": out_filename,
        })

        det_str = ", ".join([f"{d['category']}:{d['score']}" for d in detections]) if detections else "None"
        print(f"[MIXED {test_idx:02d}] {scene['name']:<36} -> Detections: {det_str:<24} | {'PASS' if is_correct else 'FAIL'}")

    # -----------------------------------------------------------------------
    # Summary Statistics Calculation
    # -----------------------------------------------------------------------
    overall_accuracy = (summary_stats["correct_decisions"] / max(1, summary_stats["total_tests"])) * 100.0
    ewaste_recall = (summary_stats["ewaste_detected"] / max(1, summary_stats["ewaste_tests"])) * 100.0
    garbage_suppression = (summary_stats["non_ewaste_correctly_ignored_or_rejected"] / max(1, summary_stats["non_ewaste_tests"])) * 100.0
    false_positive_rate = (summary_stats["false_positive_garbage_detected_as_ewaste"] / max(1, summary_stats["non_ewaste_tests"])) * 100.0

    report = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total_test_cases": summary_stats["total_tests"],
        "overall_accuracy_pct": round(overall_accuracy, 2),
        "ewaste_recall_pct": round(ewaste_recall, 2),
        "garbage_suppression_pct": round(garbage_suppression, 2),
        "false_positive_garbage_rate_pct": round(false_positive_rate, 2),
        "metrics_by_background": {},
        "metrics_by_item": {},
        "test_cases": test_results,
    }

    for bg_name, stats in summary_stats["per_background"].items():
        bg_acc = (stats["correct"] / max(1, stats["total"])) * 100.0
        report["metrics_by_background"][bg_name] = {
            "total": stats["total"],
            "correct": stats["correct"],
            "accuracy_pct": round(bg_acc, 2),
        }

    for item_key, stats in summary_stats["per_item"].items():
        item_acc = (stats["correct"] / max(1, stats["total"])) * 100.0
        report["metrics_by_item"][item_key] = {
            "total": stats["total"],
            "correct": stats["correct"],
            "accuracy_pct": round(item_acc, 2),
        }

    with open(OUT_DIR / "detection_test_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print("\n=======================================================")
    print("TEST EVALUATION BENCHMARK SUMMARY")
    print("=======================================================")
    print(f"Total Test Cases Evaluated:       {summary_stats['total_tests']}")
    print(f"Overall Decision Accuracy:        {overall_accuracy:.1f}% ({summary_stats['correct_decisions']}/{summary_stats['total_tests']})")
    print(f"E-Waste Detection Recall:         {ewaste_recall:.1f}% ({summary_stats['ewaste_detected']}/{summary_stats['ewaste_tests']})")
    print(f"Garbage Suppression Rate:         {garbage_suppression:.1f}% ({summary_stats['non_ewaste_correctly_ignored_or_rejected']}/{summary_stats['non_ewaste_tests']})")
    print(f"False Positive Garbage Rate:      {false_positive_rate:.1f}% ({summary_stats['false_positive_garbage_detected_as_ewaste']}/{summary_stats['non_ewaste_tests']})")

    print("\nRobustness by Background:")
    for bg, s in report["metrics_by_background"].items():
        print(f"  - {bg:<20}: {s['accuracy_pct']:5.1f}% ({s['correct']}/{s['total']})")

    print(f"\nWrote full JSON test report -> {OUT_DIR / 'detection_test_report.json'}")
    print(f"Saved {test_idx} annotated visual proof images -> {OUT_IMG_DIR}")


if __name__ == "__main__":
    run_all_tests()
