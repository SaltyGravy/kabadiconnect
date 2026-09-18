"""
KabadiConnect - Material image classifier.

Transfer learning on MobileNetV2 (ImageNet weights) with a small trainable
head, trained on ml/seed_dataset. Real field photos (see
prepare_real_photos.py) back 7 of the 8 categories; MIXED_OTHER still falls
back to the synthetic placeholder set from generate_seed_images.py since no
real photos were supplied for it.

Outputs:
  ml/artifacts/classifier_metrics.json   - accuracy/loss + confusion info
  app/assets/ml/classifier.tflite        - quantized model for on-device inference
  app/assets/ml/labels.txt               - class label order (matches model output index)
"""
import json
from pathlib import Path

import tensorflow as tf

ROOT = Path(__file__).resolve().parent.parent
ML_DIR = ROOT / "ml"
SEED_DIR = ML_DIR / "seed_dataset"
ARTIFACTS = ML_DIR / "artifacts"
ARTIFACTS.mkdir(exist_ok=True)
APP_ASSETS = ROOT / "app" / "assets" / "ml"
APP_ASSETS.mkdir(parents=True, exist_ok=True)

IMG_SIZE = 160
BATCH = 16
EPOCHS = 12

train_ds = tf.keras.utils.image_dataset_from_directory(
    SEED_DIR / "train", image_size=(IMG_SIZE, IMG_SIZE), batch_size=BATCH, shuffle=True, seed=42,
)
val_ds = tf.keras.utils.image_dataset_from_directory(
    SEED_DIR / "val", image_size=(IMG_SIZE, IMG_SIZE), batch_size=BATCH, shuffle=False,
)
class_names = train_ds.class_names
print("classes:", class_names)

normalize = tf.keras.layers.Rescaling(1.0 / 127.5, offset=-1)
train_ds = train_ds.map(lambda x, y: (normalize(x), y))
val_ds = val_ds.map(lambda x, y: (normalize(x), y))

data_augmentation = tf.keras.Sequential([
    tf.keras.layers.RandomFlip("horizontal"),
    tf.keras.layers.RandomRotation(0.06),
    tf.keras.layers.RandomZoom(0.1),
])

base_model = tf.keras.applications.MobileNetV2(
    input_shape=(IMG_SIZE, IMG_SIZE, 3), include_top=False, weights="imagenet",
)
base_model.trainable = False

inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
x = data_augmentation(inputs)
x = base_model(x, training=False)
x = tf.keras.layers.GlobalAveragePooling2D()(x)
x = tf.keras.layers.Dropout(0.2)(x)
outputs = tf.keras.layers.Dense(len(class_names), activation="softmax")(x)
model = tf.keras.Model(inputs, outputs)

model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
              loss="sparse_categorical_crossentropy", metrics=["accuracy"])

history = model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS, verbose=2)

val_loss, val_acc = model.evaluate(val_ds, verbose=0)
print(f"final val_accuracy={val_acc:.3f} val_loss={val_loss:.3f}")

metrics = {
    "classes": class_names,
    "epochs": EPOCHS,
    "train_accuracy_history": [round(v, 4) for v in history.history["accuracy"]],
    "val_accuracy_history": [round(v, 4) for v in history.history["val_accuracy"]],
    "final_val_accuracy": round(float(val_acc), 4),
    "final_val_loss": round(float(val_loss), 4),
    "dataset_note": (
        "Trained on real field photos for BATTERIES, CABLES, PCB, LCD_LED, "
        "MIXED_PLASTICS, MOTORS_MAGNETS, CRT (see ml/prepare_real_photos.py). "
        "MIXED_OTHER still uses the SYNTHETIC placeholder set (see "
        "generate_seed_images.py) -- no real photos were supplied for it, so "
        "treat that one category's accuracy as unproven on real photos."
    ),
}
with open(ARTIFACTS / "classifier_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

# Save labels in class-index order for the Flutter app
with open(APP_ASSETS / "labels.txt", "w") as f:
    f.write("\n".join(class_names))

# Export TFLite (dynamic-range quantized -> small size for entry-level devices)
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()
tflite_path = APP_ASSETS / "classifier.tflite"
with open(tflite_path, "wb") as f:
    f.write(tflite_model)

size_kb = tflite_path.stat().st_size / 1024
print(f"wrote {tflite_path} ({size_kb:.0f} KB)")
print(f"wrote {ARTIFACTS / 'classifier_metrics.json'}")
