"""
KabadiConnect - synthetic multi-item detection dataset generator.

We have real single-item photos (one material, roughly filling the frame --
see prepare_real_photos.py) but NO real photos of mixed piles with several
different materials in one frame, and no bounding-box annotations anywhere
in this project. Real object detection needs both.

This script builds that missing piece by composite/copy-paste augmentation:
take 1-4 real single-item photos (as whole rectangular patches, no
segmentation/cutout), paste them at random non-overlapping positions/scales
onto a synthetic background canvas, and record each patch's placement
rectangle as its ground-truth bounding box. It's an approximation -- real
photos of mixed piles would look more natural and give a better-calibrated
model -- but it lets a real detector (see train_detector.py) learn to find
and classify MULTIPLE items in one image using only the single-item photos
already collected.

Output: ml/detection_dataset/{train,val}/images/*.jpg plus one
ml/detection_dataset/{train,val}/annotations.json per split:
  [{"image": "0000.jpg", "boxes": [{"category": "CABLES", "xmin":.., "ymin":.., "xmax":.., "ymax":..}, ...]}, ...]
Boxes are normalized to [0,1] of the CANVAS_SIZE x CANVAS_SIZE canvas.
"""
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw

random.seed(7)

ROOT = Path(__file__).resolve().parent
SEED_DIR = ROOT / "seed_dataset"
OUT_DIR = ROOT / "detection_dataset"
CANVAS_SIZE = 320
MIN_PATCH = 70
MAX_PATCH = 160
MAX_OVERLAP_FRACTION = 0.15  # how much a new patch may overlap existing ones
PLACEMENT_ATTEMPTS = 25

CATEGORIES = ["CRT", "LCD_LED", "PCB", "CABLES", "BATTERIES", "MOTORS_MAGNETS", "MIXED_PLASTICS", "MIXED_OTHER"]


def list_source_images(split):
    by_cat = {}
    for cat in CATEGORIES:
        d = SEED_DIR / split / cat
        by_cat[cat] = sorted(d.glob("*")) if d.exists() else []
    return by_cat


def random_background(size):
    base = (random.randint(60, 200), random.randint(60, 200), random.randint(60, 200))
    img = Image.new("RGB", (size, size), base)
    draw = ImageDraw.Draw(img)
    for _ in range(40):
        jitter = random.randint(-25, 25)
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
        # Resize to a random target size, preserving aspect ratio.
        target = random.randint(MIN_PATCH, MAX_PATCH)
        w, h = patch.size
        scale = target / max(w, h)
        pw, ph = max(1, int(w * scale)), max(1, int(h * scale))
        patch = patch.resize((pw, ph))

        placed = False
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
                placed = True
                break
        # If we couldn't find a non-overlapping spot after PLACEMENT_ATTEMPTS,
        # just skip this item -- a composite with fewer items than requested
        # is fine, an unannotated overlapping blob is not.
        if not placed:
            continue
    return canvas, annotations


def build_split(split, count):
    by_cat = list_source_images(split)
    img_dir = OUT_DIR / split / "images"
    img_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for i in range(count):
        num_items = random.choices([1, 2, 3, 4], weights=[0.25, 0.35, 0.25, 0.15])[0]
        canvas, boxes = make_composite(by_cat, num_items)
        if not boxes:
            continue
        fname = f"{i:05d}.jpg"
        canvas.save(img_dir / fname, quality=88)
        records.append({"image": fname, "boxes": boxes})
    with open(OUT_DIR / split / "annotations.json", "w") as f:
        json.dump(records, f)
    print(f"{split}: {len(records)} composite images -> {img_dir}")


def main():
    build_split("train", 1600)
    build_split("val", 320)


if __name__ == "__main__":
    main()
