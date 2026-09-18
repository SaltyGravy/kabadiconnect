"""
KabadiConnect - multi-item material detector.

A from-scratch, single-anchor, single-scale YOLO-style detector: a
MobileNetV2 backbone (same convention as train_classifier.py) feeding a
10x10 grid, each cell predicting one box (objectness + box offsets) and a
material-category distribution. Trained on the synthetic composite dataset
built by generate_detection_dataset.py (see that file for why it's
synthetic -- no real multi-item photos exist for this project yet).

Output tensor per image: (10, 10, 13) raw logits =
  [objectness_logit, tx, ty, tw, th, class_logits(8)]
Decoding (sigmoid/exp/softmax + box math + NMS) happens on-device in Dart
(detector_service_mobile.dart), NOT baked into the exported model, exactly
like the classifier -- the model expects input already normalized to
[-1, 1], not raw 0-255 pixels.

Outputs:
  ml/artifacts/detector_metrics.json
  app/assets/ml/detector.tflite
  app/assets/ml/detector_labels.txt
  ml/artifacts/detector_val_preview/*.jpg  -- a handful of annotated val
    images for a quick human sanity check of box quality.
"""
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ML_DIR = ROOT / "ml"
DET_DIR = ML_DIR / "detection_dataset"
ARTIFACTS = ML_DIR / "artifacts"
ARTIFACTS.mkdir(exist_ok=True)
APP_ASSETS = ROOT / "app" / "assets" / "ml"
APP_ASSETS.mkdir(parents=True, exist_ok=True)

IMG_SIZE = 320
GRID = 10  # 320 / 32 (MobileNetV2 total stride)
ANCHOR_CELLS = 3.0  # fixed box-size prior, in grid-cell units
CATEGORIES = ["CRT", "LCD_LED", "PCB", "CABLES", "BATTERIES", "MOTORS_MAGNETS", "MIXED_PLASTICS", "MIXED_OTHER"]
NUM_CLASSES = len(CATEGORIES)
CHANNELS = 5 + NUM_CLASSES  # obj, tx,ty,tw,th, classes

BATCH = 16
EPOCHS = 30
LAMBDA_COORD = 5.0
LAMBDA_NOOBJ = 0.5


def load_split(split):
    records = json.load(open(DET_DIR / split / "annotations.json"))
    img_dir = DET_DIR / split / "images"
    images = np.zeros((len(records), IMG_SIZE, IMG_SIZE, 3), dtype=np.uint8)
    targets = np.zeros((len(records), GRID, GRID, CHANNELS), dtype=np.float32)
    for i, rec in enumerate(records):
        img = Image.open(img_dir / rec["image"]).convert("RGB").resize((IMG_SIZE, IMG_SIZE))
        images[i] = np.array(img)
        for box in rec["boxes"]:
            cx = (box["xmin"] + box["xmax"]) / 2 * GRID
            cy = (box["ymin"] + box["ymax"]) / 2 * GRID
            gx, gy = min(GRID - 1, int(cx)), min(GRID - 1, int(cy))
            w_cells = (box["xmax"] - box["xmin"]) * GRID
            h_cells = (box["ymax"] - box["ymin"]) * GRID
            targets[i, gy, gx, 0] = 1.0
            targets[i, gy, gx, 1] = cx - gx
            targets[i, gy, gx, 2] = cy - gy
            targets[i, gy, gx, 3] = np.log(max(w_cells, 1e-3) / ANCHOR_CELLS)
            targets[i, gy, gx, 4] = np.log(max(h_cells, 1e-3) / ANCHOR_CELLS)
            class_idx = CATEGORIES.index(box["category"])
            targets[i, gy, gx, 5 + class_idx] = 1.0
    return images, targets


def make_dataset(images, targets, shuffle):
    def normalize(img, target):
        img = tf.cast(img, tf.float32) / 127.5 - 1.0
        return img, target

    ds = tf.data.Dataset.from_tensor_slices((images, targets))
    if shuffle:
        ds = ds.shuffle(len(images), seed=42)
    return ds.map(normalize).batch(BATCH).prefetch(tf.data.AUTOTUNE)


def detector_loss(y_true, y_pred):
    obj_true = y_true[..., 0]
    obj_logit = y_pred[..., 0]
    obj_mask = obj_true
    noobj_mask = 1.0 - obj_true

    obj_bce = tf.nn.sigmoid_cross_entropy_with_logits(labels=obj_true, logits=obj_logit)
    obj_loss = tf.reduce_sum(obj_mask * obj_bce) + LAMBDA_NOOBJ * tf.reduce_sum(noobj_mask * obj_bce)

    tx_pred, ty_pred = tf.sigmoid(y_pred[..., 1]), tf.sigmoid(y_pred[..., 2])
    tw_pred, th_pred = y_pred[..., 3], y_pred[..., 4]
    tx_true, ty_true, tw_true, th_true = y_true[..., 1], y_true[..., 2], y_true[..., 3], y_true[..., 4]
    coord_loss = tf.reduce_sum(
        obj_mask * ((tx_pred - tx_true) ** 2 + (ty_pred - ty_true) ** 2 + (tw_pred - tw_true) ** 2 + (th_pred - th_true) ** 2)
    ) * LAMBDA_COORD

    cls_ce = tf.nn.softmax_cross_entropy_with_logits(labels=y_true[..., 5:], logits=y_pred[..., 5:])
    cls_loss = tf.reduce_sum(obj_mask * cls_ce)

    n = tf.maximum(tf.reduce_sum(obj_mask), 1.0)
    return (obj_loss + coord_loss + cls_loss) / n


def build_model():
    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    base = tf.keras.applications.MobileNetV2(input_shape=(IMG_SIZE, IMG_SIZE, 3), include_top=False, weights="imagenet")
    base.trainable = False
    feat = base(inputs, training=False)  # (None, GRID, GRID, 1280)
    head = tf.keras.layers.Conv2D(256, 3, padding="same", activation="relu")(feat)
    head = tf.keras.layers.Conv2D(CHANNELS, 1, padding="same")(head)
    return tf.keras.Model(inputs, head)


def decode_boxes(pred, obj_threshold=0.4):
    """pred: (GRID, GRID, CHANNELS) raw logits -> list of (score, class_idx, xmin,ymin,xmax,ymax) normalized."""
    boxes = []
    obj = 1 / (1 + np.exp(-pred[..., 0]))
    for gy in range(GRID):
        for gx in range(GRID):
            score = obj[gy, gx]
            if score < obj_threshold:
                continue
            tx, ty, tw, th = pred[gy, gx, 1:5]
            cx = (gx + 1 / (1 + np.exp(-tx))) / GRID
            cy = (gy + 1 / (1 + np.exp(-ty))) / GRID
            w = np.exp(tw) * ANCHOR_CELLS / GRID
            h = np.exp(th) * ANCHOR_CELLS / GRID
            class_logits = pred[gy, gx, 5:]
            class_idx = int(np.argmax(class_logits))
            boxes.append((float(score), class_idx, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2))
    boxes.sort(key=lambda b: -b[0])
    # simple greedy NMS
    kept = []
    for b in boxes:
        overlap = False
        for k in kept:
            ix1, iy1 = max(b[2], k[2]), max(b[3], k[3])
            ix2, iy2 = min(b[4], k[4]), min(b[5], k[5])
            inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
            area_b = (b[4] - b[2]) * (b[5] - b[3])
            area_k = (k[4] - k[2]) * (k[5] - k[3])
            iou = inter / max(1e-6, area_b + area_k - inter)
            if iou > 0.35:
                overlap = True
                break
        if not overlap:
            kept.append(b)
    return kept


def save_val_previews(model, images_uint8, n=8):
    out_dir = ARTIFACTS / "detector_val_preview"
    out_dir.mkdir(exist_ok=True)
    normalized = images_uint8[:n].astype(np.float32) / 127.5 - 1.0
    preds = model.predict(normalized, verbose=0)
    for i in range(n):
        img = Image.fromarray(images_uint8[i])
        draw = ImageDraw.Draw(img)
        for score, class_idx, x1, y1, x2, y2 in decode_boxes(preds[i]):
            draw.rectangle([x1 * IMG_SIZE, y1 * IMG_SIZE, x2 * IMG_SIZE, y2 * IMG_SIZE], outline=(255, 0, 0), width=3)
            draw.text((x1 * IMG_SIZE + 2, y1 * IMG_SIZE + 2), f"{CATEGORIES[class_idx]} {score:.2f}", fill=(255, 255, 0))
        img.save(out_dir / f"val_{i:02d}.jpg")
    print(f"wrote {n} annotated val previews -> {out_dir}")


def main():
    print("loading datasets...")
    train_images, train_targets = load_split("train")
    val_images, val_targets = load_split("val")
    print(f"train={len(train_images)} val={len(val_images)}")

    train_ds = make_dataset(train_images, train_targets, shuffle=True)
    val_ds = make_dataset(val_images, val_targets, shuffle=False)

    model = build_model()
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss=detector_loss)
    # The frozen-backbone head converges fast on this synthetic composite
    # data and then overfits it (val_loss climbs while train_loss keeps
    # dropping) -- stop at the best validation point instead of the last one.
    early_stop = tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=6, restore_best_weights=True)
    history = model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS, callbacks=[early_stop], verbose=2)

    metrics = {
        "grid": GRID,
        "anchor_cells": ANCHOR_CELLS,
        "classes": CATEGORIES,
        "epochs": EPOCHS,
        "train_loss_history": [round(float(v), 4) for v in history.history["loss"]],
        "val_loss_history": [round(float(v), 4) for v in history.history["val_loss"]],
        "dataset_note": (
            "Trained on a SYNTHETIC composite dataset (see generate_detection_dataset.py): "
            "real single-item photos pasted at random non-overlapping positions onto a "
            "generated background, 1-4 per image. No real multi-item pile photos exist in "
            "this project -- expect a real accuracy drop on messy real-world piles versus "
            "this synthetic validation set."
        ),
    }
    with open(ARTIFACTS / "detector_metrics.json", "w") as f:
        json.dump(metrics, f, indent=2)

    with open(APP_ASSETS / "detector_labels.txt", "w") as f:
        f.write("\n".join(CATEGORIES))

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    tflite_path = APP_ASSETS / "detector.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    print(f"wrote {tflite_path} ({tflite_path.stat().st_size / 1024:.0f} KB)")

    save_val_previews(model, val_images)


if __name__ == "__main__":
    main()
