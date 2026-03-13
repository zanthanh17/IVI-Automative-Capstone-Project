# 🚗 DMS Drowsiness Detection

> Driver Monitoring System — Phát hiện buồn ngủ tài xế bằng Computer Vision & Deep Learning.

**Multi-Feature Fusion** kết hợp Eye CNN + EAR/PERCLOS + Yawn CNN + Head Pose, triển khai trên Raspberry Pi 4.

| Metric | Kết quả |
|--------|---------|
| Pipeline Accuracy | **100%** (4/4 video) |
| Avg Latency | **5.9 ms/frame** |
| FPS | **171 fps** (host) |
| Model Size | **690 KB** × 2 (INT8 TFLite) |

---

## 📋 Yêu Cầu Hệ Thống

| Thành phần | Yêu cầu |
|-----------|---------|
| **OS** | Ubuntu 22.04+ / WSL2 (Windows 10/11) |
| **Python** | 3.10.x (khuyến nghị 3.10.12) |
| **GPU** *(khuyến nghị)* | NVIDIA GPU có CUDA ≥ 12.x + Driver ≥ 535 |
| **RAM** | ≥ 8 GB |
| **Disk** | ≥ 10 GB trống (dataset + models) |

> ⚠ **Nếu dùng WSL2:** Cần cài NVIDIA GPU Driver trên Windows. **Không cần** cài CUDA Toolkit riêng — TensorFlow tự bundle CUDA 12.5.

---

## 🚀 Hướng Dẫn Cài Đặt

### 1. Clone Repository

```bash
git clone <repo-url>
cd drowsy_detection
```

### 2. Tạo Virtual Environment

```bash
python3 -m venv drowsy_env
source drowsy_env/bin/activate
```

### 3. Cài Dependencies

**Với GPU (khuyến nghị):**

```bash
pip install --upgrade pip
pip install --default-timeout=1000 -r requirements.txt
```

**Với CPU only** — sửa `requirements.txt` trước:

```bash
# Thay dòng tensorflow[and-cuda]==2.18.0 thành:
#   tensorflow==2.18.0
pip install --upgrade pip
pip install --default-timeout=1000 -r requirements.txt
```

### 4. Cấu Hình GPU (WSL2 Only)

Thêm vào `~/.bashrc` hoặc `~/.zshrc`:

```bash
export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH
```

Sau đó reload:

```bash
source ~/.zshrc   # hoặc ~/.bashrc
```

### 5. Kiểm Tra Môi Trường

```bash
python scripts/check_env.py
```

Hoặc kiểm tra thủ công:

```bash
python -c "
import tensorflow as tf
print('TF version:', tf.__version__)
print('GPU:', tf.config.list_physical_devices('GPU'))
import mediapipe as mp
print('MediaPipe:', mp.__version__)
import cv2
print('OpenCV:', cv2.__version__)
"
```

**Output mong đợi:**

```
TF version: 2.18.0
GPU: [PhysicalDevice(name='/physical_device:GPU:0', device_type='GPU')]
MediaPipe: 0.10.14
OpenCV: 4.x.x
```

> Nếu `GPU: []` → kiểm tra lại bước 4 (LD_LIBRARY_PATH) và driver NVIDIA.

---

## 📂 Cấu Trúc Dự Án

```
drowsy_detection/
├── config.yaml                  # ⚙ Cấu hình toàn bộ pipeline
├── requirements.txt             # 📦 Dependencies
│
├── data/
│   ├── raw/                     # Dữ liệu gốc (tự chuẩn bị)
│   │   ├── drowsy_data/         #   Ảnh khuôn mặt + video MP4
│   │   └── yawn_data/           #   Ảnh miệng ngáp/không ngáp
│   ├── processed/               # [auto] Face crops 224×224
│   ├── eye_dataset/             # [auto] Eye crops 64×64
│   ├── mouth_dataset/           # [auto] Mouth data
│   └── splits/                  # [auto] Train/Val/Test splits
│
├── scripts/                     # 📜 Pipeline scripts (chạy theo thứ tự)
│   ├── 01_extract_frames.py
│   ├── 02_check_quality.py
│   ├── 03_crop_faces.py
│   ├── 03b_prepare_mouth.py
│   ├── 04_crop_eye.py
│   ├── 05_split_dataset.py
│   ├── 06_augment.py
│   ├── 08_train_eye.py
│   ├── 09_train_yawn.py
│   ├── 10_evaluate.py
│   ├── 11_export_tflite.py
│   └── 12_validate_pipeline.py
│
├── pipeline/                    # 🔧 Runtime inference modules
│   ├── drowsiness_detector.py   #   DrowsinessDetectorV2 (main)
│   ├── feature_extractor.py     #   EAR, MAR, crop functions
│   └── head_pose.py             #   Head pose estimation
│
├── models/                      # 🧠 Trained models
│   ├── eye_cnn/
│   │   ├── eye_model.tflite     #   ← Deploy (690 KB)
│   │   └── final_fixed.keras    #   Full Keras model
│   └── yawn_cnn/
│       ├── yawn_model.tflite    #   ← Deploy (690 KB)
│       └── final_fixed.keras
│
├── results/                     # 📊 Evaluation outputs
│   ├── *_results.json
│   ├── *_evaluation.png
│   └── pipeline_validation.json
│
├── logs/                        # 📝 Training logs
└── docs/
    ├── DMS_AI_AGENT_PROMPT(1).md
    └── SUMMARY.md               # Báo cáo tổng kết chi tiết
```

---

## 🔄 Chạy Pipeline Từ Đầu

### Bước 0 — Chuẩn Bị Dữ Liệu

Đặt dữ liệu vào `data/raw/`:

```
data/raw/
├── drowsy_data/
│   ├── Awake/          # Ảnh mắt mở (Kaggle)
│   ├── Drowsy/         # Ảnh mắt nhắm (Kaggle)
│   ├── {Name}_awake/   # Ảnh người cụ thể (tự chụp)
│   ├── {Name}_drowsy/
│   ├── {Name}_awake.mp4   # Video test
│   └── {Name}_drowsy.mp4
└── yawn_data/
    ├── yawn/           # Ảnh đang ngáp
    └── no yawn/        # Ảnh không ngáp
```

### Bước 1–6 — Xử Lý Dữ Liệu

```bash
source drowsy_env/bin/activate

python scripts/01_extract_frames.py    # Trích frame từ video (5fps)
python scripts/02_check_quality.py     # Lọc ảnh mờ/tối
python scripts/03_crop_faces.py        # Crop mặt 224×224
python scripts/03b_prepare_mouth.py    # Copy dữ liệu miệng
python scripts/04_crop_eye.py          # Crop mắt 64×64
python scripts/05_split_dataset.py     # Chia train/val/test
python scripts/06_augment.py           # Augment 4x
```

### Bước 7 — Training

```bash
python scripts/08_train_eye.py         # ~25 phút (GPU)
python scripts/09_train_yawn.py        # ~40 phút (GPU)
```

### Bước 8 — Đánh Giá & Export

```bash
python scripts/10_evaluate.py          # Metrics + charts
python scripts/11_export_tflite.py     # INT8 quantization
python scripts/12_validate_pipeline.py # End-to-end test
```

---

## ⚡ Sử Dụng Nhanh (Đã Có Model)

Nếu repo đã có sẵn `models/*/eye_model.tflite` và `yawn_model.tflite`:

```python
import cv2
from pipeline.drowsiness_detector import DrowsinessDetectorV2

# Khởi tạo detector
detector = DrowsinessDetectorV2(
    eye_model_path  = "models/eye_cnn/eye_model.tflite",
    yawn_model_path = "models/yawn_cnn/yawn_model.tflite",
    config_path     = "config.yaml"
)

# Từ webcam
cap = cv2.VideoCapture(0)
while True:
    ret, frame = cap.read()
    if not ret:
        break

    result = detector.process_frame(frame)

    print(f"Status: {result['status']}")    # awake | warning | drowsy
    print(f"Alert:  {result['alert']}")     # True/False
    print(f"Score:  {result['fusion_score']:.3f}")

    if result["alert"]:
        print("⚠️  CẢNH BÁO BUỒN NGỦ!")

cap.release()
```

---

## 🍓 Raspberry Pi 4 (Bookworm 64-bit) — Chạy Live Camera Nhanh

Repo đã có script cài nhanh + chạy nhanh cho Pi4:

```bash
# 1) Setup 1 lần
bash scripts/pi4_setup.sh

# 2) Chạy live camera
bash scripts/pi4_run_live.sh
```

Mặc định script sẽ:
- Tạo virtualenv tại `.venv-pi`
- Ưu tiên backend `V4L2`
- Tự chọn `/dev/video0` (hoặc node camera đầu tiên)
- Chạy ở `640x480 @ 20 FPS` để ổn định realtime trên Pi4

Tuỳ chỉnh nhanh:

```bash
CAMERA_PATH=/dev/video0 WIDTH=960 HEIGHT=540 FPS=25 bash scripts/pi4_run_live.sh
SAVE_VIDEO=results/pi4_live.mp4 bash scripts/pi4_run_live.sh
```

Nếu gặp lỗi kiểu `_ARRAY_API not found` hoặc `numpy.core.multiarray failed to import`, chạy lại setup để hạ NumPy về bản tương thích:

```bash
bash scripts/pi4_setup.sh
```

---

## ⚠️ Lưu Ý Quan Trọng

### MediaPipe Version

```
mediapipe==0.10.14    ✅ Hoạt động (có solutions API)
mediapipe>=0.10.32    ❌ Lỗi (solutions API đã bị loại bỏ)
```

### TensorFlow H5 Bug (v2.18)

Model `.h5` lưu bằng TF 2.18 **không thể load trực tiếp** do lỗi `TrueDivide` op. Sử dụng file `.keras` hoặc `.tflite` thay thế.

```python
# ❌ KHÔNG dùng
model = tf.keras.models.load_model("final.h5")

# ✅ Dùng .keras
model = tf.keras.models.load_model("final_fixed.keras")

# ✅ Hoặc dùng TFLite cho inference
interpreter = tf.lite.Interpreter(model_path="eye_model.tflite")
```

### Deploy lên Raspberry Pi 4

Chỉ cần copy các file sau:

```
models/eye_cnn/eye_model.tflite     # 690 KB
models/yawn_cnn/yawn_model.tflite   # 690 KB
config.yaml
pipeline/
```

Cài trên RPi4:

```bash
pip install tflite-runtime mediapipe==0.10.14 opencv-python pyyaml
```

---

## 📖 Tài Liệu Chi Tiết

Xem [docs/SUMMARY.md](docs/SUMMARY.md) để đọc báo cáo tổng kết chi tiết toàn bộ quá trình:
- Kiến trúc mô hình & training strategy
- Thống kê dataset đầy đủ
- Kết quả đánh giá per-class
- Kiến trúc Fusion Pipeline
- Tất cả sự cố và giải pháp

---

## 📄 License

IVI Automotive Capstone Project — Internal use.
