"""
KabadiConnect - Fast Concurrent Internet Image Downloader for E-Waste Training.

Uses ThreadPoolExecutor to download images in parallel with strict timeouts.
Covers:
  - BATTERIES
  - CABLES
  - CRT
  - LCD_LED
  - PCB
  - MOTORS_MAGNETS
  - MIXED_PLASTICS
  - MIXED_OTHER
  - NON_COLLECTIBLE (negative rejection class: garbage, bottles, clothes, furniture)
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import io
import json
import random
import time
import urllib.parse
from pathlib import Path

from PIL import Image, ImageFile
import requests

ImageFile.LOAD_TRUNCATED_IMAGES = True

ROOT = Path(__file__).resolve().parent
SEED_DIR = ROOT / "seed_dataset"
TRAIN_DIR = SEED_DIR / "train"
VAL_DIR = SEED_DIR / "val"

MIN_SIDE = 100
VAL_FRACTION = 0.15
TARGET_IMAGES_PER_CLASS = 220

HEADERS = {
    "User-Agent": "KabadiConnectML/2.0 (E-Waste Recycling Platform; contact@kabadiconnect.org)"
}

CATEGORY_QUERIES = {
    "BATTERIES": [
        "lithium battery recycling",
        "18650 battery cell",
        "lead-acid battery scrap",
        "laptop battery pack",
        "car battery scrap",
        "button cell battery",
        "power bank battery teardown",
        "battery pack disassembled",
    ],
    "CABLES": [
        "copper wire scrap",
        "electric cables scrap",
        "power cord ewaste",
        "usb cable scrap",
        "wire bundle recycling",
        "network cable scrap",
        "electrical wiring harness scrap",
    ],
    "CRT": [
        "cathode ray tube tv",
        "crt monitor scrap",
        "old television crt",
        "crt tv dismantled",
        "vintage crt television",
        "crt tube glass scrap",
        "broken crt monitor",
    ],
    "LCD_LED": [
        "broken lcd screen",
        "flat screen tv panel",
        "laptop screen display scrap",
        "lcd panel backlight scrap",
        "led tv screen recycling",
        "computer monitor lcd scrap",
        "smartphone screen scrap",
    ],
    "PCB": [
        "printed circuit board scrap",
        "computer motherboard recycling",
        "circuit board pcb green",
        "computer ram memory scrap",
        "graphics card scrap",
        "computer processor cpu scrap",
        "electronic circuit board waste",
    ],
    "MOTORS_MAGNETS": [
        "electric motor scrap",
        "neodymium magnet hard drive",
        "speaker magnet scrap",
        "copper winding electric motor stator",
        "dc motor scrap electronics",
        "fan motor scrap",
        "hard drive magnet teardown",
    ],
    "MIXED_PLASTICS": [
        "electronic plastic casing scrap",
        "computer monitor plastic shell",
        "shredded ewaste plastic",
        "printer plastic casing scrap",
        "appliance plastic housing scrap",
        "keyboard plastic scrap",
    ],
    "MIXED_OTHER": [
        "electronic waste pile scrap",
        "ewaste scrap recycling heap",
        "weee waste heap electronics",
        "mixed electronic scrap junk",
        "old electronics junk pile",
        "assorted electronic waste",
        "obsolete electronics scrap yard",
        "e-waste recycling bin mixed",
    ],
    "NON_COLLECTIBLE": [
        "plastic water bottle garbage",
        "food waste organic trash",
        "cardboard box pile trash",
        "used clothes fabric waste",
        "discarded wooden furniture",
        "crumpled paper garbage",
        "glass bottle waste",
        "household trash bag garbage",
        "rubber tire waste",
        "styrofoam packaging waste",
    ],
}

WIKIMEDIA_CATEGORIES = {
    "BATTERIES": ["Lithium-ion batteries", "Batteries", "Lead-acid batteries", "AA batteries"],
    "CABLES": ["Electric cables", "Cables", "Electrical wires", "Ethernet cables"],
    "CRT": ["Cathode ray tubes", "Cathode ray tube television sets", "CRT monitors"],
    "LCD_LED": ["Liquid crystal displays", "LCD monitors", "LED displays", "Flat panel displays"],
    "PCB": ["Printed circuit boards", "Motherboards", "Computer expansion cards", "Integrated circuits"],
    "MOTORS_MAGNETS": ["Electric motors", "Permanent magnets", "DC motors", "Neodymium magnets"],
    "MIXED_PLASTICS": ["Household plastics", "Waste plastics", "Plastic recycling", "Plastic waste"],
    "MIXED_OTHER": ["Electronic waste", "Waste of electrical and electronic equipment", "Discarded computers", "Scrapyards"],
    "NON_COLLECTIBLE": ["Plastic bottle waste", "Cardboard waste", "Municipal solid waste", "Food waste"],
}


def fetch_openverse_urls(query, limit=12, pages=2):
    urls = []
    for page in range(1, pages + 1):
        try:
            url = f"https://api.openverse.org/v1/images/?q={urllib.parse.quote(query)}&page_size={limit}&page={page}"
            r = requests.get(url, headers=HEADERS, timeout=(3.0, 6.0))
            if r.status_code == 200:
                data = r.json()
                for item in data.get("results", []):
                    u = item.get("url")
                    if u and any(u.lower().endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                        urls.append(u)
            elif r.status_code == 429:
                break  # rate-limited, stop paging this query
        except Exception:
            pass
    return urls


def fetch_wikimedia_category_urls(category, limit=15):
    urls = []
    try:
        url = "https://commons.wikimedia.org/w/api.php"
        params = {
            "action": "query",
            "generator": "categorymembers",
            "gcmtitle": f"Category:{category}",
            "gcmtype": "file",
            "gcmlimit": limit,
            "prop": "imageinfo",
            "iiprop": "url|mime",
            "format": "json",
        }
        r = requests.get(url, params=params, headers=HEADERS, timeout=(3.0, 6.0))
        if r.status_code == 200:
            pages = r.json().get("query", {}).get("pages", {})
            for _, p in pages.items():
                info = p.get("imageinfo", [{}])[0]
                mime = info.get("mime", "")
                if mime in ["image/jpeg", "image/png"]:
                    urls.append(info.get("url"))
    except Exception:
        pass
    return urls


def download_single_image(url):
    try:
        r = requests.get(url, headers=HEADERS, timeout=(3.0, 4.0))
        if r.status_code != 200 or len(r.content) < 4000:
            return None
        img = Image.open(io.BytesIO(r.content))
        img.load()
        if img.width < MIN_SIDE or img.height < MIN_SIDE:
            return None
        return img.convert("RGB")
    except Exception:
        return None


def get_existing_hashes():
    seen = set()
    for p in SEED_DIR.rglob("*.*"):
        if p.is_file() and p.suffix.lower() in [".jpg", ".jpeg", ".png"]:
            try:
                seen.add(hashlib.md5(p.read_bytes()).hexdigest())
            except Exception:
                pass
    return seen


def download_category_images(label, seen_hashes):
    train_dir = TRAIN_DIR / label
    val_dir = VAL_DIR / label
    train_dir.mkdir(parents=True, exist_ok=True)
    val_dir.mkdir(parents=True, exist_ok=True)

    # Count existing web images
    existing_web = list(train_dir.glob(f"{label}_web_*")) + list(val_dir.glob(f"{label}_web_*"))
    if len(existing_web) >= TARGET_IMAGES_PER_CLASS:
        print(f"[{label}] Already has {len(existing_web)} web images, skipping download.")
        return

    print(f"\n[{label}] Fetching candidate URLs from Openverse and Wikimedia...")
    candidate_urls = []
    for q in CATEGORY_QUERIES.get(label, []):
        candidate_urls.extend(fetch_openverse_urls(q, limit=30))

    for cat in WIKIMEDIA_CATEGORIES.get(label, []):
        candidate_urls.extend(fetch_wikimedia_category_urls(cat, limit=40))

    unique_urls = list(dict.fromkeys(candidate_urls))
    random.shuffle(unique_urls)
    print(f"[{label}] {len(unique_urls)} URLs found. Downloading concurrently...")

    needed = TARGET_IMAGES_PER_CLASS - len(existing_web)
    downloaded_images = []

    executor = ThreadPoolExecutor(max_workers=6)
    try:
        futures = {executor.submit(download_single_image, u): u for u in unique_urls}
        for future in as_completed(futures):
            if len(downloaded_images) >= needed:
                break
            img = future.result()
            if img is None:
                continue
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=88)
            digest = hashlib.md5(buf.getvalue()).hexdigest()
            if digest in seen_hashes:
                continue
            seen_hashes.add(digest)
            downloaded_images.append(img)
            print(f"  + saved image {len(downloaded_images)}/{needed} ({img.width}x{img.height})")
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    # If category is MIXED_OTHER, remove synthetic placeholder images
    if label == "MIXED_OTHER":
        for d in [train_dir, val_dir]:
            for f in d.glob("*.png"):
                f.unlink()

    if downloaded_images:
        n_val = max(1, int(round(len(downloaded_images) * VAL_FRACTION)))
        n_train = len(downloaded_images) - n_val
        train_imgs = downloaded_images[:n_train]
        val_imgs = downloaded_images[n_train:]

        for i, img in enumerate(train_imgs):
            ts = int(time.time())
            img.save(train_dir / f"{label}_web_train_{ts}_{i:03d}.jpg", quality=90)

        for i, img in enumerate(val_imgs):
            ts = int(time.time())
            img.save(val_dir / f"{label}_web_val_{ts}_{i:03d}.jpg", quality=90)

        print(f"[{label}] Added {len(train_imgs)} train and {len(val_imgs)} val images.")
    else:
        print(f"[{label}] 0 new images added.")


def main():
    random.seed(42)
    seen_hashes = get_existing_hashes()
    print(f"Starting downloader. {len(seen_hashes)} existing images in seed dataset.")

    for label in CATEGORY_QUERIES.keys():
        download_category_images(label, seen_hashes)
        time.sleep(8)  # back off between classes to avoid Openverse rate-limiting (429)

    print("\nAll downloads finished!")


if __name__ == "__main__":
    main()
