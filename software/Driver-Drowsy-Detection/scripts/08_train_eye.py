#!/usr/bin/env python3
"""Script 08: Train Eye CNN (MobileNetV2 alpha=0.35)."""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import tensorflow as tf
import yaml, json, numpy as np
from datetime import datetime

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

# GPU setup
for gpu in tf.config.list_physical_devices('GPU'):
    tf.config.experimental.set_memory_growth(gpu, True)

def build_eye_cnn(input_size=64):
    from tensorflow.keras import layers, regularizers
    from tensorflow.keras.applications import MobileNetV2

    base = MobileNetV2(
        input_shape=(input_size, input_size, 3),
        include_top=False,
        weights="imagenet",
        alpha=0.35
    )
    base.trainable = False

    inp = tf.keras.Input(shape=(input_size, input_size, 3))
    x = tf.keras.applications.mobilenet_v2.preprocess_input(inp)
    x = base(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dense(64, activation="relu",
                     kernel_regularizer=regularizers.l2(1e-4))(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.35)(x)
    out = layers.Dense(1, activation="sigmoid")(x)

    model = tf.keras.Model(inp, out)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(cfg["training"]["lr_phase1"]),
        loss="binary_crossentropy",
        metrics=["accuracy",
                 tf.keras.metrics.AUC(name="auc"),
                 tf.keras.metrics.Precision(name="precision"),
                 tf.keras.metrics.Recall(name="recall")]
    )
    return model, base

def train_model(task, model, base, data_dir, model_out_dir):
    os.makedirs(model_out_dir, exist_ok=True)
    ts    = datetime.now().strftime("%Y%m%d_%H%M%S")
    isize = cfg["data"]["img_size_region"]
    bs    = cfg["training"]["batch_size"]

    def load_ds(split):
        ds = tf.keras.utils.image_dataset_from_directory(
            os.path.join(data_dir, split),
            image_size=(isize, isize),
            batch_size=bs,
            label_mode="binary",
            shuffle=(split == "train"),
            seed=cfg["project"]["seed"]
        )
        class_names = ds.class_names
        ds = ds.cache().prefetch(tf.data.AUTOTUNE)
        ds.class_names = class_names
        return ds

    train_ds = load_ds("train")
    val_ds   = load_ds("val")
    print(f"Classes: {train_ds.class_names}")

    # Class weights
    labels = np.concatenate([y.numpy() for _, y in train_ds]).flatten()
    n0, n1 = np.sum(labels == 0), np.sum(labels == 1)
    total  = len(labels)
    cw     = {0: total/(2*n0+1e-6), 1: total/(2*n1+1e-6)}
    print(f"Class weights: {cw}")

    def callbacks(phase):
        return [
            tf.keras.callbacks.ModelCheckpoint(
                f"{model_out_dir}/best_p{phase}.h5",
                save_best_only=True, monitor="val_auc",
                mode="max", verbose=1
            ),
            tf.keras.callbacks.EarlyStopping(
                monitor="val_auc", patience=cfg["training"]["patience_early_stop"],
                mode="max", restore_best_weights=True, verbose=1
            ),
            tf.keras.callbacks.ReduceLROnPlateau(
                monitor="val_loss", factor=0.3,
                patience=cfg["training"]["patience_reduce_lr"],
                min_lr=1e-7, verbose=1
            ),
            tf.keras.callbacks.TensorBoard(
                log_dir=f"logs/{task}_p{phase}_{ts}", histogram_freq=1
            ),
        ]

    # Phase 1: Frozen base
    print(f"\n{'='*50}\nPHASE 1: Training head — {task.upper()}\n{'='*50}")
    h1 = model.fit(train_ds, validation_data=val_ds,
                   epochs=cfg["training"]["epochs_phase1"],
                   class_weight=cw, callbacks=callbacks(1), verbose=1)

    # Phase 2: Fine-tune
    print(f"\n{'='*50}\nPHASE 2: Fine-tuning — {task.upper()}\n{'='*50}")
    base.trainable = True
    unfreeze = cfg["models"][f"{task}_cnn"]["unfreeze_layers"]
    for layer in base.layers[:-unfreeze]:
        layer.trainable = False

    model.compile(
        optimizer=tf.keras.optimizers.Adam(cfg["training"]["lr_phase2"]),
        loss="binary_crossentropy",
        metrics=["accuracy",
                 tf.keras.metrics.AUC(name="auc"),
                 tf.keras.metrics.Precision(name="precision"),
                 tf.keras.metrics.Recall(name="recall")]
    )
    h2 = model.fit(train_ds, validation_data=val_ds,
                   epochs=cfg["training"]["epochs_phase2"],
                   class_weight=cw, callbacks=callbacks(2), verbose=1)

    model.save(f"{model_out_dir}/final.h5")
    best_auc = max(h2.history["val_auc"])
    best_acc = max(h2.history["val_accuracy"])
    print(f"\n✅ {task} — Best val_AUC={best_auc:.4f}, val_Acc={best_acc:.4f}")

    with open(f"{model_out_dir}/train_results.json", "w") as f:
        json.dump({"task": task, "val_auc": best_auc, "val_accuracy": best_acc,
                   "timestamp": ts}, f, indent=2)
    return model

if __name__ == "__main__":
    print("=== Training Eye CNN ===")
    model, base = build_eye_cnn(64)
    model.summary()
    train_model("eye", model, base, "data/splits/eye", "models/eye_cnn")
