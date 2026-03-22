#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi-qt5"
ENV_FILE="${PROJECT_DIR}/.env"
LEGACY_ENV_FILE="${PROJECT_DIR}/.env "

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

if [[ ! -f "${ENV_FILE}" && -f "${LEGACY_ENV_FILE}" ]]; then
    ENV_FILE="${LEGACY_ENV_FILE}"
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

# Fix for "Could not queue DRM page flip" on Raspberry Pi 4/5 with Bookworm/Wayland
export QT_QPA_EGLFS_ALWAYS_SET_MODE="${QT_QPA_EGLFS_ALWAYS_SET_MODE:-1}"
export QT_QPA_EGLFS_KMS_ATOMIC="${QT_QPA_EGLFS_KMS_ATOMIC:-1}"

# Drowsiness detector launcher defaults (external app)
DEFAULT_DROWSY_ROOT="${PROJECT_DIR}/../Driver-Drowsy-Detection"
DEFAULT_DROWSY_PYTHON="${DEFAULT_DROWSY_ROOT}/.venv-pi/bin/python3"
DEFAULT_DROWSY_CTL_SCRIPT="${DEFAULT_DROWSY_ROOT}/app/drowsy_camera_ctl.py"

if [[ -z "${DROWSY_PYTHON:-}" ]]; then
    if [[ -x "${DEFAULT_DROWSY_PYTHON}" ]]; then
        export DROWSY_PYTHON="${DEFAULT_DROWSY_PYTHON}"
    fi
fi

if [[ -z "${DROWSY_CAMERA_CTL_SCRIPT:-}" && -f "${DEFAULT_DROWSY_CTL_SCRIPT}" ]]; then
    export DROWSY_CAMERA_CTL_SCRIPT="${DEFAULT_DROWSY_CTL_SCRIPT}"
fi

export DROWSY_BACKEND="${DROWSY_BACKEND:-v4l2}"
export DROWSY_CAMERA_INDEX="${DROWSY_CAMERA_INDEX:-0}"
export DROWSY_CAMERA_PATH="${DROWSY_CAMERA_PATH:-}"
export DROWSY_FALLBACK_SCAN_MAX="${DROWSY_FALLBACK_SCAN_MAX:-6}"
export DROWSY_WIDTH="${DROWSY_WIDTH:-1024}"
export DROWSY_HEIGHT="${DROWSY_HEIGHT:-600}"
export DROWSY_FPS="${DROWSY_FPS:-30}"
export DROWSY_VIEWER_FULLSCREEN="${DROWSY_VIEWER_FULLSCREEN:-0}"
export DROWSY_VIEWER_TITLE="${DROWSY_VIEWER_TITLE:-}"
export DROWSY_VIEWER_WIDTH="${DROWSY_VIEWER_WIDTH:-1024}"
export DROWSY_VIEWER_HEIGHT="${DROWSY_VIEWER_HEIGHT:-600}"
export DROWSY_DAEMON_SOCKET="${DROWSY_DAEMON_SOCKET:-/tmp/drowsy-camera-daemon.sock}"

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
echo "[INFO] DROWSY python=${DROWSY_PYTHON:-"(auto-resolve virtualenv in app)"}"
if [[ -n "${DROWSY_CAMERA_CTL_SCRIPT:-}" ]]; then
    echo "[INFO] DROWSY control=${DROWSY_CAMERA_CTL_SCRIPT}"
fi
if [[ -n "${DROWSY_CAMERA_PATH}" ]]; then
    echo "[INFO] DROWSY camera-path=${DROWSY_CAMERA_PATH}"
fi
echo "[INFO] DROWSY camera=${DROWSY_CAMERA_INDEX} ${DROWSY_WIDTH}x${DROWSY_HEIGHT}@${DROWSY_FPS}"
echo "[INFO] DROWSY fallback-scan-max=${DROWSY_FALLBACK_SCAN_MAX}"
echo "[INFO] DROWSY viewer-fullscreen=${DROWSY_VIEWER_FULLSCREEN}"
echo "[INFO] DROWSY viewer-size=${DROWSY_VIEWER_WIDTH}x${DROWSY_VIEWER_HEIGHT}"
if [[ -n "${DROWSY_VIEWER_TITLE}" ]]; then
    echo "[INFO] DROWSY viewer-title=${DROWSY_VIEWER_TITLE}"
fi
if [[ -n "${DROWSY_DAEMON_SOCKET}" ]]; then
    echo "[INFO] DROWSY daemon-socket=${DROWSY_DAEMON_SOCKET}"
fi
if [[ -z "${DROWSY_PYTHON:-}" ]]; then
    echo "[WARN] No DROWSY_PYTHON exported here; Qt launcher will only use a detected virtualenv (.venv-pi/.venv)."
fi
if [[ -n "${MAPBOX_ACCESS_TOKEN:-}" ]]; then
    echo "[INFO] MAPBOX_ACCESS_TOKEN is set (Mapbox map + routing enabled)."
else
    echo "[WARN] MAPBOX_ACCESS_TOKEN is not set (Mapbox map/routing/geocode will fail)."
fi
echo "[INFO] GPSD endpoint=${GPSD_HOST:-127.0.0.1}:${GPSD_PORT:-2947}"
echo "[INFO] MAPBOX_STYLE_URL=${MAPBOX_STYLE_URL:-mapbox://styles/mapbox/navigation-guidance-night-v2}"
echo "[INFO] Launching: ${APP_BIN}"
echo "[HINT] Framebuffer mode: QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi_qt5.sh"

LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/qt_cluster_$(date +'%Y%m%d_%H%M%S').log"

echo "[INFO] App output behaves normally but is also logged to ${LOG_FILE}"
cd "${PROJECT_DIR}"
exec "${APP_BIN}" 2>&1 | tee "${LOG_FILE}"
