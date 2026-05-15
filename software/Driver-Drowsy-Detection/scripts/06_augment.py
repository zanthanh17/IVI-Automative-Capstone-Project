#!/usr/bin/env python3
"""Script 06: Augment TRAINING SET ONLY."""

import cv2, os, yaml
import albumentations as A
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

TIMES = cfg["training"]["augment_times"]

augmentor = A.Compose([
    A.HorizontalFlip(p=0.5),
    A.Rotate(limit=15, p=0.4),
    A.ShiftScaleRotate(shift_limit=0.05, scale_limit=0.1,
                       rotate_limit=10, p=0.4),
    A.RandomBrightnessContrast(brightness_limit=0.35,
                                contrast_limit=0.35, p=0.6),
    A.HueSaturationValue(hue_shift_limit=10,
                          sat_shift_limit=25, val_shift_limit=25, p=0.4),
    A.RandomGamma(gamma_limit=(60, 140), p=0.3),
    A.CLAHE(clip_limit=4.0, p=0.25),
    A.RandomBrightnessContrast(brightness_limit=(-0.5, -0.1), p=0.15),
    A.GaussNoise(p=0.3),
    A.GaussianBlur(blur_limit=(3, 5), p=0.2),
    A.MotionBlur(blur_limit=5, p=0.2),
    A.CoarseDropout(max_holes=4, max_height=25, max_width=25,
                    min_holes=1, p=0.2),
])

def augment_folder(folder, times=TIMES):
    files = [f for f in os.listdir(folder) if f.endswith('.jpg') and '_aug' not in f]
    added = 0
    for fname in tqdm(files, desc=f"Aug {folder[-30:]}", leave=False):
        img = cv2.imread(os.path.join(folder, fname))
        if img is None: continue
        for k in range(times):
            aug = augmentor(image=img)['image']
            name = fname.replace('.jpg', f'_aug{k:02d}.jpg')
            cv2.imwrite(os.path.join(folder, name), aug,
                        [cv2.IMWRITE_JPEG_QUALITY, 90])
            added += 1
    return added

total = 0
for task in ["face", "eye", "mouth"]:
    train_dir = f"data/splits/{task}/train"
    if not os.path.exists(train_dir): continue
    for label in os.listdir(train_dir):
        folder = os.path.join(train_dir, label)
        if os.path.isdir(folder):
            n = augment_folder(folder)
            total += n
            count = len(os.listdir(folder))
            print(f"  {task}/train/{label}: {count} total (added {n})")

print(f"\n✅ Augmentation complete. Total added: {total}")
