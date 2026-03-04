#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi"

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

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"

echo "[INFO] QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"
echo "[INFO] Launching: ${APP_BIN}"
echo "[HINT] For no-desktop framebuffer mode: QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi.sh"

cd "${PROJECT_DIR}"
exec "${APP_BIN}"
