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

for candidate in \
    /usr/lib/qt5/libexec/QtWebEngineProcess \
    /usr/lib/aarch64-linux-gnu/qt5/libexec/QtWebEngineProcess \
    /usr/lib/arm-linux-gnueabihf/qt5/libexec/QtWebEngineProcess; do
    if [[ -x "${candidate}" ]]; then
        export QTWEBENGINEPROCESS_PATH="${candidate}"
        break
    fi
done

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"

echo "[INFO] QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"
echo "[INFO] QTWEBENGINEPROCESS_PATH=${QTWEBENGINEPROCESS_PATH:-<auto-not-found>}"
if [[ -n "${MAPBOX_ACCESS_TOKEN:-}" ]]; then
    echo "[INFO] MAPBOX_ACCESS_TOKEN is set (Mapbox routing enabled)."
else
    echo "[WARN] MAPBOX_ACCESS_TOKEN is not set (routing falls back to OSRM demo)."
fi
echo "[INFO] Launching: ${APP_BIN}"
echo "[HINT] Framebuffer mode: QT_QPA_PLATFORM=eglfs ./scripts/pi/run_pi_qt5.sh"

cd "${PROJECT_DIR}"
exec "${APP_BIN}"
