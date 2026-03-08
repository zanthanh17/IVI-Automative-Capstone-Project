#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi"

FAIL_COUNT=0
WARN_COUNT=0
MAP_INSTALLED=0
MAP_TOTAL=0
QML_LOCATION_MODULE_PATH=""
QML_POSITIONING_MODULE_PATH=""

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

echo "[INFO] Verifying Raspberry Pi runtime/build environment for QtInstrumentCluster..."

if command -v qmake6 >/dev/null 2>&1; then
    QMAKE_BIN="qmake6"
elif command -v qmake >/dev/null 2>&1; then
    QMAKE_BIN="qmake"
else
    fail "qmake/qmake6 not found."
    QMAKE_BIN=""
fi

if [[ -n "${QMAKE_BIN}" ]]; then
    QT_VERSION="$("${QMAKE_BIN}" -query QT_VERSION 2>/dev/null || true)"
    if [[ "${QT_VERSION}" == 6.* ]]; then
        ok "Qt version: ${QT_VERSION} (${QMAKE_BIN})"
    else
        fail "Qt6 is required but found '${QT_VERSION:-unknown}'"
    fi
fi

if command -v dpkg-query >/dev/null 2>&1; then
    REQUIRED_PKGS=(
        qt6-base-dev
        qt6-declarative-dev
        qt6-serialport-dev
        qt6-multimedia-dev
        qml6-module-qtqml
        qml6-module-qtqml-models
        qml6-module-qtqml-workerscript
        qml6-module-qtquick
        qml6-module-qtquick-controls
    )

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            ok "Package installed: ${pkg}"
        else
            fail "Missing required package: ${pkg}"
        fi
    done

    MAP_PKGS=(qt6-location-dev qml6-module-qtlocation qml6-module-qtpositioning)
    MAP_TOTAL=${#MAP_PKGS[@]}
    MAP_INSTALLED=0
    for pkg in "${MAP_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            MAP_INSTALLED=$((MAP_INSTALLED + 1))
        fi
    done
    if ((MAP_INSTALLED == MAP_TOTAL)); then
        ok "Qt Location stack installed (${MAP_PKGS[*]})"
    else
        warn "Qt Location stack incomplete by package check (${MAP_INSTALLED}/${MAP_TOTAL})."
    fi

    WEB_PKGS=(qt6-webengine-dev qml6-module-qtwebengine qml6-module-qtwebchannel)
    WEB_INSTALLED=0
    for pkg in "${WEB_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            WEB_INSTALLED=$((WEB_INSTALLED + 1))
        fi
    done
    if ((WEB_INSTALLED > 0)); then
        ok "Qt WebEngine packages detected (${WEB_INSTALLED}/${#WEB_PKGS[@]})"
    else
        warn "Qt WebEngine packages not installed. WebEngine map MVP is unavailable."
    fi
else
    warn "dpkg-query not found; skipping package checks."
fi

if [[ -n "${QMAKE_BIN}" ]]; then
    QML_INSTALL_DIR="$("${QMAKE_BIN}" -query QT_INSTALL_QML 2>/dev/null || true)"
    if [[ -n "${QML_INSTALL_DIR}" && -d "${QML_INSTALL_DIR}" ]]; then
        if [[ -f "${QML_INSTALL_DIR}/QtLocation/qmldir" ]]; then
            QML_LOCATION_MODULE_PATH="${QML_INSTALL_DIR}/QtLocation/qmldir"
        fi
        if [[ -f "${QML_INSTALL_DIR}/QtPositioning/qmldir" ]]; then
            QML_POSITIONING_MODULE_PATH="${QML_INSTALL_DIR}/QtPositioning/qmldir"
        fi
    fi
fi

if [[ -z "${QML_LOCATION_MODULE_PATH}" ]]; then
    QML_LOCATION_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt6/qml/QtLocation/qmldir' 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${QML_POSITIONING_MODULE_PATH}" ]]; then
    QML_POSITIONING_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt6/qml/QtPositioning/qmldir' 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "${QML_LOCATION_MODULE_PATH}" ]]; then
    ok "Found QtLocation QML module: ${QML_LOCATION_MODULE_PATH}"
else
    warn "QtLocation QML module not found. On Raspberry Pi OS Bookworm this package is often unavailable in apt."
fi

if [[ -n "${QML_POSITIONING_MODULE_PATH}" ]]; then
    ok "Found QtPositioning QML module: ${QML_POSITIONING_MODULE_PATH}"
else
    warn "QtPositioning QML module not found."
fi

if [[ -z "${QML_LOCATION_MODULE_PATH}" || -z "${QML_POSITIONING_MODULE_PATH}" ]]; then
    warn "Navigation map may fall back to HUD. Check available packages with: apt-cache search qt6 | grep -E 'location|positioning'"
fi

OSM_PLUGIN_PATH=""
if [[ -n "${QMAKE_BIN}" ]]; then
    QT_PLUGINS_DIR="$("${QMAKE_BIN}" -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
    if [[ -n "${QT_PLUGINS_DIR}" && -d "${QT_PLUGINS_DIR}" ]]; then
        OSM_PLUGIN_PATH="$(find "${QT_PLUGINS_DIR}" -type f -iname '*qtgeoservices*osm*' 2>/dev/null | head -n 1 || true)"
    fi
fi

if [[ -z "${OSM_PLUGIN_PATH}" ]]; then
    OSM_PLUGIN_PATH="$(find /usr/lib /lib -type f -iname '*qtgeoservices*osm*' 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "${OSM_PLUGIN_PATH}" ]]; then
    ok "Found OSM geoservices plugin: ${OSM_PLUGIN_PATH}"
else
    if [[ -n "${QML_LOCATION_MODULE_PATH}" ]] && [[ -n "${QML_POSITIONING_MODULE_PATH}" ]]; then
        fail "Qt OSM geoservices plugin not found under Qt plugin paths."
    else
        warn "Qt OSM geoservices plugin not found (expected while Qt Location QML modules are missing)."
    fi
fi

if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 12 "https://basemaps.cartocdn.com/dark_all/0/0/0.png" -o /dev/null; then
        ok "Carto tile server reachable."
    else
        warn "Cannot reach Carto tile server. Map tiles may be blank."
    fi

    if curl -fsS --max-time 12 "https://router.project-osrm.org/route/v1/driving/108.2196,16.0632;108.2187,16.0520?overview=false" -o /dev/null; then
        ok "OSRM demo server reachable."
    else
        warn "Cannot reach OSRM demo server. Live route fetch may fail."
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
    ok "Existing build artifact found in ${BUILD_DIR}."
else
    warn "No build artifact found yet in ${BUILD_DIR}. Run ./scripts/pi/build_pi.sh"
fi

echo
echo "[INFO] Verification summary: FAIL=${FAIL_COUNT}, WARN=${WARN_COUNT}"

if ((FAIL_COUNT > 0)); then
    exit 1
fi

exit 0
