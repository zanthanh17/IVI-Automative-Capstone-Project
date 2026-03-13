#!/usr/bin/env python3
"""Script 11: Export TFLite (INT8 quantized)."""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import tensorflow as tf
import numpy as np, json, time, yaml

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

def export_tflite(model_path, task, data_dir_for_calib, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    model = tf.keras.models.load_model(model_path)
    isize = cfg["data"]["img_size_region"]

    def rep_dataset():
        import cv2
        calib_dir = os.path.join(data_dir_for_calib, "train")
        count = 0
        for label_name in sorted(os.listdir(calib_dir)):
            label_dir = os.path.join(calib_dir, label_name)
            if not os.path.isdir(label_dir):
                continue
            for fname in sorted(os.listdir(label_dir))[:100]:
                img = cv2.imread(os.path.join(label_dir, fname))
                if img is None: continue
                img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                img = cv2.resize(img, (isize, isize)).astype(np.float32)
                yield [np.expand_dims(img, 0)]
                count += 1
                if count >= 200:
                    return

    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    conv.representative_dataset = rep_dataset
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    conv.inference_input_type  = tf.uint8
    conv.inference_output_type = tf.uint8

    tflite_model = conv.convert()
    out_path = os.path.join(out_dir, f"{task}_model.tflite")
    with open(out_path, "wb") as f:
        f.write(tflite_model)

    size_kb = len(tflite_model) / 1024
    print(f"✅ {task} TFLite: {size_kb:.1f} KB → {out_path}")

    interp = tf.lite.Interpreter(out_path)
    interp.allocate_tensors()
    inp_d  = interp.get_input_details()
    dummy  = np.random.randint(0, 255, inp_d[0]['shape'], dtype=np.uint8)

    times = []
    for _ in range(100):
        t0 = time.perf_counter()
        interp.set_tensor(inp_d[0]['index'], dummy)
        interp.invoke()
        times.append((time.perf_counter()-t0)*1000)

    avg_ms = np.mean(times)
    print(f"   Inference (host CPU): {avg_ms:.1f}ms avg")
    print(f"   RPi4 estimate (~3x): {avg_ms*3:.0f}ms")

    return out_path, size_kb, avg_ms

if __name__ == "__main__":
    print("=== Exporting TFLite models ===")
    export_tflite("models/eye_cnn/final_fixed.keras",  "eye",  "data/splits/eye",   "models/eye_cnn")
    export_tflite("models/yawn_cnn/final_fixed.keras", "yawn", "data/splits/mouth", "models/yawn_cnn")
    print("✅ Export complete")
