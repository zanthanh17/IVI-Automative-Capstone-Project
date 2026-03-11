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

# Root sessions often use /run/user/0 with wrong permissions (0755).
# Force a private runtime dir to satisfy Qt's 0700 requirement.
if [[ "$(id -u)" -eq 0 ]]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/qt-runtime-root}"
    mkdir -p "${XDG_RUNTIME_DIR}"
    chmod 700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
fi

echo "[INFO] QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"
echo "[INFO] XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-"(not set)"}"
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
