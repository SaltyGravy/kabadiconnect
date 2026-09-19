"""
KabadiConnect - Synthetic Multi-Item Detection Dataset Generator with Negative Distractors.

Enhancements:
1. Uses real internet photos + field photos across all 8 target e-waste categories:
   CRT, LCD_LED, PCB, CABLES, BATTERIES, MOTORS_MAGNETS, MIXED_PLASTICS, MIXED_OTHER.
2. Injects negative distractor patches from NON_COLLECTIBLE (plastic bottles, trash, paper,
   furniture) without bounding box annotations, explicitly training the detector to IGNORE
   non-e-waste items and ONLY detect the things we actually collect.
3. Realistic composite placement with non-overlapping bounding boxes.

Output:
  ml/detection_dataset/{train,val}/images/*.jpg
  ml/detection_dataset/{train,val}/annotations.json
"""
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw

random.seed(42)

ROOT = Path(__file__).resolve().parent
SEED_DIR = ROOT / "seed_dataset"
OUT_DIR = ROOT / "detection_dataset"
CANVAS_SIZE = 320
MIN_PATCH = 65
MAX_PATCH = 155
MAX_OVERLAP_FRACTION = 0.15
PLACEMENT_ATTEMPTS = 30

CATEGORIES = ["CRT", "LCD_LED", "PCB", "CABLES", "BATTERIES", "MOTORS_MAGNETS", "MIXED_PLASTICS", "MIXED_OTHER"]


def list_source_images(split):
    by_cat = {}
    for cat in CATEGORIES:
        d = SEED_DIR / split / cat
        by_cat[cat] = sorted(d.glob("*")) if d.exists() else []
    # Also load negative distractor images (things we DO NOT collect)
    non_col_dir = SEED_DIR / split / "NON_COLLECTIBLE"
    by_cat["_NON_COLLECTIBLE_"] = sorted(non_col_dir.glob("*")) if non_col_dir.exists() else []
    return by_cat


def random_background(size):
    base = (random.randint(50, 210), random.randint(50, 210), random.randint(50, 210))
    img = Image.new("RGB", (size, size), base)
    draw = ImageDraw.Draw(img)
    for _ in range(35):
        jitter = random.randint(-30, 30)
        x, y = random.randint(0, size), random.randint(0, size)
        r = random.randint(10, 60)
        shade = tuple(max(0, min(255, c + jitter)) for c in base)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=shade)
    return img


def boxes_overlap_fraction(box, others):
    x1, y1, x2, y2 = box
    area = max(1, (x2 - x1) * (y2 - y1))
    worst = 0.0
    for ox1, oy1, ox2, oy2 in others:
        ix1, iy1 = max(x1, ox1), max(y1, oy1)
        ix2, iy2 = min(x2, ox2), min(y2, oy2)
        if ix2 > ix1 and iy2 > iy1:
            inter = (ix2 - ix1) * (iy2 - iy1)
            worst = max(worst, inter / area)
    return worst


def make_composite(by_cat, num_items):
    canvas = random_background(CANVAS_SIZE)
    placed_boxes = []
    annotations = []

    # 1. Place target e-waste items (with ground truth annotations)
    categories = random.choices(CATEGORIES, k=num_items)
    for cat in categories:
        sources = by_cat.get(cat, [])
        if not sources:
            continue
        src_path = random.choice(sources)
        try:
            patch = Image.open(src_path).convert("RGB")
        except Exception:
            continue

        target = random.randint(MIN_PATCH, MAX_PATCH)
        w, h = patch.size
        scale = target / max(w, h)
        pw, ph = max(1, int(w * scale)), max(1, int(h * scale))
        patch = patch.resize((pw, ph))

        for _ in range(PLACEMENT_ATTEMPTS):
            x = random.randint(0, max(0, CANVAS_SIZE - pw))
            y = random.randint(0, max(0, CANVAS_SIZE - ph))
            box = (x, y, x + pw, y + ph)
            if boxes_overlap_fraction(box, placed_boxes) <= MAX_OVERLAP_FRACTION:
                canvas.paste(patch, (x, y))
                placed_boxes.append(box)
                annotations.append({
                    "category": cat,
                    "xmin": x / CANVAS_SIZE,
                    "ymin": y / CANVAS_SIZE,
                    "xmax": (x + pw) / CANVAS_SIZE,
                    "ymax": (y + ph) / CANVAS_SIZE,
                })
                break

    # 2. In 35% of images, inject 1 negative distractor patch (NOT ANNOTATED)
    # This explicitly teaches the detector to ignore ordinary trash and non-e-waste objects!
    distractor_sources = by_cat.get("_NON_COLLECTIBLE_", [])
    if distractor_sources and random.random() < 0.35:
        dist_path = random.choice(distractor_sources)
        try:
            d_patch = Image.open(dist_path).convert("RGB")
            target = random.randint(MIN_PATCH, MAX_PATCH)
            w, h = d_patch.size
            scale = target / max(w, h)
            pw, ph = max(1, int(w * scale)), max(1, int(h * scale))
            d_patch = d_patch.resize((pw, ph))

            for _ in range(PLACEMENT_ATTEMPTS):
                x = random.randint(0, max(0, CANVAS_SIZE - pw))
                y = random.randint(0, max(0, CANVAS_SIZE - ph))
                box = (x, y, x + pw, y + ph)
                if boxes_overlap_fraction(box, placed_boxes) <= MAX_OVERLAP_FRACTION:
                    canvas.paste(d_patch, (x, y))
                    placed_boxes.append(box)
                    # NOTE: Do NOT add to annotations! It's a negative distractor.
                    break
        except Exception:
            pass

    return canvas, annotations


def build_split(split, count):
    by_cat = list_source_images(split)
    img_dir = OUT_DIR / split / "images"
    img_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for i in range(count):
        num_items = random.choices([1, 2, 3, 4], weights=[0.25, 0.40, 0.25, 0.10])[0]
        canvas, boxes = make_composite(by_cat, num_items)
        if not boxes:
            continue
        fname = f"{i:05d}.jpg"
        canvas.save(img_dir / fname, quality=88)
        records.append({"image": fname, "boxes": boxes})
    with open(OUT_DIR / split / "annotations.json", "w") as f:
        json.dump(records, f)
    print(f"{split}: {len(records)} composite images generated -> {img_dir}")


def main():
    print("Building composite detection dataset with negative distractor augmentation...")
    build_split("train", 1200)
    build_split("val", 250)


if __name__ == "__main__":
    main()
