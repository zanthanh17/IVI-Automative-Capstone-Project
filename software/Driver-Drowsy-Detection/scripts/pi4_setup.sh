#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv-pi}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "==> Drowsiness app setup for Raspberry Pi 4 (Bookworm 64-bit)"
echo "Project root: $ROOT_DIR"
echo "Venv path:    $VENV_DIR"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "ERROR: $PYTHON_BIN not found. Install Python 3 first."
  exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" ]]; then
  echo "WARNING: Detected arch '$ARCH' (expected aarch64 for Pi OS 64-bit)."
fi

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: sudo not available. Run this script as root."
    exit 1
  fi
fi

wait_for_ntp_sync() {
  if ! command -v timedatectl >/dev/null 2>&1; then
    return 0
  fi

  local sync_state=""
  sync_state="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
  if [[ "$sync_state" == "yes" ]]; then
    return 0
  fi

  echo "==> System clock not synchronized yet; enabling NTP"
  "$SUDO" timedatectl set-ntp true >/dev/null 2>&1 || true
  "$SUDO" systemctl restart systemd-timesyncd >/dev/null 2>&1 || true

  local i=0
  for i in {1..24}; do
    sync_state="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
    if [[ "$sync_state" == "yes" ]]; then
      echo "==> NTP synchronized"
      return 0
    fi
    sleep 5
  done

  echo "WARNING: NTP synchronization is still pending."
  echo "Current time: $(date -Is)"
}

apt_update_with_retry() {
  if "$SUDO" apt-get update; then
    return 0
  fi

  echo "apt-get update failed. Retrying after NTP sync attempt..."
  wait_for_ntp_sync
  if "$SUDO" apt-get update; then
    return 0
  fi

  cat <<'EOF'
ERROR: apt-get update failed after retry.
If you see "Release file ... is not valid yet", the Pi clock is behind.
Fix with:
  sudo timedatectl set-ntp true
  sudo systemctl restart systemd-timesyncd
  timedatectl status
Wait until "System clock synchronized: yes", then rerun this script.
EOF
  exit 1
}

echo "==> Installing system packages"
wait_for_ntp_sync
apt_update_with_retry
"$SUDO" apt-get install -y \
  python3-venv \
  python3-pip \
  python3-dev \
  libatlas-base-dev \
  libopenblas-dev \
  libhdf5-dev \
  libjpeg-dev \
  libpng-dev \
  libglib2.0-0 \
  libgl1 \
  libegl1 \
  libgomp1 \
  v4l-utils \
  ffmpeg

echo "==> Creating virtual environment"
"$PYTHON_BIN" -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

echo "==> Installing Python runtime dependencies"
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r "$ROOT_DIR/requirements.pi4.txt"

echo "==> Enforcing NumPy/TFLite ABI compatibility"
python -m pip install --upgrade --force-reinstall --no-cache-dir \
  "numpy==1.26.4" \
  "tflite-runtime>=2.14"

echo "==> Installing MediaPipe"
if python -c "import mediapipe" >/dev/null 2>&1; then
  echo "MediaPipe already available in venv."
else
  set +e
  python -m pip install "mediapipe==0.10.14"
  MP_STATUS=$?
  set -e
  if [[ "$MP_STATUS" -ne 0 ]]; then
    echo "Official mediapipe wheel unavailable. Trying piwheels build..."
    python -m pip install --extra-index-url https://www.piwheels.org/simple mediapipe-rpi4
  fi
fi

echo "==> Verifying runtime"
python - <<'PY'
import cv2
import mediapipe as mp
import yaml
import numpy as np

backend = "tensorflow-lite-fallback"
try:
    import tflite_runtime.interpreter as _tflite  # noqa: F401
    backend = "tflite-runtime"
except Exception:
    pass

print("OpenCV:", cv2.__version__)
print("MediaPipe:", mp.__version__)
print("PyYAML:", yaml.__version__)
print("NumPy:", np.__version__)
print("TFLite backend:", backend)

major = int(np.__version__.split(".")[0])
if major >= 2:
    raise SystemExit("ERROR: NumPy 2.x detected. Re-run scripts/pi4_setup.sh")
PY

echo "==> Setup completed"
echo "Run live app:"
echo "  source \"$VENV_DIR/bin/activate\""
echo "  bash \"$ROOT_DIR/scripts/pi4_run_live.sh\""
