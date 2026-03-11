#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ASSUME_YES=0
INSTALL_QT5_AFTER=1

usage() {
    cat <<'EOF'
Usage: ./scripts/pi/migrate_qt6_to_qt5.sh [options]

Options:
  -y, --yes               Non-interactive mode (assume "yes" for prompts)
  --skip-install-qt5      Do not run setup_pi_native_qt5.sh automatically
  -h, --help              Show this help

What this script does:
  1) Detect installed Qt6-related packages
  2) Remove them with apt
  3) Run apt autoremove
  4) (Default) install Qt5 stack via setup_pi_native_qt5.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        --skip-install-qt5)
            INSTALL_QT5_AFTER=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "${EUID}" -eq 0 ]]; then
    echo "[ERROR] Do not run this script as root."
    echo "        Run it as your normal user. The script will use sudo when needed."
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "[ERROR] apt was not found. This script targets Debian-based systems."
    exit 1
fi

if ! command -v dpkg-query >/dev/null 2>&1; then
    echo "[ERROR] dpkg-query was not found."
    exit 1
fi

if ! command -v sort >/dev/null 2>&1; then
    echo "[ERROR] sort command was not found."
    exit 1
fi

mapfile -t QT6_PACKAGES < <(
    dpkg-query -W -f='${binary:Package}\n' 2>/dev/null \
    | grep -E '^(qt6-|qml6-|libqt6)' \
    | sort -u
)

if ((${#QT6_PACKAGES[@]} == 0)); then
    echo "[INFO] No installed Qt6 packages detected."
else
    echo "[INFO] Detected Qt6 packages to remove (${#QT6_PACKAGES[@]}):"
    printf '  - %s\n' "${QT6_PACKAGES[@]}"
fi

echo
echo "[WARN] This may affect other Qt6 applications on the device."
echo "[WARN] Continue only if this Pi is dedicated for Qt5 build/runtime."

if ((ASSUME_YES == 0)); then
    read -r -p "Proceed with Qt6 -> Qt5 migration? [y/N]: " REPLY
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Cancelled by user."
        exit 0
    fi
fi

echo "[INFO] Updating apt index..."
sudo apt update

if ((${#QT6_PACKAGES[@]} > 0)); then
    echo "[INFO] Removing Qt6 packages..."
    sudo apt remove -y "${QT6_PACKAGES[@]}"
    echo "[INFO] Running apt autoremove..."
    sudo apt autoremove -y
else
    echo "[INFO] Skip remove/autoremove (no Qt6 packages found)."
fi

if ((INSTALL_QT5_AFTER == 1)); then
    echo "[INFO] Installing Qt5 dependencies..."
    "${SCRIPT_DIR}/setup_pi_native_qt5.sh"
    echo
    echo "[DONE] Migration completed."
    echo "[NEXT] Build and verify:"
    echo "       ./scripts/pi/build_pi_qt5.sh"
    echo "       ./scripts/pi/verify_pi_qt5.sh"
    echo "       ./scripts/pi/run_pi_qt5.sh"
else
    echo
    echo "[DONE] Qt6 removal completed."
    echo "[NEXT] Install Qt5 manually:"
    echo "       ./scripts/pi/setup_pi_native_qt5.sh"
fi
