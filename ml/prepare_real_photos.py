"""
KabadiConnect - fold real field photos into the seed dataset.

Reads the photos the user dropped into
`ml/seed_dataset/AI photos /<category folder>/` (loose image files, plus any
images pasted into a .docx), dedupes/filters junk, splits each category
85/15 into train/val, and REPLACES the synthetic placeholder images for that
category (see generate_seed_images.py) with the real ones.

Categories with no real photos supplied (MIXED_OTHER) are left untouched.

Run with the ml venv: `ml/.venv/bin/python3 ml/prepare_real_photos.py`
"""
import hashlib
import io
import random
import shutil
import zipfile
from pathlib import Path

from PIL import Image, ImageFile

ImageFile.LOAD_TRUNCATED_IMAGES = True

ROOT = Path(__file__).resolve().parent
SEED_DIR = ROOT / "seed_dataset"
SRC_DIR = SEED_DIR / "AI photos "

# source folder name -> label used in seed_dataset/{train,val}/<label>
FOLDER_TO_LABEL = {
    "Batteries ": "BATTERIES",
    "Cables and Wires ": "CABLES",
    "Circuit Board - PCB ": "PCB",
    "LCD - LED panel ": "LCD_LED",
    "Mixed Plastic ": "MIXED_PLASTICS",
    "Motors And Magnets ": "MOTORS_MAGNETS",
    "TV - Monitor ": "CRT",
}

LOOSE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
MIN_SIDE = 80  # drop tiny icons/watermarks that leak into bulk image downloads
VAL_FRACTION = 0.15
random.seed(42)


def iter_docx_images(docx_path: Path):
    try:
        with zipfile.ZipFile(docx_path) as z:
            for name in z.namelist():
                if name.startswith("word/media/"):
                    yield name, z.read(name)
    except zipfile.BadZipFile:
        print(f"  skip (not a valid docx): {docx_path}")


def collect_images(folder: Path):
    """Return list of PIL RGB images collected from loose files + embedded docx media."""
    images = []
    seen_hashes = set()

    def add(raw_bytes, source):
        digest = hashlib.md5(raw_bytes).hexdigest()
        if digest in seen_hashes:
            return
        try:
            img = Image.open(io.BytesIO(raw_bytes))
            img.load()
        except Exception as e:
            print(f"  unreadable ({source}): {e}")
            return
        if img.width < MIN_SIDE or img.height < MIN_SIDE:
            return
        seen_hashes.add(digest)
        images.append(img.convert("RGB"))

    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.name.startswith("~$"):
            continue
        ext = path.suffix.lower()
        if ext in LOOSE_EXTS:
            add(path.read_bytes(), str(path))
        elif ext == ".docx":
            for name, raw in iter_docx_images(path):
                add(raw, f"{path}:{name}")

    return images


def replace_category(label, images):
    train_count = int(round(len(images) * (1 - VAL_FRACTION)))
    shuffled = images[:]
    random.shuffle(shuffled)
    train_imgs, val_imgs = shuffled[:train_count], shuffled[train_count:]

    for split, imgs in (("train", train_imgs), ("val", val_imgs)):
        d = SEED_DIR / split / label
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True, exist_ok=True)
        for i, img in enumerate(imgs):
            img.save(d / f"{label}_real_{split}_{i:03d}.jpg", quality=90)

    return len(train_imgs), len(val_imgs)


def main():
    for folder_name, label in FOLDER_TO_LABEL.items():
        folder = SRC_DIR / folder_name
        if not folder.exists():
            print(f"[{label}] no source folder, skipping")
            continue
        images = collect_images(folder)
        if not images:
            print(f"[{label}] 0 usable images, leaving synthetic set untouched")
            continue
        n_train, n_val = replace_category(label, images)
        print(f"[{label}] {len(images)} real photos -> train={n_train} val={n_val}")

    print("MIXED_OTHER left as synthetic placeholder (no real photos supplied)")


if __name__ == "__main__":
    main()
