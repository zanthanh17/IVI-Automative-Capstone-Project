#!/usr/bin/env python3
"""Script 03b: Prepare mouth dataset from yawn_data/
Images are already mouth crops (small ~50-130px), just resize to 64x64."""

import cv2, os
from tqdm import tqdm

YAWN_SRC = "data/raw/yawn_data"
MOUTH_OUT = "data/mouth_dataset"

LABEL_MAP = {
    "no yawn": "no_yawn",
    "yawn":    "yawn"
}

def copy_and_resize(src_folder, dst_folder, label_out, size=64):
    os.makedirs(dst_folder, exist_ok=True)
    files = [f for f in os.listdir(src_folder)
             if f.lower().endswith(('.jpg','.png','.jpeg'))]
    saved = 0
    for i, fname in enumerate(tqdm(files, desc=f"  {label_out}")):
        img = cv2.imread(os.path.join(src_folder, fname))
        if img is None: continue
        img_resized = cv2.resize(img, (size, size))
        out_name = f"yawn_{label_out}_{i:06d}.jpg"
        cv2.imwrite(os.path.join(dst_folder, out_name), img_resized,
                    [cv2.IMWRITE_JPEG_QUALITY, 95])
        saved += 1
    return saved


if __name__ == "__main__":
    print("=== Preparing mouth dataset from yawn_data ===")
    total = 0
    for src_label, out_label in LABEL_MAP.items():
        src = os.path.join(YAWN_SRC, src_label)
        dst = os.path.join(MOUTH_OUT, out_label)
        if os.path.exists(src):
            n = copy_and_resize(src, dst, out_label)
            total += n
            print(f"  {src_label} → {out_label}: {n} images")
        else:
            print(f"  ⚠️ Not found: {src}")

    print(f"\n✅ Mouth dataset ready. Total: {total}")
    for label in ["yawn", "no_yawn"]:
        d = os.path.join(MOUTH_OUT, label)
        if os.path.exists(d):
            print(f"  {label}: {len(os.listdir(d))}")
