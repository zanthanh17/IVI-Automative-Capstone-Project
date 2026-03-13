#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi-qt5"
ENV_FILE="${PROJECT_DIR}/.env"

APP_BIN=""
if [[ -x "${BUILD_DIR}/QtInstrumentCluster" ]]; then
    APP_BIN="${BUILD_DIR}/QtInstrumentCluster"
elif [[ -x "${BUILD_DIR}/release/QtInstrumentCluster" ]]; then
    APP_BIN="${BUILD_DIR}/release/QtInstrumentCluster"
fi

if [[ -z "${APP_BIN}" ]]; then
    echo "[ERROR] Qt5 executable not found in ${BUILD_DIR}."
    echo "        Please run: ./scripts/pi/build_pi_qt5.sh"
    exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
    echo "[INFO] Loading environment from ${ENV_FILE}"
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export QT_IM_MODULE="${QT_IM_MODULE:-qtvirtualkeyboard}"
export QT_VIRTUALKEYBOARD_LOCALE="${QT_VIRTUALKEYBOARD_LOCALE:-vi_VN}"

# Drowsiness detector worker defaults (Camera page, Qt5)
DEFAULT_DROWSY_ROOT="${PROJECT_DIR}/../Driver-Drowsy-Detection"
DEFAULT_DROWSY_PYTHON="${DEFAULT_DROWSY_ROOT}/.venv-pi/bin/python3"
DEFAULT_DROWSY_SCRIPT="${DEFAULT_DROWSY_ROOT}/app/live_camera.py"

if [[ -z "${DROWSY_PYTHON:-}" ]]; then
    if [[ -x "${DEFAULT_DROWSY_PYTHON}" ]]; then
        export DROWSY_PYTHON="${DEFAULT_DROWSY_PYTHON}"
    else
        export DROWSY_PYTHON="python3"
    fi
fi

if [[ -z "${DROWSY_LIVE_CAMERA_SCRIPT:-}" && -f "${DEFAULT_DROWSY_SCRIPT}" ]]; then
    export DROWSY_LIVE_CAMERA_SCRIPT="${DEFAULT_DROWSY_SCRIPT}"
fi

export DROWSY_BACKEND="${DROWSY_BACKEND:-v4l2}"
export DROWSY_CAMERA_INDEX="${DROWSY_CAMERA_INDEX:-0}"
export DROWSY_CAMERA_PATH="${DROWSY_CAMERA_PATH:-}"
export DROWSY_FALLBACK_SCAN_MAX="${DROWSY_FALLBACK_SCAN_MAX:-6}"
export DROWSY_FRAME_TRANSPORT="${DROWSY_FRAME_TRANSPORT:-file}"
export DROWSY_WIDTH="${DROWSY_WIDTH:-960}"
export DROWSY_HEIGHT="${DROWSY_HEIGHT:-540}"
export DROWSY_FPS="${DROWSY_FPS:-30}"
export DROWSY_EXPORT_FRAME="${DROWSY_EXPORT_FRAME:-/tmp/drowsy_live_frame.jpg}"
export DROWSY_EXPORT_QUALITY="${DROWSY_EXPORT_QUALITY:-70}"
export DROWSY_EXPORT_EVERY_N="${DROWSY_EXPORT_EVERY_N:-1}"
export DROWSY_METRICS_EVERY_N="${DROWSY_METRICS_EVERY_N:-10}"
export DROWSY_PERSIST_WORKER="${DROWSY_PERSIST_WORKER:-1}"

# Root sessions often use /run/user/0 with wrong permissions (0755).
# Force a private runtime dir to satisfy Qt's 0700 requirement.
if [[ "$(id -u)" -eq 0 ]]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/qt-runtime-root}"
    mkdir -p "${XDG_RUNTIME_DIR}"
    chmod 700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
fi

echo "[INFO] QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"
echo "[INFO] QT_IM_MODULE=${QT_IM_MODULE}"
echo "[INFO] QT_VIRTUALKEYBOARD_LOCALE=${QT_VIRTUALKEYBOARD_LOCALE}"
echo "[INFO] XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-"(not set)"}"
echo "[INFO] DROWSY python=${DROWSY_PYTHON}"
if [[ -n "${DROWSY_LIVE_CAMERA_SCRIPT:-}" ]]; then
    echo "[INFO] DROWSY script=${DROWSY_LIVE_CAMERA_SCRIPT}"
fi
echo "[INFO] DROWSY transport=${DROWSY_FRAME_TRANSPORT}"
if [[ -n "${DROWSY_CAMERA_PATH}" ]]; then
    echo "[INFO] DROWSY camera-path=${DROWSY_CAMERA_PATH}"
fi
echo "[INFO] DROWSY camera=${DROWSY_CAMERA_INDEX} ${DROWSY_WIDTH}x${DROWSY_HEIGHT}@${DROWSY_FPS}"
echo "[INFO] DROWSY fallback-scan-max=${DROWSY_FALLBACK_SCAN_MAX}"
echo "[INFO] DROWSY stream quality=${DROWSY_EXPORT_QUALITY} everyN=${DROWSY_EXPORT_EVERY_N}"
echo "[INFO] DROWSY persist-worker=${DROWSY_PERSIST_WORKER}"
if [[ -n "${DROWSY_EXPORT_FRAME}" ]]; then
    echo "[INFO] DROWSY optional file export=${DROWSY_EXPORT_FRAME}"
fi
if [[ -n "${MAPBOX_ACCESS_TOKEN:-}" ]]; then
    echo "[INFO] MAPBOX_ACCESS_TOKEN is set (Mapbox map + routing enabled)."
else
    echo "[WARN] MAPBOX_ACCESS_TOKEN is not set (Mapbox map/routing/geocode will fail)."
fi
echo "[INFO] MAPBOX_STYLE_URL=${MAPBOX_STYLE_URL:-mapbox://styles/mapbox/navigation-guidance-night-v2}"
echo "[INFO] Launching: ${APP_BIN}"
echo "[HINT] Framebuffer mode: QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi_qt5.sh"

cd "${PROJECT_DIR}"
exec "${APP_BIN}"
