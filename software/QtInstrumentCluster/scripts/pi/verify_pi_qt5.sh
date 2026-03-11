#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi-qt5"

FAIL_COUNT=0
WARN_COUNT=0

ok() {
    echo "[OK] $*"
}

warn() {
    echo "[WARN] $*"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    echo "[FAIL] $*"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

is_installed_pkg() {
    local pkg="$1"
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"
}

echo "[INFO] Verifying Raspberry Pi environment for Qt5 build..."

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
    fail "Qt5 qmake not found."
else
    if [[ "${QT_VERSION}" == 5.* ]]; then
        ok "Qt version: ${QT_VERSION} (${QMAKE_CMD[*]})"
    else
        fail "Qt5 is required but found '${QT_VERSION:-unknown}'"
    fi
fi

if command -v dpkg-query >/dev/null 2>&1; then
    REQUIRED_PKGS=(
        qt5-qmake
        qtbase5-dev
        qtdeclarative5-dev
        qtmultimedia5-dev
        libqt5serialport5-dev
        qml-module-qtqml
        qml-module-qtqml-models2
        qml-module-qtqml-workerscript2
        qml-module-qtquick2
        qml-module-qtquick-controls2
    )

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            ok "Package installed: ${pkg}"
        else
            fail "Missing required package: ${pkg}"
        fi
    done

    MAP_PKGS=(qtlocation5-dev qtpositioning5-dev qml-module-qtlocation qml-module-qtpositioning)
    MAP_INSTALLED=0
    for pkg in "${MAP_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            MAP_INSTALLED=$((MAP_INSTALLED + 1))
        fi
    done
    if ((MAP_INSTALLED == ${#MAP_PKGS[@]})); then
        ok "Qt5 location stack installed (${MAP_PKGS[*]})"
    else
        warn "Qt5 location stack incomplete (${MAP_INSTALLED}/${#MAP_PKGS[@]})."
    fi

    WEB_PKGS=(qtwebengine5-dev qml-module-qtwebengine qml-module-qtwebchannel)
    WEB_INSTALLED=0
    for pkg in "${WEB_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            WEB_INSTALLED=$((WEB_INSTALLED + 1))
        fi
    done
    if ((WEB_INSTALLED > 0)); then
        ok "Qt5 WebEngine packages detected (${WEB_INSTALLED}/${#WEB_PKGS[@]})"
    else
        warn "Qt5 WebEngine packages not installed. WebEngine view may be unavailable."
    fi
else
    warn "dpkg-query not found; skipping package checks."
fi

QML_LOCATION_MODULE_PATH=""
QML_POSITIONING_MODULE_PATH=""

if ((${#QMAKE_CMD[@]} > 0)); then
    QML_INSTALL_DIR="$("${QMAKE_CMD[@]}" -query QT_INSTALL_QML 2>/dev/null || true)"
    if [[ -n "${QML_INSTALL_DIR}" && -d "${QML_INSTALL_DIR}" ]]; then
        [[ -f "${QML_INSTALL_DIR}/QtLocation/qmldir" ]] && QML_LOCATION_MODULE_PATH="${QML_INSTALL_DIR}/QtLocation/qmldir"
        [[ -f "${QML_INSTALL_DIR}/QtPositioning/qmldir" ]] && QML_POSITIONING_MODULE_PATH="${QML_INSTALL_DIR}/QtPositioning/qmldir"
    fi
fi

if [[ -z "${QML_LOCATION_MODULE_PATH}" ]]; then
    QML_LOCATION_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt5/qml/QtLocation/qmldir' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${QML_POSITIONING_MODULE_PATH}" ]]; then
    QML_POSITIONING_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt5/qml/QtPositioning/qmldir' 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "${QML_LOCATION_MODULE_PATH}" ]]; then
    ok "Found QtLocation QML module: ${QML_LOCATION_MODULE_PATH}"
else
    warn "QtLocation QML module not found."
fi

if [[ -n "${QML_POSITIONING_MODULE_PATH}" ]]; then
    ok "Found QtPositioning QML module: ${QML_POSITIONING_MODULE_PATH}"
else
    warn "QtPositioning QML module not found."
fi

MAPBOX_PLUGIN_PATH="$(find /usr/lib /lib -type f -iname '*qtgeoservices*mapboxgl*' 2>/dev/null | head -n 1 || true)"
if [[ -n "${MAPBOX_PLUGIN_PATH}" ]]; then
    ok "Found Mapbox GL geoservices plugin: ${MAPBOX_PLUGIN_PATH}"
else
    warn "Mapbox GL geoservices plugin not found. QtLocation mapboxgl plugin may be unavailable."
fi

if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 12 "https://basemaps.cartocdn.com/dark_all/0/0/0.png" -o /dev/null; then
        ok "Tile server reachable."
    else
        warn "Cannot reach tile server. Map may be blank."
    fi
else
    warn "curl not found; skipping network checks."
fi

if id -nG | grep -qw dialout; then
    ok "User '${USER}' is in dialout group."
else
    warn "User '${USER}' is not in dialout group. Serial access may fail."
fi

if ls /dev/ttyAMA* /dev/ttyUSB* /dev/ttyACM* >/dev/null 2>&1; then
    ok "Detected serial device nodes under /dev/ttyAMA*, /dev/ttyUSB*, or /dev/ttyACM*."
else
    warn "No serial device nodes detected now. Connect hardware and check again."
fi

if [[ -x "${BUILD_DIR}/QtInstrumentCluster" || -x "${BUILD_DIR}/release/QtInstrumentCluster" ]]; then
    ok "Existing Qt5 build artifact found in ${BUILD_DIR}."
else
    warn "No Qt5 build artifact found yet in ${BUILD_DIR}. Run ./scripts/pi/build_pi_qt5.sh"
fi

echo
echo "[INFO] Verification summary: FAIL=${FAIL_COUNT}, WARN=${WARN_COUNT}"

if ((FAIL_COUNT > 0)); then
    exit 1
fi

exit 0
