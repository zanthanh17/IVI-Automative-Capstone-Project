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

echo "[INFO] QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"
echo "[INFO] QT_IM_MODULE=${QT_IM_MODULE}"
echo "[INFO] QT_VIRTUALKEYBOARD_LOCALE=${QT_VIRTUALKEYBOARD_LOCALE}"
echo "[INFO] GPSD endpoint=${GPSD_HOST:-127.0.0.1}:${GPSD_PORT:-2947}"
echo "[INFO] Launching: ${APP_BIN}"
echo "[HINT] For no-desktop framebuffer mode: QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi.sh"

cd "${PROJECT_DIR}"
exec "${APP_BIN}"
