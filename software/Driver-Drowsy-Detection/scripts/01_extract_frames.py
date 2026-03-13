#!/usr/bin/env python3
"""Script 01: Extract frames from videos in data/raw/drowsy_data/"""

import cv2, os, yaml
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

FPS      = cfg["data"]["video_fps_extract"]
RAW_DIR  = "data/raw/drowsy_data"

def extract_frames(video_path, output_dir, fps_out=FPS, label_suffix=""):
    os.makedirs(output_dir, exist_ok=True)
    cap      = cv2.VideoCapture(video_path)
    v_fps    = cap.get(cv2.CAP_PROP_FPS) or 30
    interval = max(1, int(v_fps / fps_out))
    total    = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    saved    = count = 0
    pbar     = tqdm(total=total, desc=f"  {os.path.basename(video_path)}")

    while True:
        ret, frame = cap.read()
        if not ret: break
        if count % interval == 0:
            name = f"{label_suffix}_{saved:07d}.jpg"
            cv2.imwrite(
                os.path.join(output_dir, name),
                frame,
                [cv2.IMWRITE_JPEG_QUALITY, 95]
            )
            saved += 1
        count += 1
        pbar.update(1)

    cap.release()
    pbar.close()
    return saved

# ── 4 video trong data/raw/drowsy_data/ ──
# Output frame vào đúng person folder để được đưa vào val+test
own_videos = [
    (f"{RAW_DIR}/Bao_awake.mp4",    f"{RAW_DIR}/Bao_awake",    "bao_aw"),
    (f"{RAW_DIR}/Bao_drowsy.mp4",   f"{RAW_DIR}/Bao_drowsy",   "bao_dr"),
    (f"{RAW_DIR}/Thanh_awake.mp4",  f"{RAW_DIR}/Thanh_awake",  "thanh_aw"),
    (f"{RAW_DIR}/Thanh_drowsy.mp4", f"{RAW_DIR}/Thanh_drowsy", "thanh_dr"),
]

print("=== Extracting own videos ===")
for src, dst, tag in own_videos:
    if os.path.exists(src):
        n = extract_frames(src, dst, label_suffix=tag)
        print(f"✅ {tag}: {n} frames → {dst}")
    else:
        print(f"⚠️  Not found: {src}")

# ── UTA-RLDD (nếu đã tải) ──
def extract_uta_rldd(base="data/raw/uta_rldd"):
    if not os.path.exists(base):
        print(f"⚠️  UTA-RLDD not found at {base}, skipping")
        return
    label_map = {"0": "awake", "10": "drowsy"}
    for level, label in label_map.items():
        level_dir = os.path.join(base, level)
        if not os.path.exists(level_dir): continue
        for vf in os.listdir(level_dir):
            if not vf.endswith(".mp4"): continue
            out    = f"data/raw/uta_frames/{label}"
            prefix = f"uta_{level}_{vf[:10]}"
            extract_frames(os.path.join(level_dir, vf), out, fps_out=3, label_suffix=prefix)

# ── YawDD (nếu đã tải) ──
def extract_yawdd(base="data/raw/yawdd"):
    if not os.path.exists(base):
        print(f"⚠️  YawDD not found at {base}, skipping")
        return
    for vf in os.listdir(base):
        if not vf.endswith(".avi"): continue
        label  = "drowsy" if "yawning" in vf.lower() else "awake"
        out    = f"data/raw/yawdd_frames/{label}"
        prefix = f"yawdd_{vf[:15]}"
        extract_frames(os.path.join(base, vf), out, fps_out=3, label_suffix=prefix)

print("\n=== Extracting external datasets ===")
extract_uta_rldd()
extract_yawdd()
print("✅ Frame extraction complete")
