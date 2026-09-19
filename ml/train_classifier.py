"""
KabadiConnect - Enhanced Material & E-Waste Classifier with Internet Data & Fine-Tuning.

Features:
1. Multi-class classification across all 8 recyclable e-waste categories +
   NON_COLLECTIBLE class (rejection of ordinary garbage/household items).
2. Two-stage transfer learning on MobileNetV2:
   - Stage 1 (Feature extraction): Train dense head on frozen backbone with Adam(1e-3).
   - Stage 2 (Fine-tuning): Unfreeze top 35 layers with lower learning rate Adam(2e-5)
     to adapt high-level visual representations to real scrap textures and lighting.
3. Enhanced data augmentation (flips, rotations, zoom, translation, contrast).
4. Validation classification report, confusion matrix, and quantization.

Outputs:
  ml/artifacts/classifier_metrics.json
  app/assets/ml/classifier.tflite
  app/assets/ml/labels.txt
"""
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix

ROOT = Path(__file__).resolve().parent.parent
ML_DIR = ROOT / "ml"
SEED_DIR = ML_DIR / "seed_dataset"
ARTIFACTS = ML_DIR / "artifacts"
ARTIFACTS.mkdir(exist_ok=True)
APP_ASSETS = ROOT / "app" / "assets" / "ml"
APP_ASSETS.mkdir(parents=True, exist_ok=True)

IMG_SIZE = 160
BATCH = 16
STAGE1_EPOCHS = 10
STAGE2_EPOCHS = 8

print("Loading dataset from", SEED_DIR)
train_raw = tf.keras.utils.image_dataset_from_directory(
    SEED_DIR / "train",
    image_size=(IMG_SIZE, IMG_SIZE),
    batch_size=BATCH,
    shuffle=True,
    seed=42,
)
val_raw = tf.keras.utils.image_dataset_from_directory(
    SEED_DIR / "val",
    image_size=(IMG_SIZE, IMG_SIZE),
    batch_size=BATCH,
    shuffle=False,
)

class_names = train_raw.class_names
num_classes = len(class_names)
print(f"Loaded {num_classes} classes: {class_names}")

# Seed images are still imbalanced across classes (e.g. CABLES/PCB have
# 2-4x as many examples as MIXED_OTHER/MOTORS_MAGNETS) -- weight the loss
# inversely to class frequency so the model doesn't just learn to predict
# the majority classes.
train_counts = [0] * num_classes
for class_dir in sorted((SEED_DIR / "train").iterdir()):
    if class_dir.is_dir():
        idx = class_names.index(class_dir.name)
        train_counts[idx] = sum(1 for _ in class_dir.glob("*.*"))
total_train = sum(train_counts)
class_weight = {
    i: total_train / (num_classes * count) if count > 0 else 1.0
    for i, count in enumerate(train_counts)
}
print("Class counts:", dict(zip(class_names, train_counts)))
print("Class weights:", {class_names[i]: round(w, 3) for i, w in class_weight.items()})

normalize = tf.keras.layers.Rescaling(1.0 / 127.5, offset=-1)
train_ds = train_raw.map(lambda x, y: (normalize(x), y)).prefetch(tf.data.AUTOTUNE)
val_ds = val_raw.map(lambda x, y: (normalize(x), y)).prefetch(tf.data.AUTOTUNE)

data_augmentation = tf.keras.Sequential([
    tf.keras.layers.RandomFlip("horizontal"),
    tf.keras.layers.RandomRotation(0.12),
    tf.keras.layers.RandomZoom(0.15),
    tf.keras.layers.RandomTranslation(0.08, 0.08),
])

base_model = tf.keras.applications.MobileNetV2(
    input_shape=(IMG_SIZE, IMG_SIZE, 3),
    include_top=False,
    weights="imagenet",
)
base_model.trainable = False

inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
x = data_augmentation(inputs)
x = base_model(x, training=False)
x = tf.keras.layers.GlobalAveragePooling2D()(x)
x = tf.keras.layers.Dropout(0.3)(x)
x = tf.keras.layers.Dense(128, activation="relu")(x)
x = tf.keras.layers.Dropout(0.2)(x)
outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)

model = tf.keras.Model(inputs, outputs)

# Stage 1: Warmup frozen base
print("\n--- STAGE 1: Training top classification head (frozen backbone) ---")
model.compile(
    optimizer=tf.keras.optimizers.Adam(1e-3),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"],
)
history_stage1 = model.fit(train_ds, validation_data=val_ds, epochs=STAGE1_EPOCHS, class_weight=class_weight, verbose=2)

# Stage 2: Fine-tuning top layers of MobileNetV2
print("\n--- STAGE 2: Fine-tuning top 35 layers of MobileNetV2 ---")
base_model.trainable = True
# Freeze all layers before the 35th last layer
for layer in base_model.layers[:-35]:
    layer.trainable = False

model.compile(
    optimizer=tf.keras.optimizers.Adam(2e-5),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"],
)
reduce_lr = tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=2, min_lr=1e-6)
history_stage2 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=STAGE2_EPOCHS,
    callbacks=[reduce_lr],
    class_weight=class_weight,
    verbose=2,
)

val_loss, val_acc = model.evaluate(val_ds, verbose=0)
print(f"\nFinal Validation Accuracy: {val_acc:.4f}, Loss: {val_loss:.4f}")

# Detailed validation evaluation
y_true = []
y_pred = []
for images, labels in val_ds:
    preds = model.predict(images, verbose=0)
    y_true.extend(labels.numpy())
    y_pred.extend(np.argmax(preds, axis=1))

y_true = np.array(y_true)
y_pred = np.array(y_pred)

report = classification_report(y_true, y_pred, target_names=class_names, output_dict=True)
cm = confusion_matrix(y_true, y_pred).tolist()

metrics = {
    "classes": class_names,
    "num_classes": num_classes,
    "stage1_epochs": STAGE1_EPOCHS,
    "stage2_epochs": STAGE2_EPOCHS,
    "final_val_accuracy": round(float(val_acc), 4),
    "final_val_loss": round(float(val_loss), 4),
    "per_class_metrics": {
        cls: {
            "precision": round(report[cls]["precision"], 4),
            "recall": round(report[cls]["recall"], 4),
            "f1-score": round(report[cls]["f1-score"], 4),
            "support": report[cls]["support"],
        }
        for cls in class_names if cls in report
    },
    "macro_avg": {
        "precision": round(report["macro avg"]["precision"], 4),
        "recall": round(report["macro avg"]["recall"], 4),
        "f1-score": round(report["macro avg"]["f1-score"], 4),
    },
    "confusion_matrix": cm,
    "dataset_note": (
        "Trained on real internet photographs and field photos downloaded from Wikimedia Commons "
        "and Openverse, covering all 8 collection categories plus a NON_COLLECTIBLE class "
        "to explicitly reject ordinary trash, non-e-waste items, and household debris."
    ),
}

with open(ARTIFACTS / "classifier_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

with open(APP_ASSETS / "labels.txt", "w") as f:
    f.write("\n".join(class_names))

# Export TFLite (dynamic-range quantized)
print("Converting to quantized TFLite...")
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()
tflite_path = APP_ASSETS / "classifier.tflite"
with open(tflite_path, "wb") as f:
    f.write(tflite_model)

print(f"Exported TFLite: {tflite_path} ({tflite_path.stat().st_size / 1024:.1f} KB)")
print(f"Updated labels: {APP_ASSETS / 'labels.txt'}")
print(f"Saved metrics: {ARTIFACTS / 'classifier_metrics.json'}")
