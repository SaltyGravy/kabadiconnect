"""
KabadiConnect - Synthetic seed image dataset generator.

LIMITATION (read this before treating the classifier as production-grade):
We do not have access to a real photographed e-waste image corpus for this
build session. Real field photos (per category, varied lighting/background,
captured by the two field-research collectors) are required before this
model can be trusted for real classification. What this script produces is
a small PROCEDURALLY GENERATED, visually-separable placeholder dataset
(shapes/colors/textures loosely evocative of each material category) whose
only purpose is to let the training/export/on-device-inference PIPELINE be
built and demonstrated end-to-end. Accuracy on this synthetic set says
nothing about real-world accuracy.

Source: procedurally generated with Pillow, seed=42.
Size: 8 categories x (train 70 + val 15) = 680 images, 160x160 RGB.
Quality: synthetic placeholder only, NOT photographic.
"""
import random
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

random.seed(42)

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "seed_dataset"
IMG_SIZE = 160
PER_CLASS_TRAIN = 70
PER_CLASS_VAL = 15

CATEGORIES = ["CRT", "LCD_LED", "PCB", "CABLES", "BATTERIES", "MOTORS_MAGNETS", "MIXED_PLASTICS", "MIXED_OTHER"]


def bg(draw, size, base_color, jitter=18):
    r, g, b = base_color
    for y in range(0, size, 4):
        shade = random.randint(-jitter, jitter)
        draw.line([(0, y), (size, y)], fill=(
            max(0, min(255, r + shade)),
            max(0, min(255, g + shade)),
            max(0, min(255, b + shade)),
        ), width=4)


def draw_crt(d, s):
    bg(d, s, (40, 42, 46))
    m = s * 0.12
    d.rounded_rectangle([m, m, s - m, s - m * 1.3], radius=s * 0.08, fill=(28, 28, 30), outline=(70, 70, 75), width=3)
    d.rectangle([m * 1.6, m * 1.6, s - m * 1.6, s - m * 2.1], fill=(10, 12, 20))
    d.rectangle([m, s - m * 1.3, s - m, s - m * 0.6], fill=(35, 36, 40))


def draw_lcd(d, s):
    bg(d, s, (15, 15, 18))
    m = s * 0.08
    d.rectangle([m, m, s - m, s - m], fill=(5, 5, 8), outline=(90, 90, 95), width=2)
    for i in range(6):
        x = m + (s - 2 * m) * i / 6
        d.line([(x, m), (x, s - m)], fill=(30, 30, 60), width=1)


def draw_pcb(d, s):
    bg(d, s, (20, 90, 45))
    for _ in range(10):
        x1, y1 = random.uniform(0, s), random.uniform(0, s)
        x2, y2 = x1 + random.uniform(-40, 40), y1 + random.uniform(-40, 40)
        d.line([(x1, y1), (x2, y2)], fill=(200, 170, 90), width=random.choice([2, 3]))
    for _ in range(14):
        x, y = random.uniform(10, s - 10), random.uniform(10, s - 10)
        r = random.uniform(3, 6)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(180, 150, 70))
    d.rectangle([s * 0.35, s * 0.35, s * 0.65, s * 0.65], fill=(15, 15, 15), outline=(90, 90, 90))


def draw_cables(d, s):
    bg(d, s, (25, 25, 28))
    colors = [(200, 60, 50), (60, 130, 200), (230, 200, 60), (60, 180, 90), (200, 200, 200)]
    for _ in range(9):
        c = random.choice(colors)
        x, y = random.uniform(0, s), random.uniform(0, s)
        pts = [(x, y)]
        for _ in range(5):
            x += random.uniform(-25, 25)
            y += random.uniform(-25, 25)
            pts.append((x, y))
        d.line(pts, fill=c, width=random.randint(4, 8), joint="curve")


def draw_batteries(d, s):
    bg(d, s, (30, 30, 34))
    for i in range(3):
        x = s * 0.2 + i * s * 0.28
        d.rounded_rectangle([x, s * 0.15, x + s * 0.2, s * 0.85], radius=8,
                             fill=random.choice([(40, 120, 60), (180, 60, 50), (60, 60, 190)]),
                             outline=(200, 200, 200), width=2)
        d.rectangle([x + s * 0.04, s * 0.1, x + s * 0.16, s * 0.17], fill=(210, 210, 60))


def draw_motors(d, s):
    bg(d, s, (35, 35, 38))
    cx, cy = s / 2, s / 2
    d.ellipse([cx - s * 0.35, cy - s * 0.35, cx + s * 0.35, cy + s * 0.35], fill=(150, 150, 155), outline=(60, 60, 60), width=3)
    d.ellipse([cx - s * 0.12, cy - s * 0.12, cx + s * 0.12, cy + s * 0.12], fill=(90, 60, 30))
    for ang in range(0, 360, 45):
        x = cx + s * 0.3 * math.cos(math.radians(ang))
        y = cy + s * 0.3 * math.sin(math.radians(ang))
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(200, 170, 90))


def draw_plastics(d, s):
    bg(d, s, (60, 60, 60))
    colors = [(220, 220, 225), (40, 40, 45), (200, 100, 40), (80, 130, 200)]
    for _ in range(5):
        c = random.choice(colors)
        x, y = random.uniform(10, s - 40), random.uniform(10, s - 40)
        w, h = random.uniform(30, 70), random.uniform(20, 50)
        d.rounded_rectangle([x, y, x + w, y + h], radius=6, fill=c, outline=(20, 20, 20))


def draw_mixed(d, s):
    bg(d, s, (45, 45, 48))
    drawers = [draw_pcb, draw_cables, draw_plastics, draw_motors]
    for _ in range(3):
        fn = random.choice(drawers)
        tmp = Image.new("RGB", (s, s))
        td = ImageDraw.Draw(tmp)
        fn(td, s)
        d.bitmap((0, 0), tmp.convert("1"), fill=None) if False else None
    # simpler: just layer a couple of category sketches with transparency-ish overdraw
    for fn in random.sample(drawers, 2):
        fn(d, s)


DRAWERS = {
    "CRT": draw_crt, "LCD_LED": draw_lcd, "PCB": draw_pcb, "CABLES": draw_cables,
    "BATTERIES": draw_batteries, "MOTORS_MAGNETS": draw_motors,
    "MIXED_PLASTICS": draw_plastics, "MIXED_OTHER": draw_mixed,
}


def make_image(category):
    img = Image.new("RGB", (IMG_SIZE, IMG_SIZE), (30, 30, 30))
    d = ImageDraw.Draw(img)
    DRAWERS[category](d, IMG_SIZE)
    if random.random() > 0.5:
        img = img.rotate(random.uniform(-12, 12), fillcolor=(30, 30, 30))
    img = img.filter(ImageFilter.GaussianBlur(radius=random.uniform(0, 0.8)))
    return img


def main():
    manifest = []
    for cat in CATEGORIES:
        for split, count in (("train", PER_CLASS_TRAIN), ("val", PER_CLASS_VAL)):
            d = OUT / split / cat
            d.mkdir(parents=True, exist_ok=True)
            for i in range(count):
                img = make_image(cat)
                fname = f"{cat}_{split}_{i:03d}.png"
                img.save(d / fname)
                manifest.append((split, cat, fname))
    print(f"generated {len(manifest)} synthetic images -> {OUT}")


if __name__ == "__main__":
    main()
