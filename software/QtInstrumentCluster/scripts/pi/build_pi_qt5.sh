#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi-qt5"
PRO_FILE="${PROJECT_DIR}/QtInstrumentCluster.pro"

if [[ ! -f "${PRO_FILE}" ]]; then
    echo "[ERROR] Project file not found: ${PRO_FILE}"
    exit 1
fi

QMAKE_CMD=()
QT_VERSION=""

if command -v qmake5 >/dev/null 2>&1; then
    QMAKE_CMD=(qmake5)
    QT_VERSION="$("${QMAKE_CMD[@]}" -query QT_VERSION 2>/dev/null || true)"
elif command -v qmake >/dev/null 2>&1; then
    QT_VERSION="$(qmake -query QT_VERSION 2>/dev/null || true)"
    if [[ "${QT_VERSION}" == 5.* ]]; then
        QMAKE_CMD=(qmake)
    else
        QT_VERSION="$(qmake -qt=5 -query QT_VERSION 2>/dev/null || true)"
        if [[ "${QT_VERSION}" == 5.* ]]; then
            QMAKE_CMD=(qmake -qt=5)
        fi
    fi
fi

if ((${#QMAKE_CMD[@]} == 0)); then
    echo "[ERROR] Qt5 qmake not found."
    echo "        Run ./scripts/pi/setup_pi_native_qt5.sh first."
    exit 1
fi

if [[ -z "${QT_VERSION}" || "${QT_VERSION}" != 5.* ]]; then
    echo "[ERROR] Qt5 is required, found: ${QT_VERSION:-unknown} (via ${QMAKE_CMD[*]})"
    exit 1
fi

JOBS="$(nproc 2>/dev/null || echo 4)"
mkdir -p "${BUILD_DIR}"

echo "[INFO] Using qmake: ${QMAKE_CMD[*]} (Qt ${QT_VERSION})"
echo "[INFO] Build directory: ${BUILD_DIR}"

pushd "${BUILD_DIR}" >/dev/null
if [[ -f Makefile ]]; then
    echo "[INFO] Forcing full rebuild to avoid stale Qt object files"
fi
"${QMAKE_CMD[@]}" "${PRO_FILE}" "CONFIG+=release"
make -B -j"${JOBS}"
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

echo "[DONE] Qt5 build successful."
echo "[INFO] Executable: ${APP_BIN}"
