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

WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-600}"
FPS="${FPS:-30}"
BACKEND="${BACKEND:-v4l2}"
CAMERA_INDEX="${CAMERA_INDEX:-0}"
FALLBACK_SCAN_MAX="${FALLBACK_SCAN_MAX:-6}"
SOCKET_PATH="${SOCKET_PATH:-${DROWSY_DAEMON_SOCKET:-}}"
VIEWER_TITLE="${VIEWER_TITLE:-Drowsiness Detection Live}"
VIEWER_WIDTH="${VIEWER_WIDTH:-1024}"
VIEWER_HEIGHT="${VIEWER_HEIGHT:-600}"
JPEG_QUALITY="${JPEG_QUALITY:-70}"
STREAM_EVERY_N="${STREAM_EVERY_N:-1}"
METRICS_EVERY_N="${METRICS_EVERY_N:-10}"
METRICS_CSV="${METRICS_CSV:-}"
METRICS_CSV_EVERY_N="${METRICS_CSV_EVERY_N:-1}"

CAMERA_PATH="${CAMERA_PATH:-${DROWSY_CAMERA_PATH:-}}"
if [[ -z "$CAMERA_PATH" ]]; then
  FIRST_NODE="$(ls /dev/video* 2>/dev/null | head -n 1 || true)"
  CAMERA_PATH="$FIRST_NODE"
fi

CMD=(
  python3 "$ROOT_DIR/app/live_camera_daemon.py"
  --backend "$BACKEND"
  --width "$WIDTH"
  --height "$HEIGHT"
  --fps "$FPS"
  --fallback-scan-max "$FALLBACK_SCAN_MAX"
  --jpeg-quality "$JPEG_QUALITY"
  --stream-every-n "$STREAM_EVERY_N"
  --metrics-every-n "$METRICS_EVERY_N"
  --metrics-csv-every-n "$METRICS_CSV_EVERY_N"
  --viewer-title "$VIEWER_TITLE"
  --viewer-width "$VIEWER_WIDTH"
  --viewer-height "$VIEWER_HEIGHT"
)

if [[ -n "$SOCKET_PATH" ]]; then
  CMD+=(--socket-path "$SOCKET_PATH")
fi

if [[ -n "$CAMERA_PATH" ]]; then
  CMD+=(--camera-path "$CAMERA_PATH")
else
  CMD+=(--camera-index "$CAMERA_INDEX")
fi

if [[ "${MIRROR:-1}" == "0" ]]; then
  CMD+=(--no-mirror)
fi

if [[ "${VIEWER_FULLSCREEN:-0}" == "1" ]]; then
  CMD+=(--viewer-fullscreen)
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

echo "Running drowsy daemon with:"
echo "  WIDTH=$WIDTH HEIGHT=$HEIGHT FPS=$FPS BACKEND=$BACKEND"
echo "  VIEWER=${VIEWER_WIDTH}x${VIEWER_HEIGHT}"
if [[ -n "$METRICS_CSV" ]]; then
  echo "  METRICS_CSV=$METRICS_CSV"
fi
if [[ -n "$CAMERA_PATH" ]]; then
  echo "  CAMERA_PATH=$CAMERA_PATH"
else
  echo "  CAMERA_INDEX=$CAMERA_INDEX FALLBACK_SCAN_MAX=$FALLBACK_SCAN_MAX"
fi
if [[ -n "$SOCKET_PATH" ]]; then
  echo "  SOCKET_PATH=$SOCKET_PATH"
fi

exec "${CMD[@]}"
