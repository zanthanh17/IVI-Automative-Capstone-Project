#!/usr/bin/env python3
"""Script 02: Quality check & filter — remove blurry/dark/bright images"""

import cv2, os, yaml
import numpy as np
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

BLUR_TH  = cfg["data"]["blur_threshold"]
BMIN     = cfg["data"]["brightness_min"]
BMAX     = cfg["data"]["brightness_max"]

def quality_check_folder(folder, remove=True):
    files   = [f for f in os.listdir(folder) if f.lower().endswith(('.jpg','.png'))]
    removed = kept = 0

    for fname in tqdm(files, desc=f"QC {os.path.basename(folder)}", leave=False):
        path = os.path.join(folder, fname)
        img  = cv2.imread(path)
        if img is None:
            if remove: os.remove(path)
            removed += 1; continue

        h, w = img.shape[:2]
        if h < 40 or w < 40:
            if remove: os.remove(path)
            removed += 1; continue

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        # Blur check
        if cv2.Laplacian(gray, cv2.CV_64F).var() < BLUR_TH:
            if remove: os.remove(path)
            removed += 1; continue

        # Brightness check
        mean_b = np.mean(gray)
        if mean_b < BMIN or mean_b > BMAX:
            if remove: os.remove(path)
            removed += 1; continue

        kept += 1

    return kept, removed

# Quét tất cả folder trong data/raw/
total_removed = 0
for root, dirs, files in os.walk("data/raw"):
    imgs = [f for f in files if f.lower().endswith(('.jpg', '.png'))]
    if imgs:
        k, r = quality_check_folder(root)
        total_removed += r
        print(f"  {root}: kept={k}, removed={r}")

print(f"\n✅ Total removed: {total_removed} low-quality images")
