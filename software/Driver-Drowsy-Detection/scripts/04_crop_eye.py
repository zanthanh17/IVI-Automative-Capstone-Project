#!/usr/bin/env python3
"""Script 04: Crop eye regions 64x64 from processed face dataset.
Uses OpenCV Haar cascades for eye detection (MediaPipe hangs on this system)."""

import cv2, os, shutil
import numpy as np, yaml
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

EAR_TH = cfg["thresholds"]["ear"]

# Load cascade classifiers
eye_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_eye.xml')
eye_glasses_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_eye_tree_eyeglasses.xml')
mouth_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_smile.xml')


def estimate_eye_openness(eye_crop):
    """Estimate if eye is open or closed using simple pixel analysis.
    Closed eyes have less white (sclera) and more uniform texture."""
    gray = cv2.cvtColor(eye_crop, cv2.COLOR_BGR2GRAY) if len(eye_crop.shape) == 3 else eye_crop
    h, w = gray.shape[:2]

    # Focus on middle region (iris area)
    mid = gray[h//4:3*h//4, w//4:3*w//4]

    # White pixel ratio (sclera detection)
    _, thresh = cv2.threshold(mid, 200, 255, cv2.THRESH_BINARY)
    white_ratio = np.sum(thresh > 0) / (mid.size + 1e-6)

    # Gradient magnitude (open eyes have more texture from iris/pupil)
    grad_x = cv2.Sobel(mid, cv2.CV_64F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(mid, cv2.CV_64F, 0, 1, ksize=3)
    gradient = np.sqrt(grad_x**2 + grad_y**2).mean()

    # Height to width ratio of the eye region
    aspect = h / (w + 1e-6)

    # Heuristic: open eye has more gradient, more white pixels, higher aspect
    openness_score = gradient * 0.01 + white_ratio * 2 + aspect
    return openness_score


def crop_eyes_from_face(img, face_label, idx, eye_out, mouth_out):
    """Extract eye region from 224x224 face image using geometry + cascade."""
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # ── Eye region: top 40-65% of face, centered ──
    eye_region_y1 = int(h * 0.20)
    eye_region_y2 = int(h * 0.55)
    eye_region = img[eye_region_y1:eye_region_y2, :]

    if eye_region.size == 0:
        return False, False

    eye_crop = cv2.resize(eye_region, (64, 64))

    # Label based on folder label + eye openness estimate
    if face_label == "awake":
        eye_label = "open"
    elif face_label == "drowsy":
        openness = estimate_eye_openness(eye_crop)
        eye_label = "closed" if openness < 1.5 else "open"
    else:
        openness = estimate_eye_openness(eye_crop)
        eye_label = "closed" if openness < 1.5 else "open"

    out = os.path.join(eye_out, eye_label)
    os.makedirs(out, exist_ok=True)
    cv2.imwrite(os.path.join(out, f"{face_label}_{idx:07d}.jpg"), eye_crop)
    eye_saved = True

    # ── Mouth region: bottom 55-90% of face ──
    mouth_region_y1 = int(h * 0.55)
    mouth_region_y2 = int(h * 0.90)
    mouth_x1 = int(w * 0.15)
    mouth_x2 = int(w * 0.85)
    mouth_region = img[mouth_region_y1:mouth_region_y2, mouth_x1:mouth_x2]

    mouth_saved = False
    if mouth_region.size > 0:
        mouth_crop = cv2.resize(mouth_region, (64, 64))

        # Simple mouth open detection
        mouth_gray = cv2.cvtColor(mouth_crop, cv2.COLOR_BGR2GRAY)
        mid_mouth = mouth_gray[16:48, 16:48]
        dark_ratio = np.sum(mid_mouth < 80) / (mid_mouth.size + 1e-6)

        mouth_label = "yawn" if dark_ratio > 0.3 else "no_yawn"
        out = os.path.join(mouth_out, mouth_label)
        os.makedirs(out, exist_ok=True)
        cv2.imwrite(os.path.join(out, f"{face_label}_{idx:07d}.jpg"), mouth_crop)
        mouth_saved = True

    return eye_saved, mouth_saved


def process_folder(face_folder, face_label, eye_out, mouth_out):
    """Process all face images in a folder."""
    files = [f for f in os.listdir(face_folder) if f.lower().endswith(('.jpg', '.png'))]
    eye_count = mouth_count = 0

    for i, fname in enumerate(tqdm(files, desc=f"  {os.path.basename(face_folder)}", leave=False)):
        img = cv2.imread(os.path.join(face_folder, fname))
        if img is None: continue

        e, m = crop_eyes_from_face(img, face_label, i, eye_out, mouth_out)
        if e: eye_count += 1
        if m: mouth_count += 1

    print(f"  {os.path.basename(face_folder)}/{face_label}: eyes={eye_count}, mouths={mouth_count}")
    return eye_count, mouth_count


if __name__ == "__main__":
    print("=== Cropping eye & mouth regions 64x64 ===")

    total_eyes = total_mouths = 0
    for label in ["awake", "drowsy"]:
        folder = f"data/processed/{label}"
        if os.path.exists(folder):
            e, m = process_folder(folder, label, "data/eye_dataset", "data/mouth_dataset")
            total_eyes += e
            total_mouths += m

    # Add MRL Eye dataset if available
    mrl_mapping = {"Open": "open", "Closed": "closed"}
    for mrl_label, eye_label in mrl_mapping.items():
        src = f"data/raw/mrl_eye/{mrl_label}"
        if os.path.exists(src):
            dst = f"data/eye_dataset/{eye_label}"
            os.makedirs(dst, exist_ok=True)
            for f in os.listdir(src):
                if f.endswith(('.jpg', '.png')):
                    shutil.copy(os.path.join(src, f), os.path.join(dst, f"mrl_{f}"))
            print(f"  Added MRL {mrl_label} → eye_dataset/{eye_label}")

    # Stats
    print("\n=== Dataset counts ===")
    for ds_name, ds_dir in [("eye_dataset", "data/eye_dataset"), ("mouth_dataset", "data/mouth_dataset")]:
        if os.path.exists(ds_dir):
            for label in os.listdir(ds_dir):
                d = os.path.join(ds_dir, label)
                if os.path.isdir(d):
                    n = len(os.listdir(d))
                    print(f"  {ds_name}/{label}: {n}")

    print("\n✅ Eye & mouth regions cropped")
