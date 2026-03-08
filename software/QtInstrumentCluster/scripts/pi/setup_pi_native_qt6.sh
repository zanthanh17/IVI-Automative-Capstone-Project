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
    build-essential \
    pkg-config \
    git \
    rsync \
    ca-certificates \
    qt6-base-dev \
    qt6-base-dev-tools \
    qt6-declarative-dev \
    qt6-declarative-dev-tools \
    qt6-serialport-dev \
    qt6-multimedia-dev \
    qt6-svg-dev \
    qt6-tools-dev-tools \
    qt6-l10n-tools \
    libqt6dbus6 \
    qt6-connectivity-dev \
    qml6-module-qtqml \
    qml6-module-qtqml-models \
    qml6-module-qtqml-workerscript \
    qml6-module-qtquick \
    qml6-module-qtquick-window \
    qml6-module-qtquick-controls \
    libgl1-mesa-dri \
    libgles2 \
    libxkbcommon0 \
    libpulse0 \
    bluez \
    bluez-tools \
    libspa-0.2-bluetooth
)

MAP_OPTIONAL_PACKAGES=(
    qt6-location-dev
    qt6-positioning-dev
    qt6-location-dev-tools
    qml6-module-qtlocation
    qml6-module-qtpositioning
)

WEB_OPTIONAL_PACKAGES=(
    qt6-webengine-dev
    qt6-webengine-dev-tools
    qml6-module-qtwebengine
    qml6-module-qtwebchannel
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
AVAILABLE_WEB_PACKAGES=()
MISSING_WEB_PACKAGES=()

collect_available_packages MAP_OPTIONAL_PACKAGES AVAILABLE_MAP_PACKAGES MISSING_MAP_PACKAGES
collect_available_packages WEB_OPTIONAL_PACKAGES AVAILABLE_WEB_PACKAGES MISSING_WEB_PACKAGES

echo "[INFO] Installing build tools and runtime dependencies..."
sudo apt install -y "${BASE_PACKAGES[@]}" "${AVAILABLE_MAP_PACKAGES[@]}" "${AVAILABLE_WEB_PACKAGES[@]}"

if ((${#AVAILABLE_MAP_PACKAGES[@]} > 0)); then
    echo "[INFO] Installed Qt map packages: ${AVAILABLE_MAP_PACKAGES[*]}"
fi

if ((${#MISSING_MAP_PACKAGES[@]} > 0)); then
    echo "[WARN] Some Qt6 map packages are not available in this apt repo:"
    echo "       ${MISSING_MAP_PACKAGES[*]}"
    echo "       Navigation map will fall back to turn-by-turn HUD."
    echo "       For full QtLocation map, use a repo/Qt SDK that provides these packages."
fi

if ((${#AVAILABLE_WEB_PACKAGES[@]} > 0)); then
    echo "[INFO] Installed Qt WebEngine packages: ${AVAILABLE_WEB_PACKAGES[*]}"
fi

if ((${#MISSING_WEB_PACKAGES[@]} > 0)); then
    echo "[WARN] Some Qt6 WebEngine packages are not available in this apt repo:"
    echo "       ${MISSING_WEB_PACKAGES[*]}"
    echo "       WebEngine-based map MVP will not be available on this image."
fi

echo "[INFO] Adding user '${USER}' to dialout group for serial access..."
sudo usermod -aG dialout "${USER}"

echo
echo "[DONE] Raspberry Pi native Qt6 dependencies installed."
echo "[NEXT] Re-login (or run: newgrp dialout) so serial permission takes effect."
echo "[NEXT] Then run:"
echo "       ./scripts/pi/build_pi.sh"
echo "       ./scripts/pi/run_pi.sh"
