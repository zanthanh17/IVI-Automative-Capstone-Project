#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi"
ENV_FILE="${PROJECT_DIR}/.env"
LEGACY_ENV_FILE="${PROJECT_DIR}/.env "

APP_BIN=""
if [[ -x "${BUILD_DIR}/QtInstrumentCluster" ]]; then
    APP_BIN="${BUILD_DIR}/QtInstrumentCluster"
elif [[ -x "${BUILD_DIR}/release/QtInstrumentCluster" ]]; then
    APP_BIN="${BUILD_DIR}/release/QtInstrumentCluster"
fi

if [[ -z "${APP_BIN}" ]]; then
    echo "[ERROR] Executable not found in build-pi."
    echo "        Please run: ./scripts/pi/build_pi.sh"
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
export QT_QPA_EGLFS_HIDECURSOR="${QT_QPA_EGLFS_HIDECURSOR:-1}"

# Fix for "Zoomed in" UI issue on standard HDMI displays
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_ENABLE_HIGHDPI_SCALING=0
export QT_QPA_EGLFS_WIDTH=1024
export QT_QPA_EGLFS_HEIGHT=600
export QT_QPA_EGLFS_PHYSICAL_WIDTH=154
export QT_QPA_EGLFS_PHYSICAL_HEIGHT=90

export DROWSY_DAEMON_SOCKET="${DROWSY_DAEMON_SOCKET:-/tmp/drowsy-camera-daemon.sock}"

echo "[INFO] QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"
echo "[INFO] QT_IM_MODULE=${QT_IM_MODULE}"
echo "[INFO] QT_VIRTUALKEYBOARD_LOCALE=${QT_VIRTUALKEYBOARD_LOCALE}"
echo "[INFO] GPSD endpoint=${GPSD_HOST:-127.0.0.1}:${GPSD_PORT:-2947}"
echo "[INFO] Launching: ${APP_BIN}"
echo "[HINT] For no-desktop framebuffer mode: QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi.sh"

LOG_DIR="${PROJECT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/qt_cluster_$(date +'%Y%m%d_%H%M%S').log"

echo "[INFO] Waiting 2 seconds for DRM/KMS to settle..."
sleep 2

echo "[INFO] App output behaves normally but is also logged to ${LOG_FILE}"
cd "${PROJECT_DIR}"
exec "${APP_BIN}" 2>&1 | tee "${LOG_FILE}"
