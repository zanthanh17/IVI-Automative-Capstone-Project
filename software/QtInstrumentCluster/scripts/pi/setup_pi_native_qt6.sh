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

echo "[INFO] Installing build tools and runtime dependencies..."
sudo apt install -y \
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

echo "[INFO] Adding user '${USER}' to dialout group for serial access..."
sudo usermod -aG dialout "${USER}"

echo
echo "[DONE] Raspberry Pi native Qt6 dependencies installed."
echo "[NEXT] Re-login (or run: newgrp dialout) so serial permission takes effect."
echo "[NEXT] Then run:"
echo "       ./scripts/pi/build_pi.sh"
echo "       ./scripts/pi/run_pi.sh"
