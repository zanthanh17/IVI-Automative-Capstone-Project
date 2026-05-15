#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "[ERROR] Do not run this script as root."
    echo "        Run it as your normal user. The script will use sudo when needed."
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "[ERROR] apt was not found. This script targets Debian-based Raspberry Pi OS."
    exit 1
fi

echo "[INFO] Updating apt index..."
sudo apt update

BASE_PACKAGES=(
    build-essential
    pkg-config
    git
    rsync
    ca-certificates
    qt5-qmake
    qtbase5-dev
    qtbase5-dev-tools
    qtdeclarative5-dev
    qtdeclarative5-dev-tools
    qtmultimedia5-dev
    libqt5serialport5-dev
    libqt5svg5-dev
    qttools5-dev
    qttools5-dev-tools
    qttranslations5-l10n
    libqt5dbus5
    qml-module-qtqml
    qml-module-qtqml-models2
    qml-module-qtqml-workerscript2
    qml-module-qtquick2
    qml-module-qtquick-window2
    qml-module-qtquick-controls
    qml-module-qtquick-controls2
    qml-module-qtmultimedia
    libgl1-mesa-dri
    libgles2
    libxkbcommon0
    libpulse0
    bluez
    bluez-tools
    can-utils
)

MAP_OPTIONAL_PACKAGES=(
    qtlocation5-dev
    qtpositioning5-dev
    qml-module-qtlocation
    qml-module-qtpositioning
    libqt5location5-plugin-mapboxgl
)

VKB_OPTIONAL_PACKAGES=(
    qml-module-qtquick-virtualkeyboard
    qtvirtualkeyboard-plugin
    qml-module-qt-labs-folderlistmodel
    qml-module-qt-labs-settings
    qml-module-qt-labs-platform
)

collect_available_packages() {
    local -n input_ref=$1
    local -n available_ref=$2
    local -n missing_ref=$3

    available_ref=()
    missing_ref=()
    for pkg in "${input_ref[@]}"; do
        if apt-cache show "${pkg}" >/dev/null 2>&1; then
            available_ref+=("${pkg}")
        else
            missing_ref+=("${pkg}")
        fi
    done
}

AVAILABLE_MAP_PACKAGES=()
MISSING_MAP_PACKAGES=()
AVAILABLE_VKB_PACKAGES=()
MISSING_VKB_PACKAGES=()

collect_available_packages MAP_OPTIONAL_PACKAGES AVAILABLE_MAP_PACKAGES MISSING_MAP_PACKAGES
collect_available_packages VKB_OPTIONAL_PACKAGES AVAILABLE_VKB_PACKAGES MISSING_VKB_PACKAGES

echo "[INFO] Installing Qt5 toolchain and runtime dependencies..."
sudo apt install -y "${BASE_PACKAGES[@]}" "${AVAILABLE_MAP_PACKAGES[@]}" "${AVAILABLE_VKB_PACKAGES[@]}"

if ((${#AVAILABLE_MAP_PACKAGES[@]} > 0)); then
    echo "[INFO] Installed Qt5 map packages: ${AVAILABLE_MAP_PACKAGES[*]}"
fi

if ((${#MISSING_MAP_PACKAGES[@]} > 0)); then
    echo "[WARN] Some Qt5 map packages are not available in this apt repo:"
    echo "       ${MISSING_MAP_PACKAGES[*]}"
    echo "       Mapbox navigation requires this stack; install missing packages or use a repo that provides them."
fi

if ((${#AVAILABLE_VKB_PACKAGES[@]} > 0)); then
    echo "[INFO] Installed Qt5 virtual keyboard packages: ${AVAILABLE_VKB_PACKAGES[*]}"
fi

if ((${#MISSING_VKB_PACKAGES[@]} > 0)); then
    echo "[WARN] Some Qt5 virtual keyboard packages are not available in this apt repo:"
    echo "       ${MISSING_VKB_PACKAGES[*]}"
    echo "       On-screen Vietnamese keyboard needs qml-module-qtquick-virtualkeyboard and qml-module-qt-labs-folderlistmodel."
fi

echo "[INFO] Adding user '${USER}' to dialout group for serial access..."
sudo usermod -aG dialout "${USER}"

echo
echo "[DONE] Raspberry Pi native Qt5 dependencies installed."
echo "[NEXT] Re-login (or run: newgrp dialout) so serial permission takes effect."
echo "[NEXT] Then run:"
echo "       ./scripts/pi/build_pi_qt5.sh"
echo "       ./scripts/pi/verify_pi_qt5.sh"
echo "       ./scripts/pi/run_pi_qt5.sh"
