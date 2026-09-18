"""One-off: reload the exported detector.tflite and regenerate annotated val
previews with adjusted objectness/NMS thresholds, without retraining."""
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DET_DIR = ROOT / "ml" / "detection_dataset"
ARTIFACTS = ROOT / "ml" / "artifacts"
IMG_SIZE = 320
GRID = 10
ANCHOR_CELLS = 3.0
CATEGORIES = ["CRT", "LCD_LED", "PCB", "CABLES", "BATTERIES", "MOTORS_MAGNETS", "MIXED_PLASTICS", "MIXED_OTHER"]

OBJ_THRESHOLD = 0.42
IOU_THRESHOLD = 0.2


def decode_boxes(pred):
    boxes = []
    obj = 1 / (1 + np.exp(-pred[..., 0]))
    for gy in range(GRID):
        for gx in range(GRID):
            score = obj[gy, gx]
            if score < OBJ_THRESHOLD:
                continue
            tx, ty, tw, th = pred[gy, gx, 1:5]
            cx = (gx + 1 / (1 + np.exp(-tx))) / GRID
            cy = (gy + 1 / (1 + np.exp(-ty))) / GRID
            w = np.exp(tw) * ANCHOR_CELLS / GRID
            h = np.exp(th) * ANCHOR_CELLS / GRID
            class_idx = int(np.argmax(pred[gy, gx, 5:]))
            boxes.append((float(score), class_idx, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2))
    boxes.sort(key=lambda b: -b[0])
    kept = []
    for b in boxes:
        bcx, bcy = (b[2] + b[4]) / 2, (b[3] + b[5]) / 2
        overlap = False
        for k in kept:
            ix1, iy1 = max(b[2], k[2]), max(b[3], k[3])
            ix2, iy2 = min(b[4], k[4]), min(b[5], k[5])
            inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
            area_b = (b[4] - b[2]) * (b[5] - b[3])
            area_k = (k[4] - k[2]) * (k[5] - k[3])
            iou = inter / max(1e-6, area_b + area_k - inter)
            # A large object can make several adjacent grid cells fire on
            # (mostly) the same thing at slightly different offsets --
            # IoU alone can miss these since the boxes are offset rather
            # than concentric. If the weaker box's centre falls inside an
            # already-kept box of the SAME class, treat it as the same
            # object too.
            same_class_center_inside = b[1] == k[1] and k[2] <= bcx <= k[4] and k[3] <= bcy <= k[5]
            if iou > IOU_THRESHOLD or same_class_center_inside:
                overlap = True
                break
        if not overlap:
            kept.append(b)
    return kept


def main():
    interpreter = tf.lite.Interpreter(model_path=str(ROOT / "app" / "assets" / "ml" / "detector.tflite"))
    interpreter.allocate_tensors()
    in_idx = interpreter.get_input_details()[0]["index"]
    out_idx = interpreter.get_output_details()[0]["index"]

    records = json.load(open(DET_DIR / "val" / "annotations.json"))
    img_dir = DET_DIR / "val" / "images"
    out_dir = ARTIFACTS / "detector_val_preview_tuned"
    out_dir.mkdir(exist_ok=True)

    for i, rec in enumerate(records[:10]):
        img = Image.open(img_dir / rec["image"]).convert("RGB").resize((IMG_SIZE, IMG_SIZE))
        arr = np.array(img).astype(np.float32) / 127.5 - 1.0
        interpreter.set_tensor(in_idx, arr[np.newaxis, ...])
        interpreter.invoke()
        pred = interpreter.get_tensor(out_idx)[0]
        draw_img = img.copy()
        draw = ImageDraw.Draw(draw_img)
        for score, class_idx, x1, y1, x2, y2 in decode_boxes(pred):
            draw.rectangle([x1 * IMG_SIZE, y1 * IMG_SIZE, x2 * IMG_SIZE, y2 * IMG_SIZE], outline=(255, 0, 0), width=3)
            draw.text((x1 * IMG_SIZE + 2, y1 * IMG_SIZE + 2), f"{CATEGORIES[class_idx]} {score:.2f}", fill=(255, 255, 0))
        draw_img.save(out_dir / f"val_{i:02d}.jpg")
    print(f"wrote previews -> {out_dir}")


if __name__ == "__main__":
    main()
