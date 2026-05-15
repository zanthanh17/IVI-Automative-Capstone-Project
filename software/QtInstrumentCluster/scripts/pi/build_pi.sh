#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi"
PRO_FILE="${PROJECT_DIR}/QtInstrumentCluster.pro"

if [[ ! -f "${PRO_FILE}" ]]; then
    echo "[ERROR] Project file not found: ${PRO_FILE}"
    exit 1
fi

if command -v qmake6 >/dev/null 2>&1; then
    QMAKE_BIN="qmake6"
elif command -v qmake >/dev/null 2>&1; then
    QMAKE_BIN="qmake"
else
    echo "[ERROR] qmake was not found. Run ./scripts/pi/setup_pi_native_qt6.sh first."
    exit 1
fi

QT_VERSION="$("${QMAKE_BIN}" -query QT_VERSION 2>/dev/null || true)"
if [[ -z "${QT_VERSION}" ]]; then
    echo "[ERROR] Unable to query Qt version from ${QMAKE_BIN}."
    exit 1
fi
if [[ "${QT_VERSION}" != 6.* ]]; then
    echo "[ERROR] Qt6 is required, found: ${QT_VERSION} (via ${QMAKE_BIN})"
    exit 1
fi

JOBS="$(nproc 2>/dev/null || echo 4)"
mkdir -p "${BUILD_DIR}"

echo "[INFO] Using qmake: ${QMAKE_BIN} (Qt ${QT_VERSION})"
echo "[INFO] Build directory: ${BUILD_DIR}"

pushd "${BUILD_DIR}" >/dev/null
"${QMAKE_BIN}" "${PRO_FILE}" "CONFIG+=release"
make -j"${JOBS}"
popd >/dev/null

APP_BIN=""
if [[ -x "${BUILD_DIR}/QtInstrumentCluster" ]]; then
    APP_BIN="${BUILD_DIR}/QtInstrumentCluster"
elif [[ -x "${BUILD_DIR}/release/QtInstrumentCluster" ]]; then
    APP_BIN="${BUILD_DIR}/release/QtInstrumentCluster"
fi

if [[ -z "${APP_BIN}" ]]; then
    echo "[ERROR] Build finished but executable not found."
    echo "        Expected one of:"
    echo "        - ${BUILD_DIR}/QtInstrumentCluster"
    echo "        - ${BUILD_DIR}/release/QtInstrumentCluster"
    exit 1
fi

echo "[DONE] Build successful."
echo "[INFO] Executable: ${APP_BIN}"
