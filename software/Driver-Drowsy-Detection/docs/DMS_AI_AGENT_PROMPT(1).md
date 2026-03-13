# 🤖 AI AGENT PROMPT — DROWSINESS DETECTION MODEL TRAINING
## Driver Monitoring System | IVI Automotive Capstone Project
### Version: 2.0 | Target Accuracy: ≥ 95%

---

> **📌 HƯỚNG DẪN SỬ DỤNG FILE NÀY**
>
> File này là **specification đầy đủ** cho AI Agent tự động thực hiện toàn bộ pipeline
> training model phát hiện buồn ngủ. Agent cần đọc **toàn bộ** file trước khi thực thi.
> Thực hiện tuần tự từng Phase, kiểm tra output của mỗi bước trước khi sang bước tiếp theo.

---

## 🎯 MISSION STATEMENT

```
Bạn là một AI Agent chuyên về Computer Vision và Deep Learning.
Nhiệm vụ của bạn là:

1. Chuẩn bị và xử lý dataset buồn ngủ tài xế
2. Train 2 sub-model CNN: Eye State + Yawn Detection
3. Tích hợp MediaPipe để tính EAR, MAR, Head Pose
4. Implement Multi-Feature Fusion pipeline
5. Export TFLite models tối ưu cho Raspberry Pi 4
6. Validate accuracy ≥ 95% trên test set

Ngôn ngữ: Python 3.10+
Framework: TensorFlow 2.13 + MediaPipe 0.10
Target hardware: Raspberry Pi 4 (aarch64)
Inference target: ≤ 80ms/frame, ≥ 12fps
```

---

## 📁 SECTION 1 — CẤU TRÚC DỰ ÁN

### 1.1 Thư Mục Làm Việc

```
drowsy_detection/
│
├── data/
│   ├── raw/                            # Data gốc — KHÔNG sửa đổi
│   │   │
│   │   ├── drowsy_data/                # ← DATASET KHUÔN MẶT CHÍNH
│   │   │   ├── Awake/                  # Ảnh awake chung (không tên người) → train
│   │   │   ├── Drowsy/                 # Ảnh drowsy chung (không tên người) → train
│   │   │   │
│   │   │   ├── Bao_awake/              # 5 người × 2 trạng thái → val + test
│   │   │   ├── Bao_drowsy/
│   │   │   ├── Dien_awake/
│   │   │   ├── Dien_drowsy/
│   │   │   ├── Hkanh_awake/
│   │   │   ├── Hkanh_drowsy/
│   │   │   ├── Hnan_awake/
│   │   │   ├── Hnan_drowsy/
│   │   │   ├── Thanh_awake/
│   │   │   ├── Thanh_drowsy/
│   │   │   │
│   │   │   ├── Bao_awake.mp4           # 4 video → extract → person folders
│   │   │   ├── Bao_drowsy.mp4
│   │   │   ├── Thanh_awake.mp4
│   │   │   └── Thanh_drowsy.mp4
│   │   │
│   │   ├── yawn_data/                  # ← DATASET MIỆNG CÓ SẴN ✅
│   │   │   ├── no yawn/                # Ảnh miệng bình thường
│   │   │   └── yawn/                   # Ảnh đang ngáp
│   │   │
│   │   ├── ddd/                        # Driver Drowsiness Dataset (Kaggle, optional)
│   │   │   ├── Non Drowsy/
│   │   │   └── Drowsy/
│   │   ├── yawdd/                      # YawDD video dataset (Kaggle, optional)
│   │   └── uta_rldd/                   # UTA-RLDD video dataset (Kaggle, optional)
│   │
│   ├── processed/                      # Sau bước crop face 224x224
│   │   ├── awake/
│   │   └── drowsy/
│   │
│   ├── eye_dataset/                    # Crop vùng mắt 64x64 (từ processed/)
│   │   ├── open/
│   │   └── closed/
│   │
│   ├── mouth_dataset/                  # Copy trực tiếp từ yawn_data/ + crop thêm
│   │   ├── no_yawn/                    # ← từ yawn_data/no yawn/
│   │   └── yawn/                       # ← từ yawn_data/yawn/
│   │
│   └── splits/                         # Train/Val/Test splits
│       ├── face/
│       │   ├── train/{awake,drowsy}/
│       │   ├── val/{awake,drowsy}/
│       │   └── test/{awake,drowsy}/    # CHỈ person folders (người Việt)
│       ├── eye/
│       │   ├── train/{open,closed}/
│       │   └── val/{open,closed}/
│       └── mouth/
│           ├── train/{no_yawn,yawn}/
│           └── val/{no_yawn,yawn}/
│
├── models/
│   ├── eye_cnn/
│   │   ├── best.h5
│   │   └── eye_model.tflite
│   ├── yawn_cnn/
│   │   ├── best.h5
│   │   └── yawn_model.tflite
│   └── fusion/
│       └── config.json             # Fusion weights + thresholds
│
├── scripts/
│   ├── 01_extract_frames.py
│   ├── 02_check_quality.py
│   ├── 03_crop_faces.py
│   ├── 04_crop_eye_mouth.py
│   ├── 05_auto_label.py
│   ├── 06_split_dataset.py
│   ├── 07_augment.py
│   ├── 08_train_eye.py
│   ├── 09_train_yawn.py
│   ├── 10_evaluate.py
│   ├── 11_export_tflite.py
│   └── 12_validate_pipeline.py
│
├── pipeline/
│   ├── feature_extractor.py        # EAR + MAR + Head Pose
│   ├── drowsiness_detector.py      # Full fusion pipeline
│   └── head_pose.py                # solvePnP head pose
│
├── results/
│   ├── confusion_matrix.png
│   ├── roc_curve.png
│   ├── training_history_eye.png
│   ├── training_history_yawn.png
│   └── evaluation_report.json
│
├── requirements.txt
└── config.yaml                     # Tất cả hyperparameter ở đây
```

### 1.2 File config.yaml — Single Source of Truth

```yaml
# config.yaml — AI Agent đọc file này trước khi làm bất cứ điều gì

project:
  name: "IVI_DMS_Drowsiness_Detection"
  version: "2.0"
  seed: 42

data:
  img_size_face: 224          # Full face model input
  img_size_region: 64         # Eye/mouth crop input
  val_split: 0.15
  test_split: 0.05            # CHỈ dùng own dataset (người Việt)
  train_split: 0.80

  # Số lượng minimum trước khi train
  min_samples_face: 1500      # Mỗi class
  min_samples_eye: 5000       # Mỗi class
  min_samples_mouth: 2000     # Mỗi class

  # Video extraction
  video_fps_extract: 5        # Frame/giây lấy từ video

  # Quality filters
  blur_threshold: 80          # Laplacian variance minimum
  brightness_min: 25
  brightness_max: 245

training:
  batch_size: 32
  epochs_phase1: 20           # Frozen base
  epochs_phase2: 30           # Fine-tune
  lr_phase1: 0.001
  lr_phase2: 0.000005
  patience_early_stop: 8
  patience_reduce_lr: 4

  # Augmentation
  augment_times: 4            # Nhân dataset train lên 4x

  # Class balance
  use_class_weights: true

models:
  eye_cnn:
    base: "MobileNetV2"
    alpha: 0.35               # Lightweight version
    input_size: 64
    unfreeze_layers: 30

  yawn_cnn:
    base: "MobileNetV2"
    alpha: 0.35
    input_size: 64
    unfreeze_layers: 30

thresholds:
  ear: 0.25                   # < này → mắt nhắm
  mar: 0.60                   # > này → đang ngáp
  pitch_danger: 15.0          # độ, > này → đầu cúi nguy hiểm
  roll_danger: 20.0           # độ
  perclos_window: 90          # frames (~3s ở 30fps)
  perclos_alert: 0.15         # 15% thời gian mắt nhắm
  yawn_decay_frames: 150      # Frame để yawn counter về 0
  fusion_alert: 0.55          # Ngưỡng cảnh báo cuối cùng
  drowsy_confirm_frames: 20   # Liên tục bao nhiêu frame mới alert

fusion_weights:
  eye_cnn: 0.30
  ear_perclos: 0.20
  yawn_combined: 0.25
  head_pose: 0.25

export:
  quantize: true              # INT8 quantization
  target_device: "rpi4"

targets:
  accuracy_eye: 0.97
  accuracy_yawn: 0.95
  accuracy_overall: 0.95
  latency_ms: 80
  fps_rpi4: 12
```

---

## 🔧 SECTION 2 — ENVIRONMENT SETUP

### 2.1 Agent thực hiện lệnh sau đầu tiên

```bash
# Tạo virtual environment
python -m venv drowsy_env
source drowsy_env/bin/activate

# Cài đặt dependencies
pip install tensorflow==2.13.0
pip install opencv-python==4.9.0.80
pip install mediapipe==0.10.14
pip install scikit-learn==1.3.0
pip install albumentations==1.3.1
pip install scipy matplotlib seaborn pandas numpy tqdm pillow
pip install tensorboard pyyaml

# Lưu requirements
pip freeze > requirements.txt
```

### 2.2 Kiểm Tra Môi Trường

```python
# Agent chạy script này, xác nhận output trước khi tiếp tục
import tensorflow as tf, mediapipe as mp, cv2, numpy as np

checks = {
    "TensorFlow":  tf.__version__,
    "MediaPipe":   mp.__version__,
    "OpenCV":      cv2.__version__,
    "GPU":         bool(tf.config.list_physical_devices('GPU')),
    "NumPy":       np.__version__,
}
for k, v in checks.items():
    status = "✅" if v else "⚠️ "
    print(f"{status} {k}: {v}")

# Enable GPU memory growth nếu có GPU
for gpu in tf.config.list_physical_devices('GPU'):
    tf.config.experimental.set_memory_growth(gpu, True)

# AGENT: Nếu không có GPU → thêm flag --use_multiprocessing=False khi train
```

---

## 📦 SECTION 3 — DATASET SPECIFICATION

### 3.1 Dataset Nguồn Gốc

```yaml
# ══════════════════════════════════════════════════════════════
# Dataset 1 — DROWSY_DATA (data/raw/drowsy_data/) — KHUÔN MẶT
# ══════════════════════════════════════════════════════════════
drowsy_data:
  location: "data/raw/drowsy_data/"

  # Folder CHUNG — không rõ người → dùng cho TRAIN
  general_folders:
    Awake/:   label: awake   → usage: train
    Drowsy/:  label: drowsy  → usage: train

  # Folder THEO NGƯỜI — 5 người Việt Nam → dùng cho VAL + TEST
  person_folders:
    Bao_awake/:    label: awake,  person: Bao
    Bao_drowsy/:   label: drowsy, person: Bao
    Dien_awake/:   label: awake,  person: Dien
    Dien_drowsy/:  label: drowsy, person: Dien
    Hkanh_awake/:  label: awake,  person: Hkanh
    Hkanh_drowsy/: label: drowsy, person: Hkanh
    Hnan_awake/:   label: awake,  person: Hnan
    Hnan_drowsy/:  label: drowsy, person: Hnan
    Thanh_awake/:  label: awake,  person: Thanh
    Thanh_drowsy/: label: drowsy, person: Thanh
    usage: val (70%) + test (30%)

  # Videos → extract frame → vào đúng person folder → val + test
  videos:
    Bao_awake.mp4:    output_folder: Bao_awake/,   label: awake
    Bao_drowsy.mp4:   output_folder: Bao_drowsy/,  label: drowsy
    Thanh_awake.mp4:  output_folder: Thanh_awake/, label: awake
    Thanh_drowsy.mp4: output_folder: Thanh_drowsy/,label: drowsy

  # File prefix nhận diện own data
  own_prefixes: ["bao_", "dien_", "hkanh_", "hnan_", "thanh_"]

# ══════════════════════════════════════════════════════════════
# Dataset 2 — YAWN_DATA (data/raw/yawn_data/) — MIỆNG ✅ CÓ SẴN
# ══════════════════════════════════════════════════════════════
yawn_data:
  location: "data/raw/yawn_data/"
  note: "Dataset miệng đã có sẵn, có label rõ ràng"
  folders:
    "no yawn/":  label: no_yawn   # Chú ý: tên folder có dấu cách
    "yawn/":     label: yawn
  usage: mouth_dataset directly
  action: >
    Copy/rename sang data/mouth_dataset/{no_yawn,yawn}/
    KHÔNG cần crop thêm nếu ảnh đã là vùng miệng.
    Nếu là ảnh khuôn mặt → cần crop miệng bằng MediaPipe.

# ══════════════════════════════════════════════════════════════
# Dataset 3 — DDD (Kaggle, tùy chọn thêm)
# ══════════════════════════════════════════════════════════════
ddd_dataset:
  kaggle_url: "https://www.kaggle.com/datasets/ismailnasri20/driver-drowsiness-dataset-ddd"
  location: "data/raw/ddd/"
  size: ~41000 images
  label_map:
    "Non Drowsy": awake
    "Drowsy": drowsy
  usage: train only (nếu cần thêm data)

# ══════════════════════════════════════════════════════════════
# Dataset 4 — MRL Eye (Kaggle, cho Eye CNN)
# ══════════════════════════════════════════════════════════════
mrl_eye:
  kaggle_url: "https://www.kaggle.com/datasets/prasadvpatil/mrl-dataset"
  location: "data/raw/mrl_eye/"
  type: eye_crops   # Ảnh mắt crop sẵn, KHÔNG phải khuôn mặt
  label_map:
    Open:   open
    Closed: closed
  usage: eye_dataset only

# ══════════════════════════════════════════════════════════════
# Dataset 5 — UTA-RLDD (Kaggle, tùy chọn)
# ══════════════════════════════════════════════════════════════
uta_rldd:
  kaggle_url: "https://www.kaggle.com/datasets/rishab260/uta-reallife-drowsiness-dataset"
  location: "data/raw/uta_rldd/"
  type: video
  label_map:
    "0":  awake
    "5":  skip
    "10": drowsy
  fps_extract: 3
  usage: train only

# ══════════════════════════════════════════════════════════════
# Dataset 6 — YawDD (Kaggle, tùy chọn — thêm yawn samples)
# ══════════════════════════════════════════════════════════════
yawdd:
  kaggle_url: "https://www.kaggle.com/datasets/enider/yawdd-dataset"
  location: "data/raw/yawdd/"
  type: video (.avi)
  label_logic: "filename contains 'yawning' → drowsy, else → awake"
  fps_extract: 3
  usage: train only
```

### 3.2 Sơ Đồ Luồng Data Thực Tế

```
data/raw/
│
├── drowsy_data/
│   ├── Awake/          ──────────────────────────────→ train/awake/
│   ├── Drowsy/         ──────────────────────────────→ train/drowsy/
│   │
│   ├── Bao_awake/      ─┐
│   ├── Dien_awake/      │  extract landmarks
│   ├── Hkanh_awake/     ├─ crop face 224x224 ──→  70% val/awake/
│   ├── Hnan_awake/      │                          30% test/awake/
│   ├── Thanh_awake/    ─┘
│   │
│   ├── Bao_drowsy/     ─┐
│   ├── Dien_drowsy/     │  extract landmarks
│   ├── Hkanh_drowsy/    ├─ crop face 224x224 ──→  70% val/drowsy/
│   ├── Hnan_drowsy/     │                          30% test/drowsy/
│   ├── Thanh_drowsy/   ─┘
│   │
│   ├── Bao_awake.mp4   ──→ extract 5fps → Bao_awake/   → val+test
│   ├── Bao_drowsy.mp4  ──→ extract 5fps → Bao_drowsy/  → val+test
│   ├── Thanh_awake.mp4 ──→ extract 5fps → Thanh_awake/ → val+test
│   └── Thanh_drowsy.mp4──→ extract 5fps → Thanh_drowsy/→ val+test
│
└── yawn_data/                          ✅ DÙNG TRỰC TIẾP
    ├── no yawn/  ──────────────────────→ mouth_dataset/no_yawn/
    └── yawn/     ──────────────────────→ mouth_dataset/yawn/

⚠️  AGENT CHÚ Ý:
    1. drowsy_data/Awake/ và Drowsy/ → CHỈ train (không rõ người)
    2. Person folders (Bao_*, ...) → val + test (người Việt thật)
    3. yawn_data/ → dùng TRỰC TIẾP cho mouth_dataset (không qua crop)
       Nếu ảnh trong yawn_data/ là khuôn mặt đầy đủ → cần crop miệng
       Nếu ảnh trong yawn_data/ đã là vùng miệng → copy thẳng
    4. AGENT kiểm tra kích thước ảnh trong yawn_data/ để quyết định
```

### 3.3 Kiểm Tra Tự Động yawn_data

```python
# AGENT chạy đoạn này trước khi xử lý yawn_data
import cv2, os

def check_yawn_data_type():
    """
    Kiểm tra ảnh trong yawn_data là:
    - Ảnh miệng crop sẵn (nhỏ, ratio ngang) → copy thẳng
    - Ảnh khuôn mặt đầy đủ (lớn hơn) → cần crop miệng
    """
    for label in ["no yawn", "yawn"]:
        folder = f"data/raw/yawn_data/{label}"
        if not os.path.exists(folder): continue
        files  = [f for f in os.listdir(folder) if f.endswith(('.jpg','.png'))][:5]
        sizes  = []
        for f in files:
            img = cv2.imread(os.path.join(folder, f))
            if img is not None:
                sizes.append(img.shape[:2])  # (h, w)

        if sizes:
            avg_h = sum(h for h,w in sizes) / len(sizes)
            avg_w = sum(w for h,w in sizes) / len(sizes)
            ratio = avg_w / avg_h
            print(f"\n{label}/: avg size = {avg_h:.0f}x{avg_w:.0f}, ratio={ratio:.2f}")

            if avg_h < 150 and avg_w < 250:
                print(f"  → ✅ Ảnh miệng crop sẵn → COPY THẲNG vào mouth_dataset")
                return "direct_copy"
            else:
                print(f"  → ⚠️  Ảnh khuôn mặt → CẦN crop miệng bằng MediaPipe")
                return "need_crop"

data_type = check_yawn_data_type()
```

### 3.4 Minimum Dataset Requirements

```
AGENT PHẢI KIỂM TRA trước khi train:

Face Dataset (từ drowsy_data/):
  train/awake:  ≥ 1500 ảnh  (Awake/ + DDD nếu có + UTA nếu có)
  train/drowsy: ≥ 1500 ảnh  (Drowsy/ + DDD nếu có + UTA nếu có)
  val/awake:    ≥ 300 ảnh   (Bao/Dien/Hkanh/Hnan/Thanh _awake)
  val/drowsy:   ≥ 300 ảnh   (Bao/Dien/Hkanh/Hnan/Thanh _drowsy)
  test/awake:   ≥ 80 ảnh    (CHỈ person folders)
  test/drowsy:  ≥ 80 ảnh    (CHỈ person folders)

Mouth Dataset (từ yawn_data/):
  no_yawn:  ≥ 500 ảnh   (từ yawn_data/no yawn/)
  yawn:     ≥ 500 ảnh   (từ yawn_data/yawn/)
  Nếu thiếu → augment_times lên 6-8

Eye Dataset (crop từ processed/ + MRL nếu có):
  open:   ≥ 3000 ảnh
  closed: ≥ 3000 ảnh

Nếu face dataset < minimum → báo user cần tải DDD từ Kaggle
Nếu mouth dataset < 500/class → tăng augment_times lên 8
```

---

## ⚙️ SECTION 4 — DATA PROCESSING PIPELINE

### 4.1 Script 01 — Extract Video Frames

```python
# scripts/01_extract_frames.py
# AGENT: Extract frames từ 4 video trong data/raw/anh/

import cv2, os, yaml
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

FPS      = cfg["data"]["video_fps_extract"]
RAW_DIR  = "data/raw/drowsy_data"   # ← đường dẫn thực tế

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

# ── 4 video trong data/raw/anh/ ──
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
```

### 4.2 Script 02 — Quality Check & Filter

```python
# scripts/02_check_quality.py
# AGENT: Tự động xóa ảnh không đạt tiêu chuẩn

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
    imgs = [f for f in files if f.endswith('.jpg')]
    if imgs:
        k, r = quality_check_folder(root)
        total_removed += r
        print(f"  {root}: kept={k}, removed={r}")

print(f"\n✅ Total removed: {total_removed} low-quality images")
```

### 4.3 Script 03 — Crop Faces (224x224)

```python
# scripts/03_crop_faces.py
# AGENT: Detect + crop khuôn mặt từ tất cả ảnh raw

import cv2, os, mediapipe as mp
import numpy as np
from tqdm import tqdm

mp_face = mp.solutions.face_detection

RAW_OWN = "data/raw/drowsy_data"   # ← đường dẫn thực tế

# ── Mapping nguồn → label → output ──
# Awake/ và Drowsy/ chung → train
# Person folders → val+test (tagged bằng prefix tên người)
SOURCES = [
    # General folders (không tên người) → TRAIN
    (f"{RAW_OWN}/Awake",         "awake",  "data/processed"),
    (f"{RAW_OWN}/Drowsy",        "drowsy", "data/processed"),

    # Person folders → VAL + TEST (prefix tên người để nhận diện)
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

    # External datasets → TRAIN
    ("data/raw/ddd/Non Drowsy",        "awake",  "data/processed"),
    ("data/raw/ddd/Drowsy",            "drowsy", "data/processed"),
    ("data/raw/uta_frames/awake",      "awake",  "data/processed"),
    ("data/raw/uta_frames/drowsy",     "drowsy", "data/processed"),
    ("data/raw/yawdd_frames/awake",    "awake",  "data/processed"),
    ("data/raw/yawdd_frames/drowsy",   "drowsy", "data/processed"),
]

def crop_face_from_folder(src, label, out_base, size=224):
    out_dir = os.path.join(out_base, label)
    os.makedirs(out_dir, exist_ok=True)
    files = [f for f in os.listdir(src) if f.lower().endswith(('.jpg','.png'))]
    saved = skipped = 0
    src_tag = os.path.basename(src)[:20]

    with mp_face.FaceDetection(model_selection=1, min_detection_confidence=0.55) as det:
        for i, fname in enumerate(tqdm(files, desc=f"  {src_tag}", leave=False)):
            img = cv2.imread(os.path.join(src, fname))
            if img is None: continue
            h, w = img.shape[:2]
            res  = det.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))

            if res.detections:
                bb  = res.detections[0].location_data.relative_bounding_box
                pad = 0.25
                x1  = max(0, int((bb.xmin - bb.width*pad) * w))
                y1  = max(0, int((bb.ymin - bb.height*pad) * h))
                x2  = min(w, int((bb.xmin + bb.width*(1+pad)) * w))
                y2  = min(h, int((bb.ymin + bb.height*(1+pad)) * h))
                face = img[y1:y2, x1:x2]
                if face.size > 0:
                    face = cv2.resize(face, (size, size))
                    cv2.imwrite(
                        os.path.join(out_dir, f"{src_tag}_{i:07d}.jpg"),
                        face, [cv2.IMWRITE_JPEG_QUALITY, 95]
                    )
                    saved += 1; continue
            skipped += 1

    print(f"  {src_tag}/{label}: saved={saved}, skipped={skipped}")
    return saved

if __name__ == "__main__":
    for src, label, out_base in SOURCES:
        if os.path.exists(src):
            crop_face_from_folder(src, label, out_base)
    print("✅ Face cropping complete")
```

### 4.3b Script 03b — Chuẩn Bị Mouth Dataset Từ yawn_data

```python
# scripts/03b_prepare_mouth_dataset.py
# AGENT: Xử lý yawn_data/ → mouth_dataset/
# yawn_data có sẵn, chỉ cần copy + resize về 64x64

import cv2, os, shutil
import numpy as np
from tqdm import tqdm

YAWN_SRC = "data/raw/yawn_data"
MOUTH_OUT = "data/mouth_dataset"

# Mapping tên folder (có dấu cách) → tên chuẩn
LABEL_MAP = {
    "no yawn": "no_yawn",   # ← chú ý dấu cách trong tên folder gốc
    "yawn":    "yawn"
}

def check_image_type(folder, n_sample=5):
    """
    Kiểm tra ảnh trong folder là:
    - Ảnh miệng crop sẵn → copy + resize 64x64
    - Ảnh khuôn mặt đầy đủ → cần crop miệng bằng MediaPipe
    """
    files = [f for f in os.listdir(folder)
             if f.lower().endswith(('.jpg','.png','.jpeg'))][:n_sample]
    if not files:
        return "unknown"

    heights = []
    for f in files:
        img = cv2.imread(os.path.join(folder, f))
        if img is not None:
            heights.append(img.shape[0])

    avg_h = np.mean(heights) if heights else 0
    # Ảnh miệng crop thường nhỏ hơn 200px height
    return "mouth_crop" if avg_h < 200 else "full_face"

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

def crop_mouth_from_face(src_folder, dst_folder, label_out, size=64):
    """Dùng khi ảnh là khuôn mặt đầy đủ → cần crop miệng"""
    import mediapipe as mp
    os.makedirs(dst_folder, exist_ok=True)
    mp_mesh = mp.solutions.face_mesh
    MOUTH_IDX = [61,146,91,181,84,17,314,405,321,375,
                  291,308,324,318,402,317,14,87,178,88,
                  95,78,191,80,81,82,13,312,311,310,415,308]
    files = [f for f in os.listdir(src_folder)
             if f.lower().endswith(('.jpg','.png','.jpeg'))]
    saved = 0
    with mp_mesh.FaceMesh(static_image_mode=True, max_num_faces=1,
                           min_detection_confidence=0.5) as mesh:
        for i, fname in enumerate(tqdm(files, desc=f"  crop mouth {label_out}")):
            img = cv2.imread(os.path.join(src_folder, fname))
            if img is None: continue
            h, w = img.shape[:2]
            res = mesh.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
            if not res.multi_face_landmarks: continue
            lms = res.multi_face_landmarks[0].landmark
            xs = [lms[i].x * w for i in MOUTH_IDX]
            ys = [lms[i].y * h for i in MOUTH_IDX]
            pad = 0.4
            xmin,xmax = min(xs),max(xs); ymin,ymax = min(ys),max(ys)
            pw=(xmax-xmin)*pad; ph=(ymax-ymin)*pad
            x1=max(0,int(xmin-pw)); y1=max(0,int(ymin-ph))
            x2=min(w,int(xmax+pw)); y2=min(h,int(ymax+ph))
            mouth = img[y1:y2, x1:x2]
            if mouth.size == 0: continue
            mouth = cv2.resize(mouth, (size, size))
            cv2.imwrite(os.path.join(dst_folder,
                        f"yawn_{label_out}_{i:06d}.jpg"), mouth)
            saved += 1
    return saved

# ── Chạy chính ──
print("=== Preparing mouth dataset from yawn_data ===")
for src_label, out_label in LABEL_MAP.items():
    src_dir = os.path.join(YAWN_SRC, src_label)
    dst_dir = os.path.join(MOUTH_OUT, out_label)

    if not os.path.exists(src_dir):
        print(f"⚠️  Not found: {src_dir}")
        continue

    img_type = check_image_type(src_dir)
    print(f"\n{src_label}/ → detected as: {img_type}")

    if img_type == "mouth_crop":
        # Ảnh miệng crop sẵn → copy + resize
        n = copy_and_resize(src_dir, dst_dir, out_label, size=64)
    else:
        # Ảnh khuôn mặt → crop miệng
        n = crop_mouth_from_face(src_dir, dst_dir, out_label, size=64)

    print(f"✅ {out_label}: {n} ảnh → {dst_dir}")

# Thống kê
for label in ["no_yawn", "yawn"]:
    d = os.path.join(MOUTH_OUT, label)
    if os.path.exists(d):
        n = len([f for f in os.listdir(d) if f.endswith('.jpg')])
        print(f"  mouth_dataset/{label}: {n} ảnh")
```



### 4.4 Script 04 — Crop Eye Regions (64x64)

```python
# scripts/04_crop_eye.py
# AGENT: Crop vùng MẮT 64x64 từ face dataset để train Eye CNN
# NOTE: Mouth dataset đã xử lý trong script 03b từ yawn_data/ rồi
# Script này CHỈ xử lý EYE region

import cv2, os, mediapipe as mp
import numpy as np, yaml
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

mp_mesh = mp.solutions.face_mesh

# MediaPipe Face Mesh landmark indices
LEFT_EYE_IDX   = [362,382,381,380,374,373,390,249,263,466,388,387,386,385,384,398]
RIGHT_EYE_IDX  = [33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246]
MOUTH_IDX      = [61,146,91,181,84,17,314,405,321,375,291,308,324,318,402,317,
                   14,87,178,88,95,78,191,80,81,82,13,312,311,310,415,308]

EAR_POINTS = dict(
    L_top=[386,387,388], L_bot=[374,380,381], L_left=[362], L_right=[263],
    R_top=[159,158,157], R_bot=[145,153,144], R_left=[33],  R_right=[133]
)

def calc_ear(lms, h, w):
    def p(i): return np.array([lms[i].x*w, lms[i].y*h])
    A = np.linalg.norm(p(386)-p(374)); B = np.linalg.norm(p(387)-p(380))
    C = np.linalg.norm(p(362)-p(263))
    ear_l = (A+B)/(2*C+1e-6)
    A = np.linalg.norm(p(159)-p(145)); B = np.linalg.norm(p(158)-p(153))
    C = np.linalg.norm(p(33) -p(133))
    ear_r = (A+B)/(2*C+1e-6)
    return (ear_l+ear_r)/2

def calc_mar(lms, h, w):
    def p(i): return np.array([lms[i].x*w, lms[i].y*h])
    vert = np.linalg.norm(p(13)-p(14))
    horiz= np.linalg.norm(p(61)-p(291))
    return vert/(horiz+1e-6)

def crop_region(img, lms, indices, size=64, padding=0.4):
    h, w = img.shape[:2]
    xs = [lms[i].x*w for i in indices]
    ys = [lms[i].y*h for i in indices]
    xmin,xmax = min(xs),max(xs); ymin,ymax = min(ys),max(ys)
    pw=(xmax-xmin)*padding; ph=(ymax-ymin)*padding
    x1=max(0,int(xmin-pw)); y1=max(0,int(ymin-ph))
    x2=min(w,int(xmax+pw)); y2=min(h,int(ymax+ph))
    r = img[y1:y2, x1:x2]
    return cv2.resize(r,(size,size)) if r.size>0 else None

EAR_TH = cfg["thresholds"]["ear"]
MAR_TH = cfg["thresholds"]["mar"]

def process_for_eye_mouth(face_folder, face_label, eye_out, mouth_out):
    """
    Từ ảnh khuôn mặt → crop eye + mouth với auto-label
    face_label=awake → eye=open, mouth=no_yawn (theo EAR/MAR)
    face_label=drowsy → có thể cả 2 label tùy EAR/MAR
    """
    files = [f for f in os.listdir(face_folder) if f.endswith('.jpg')]

    with mp_mesh.FaceMesh(static_image_mode=True, max_num_faces=1,
                          refine_landmarks=True,
                          min_detection_confidence=0.5) as mesh:
        for i, fname in enumerate(tqdm(files, desc=face_folder[-25:], leave=False)):
            img = cv2.imread(os.path.join(face_folder, fname))
            if img is None: continue
            h, w = img.shape[:2]
            res = mesh.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
            if not res.multi_face_landmarks: continue
            lms = res.multi_face_landmarks[0].landmark

            ear = calc_ear(lms, h, w)
            mar = calc_mar(lms, h, w)

            # ── Eye crop ──
            eye_all_idx = list(set(LEFT_EYE_IDX + RIGHT_EYE_IDX))
            eye_crop = crop_region(img, lms, eye_all_idx, 64, padding=0.5)
            if eye_crop is not None:
                # Auto-label bằng EAR
                if face_label == "awake":
                    eye_label = "open"
                elif face_label == "drowsy":
                    eye_label = "closed" if ear < EAR_TH else "open"
                else:
                    eye_label = "closed" if ear < EAR_TH else "open"

                out = os.path.join(eye_out, eye_label)
                os.makedirs(out, exist_ok=True)
                cv2.imwrite(os.path.join(out, f"{face_label}_{i:07d}.jpg"), eye_crop)

            # ── Mouth crop ──
            mouth_crop = crop_region(img, lms, MOUTH_IDX, 64, padding=0.4)
            if mouth_crop is not None:
                # Auto-label bằng MAR
                mouth_label = "yawn" if mar > MAR_TH else "no_yawn"
                out = os.path.join(mouth_out, mouth_label)
                os.makedirs(out, exist_ok=True)
                cv2.imwrite(os.path.join(out, f"{face_label}_{i:07d}.jpg"), mouth_crop)

# Chạy với tất cả processed data
for label in ["awake", "drowsy"]:
    folder = f"data/processed/{label}"
    if os.path.exists(folder):
        process_for_eye_mouth(folder, label, "data/eye_dataset", "data/mouth_dataset")

# Thêm MRL Eye dataset trực tiếp vào eye_dataset
mrl_mapping = {"Open": "open", "Closed": "closed"}
for mrl_label, eye_label in mrl_mapping.items():
    src = f"data/raw/mrl_eye/{mrl_label}"
    if os.path.exists(src):
        import shutil
        dst = f"data/eye_dataset/{eye_label}"
        os.makedirs(dst, exist_ok=True)
        for f in os.listdir(src):
            if f.endswith(('.jpg','.png')):
                shutil.copy(os.path.join(src,f), os.path.join(dst,f"mrl_{f}"))

print("✅ Eye & mouth regions cropped")
```

### 4.5 Script 05 — Split Dataset

```python
# scripts/05_split_dataset.py
# AGENT: Split data theo tỉ lệ trong config.yaml
# QUAN TRỌNG: own dataset → CHỈ đưa vào val + test

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
    """
    task: "face" | "eye" | "mouth"
    test_from_own_only: nếu True, chỉ copy own_ files vào test
    """
    for label in os.listdir(src_dir):
        src   = os.path.join(src_dir, label)
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

            # Own data prefixes (person folders từ data/raw/anh/)
            own_prefixes = ("bao_", "dien_", "hkanh_", "hnan_", "thanh_")

            for fname in tqdm(split_files, desc=f"{task}/{split}/{label}", leave=False):
                # Test set: chỉ lấy file có prefix tên người (own dataset)
                if split == "test" and test_from_own_only:
                    if not fname.lower().startswith(own_prefixes):
                        continue  # Bỏ qua non-own files cho test set
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
    for split in ["train","val","test"]:
        for label in os.listdir(f"data/splits/{task}/{split}"):
            n = len(os.listdir(f"data/splits/{task}/{split}/{label}"))
            print(f"  {split}/{label}: {n}")
```

### 4.6 Script 06 — Augmentation

```python
# scripts/06_augment.py
# AGENT: Augment TRAINING SET ONLY — không augment val/test

import cv2, os, yaml
import albumentations as A
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

TIMES = cfg["training"]["augment_times"]

# Augmentation pipeline — tối ưu cho driving conditions
augmentor = A.Compose([
    A.HorizontalFlip(p=0.5),
    A.Rotate(limit=15, p=0.4),
    A.ShiftScaleRotate(shift_limit=0.05, scale_limit=0.1,
                       rotate_limit=10, p=0.4),
    # Lighting variations — quan trọng cho điều kiện lái xe
    A.RandomBrightnessContrast(brightness_limit=0.35,
                                contrast_limit=0.35, p=0.6),
    A.HueSaturationValue(hue_shift_limit=10,
                          sat_shift_limit=25, val_shift_limit=25, p=0.4),
    A.RandomGamma(gamma_limit=(60, 140), p=0.3),
    A.CLAHE(clip_limit=4.0, p=0.25),
    # Night driving simulation
    A.RandomBrightnessContrast(brightness_limit=(-0.5,-0.1), p=0.15),
    # Sensor noise
    A.GaussNoise(var_limit=(10, 60), p=0.3),
    A.GaussianBlur(blur_limit=(3,5), p=0.2),
    A.MotionBlur(blur_limit=5, p=0.2),
    # Partial occlusion (tay che mặt, kính)
    A.CoarseDropout(max_holes=4, max_height=25, max_width=25,
                    min_holes=1, p=0.2),
])

def augment_folder(folder, times=TIMES):
    files   = [f for f in os.listdir(folder) if f.endswith('.jpg')]
    added   = 0
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
    for label in os.listdir(f"data/splits/{task}/train"):
        folder = f"data/splits/{task}/train/{label}"
        if os.path.isdir(folder):
            n = augment_folder(folder)
            total += n
            count = len(os.listdir(folder))
            print(f"  {task}/train/{label}: {count} total (added {n})")

print(f"\n✅ Augmentation complete. Total added: {total}")
```

---

## 🧠 SECTION 5 — MODEL ARCHITECTURE

### 5.1 Tổng Quan Kiến Trúc

```
KIẾN TRÚC: Multi-Feature Fusion (Hybrid Rule-Based + Deep Learning)

                    ┌─────────────────────────────────────────┐
                    │         CAMERA FRAME (BGR)               │
                    └────────────────┬────────────────────────┘
                                     │
                    ┌────────────────▼────────────────────────┐
                    │    MediaPipe Face Mesh (478 landmarks)   │
                    │    Detection confidence: 0.6             │
                    └──────┬──────────┬──────────┬────────────┘
                           │          │          │
             ┌─────────────▼──┐ ┌─────▼─────┐ ┌─▼──────────────┐
             │   EYE REGION   │ │   MOUTH   │ │   HEAD POSE    │
             │   Crop 64x64   │ │  Crop 64x64│ │  solvePnP 3D  │
             └───────┬────────┘ └─────┬─────┘ └────────┬───────┘
                     │                │                 │
        ┌────────────┼───────┐        │        ┌────────┴──────────┐
        ▼            ▼       ▼        ▼        ▼                   ▼
   ┌─────────┐ ┌─────────┐ EAR   ┌─────────┐ MAR            Pitch/Yaw/Roll
   │Eye CNN  │ │EAR rule │ calc  │Yawn CNN │ calc               angles
   │MobileV2 │ │< 0.25   │       │MobileV2 │
   │alpha=.35│ │→ closed │       │alpha=.35│
   │(trained)│ │         │       │(trained)│
   └────┬────┘ └────┬────┘       └────┬────┘
        │           │                 │
        │    PERCLOS calc             │  Yawn decay counter
        │    (90-frame window)        │  (rises fast, decays slow)
        │           │                 │
        └─────────┬─┘                 │
                  │     ┌─────────────┘
                  │     │
        ┌─────────▼─────▼──────────────────────┐
        │         WEIGHTED FUSION               │
        │  score = 0.30×eye_cnn                 │
        │        + 0.20×ear_perclos             │
        │        + 0.25×yawn_counter            │
        │        + 0.25×head_pose_score         │
        └──────────────────┬───────────────────┘
                           │
        ┌──────────────────▼───────────────────┐
        │       TEMPORAL SMOOTHER               │
        │  sliding_window = 30 frames           │
        │  drowsy_counter++ / --                │
        │  alert if counter ≥ 20                │
        └──────────────────┬───────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
           "awake"      "warning"    "drowsy"
         score<0.35   0.35-0.55    score>0.55
```

### 5.2 Eye CNN Architecture

```python
# Dùng MobileNetV2 alpha=0.35 — nhẹ nhất, vẫn đủ chính xác cho 64x64
# Input: (64, 64, 3) — ảnh mắt crop
# Output: sigmoid → 0=open, 1=closed

import tensorflow as tf
from tensorflow.keras import layers, models, regularizers
from tensorflow.keras.applications import MobileNetV2

def build_eye_cnn(input_size=64):
    base = MobileNetV2(
        input_shape = (input_size, input_size, 3),
        include_top = False,
        weights     = "imagenet",
        alpha       = 0.35
    )
    base.trainable = False

    inp = tf.keras.Input(shape=(input_size, input_size, 3))
    x   = tf.keras.applications.mobilenet_v2.preprocess_input(inp)
    x   = base(x, training=False)
    x   = layers.GlobalAveragePooling2D()(x)
    x   = layers.Dense(64, activation="relu",
                        kernel_regularizer=regularizers.l2(1e-4))(x)
    x   = layers.BatchNormalization()(x)
    x   = layers.Dropout(0.35)(x)
    out = layers.Dense(1, activation="sigmoid")(x)

    model = tf.keras.Model(inp, out)
    model.compile(
        optimizer = tf.keras.optimizers.Adam(0.001),
        loss      = "binary_crossentropy",
        metrics   = ["accuracy",
                     tf.keras.metrics.AUC(name="auc"),
                     tf.keras.metrics.Precision(name="precision"),
                     tf.keras.metrics.Recall(name="recall")]
    )
    return model, base

def build_yawn_cnn(input_size=64):
    # Giống Eye CNN — chỉ khác data input
    return build_eye_cnn(input_size)  # Reuse architecture
```

### 5.3 Training Function

```python
# scripts/08_train_eye.py & scripts/09_train_yawn.py
# AGENT: Dùng function này cho cả 2 models, chỉ thay đổi data path

import tensorflow as tf
import yaml, os, json
from datetime import datetime

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

def train_model(task, model, base, data_dir, model_out_dir):
    """
    task: "eye" | "yawn"
    """
    os.makedirs(model_out_dir, exist_ok=True)
    ts    = datetime.now().strftime("%Y%m%d_%H%M%S")
    isize = cfg["data"]["img_size_region"]
    bs    = cfg["training"]["batch_size"]

    # ── Data ──
    def load_ds(split):
        return tf.keras.utils.image_dataset_from_directory(
            os.path.join(data_dir, split),
            image_size   = (isize, isize),
            batch_size   = bs,
            label_mode   = "binary",
            shuffle      = (split=="train"),
            seed         = cfg["project"]["seed"]
        ).cache().prefetch(tf.data.AUTOTUNE)

    train_ds = load_ds("train")
    val_ds   = load_ds("val")
    print(f"Classes: {train_ds.class_names}")

    # Class weights
    import numpy as np
    labels = np.concatenate([y.numpy() for _, y in train_ds]).flatten()
    n0, n1 = np.sum(labels==0), np.sum(labels==1)
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

    # ── Phase 1 ──
    print(f"\n{'='*50}\nPHASE 1: Training head — {task.upper()}\n{'='*50}")
    h1 = model.fit(train_ds, validation_data=val_ds,
                   epochs=cfg["training"]["epochs_phase1"],
                   class_weight=cw, callbacks=callbacks(1), verbose=1)

    # ── Phase 2: Fine-tune ──
    print(f"\n{'='*50}\nPHASE 2: Fine-tuning — {task.upper()}\n{'='*50}")
    base.trainable = True
    for layer in base.layers[:-cfg["models"]["eye_cnn"]["unfreeze_layers"]]:
        layer.trainable = False

    model.compile(
        optimizer = tf.keras.optimizers.Adam(cfg["training"]["lr_phase2"]),
        loss      = "binary_crossentropy",
        metrics   = ["accuracy",
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

    # Lưu kết quả
    with open(f"{model_out_dir}/train_results.json","w") as f:
        json.dump({"task":task,"val_auc":best_auc,"val_accuracy":best_acc,
                   "timestamp":ts}, f, indent=2)
    return model
```

---

## 📊 SECTION 6 — EVALUATION PROTOCOL

### 6.1 Script 10 — Đánh Giá Model

```python
# scripts/10_evaluate.py
# AGENT: Chạy evaluate sau khi train xong TỪNG model
# Target: Eye CNN AUC ≥ 0.97, Yawn CNN AUC ≥ 0.95

import tensorflow as tf
import numpy as np, matplotlib.pyplot as plt, json, os
import seaborn as sns
from sklearn.metrics import (classification_report, confusion_matrix,
                              roc_curve, auc, precision_recall_curve)

def evaluate_model(model_path, test_dir, task, input_size, out_dir="results"):
    os.makedirs(out_dir, exist_ok=True)
    model = tf.keras.models.load_model(model_path)

    test_ds = tf.keras.utils.image_dataset_from_directory(
        test_dir, image_size=(input_size,input_size),
        batch_size=32, label_mode="binary", shuffle=False
    )
    class_names = test_ds.class_names

    y_scores = model.predict(test_ds, verbose=1).flatten()
    y_pred   = (y_scores > 0.5).astype(int)
    y_true   = np.concatenate([y.numpy() for _,y in test_ds]).flatten().astype(int)

    report = classification_report(y_true, y_pred,
                                    target_names=class_names, digits=4, output_dict=True)
    print(f"\n{'='*50}")
    print(f"EVALUATION: {task.upper()}")
    print('='*50)
    print(classification_report(y_true, y_pred, target_names=class_names, digits=4))

    # ROC AUC
    fpr, tpr, _ = roc_curve(y_true, y_scores)
    roc_auc_val = auc(fpr, tpr)
    print(f"ROC AUC: {roc_auc_val:.4f}")

    # Optimal threshold
    prec, rec, thrs = precision_recall_curve(y_true, y_scores)
    f1s = 2*prec*rec/(prec+rec+1e-8)
    best_thr = thrs[np.argmax(f1s[:-1])]
    print(f"Optimal threshold: {best_thr:.3f}")

    # Plots
    fig, axes = plt.subplots(1,3, figsize=(18,5))
    fig.suptitle(f"{task.upper()} Evaluation", fontsize=14, fontweight='bold')

    cm = confusion_matrix(y_true, y_pred, normalize='true')
    sns.heatmap(cm, annot=True, fmt='.2%', ax=axes[0],
                xticklabels=class_names, yticklabels=class_names, cmap='Blues')
    axes[0].set_title('Confusion Matrix')

    axes[1].plot(fpr, tpr, '#00d4ff', lw=2, label=f'AUC={roc_auc_val:.4f}')
    axes[1].plot([0,1],[0,1],'k--'); axes[1].legend()
    axes[1].set_title('ROC Curve')

    axes[2].plot(rec[:-1], prec[:-1], '#ff6b35', lw=2)
    axes[2].set_title('Precision-Recall Curve')

    plt.tight_layout()
    plt.savefig(f"{out_dir}/{task}_evaluation.png", dpi=150)
    plt.close()

    result = {
        "task": task, "roc_auc": roc_auc_val,
        "accuracy": report["accuracy"],
        "optimal_threshold": float(best_thr),
        "report": report
    }
    with open(f"{out_dir}/{task}_results.json","w") as f:
        json.dump(result, f, indent=2)

    # ── AGENT: Kiểm tra target ──
    targets = {"eye": 0.97, "yawn": 0.95, "face": 0.95}
    target  = targets.get(task, 0.92)
    if roc_auc_val >= target:
        print(f"\n✅ {task} PASSED: AUC={roc_auc_val:.4f} ≥ {target}")
    else:
        print(f"\n❌ {task} FAILED: AUC={roc_auc_val:.4f} < {target}")
        print("   → Cần thêm data hoặc điều chỉnh hyperparameter")
    return result
```

### 6.2 Evaluation Targets (AGENT Phải Đạt)

```yaml
# AGENT: Nếu không đạt → thực hiện fallback action tương ứng

evaluation_targets:
  eye_cnn:
    val_auc:      0.97
    val_accuracy: 0.95
    fallback:
      - "Tăng augment_times lên 6"
      - "Unfreeze thêm 20 layers: unfreeze_layers = 50"
      - "Giảm dropout: 0.35 → 0.25"

  yawn_cnn:
    val_auc:      0.95
    val_accuracy: 0.93
    fallback:
      - "Kiểm tra lại auto-label MAR threshold (thử 0.55)"
      - "Tăng augment_times lên 6"
      - "Thêm manual yawn samples nếu < 2000"

  overall_pipeline:
    accuracy: 0.95
    false_alarm_rate: 0.05   # Tối đa 5% false alarm
    miss_rate: 0.04          # Tối đa 4% bỏ sót
    latency_rpi4_ms: 80
```

---

## 🚀 SECTION 7 — EXPORT & DEPLOYMENT

### 7.1 Script 11 — Export TFLite

```python
# scripts/11_export_tflite.py
# AGENT: Export sau khi cả 2 model đạt target accuracy

import tensorflow as tf
import numpy as np, os, json, time, yaml

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

def export_tflite(model_path, task, data_dir_for_calib, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    model = tf.keras.models.load_model(model_path)
    isize = cfg["data"]["img_size_region"]

    # ── Calibration dataset ──
    def rep_dataset():
        import cv2
        calib_dir = os.path.join(data_dir_for_calib, "train")
        label_dir = os.path.join(calib_dir, os.listdir(calib_dir)[0])
        files = os.listdir(label_dir)[:200]
        for fname in files:
            img = cv2.imread(os.path.join(label_dir, fname))
            if img is None: continue
            img = cv2.resize(img, (isize, isize)).astype(np.float32)
            img = (img / 127.5) - 1.0
            yield [np.expand_dims(img, 0)]

    # INT8 Quantized
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

    # Benchmark inference
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

# Export cả 2 models
export_tflite("models/eye_cnn/final.h5",  "eye",  "data/splits/eye",   "models/eye_cnn")
export_tflite("models/yawn_cnn/final.h5", "yawn", "data/splits/mouth", "models/yawn_cnn")
```

### 7.2 Script 12 — Validate Full Pipeline

```python
# scripts/12_validate_pipeline.py
# AGENT: Test toàn bộ fusion pipeline trên test set

import cv2, numpy as np, os, json, yaml, time
import mediapipe as mp
import tflite_runtime.interpreter as tflite
from tqdm import tqdm

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

THR = cfg["thresholds"]
W   = cfg["fusion_weights"]

# Load pipeline
from pipeline.drowsiness_detector import DrowsinessDetectorV2

detector = DrowsinessDetectorV2(
    eye_model_path  = "models/eye_cnn/eye_model.tflite",
    yawn_model_path = "models/yawn_cnn/yawn_model.tflite",
    config_path     = "config.yaml"
)

# Test với ảnh tĩnh (không phải video)
def test_on_images(test_dir):
    results = {"awake": {"correct":0,"total":0}, "drowsy":{"correct":0,"total":0}}

    for true_label in ["awake","drowsy"]:
        folder = os.path.join(test_dir, true_label)
        if not os.path.exists(folder): continue
        files  = [f for f in os.listdir(folder) if f.endswith('.jpg')]

        for fname in tqdm(files, desc=f"Test {true_label}"):
            img    = cv2.imread(os.path.join(folder, fname))
            if img is None: continue
            result = detector.process_frame(img)
            pred   = result["status"]
            results[true_label]["total"] += 1
            if (true_label == "drowsy" and pred in ["drowsy","warning"]) or \
               (true_label == "awake"  and pred == "awake"):
                results[true_label]["correct"] += 1

    # Summary
    print("\n" + "="*50)
    print("PIPELINE VALIDATION RESULTS")
    print("="*50)
    total_correct = total_all = 0
    for label, r in results.items():
        acc = r["correct"]/max(r["total"],1)
        total_correct += r["correct"]
        total_all     += r["total"]
        print(f"  {label:10s}: {acc:.2%} ({r['correct']}/{r['total']})")

    overall = total_correct / max(total_all, 1)
    print(f"\n  Overall:   {overall:.2%}")

    target = cfg["targets"]["accuracy_overall"]
    if overall >= target:
        print(f"\n✅ PIPELINE PASSED: {overall:.2%} ≥ {target:.0%}")
    else:
        print(f"\n❌ PIPELINE FAILED: {overall:.2%} < {target:.0%}")
        print("   → Điều chỉnh fusion_weights trong config.yaml")

    with open("results/pipeline_validation.json","w") as f:
        json.dump({"overall": overall, "per_class": results,
                   "target": target, "passed": overall>=target}, f, indent=2)

test_on_images("data/splits/face/test")
```

---

## 📋 SECTION 8 — EXECUTION ORDER

### 8.1 Agent Thực Hiện Theo Thứ Tự Này

```
╔══════════════════════════════════════════════════════════════╗
║          EXECUTION SEQUENCE FOR AI AGENT                     ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  PHASE 0 — SETUP (thực hiện 1 lần)                          ║
║  ├── Đọc config.yaml                                         ║
║  ├── Tạo toàn bộ thư mục theo Section 1.1                    ║
║  ├── Cài dependencies                                         ║
║  └── Kiểm tra GPU                                            ║
║                                                              ║
║  PHASE 1 — DATA PREPARATION                                  ║
║  ├── script 01:  Extract 4 video trong drowsy_data/           ║
║  ├── script 02:  Quality check & filter                       ║
║  ├── script 03:  Crop faces 224x224 từ drowsy_data/           ║
║  ├── script 03b: Chuẩn bị mouth_dataset từ yawn_data/  ⭐    ║
║  │               (tự detect loại ảnh → copy hoặc crop)       ║
║  ├── script 04:  Crop eye regions 64x64                       ║
║  ├── CHECK:      Verify dataset counts ≥ minimum             ║
║  ├── script 05:  Split train/val/test                         ║
║  │               drowsy_data persons → val+test               ║
║  │               Awake/Drowsy general → train                 ║
║  └── script 06:  Augment training data                        ║
║                                                              ║
║  PHASE 2 — TRAINING                                          ║
║  ├── script 08: Train Eye CNN (data/splits/eye/)              ║
║  ├── CHECK: Eye CNN val_AUC ≥ 0.97?                          ║
║  │   └── NO → Apply fallback                                  ║
║  ├── script 09: Train Yawn CNN (data/splits/mouth/)           ║
║  └── CHECK: Yawn CNN val_AUC ≥ 0.95?                        ║
║                                                              ║
║  PHASE 3 — EVALUATION                                        ║
║  ├── script 10: Evaluate Eye CNN                              ║
║  ├── script 10: Evaluate Yawn CNN                             ║
║  └── Generate evaluation report                              ║
║                                                              ║
║  PHASE 4 — EXPORT                                            ║
║  ├── script 11: Export TFLite (INT8 quantized)               ║
║  └── Benchmark inference speed                               ║
║                                                              ║
║  PHASE 5 — VALIDATION                                        ║
║  ├── script 12: Validate full fusion pipeline                 ║
║  ├── CHECK: Overall accuracy ≥ 95%?                          ║
║  │   └── NO → Tune fusion_weights in config.yaml             ║
║  └── Generate final report                                   ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

### 8.2 Decision Logic Cho Agent

```python
# AGENT tuân theo logic này ở mỗi checkpoint

def agent_checkpoint(task, metric_name, actual_value, target_value, fallbacks):
    """
    Được gọi sau mỗi bước training/evaluation
    """
    if actual_value >= target_value:
        print(f"✅ CHECKPOINT PASSED: {task} {metric_name}={actual_value:.4f}")
        return "CONTINUE"
    else:
        print(f"⚠️  CHECKPOINT FAILED: {task} {metric_name}={actual_value:.4f} < {target_value}")
        print(f"   Applying fallback #{len(fallbacks)} strategies:")
        for i, fb in enumerate(fallbacks):
            print(f"   {i+1}. {fb}")

        # Nếu đã thử hết fallback → dừng và báo user
        print("\n   → Cần thêm data thực tế. Hãy:")
        print("   1. Quay thêm video ngáp + gật đầu")
        print("   2. Tải thêm dataset từ Kaggle")
        print("   3. Kiểm tra data labeling quality")
        return "RETRY_WITH_FALLBACK"
```

---

## ✅ SECTION 9 — FINAL DELIVERABLES

### 9.1 Agent Phải Tạo Ra Các File Sau

```
models/
├── eye_cnn/
│   ├── best_p1.h5           ← Phase 1 checkpoint
│   ├── best_p2.h5           ← Phase 2 checkpoint
│   ├── final.h5             ← Final model
│   ├── eye_model.tflite     ← Quantized TFLite
│   └── train_results.json   ← Training metrics
│
├── yawn_cnn/
│   ├── final.h5
│   ├── yawn_model.tflite
│   └── train_results.json
│
└── fusion/
    └── config.json          ← Optimal thresholds + weights

results/
├── eye_evaluation.png       ← Confusion matrix + ROC
├── yawn_evaluation.png
├── eye_results.json         ← Classification report
├── yawn_results.json
├── pipeline_validation.json ← Overall pipeline accuracy
└── FINAL_REPORT.md          ← Summary cho user
```

### 9.2 FINAL_REPORT.md Template

```markdown
# DMS Model Training Report
**Date:** {timestamp}
**Project:** IVI Automotive Capstone

## Dataset Summary
- Total awake images: {n}
- Total drowsy images: {n}
- Test set: {n} images (own dataset — người Việt)

## Model Performance
| Model     | Val AUC | Val Acc | Test Acc | Status |
|-----------|---------|---------|----------|--------|
| Eye CNN   | {val}   | {val}   | {test}   | ✅/❌  |
| Yawn CNN  | {val}   | {val}   | {test}   | ✅/❌  |
| Pipeline  | —       | —       | {test}   | ✅/❌  |

## TFLite Export
| Model    | Size    | Host Inf. | RPi4 Est. |
|----------|---------|-----------|-----------|
| Eye CNN  | {kb} KB | {ms}ms    | {ms*3}ms  |
| Yawn CNN | {kb} KB | {ms}ms    | {ms*3}ms  |

## Optimal Thresholds (từ PR Curve)
- Eye threshold:   {thr}
- Yawn threshold:  {thr}
- Fusion alert:    {thr}

## Deployment
Copy sang RPi4:
  scp models/eye_cnn/eye_model.tflite pi@192.168.1.100:~/IVI-Automative-Capstone-Project/models/
  scp models/yawn_cnn/yawn_model.tflite pi@192.168.1.100:~/IVI-Automative-Capstone-Project/models/
```

---

## ⚠️ SECTION 10 — LƯU Ý QUAN TRỌNG CHO AGENT

```
1. KHÔNG BAO GIỜ:
   ✗ Augment val/test set
   ✓ Awake/, Drowsy/ (không tên người) → CHỈ train, KHÔNG đưa vào val/test
   ✓ Bao_*, Dien_*, Hkanh_*, Hnan_*, Thanh_* → val + test (người Việt Nam thật)
   ✗ Dùng MRL Eye dataset trong face classifier
   ✗ Bỏ qua checkpoint validation

2. LUÔN LUÔN:
   ✓ Đọc config.yaml trước khi làm bất cứ điều gì
   ✓ Kiểm tra dataset count trước khi train
   ✓ Set random seed = 42 (reproducibility)
   ✓ Save model checkpoint sau mỗi epoch tốt nhất
   ✓ Log tất cả metrics vào results/

3. ĐIỀU CHỈNH KHI CẦN:
   → Nếu GPU VRAM < 4GB: giảm batch_size xuống 16
   → Nếu thiếu data: tăng augment_times lên 6-8
   → Nếu overfitting: tăng dropout lên 0.5
   → Nếu underfitting: unfreeze thêm layers

4. TEST SET LÀ THIÊNG LIÊNG:
   → Chỉ dùng test set 1 lần duy nhất ở cuối
   → Không dùng test metrics để tune hyperparameter
   → Chỉ val set mới được dùng để tune

5. THÔNG BÁO CHO USER NẾU:
   → Dataset quá ít (< minimum)
   → Accuracy sau fallback vẫn không đạt target
   → Inference time > 120ms trên host
   → Imbalance ratio < 0.7
```

---

*IVI Automotive Capstone — DMS AI Agent Specification v2.2*
*Data: data/raw/drowsy_data/ + data/raw/yawn_data/*
*People: Bao, Dien, Hkanh, Hnan, Thanh | Hardware: Raspberry Pi 4 aarch64*
