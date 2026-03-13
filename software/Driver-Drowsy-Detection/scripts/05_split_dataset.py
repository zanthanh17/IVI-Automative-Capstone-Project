#!/usr/bin/env python3
"""Script 05: Split dataset into train/val/test."""

import os, shutil, random, yaml
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

SEED        = cfg["project"]["seed"]
TRAIN_RATIO = cfg["data"]["train_split"]
VAL_RATIO   = cfg["data"]["val_split"]
random.seed(SEED)

def split_folder(src_dir, out_base, task="face",
                 train_r=TRAIN_RATIO, val_r=VAL_RATIO,
                 test_from_own_only=False):
    for label in os.listdir(src_dir):
        src = os.path.join(src_dir, label)
        if not os.path.isdir(src): continue
        files = [f for f in os.listdir(src) if f.endswith('.jpg')]
        random.shuffle(files)

        n       = len(files)
        n_train = int(n * train_r)
        n_val   = int(n * val_r)

        splits = {
            "train": files[:n_train],
            "val":   files[n_train:n_train+n_val],
            "test":  files[n_train+n_val:]
        }

        for split, split_files in splits.items():
            dst = os.path.join(out_base, task, split, label)
            os.makedirs(dst, exist_ok=True)

            own_prefixes = ("bao_", "dien_", "hkanh_", "hnan_", "thanh_")

            for fname in tqdm(split_files, desc=f"{task}/{split}/{label}", leave=False):
                if split == "test" and test_from_own_only:
                    if not fname.lower().startswith(own_prefixes):
                        continue
                shutil.copy(os.path.join(src, fname), os.path.join(dst, fname))

            actual = len(os.listdir(dst))
            print(f"  {task}/{split}/{label}: {actual} ảnh")

# Face dataset — test set CHỈ từ own
split_folder("data/processed", "data/splits", task="face", test_from_own_only=True)

# Eye dataset
split_folder("data/eye_dataset", "data/splits", task="eye", test_from_own_only=False)

# Mouth dataset
split_folder("data/mouth_dataset", "data/splits", task="mouth", test_from_own_only=False)

print("\n✅ Dataset split complete")

# Verify
for task in ["face", "eye", "mouth"]:
    print(f"\n{task.upper()} split summary:")
    for split in ["train", "val", "test"]:
        split_dir = f"data/splits/{task}/{split}"
        if not os.path.exists(split_dir): continue
        for label in sorted(os.listdir(split_dir)):
            label_dir = os.path.join(split_dir, label)
            if os.path.isdir(label_dir):
                n = len(os.listdir(label_dir))
                print(f"  {split}/{label}: {n}")
