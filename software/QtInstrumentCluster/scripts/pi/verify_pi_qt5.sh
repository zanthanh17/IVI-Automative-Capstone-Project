#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build-pi-qt5"
ENV_FILE="${PROJECT_DIR}/.env"

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

if [[ -f "${ENV_FILE}" ]]; then
    echo "[INFO] Loading environment from ${ENV_FILE}"
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

MAPBOX_STYLE_URL="${MAPBOX_STYLE_URL:-mapbox://styles/mapbox/navigation-guidance-night-v2



}"
MAPBOX_STYLE_PATH=""
if [[ "${MAPBOX_STYLE_URL}" == mapbox://styles/* ]]; then
    MAPBOX_STYLE_PATH="${MAPBOX_STYLE_URL#mapbox://styles/}"
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
        qml-module-qtquick-virtualkeyboard
        qml-module-qt-labs-folderlistmodel
    )

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            ok "Package installed: ${pkg}"
        else
            fail "Missing required package: ${pkg}"
        fi
    done

    MAP_PKGS=(qtlocation5-dev qtpositioning5-dev qml-module-qtlocation qml-module-qtpositioning libqt5location5-plugin-mapboxgl)
    MAP_INSTALLED=0
    for pkg in "${MAP_PKGS[@]}"; do
        if is_installed_pkg "${pkg}"; then
            MAP_INSTALLED=$((MAP_INSTALLED + 1))
        fi
    done
    if ((MAP_INSTALLED == ${#MAP_PKGS[@]})); then
        ok "Qt5 location stack installed (${MAP_PKGS[*]})"
    else
        fail "Qt5 Mapbox location stack incomplete (${MAP_INSTALLED}/${#MAP_PKGS[@]})."
    fi
else
    warn "dpkg-query not found; skipping package checks."
fi

if command -v dpkg-query >/dev/null 2>&1; then
    if is_installed_pkg qtvirtualkeyboard-plugin; then
        ok "Package installed: qtvirtualkeyboard-plugin"
    else
        warn "Package qtvirtualkeyboard-plugin not installed (may still work if plugin is bundled in qml-module-qtquick-virtualkeyboard)."
    fi
fi

QML_LOCATION_MODULE_PATH=""
QML_POSITIONING_MODULE_PATH=""
QML_VIRTUALKEYBOARD_MODULE_PATH=""
QML_FOLDERLISTMODEL_MODULE_PATH=""

if ((${#QMAKE_CMD[@]} > 0)); then
    QML_INSTALL_DIR="$("${QMAKE_CMD[@]}" -query QT_INSTALL_QML 2>/dev/null || true)"
    if [[ -n "${QML_INSTALL_DIR}" && -d "${QML_INSTALL_DIR}" ]]; then
        [[ -f "${QML_INSTALL_DIR}/QtLocation/qmldir" ]] && QML_LOCATION_MODULE_PATH="${QML_INSTALL_DIR}/QtLocation/qmldir"
        [[ -f "${QML_INSTALL_DIR}/QtPositioning/qmldir" ]] && QML_POSITIONING_MODULE_PATH="${QML_INSTALL_DIR}/QtPositioning/qmldir"
        [[ -f "${QML_INSTALL_DIR}/QtQuick/VirtualKeyboard/qmldir" ]] && QML_VIRTUALKEYBOARD_MODULE_PATH="${QML_INSTALL_DIR}/QtQuick/VirtualKeyboard/qmldir"
        [[ -f "${QML_INSTALL_DIR}/Qt/labs/folderlistmodel/qmldir" ]] && QML_FOLDERLISTMODEL_MODULE_PATH="${QML_INSTALL_DIR}/Qt/labs/folderlistmodel/qmldir"
    fi
fi

if [[ -z "${QML_LOCATION_MODULE_PATH}" ]]; then
    QML_LOCATION_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt5/qml/QtLocation/qmldir' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${QML_POSITIONING_MODULE_PATH}" ]]; then
    QML_POSITIONING_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt5/qml/QtPositioning/qmldir' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${QML_VIRTUALKEYBOARD_MODULE_PATH}" ]]; then
    QML_VIRTUALKEYBOARD_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt5/qml/QtQuick/VirtualKeyboard/qmldir' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${QML_FOLDERLISTMODEL_MODULE_PATH}" ]]; then
    QML_FOLDERLISTMODEL_MODULE_PATH="$(find /usr/lib /usr/local/lib -type f -path '*/qt5/qml/Qt/labs/folderlistmodel/qmldir' 2>/dev/null | head -n 1 || true)"
fi

if [[ -n "${QML_LOCATION_MODULE_PATH}" ]]; then
    ok "Found QtLocation QML module: ${QML_LOCATION_MODULE_PATH}"
else
    fail "QtLocation QML module not found."
fi

if [[ -n "${QML_POSITIONING_MODULE_PATH}" ]]; then
    ok "Found QtPositioning QML module: ${QML_POSITIONING_MODULE_PATH}"
else
    fail "QtPositioning QML module not found."
fi

if [[ -n "${QML_VIRTUALKEYBOARD_MODULE_PATH}" ]]; then
    ok "Found Qt Virtual Keyboard QML module: ${QML_VIRTUALKEYBOARD_MODULE_PATH}"
else
    fail "Qt Quick Virtual Keyboard QML module not found."
fi

if [[ -n "${QML_FOLDERLISTMODEL_MODULE_PATH}" ]]; then
    ok "Found Qt.labs.folderlistmodel QML module: ${QML_FOLDERLISTMODEL_MODULE_PATH}"
else
    fail "Qt.labs.folderlistmodel QML module not found (required by Qt Virtual Keyboard)."
fi

MAPBOX_PLUGIN_PATH="$(find /usr/lib /lib -type f -iname '*qtgeoservices*mapboxgl*' 2>/dev/null | head -n 1 || true)"
if [[ -n "${MAPBOX_PLUGIN_PATH}" ]]; then
    ok "Found Mapbox GL geoservices plugin: ${MAPBOX_PLUGIN_PATH}"
else
    fail "Mapbox GL geoservices plugin not found."
fi

if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 12 "https://api.mapbox.com/" -o /dev/null; then
        ok "Mapbox API host reachable."
    else
        fail "Cannot reach api.mapbox.com. Mapbox map will be blank."
    fi

    if [[ -n "${MAPBOX_ACCESS_TOKEN:-}" ]]; then
        if [[ "${MAPBOX_ACCESS_TOKEN}" == pk.* ]]; then
            ok "MAPBOX_ACCESS_TOKEN format looks valid for client-side use (pk.*)."
        elif [[ "${MAPBOX_ACCESS_TOKEN}" == sk.* ]]; then
            warn "MAPBOX_ACCESS_TOKEN starts with sk.* (secret token). Use a public pk.* token on dashboard client."
        else
            warn "MAPBOX_ACCESS_TOKEN format is unusual. Expected pk.* for Qt client app."
        fi

        if [[ -n "${MAPBOX_STYLE_PATH}" ]]; then
            STYLE_API_URL="https://api.mapbox.com/styles/v1/${MAPBOX_STYLE_PATH}?access_token=${MAPBOX_ACCESS_TOKEN}"
            if curl -fsS --max-time 12 \
                "${STYLE_API_URL}" \
                -o /dev/null; then
                ok "Mapbox style API reachable for MAPBOX_STYLE_URL=${MAPBOX_STYLE_URL}."

                STYLE_JSON="$(curl -fsS --max-time 12 "${STYLE_API_URL}" || true)"
                if [[ -n "${STYLE_JSON}" && "${STYLE_JSON}" == *"\"imports\""* ]]; then
                    warn "MAPBOX_STYLE_URL appears to use style imports. Qt5 mapboxgl may render blank with imported styles."
                fi
            else
                fail "MAPBOX_ACCESS_TOKEN cannot access MAPBOX_STYLE_URL=${MAPBOX_STYLE_URL}."
            fi
        else
            warn "MAPBOX_STYLE_URL should use mapbox://styles/<username>/<style_id> format. Current: ${MAPBOX_STYLE_URL}"
        fi
    else
        fail "MAPBOX_ACCESS_TOKEN is not set. Mapbox-only navigation cannot run."
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
