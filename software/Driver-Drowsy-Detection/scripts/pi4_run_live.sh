#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv-pi}"

if [[ ! -x "$VENV_DIR/bin/python3" ]]; then
  echo "ERROR: venv not found at $VENV_DIR"
  echo "Run setup first: bash \"$ROOT_DIR/scripts/pi4_setup.sh\""
  exit 1
fi

# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"
cd "$ROOT_DIR"

if ! python3 - <<'PY'
import numpy as np

major = int(np.__version__.split(".")[0])
if major >= 2:
    raise SystemExit(
        f"Incompatible NumPy version: {np.__version__}. "
        "Expected NumPy 1.x for tflite-runtime on Pi."
    )

try:
    import tflite_runtime.interpreter as _tflite  # noqa: F401
except Exception as exc:
    raise SystemExit(f"tflite-runtime import failed: {exc}") from exc
PY
then
  echo "Runtime preflight failed. Fix with:"
  echo "  bash \"$ROOT_DIR/scripts/pi4_setup.sh\""
  echo "or manual fix:"
  echo "  pip install --force-reinstall --no-cache-dir numpy==1.26.4 tflite-runtime"
  exit 1
fi

WIDTH="${WIDTH:-640}"
HEIGHT="${HEIGHT:-480}"
FPS="${FPS:-20}"
BACKEND="${BACKEND:-v4l2}"
CAMERA_INDEX="${CAMERA_INDEX:-0}"
FALLBACK_SCAN_MAX="${FALLBACK_SCAN_MAX:-6}"
METRICS_EVERY_N="${METRICS_EVERY_N:-10}"
METRICS_CSV="${METRICS_CSV:-}"
METRICS_CSV_EVERY_N="${METRICS_CSV_EVERY_N:-1}"

CAMERA_PATH="${CAMERA_PATH:-}"
if [[ -z "$CAMERA_PATH" ]]; then
  FIRST_NODE="$(ls /dev/video* 2>/dev/null | head -n 1 || true)"
  CAMERA_PATH="$FIRST_NODE"
fi

CMD=(
  python3 "$ROOT_DIR/app/live_camera.py"
  --backend "$BACKEND"
  --width "$WIDTH"
  --height "$HEIGHT"
  --fps "$FPS"
  --metrics-every-n "$METRICS_EVERY_N"
  --metrics-csv-every-n "$METRICS_CSV_EVERY_N"
)

if [[ -n "$CAMERA_PATH" ]]; then
  CMD+=(--camera-path "$CAMERA_PATH")
else
  CMD+=(--camera-index "$CAMERA_INDEX" --fallback-scan-max "$FALLBACK_SCAN_MAX")
fi

if [[ "${MIRROR:-1}" == "0" ]]; then
  CMD+=(--no-mirror)
fi

if [[ -n "${SAVE_VIDEO:-}" ]]; then
  CMD+=(--save-video "$SAVE_VIDEO")
fi

if [[ -n "$METRICS_CSV" ]]; then
  CMD+=(--metrics-csv "$METRICS_CSV")
fi

if [[ "$#" -gt 0 ]]; then
  CMD+=("$@")
fi

echo "Running live camera with:"
echo "  WIDTH=$WIDTH HEIGHT=$HEIGHT FPS=$FPS BACKEND=$BACKEND"
if [[ -n "$METRICS_CSV" ]]; then
  echo "  METRICS_CSV=$METRICS_CSV"
fi
if [[ -n "$CAMERA_PATH" ]]; then
  echo "  CAMERA_PATH=$CAMERA_PATH"
else
  echo "  CAMERA_INDEX=$CAMERA_INDEX FALLBACK_SCAN_MAX=$FALLBACK_SCAN_MAX"
fi

exec "${CMD[@]}"
