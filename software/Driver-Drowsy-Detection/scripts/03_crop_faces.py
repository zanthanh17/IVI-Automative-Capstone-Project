#!/usr/bin/env python3
"""Script 03: Crop faces 224x224 using OpenCV DNN face detector
(MediaPipe solutions API hangs on this system, using cv2.dnn as fallback)"""

import cv2, os
import numpy as np
from tqdm import tqdm

# Use OpenCV's built-in DNN face detector (Caffe model)
PROTOTXT_URL = "https://raw.githubusercontent.com/opencv/opencv/master/samples/dnn/face_detector/deploy.prototxt"
MODEL_URL = "https://raw.githubusercontent.com/opencv/opencv_3rdparty/dnn_samples_face_detector_20170830/res10_300x300_ssd_iter_140000.caffemodel"

MODEL_DIR = "models/face_detector"
PROTOTXT = os.path.join(MODEL_DIR, "deploy.prototxt")
CAFFEMODEL = os.path.join(MODEL_DIR, "res10_300x300_ssd_iter_140000.caffemodel")

def download_model():
    os.makedirs(MODEL_DIR, exist_ok=True)
    import urllib.request
    if not os.path.exists(PROTOTXT):
        print("Downloading face detector prototxt...")
        urllib.request.urlretrieve(PROTOTXT_URL, PROTOTXT)
    if not os.path.exists(CAFFEMODEL):
        print("Downloading face detector model (~10MB)...")
        urllib.request.urlretrieve(MODEL_URL, CAFFEMODEL)
    print("✅ Face detector model ready")

RAW_OWN = "data/raw/drowsy_data"

# ── Mapping source → label → output ──
SOURCES = [
    # General folders → TRAIN
    (f"{RAW_OWN}/Awake",         "awake",  "data/processed"),
    (f"{RAW_OWN}/Drowsy",        "drowsy", "data/processed"),
    # Person folders → VAL + TEST
    (f"{RAW_OWN}/Bao_awake",     "awake",  "data/processed"),
    (f"{RAW_OWN}/Bao_drowsy",    "drowsy", "data/processed"),
    (f"{RAW_OWN}/Dien_awake",    "awake",  "data/processed"),
    (f"{RAW_OWN}/Dien_drowsy",   "drowsy", "data/processed"),
    (f"{RAW_OWN}/Hkanh_awake",   "awake",  "data/processed"),
    (f"{RAW_OWN}/Hkanh_drowsy",  "drowsy", "data/processed"),
    (f"{RAW_OWN}/Hnan_awake",    "awake",  "data/processed"),
    (f"{RAW_OWN}/Hnan_drowsy",   "drowsy", "data/processed"),
    (f"{RAW_OWN}/Thanh_awake",   "awake",  "data/processed"),
    (f"{RAW_OWN}/Thanh_drowsy",  "drowsy", "data/processed"),
]

def crop_face_from_folder(net, src, label, out_base, size=224, conf_th=0.5):
    out_dir = os.path.join(out_base, label)
    os.makedirs(out_dir, exist_ok=True)
    files = [f for f in os.listdir(src) if f.lower().endswith(('.jpg','.png'))]
    saved = skipped = 0
    src_tag = os.path.basename(src)[:20]

    cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')

    for i, fname in enumerate(tqdm(files, desc=f"  {src_tag}", leave=False)):
        img = cv2.imread(os.path.join(src, fname))
        if img is None:
            skipped += 1; continue
        h, w = img.shape[:2]

        # Method 1: DNN face detector
        blob = cv2.dnn.blobFromImage(
            cv2.resize(img, (300, 300)), 1.0, (300, 300),
            (104.0, 177.0, 123.0)
        )
        net.setInput(blob)
        detections = net.forward()

        best_conf = 0
        best_box = None
        for j in range(detections.shape[2]):
            confidence = detections[0, 0, j, 2]
            if confidence > best_conf:
                best_conf = confidence
                best_box = detections[0, 0, j, 3:7]

        if best_conf >= conf_th and best_box is not None:
            box = best_box * np.array([w, h, w, h])
            x1, y1, x2, y2 = box.astype(int)
            pad = 0.25
            bw, bh = x2-x1, y2-y1
            x1 = max(0, int(x1 - bw*pad))
            y1 = max(0, int(y1 - bh*pad))
            x2 = min(w, int(x2 + bw*pad))
            y2 = min(h, int(y2 + bh*pad))
            face = img[y1:y2, x1:x2]
            if face.size > 0:
                face = cv2.resize(face, (size, size))
                cv2.imwrite(
                    os.path.join(out_dir, f"{src_tag}_{i:07d}.jpg"),
                    face, [cv2.IMWRITE_JPEG_QUALITY, 95]
                )
                saved += 1; continue

        # Method 2: Haar cascade fallback
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        faces = cascade.detectMultiScale(gray, 1.1, 5, minSize=(30, 30))
        if len(faces) > 0:
            fx, fy, fw, fh = faces[0]
            pad = 0.2
            x1 = max(0, int(fx - fw*pad))
            y1 = max(0, int(fy - fh*pad))
            x2 = min(w, int(fx + fw*(1+pad)))
            y2 = min(h, int(fy + fh*(1+pad)))
            face = img[y1:y2, x1:x2]
            if face.size > 0:
                face = cv2.resize(face, (size, size))
                cv2.imwrite(
                    os.path.join(out_dir, f"{src_tag}_{i:07d}.jpg"),
                    face, [cv2.IMWRITE_JPEG_QUALITY, 95]
                )
                saved += 1; continue

        # Method 3: If image is already face-like (small, square-ish), just resize
        if h > 100 and w > 100 and 0.6 < w/h < 1.7:
            face = cv2.resize(img, (size, size))
            cv2.imwrite(
                os.path.join(out_dir, f"{src_tag}_{i:07d}.jpg"),
                face, [cv2.IMWRITE_JPEG_QUALITY, 95]
            )
            saved += 1; continue

        skipped += 1

    print(f"  {src_tag}/{label}: saved={saved}, skipped={skipped}")
    return saved


if __name__ == "__main__":
    print("=== Cropping faces 224x224 (OpenCV DNN) ===")
    download_model()

    net = cv2.dnn.readNetFromCaffe(PROTOTXT, CAFFEMODEL)
    print("✅ Face detector loaded")

    total = 0
    for src, label, out_base in SOURCES:
        if os.path.exists(src):
            n = crop_face_from_folder(net, src, label, out_base)
            total += n
        else:
            print(f"  ⚠️  Not found: {src}")

    print(f"\n✅ Face cropping complete. Total: {total} faces")
    print(f"  awake: {len(os.listdir('data/processed/awake'))}")
    print(f"  drowsy: {len(os.listdir('data/processed/drowsy'))}")
