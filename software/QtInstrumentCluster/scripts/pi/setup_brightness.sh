#!/usr/bin/env bash
# setup_brightness.sh — Cấu hình quyền backlight trên Raspberry Pi
# Chạy 1 lần: sudo bash scripts/pi/setup_brightness.sh
set -euo pipefail

echo "=== Brightness Setup for IVI Dashboard ==="

# 1. Cài brightnessctl nếu chưa có
if ! command -v brightnessctl &>/dev/null; then
    echo "[1/3] Installing brightnessctl..."
    sudo apt-get update -qq
    sudo apt-get install -y brightnessctl
else
    echo "[1/3] brightnessctl already installed."
fi

# 2. Tạo udev rule để user có quyền ghi backlight
UDEV_RULE="/etc/udev/rules.d/90-backlight.rules"
echo "[2/3] Creating udev rule: ${UDEV_RULE}"
sudo tee "${UDEV_RULE}" > /dev/null <<'EOF'
# Allow non-root users in video group to control backlight
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness"
EOF

# 3. Đảm bảo user hiện tại thuộc nhóm video
CURRENT_USER="${SUDO_USER:-${USER}}"
if id -nG "${CURRENT_USER}" | grep -qw video; then
    echo "[3/3] User '${CURRENT_USER}' already in 'video' group."
else
    echo "[3/3] Adding '${CURRENT_USER}' to 'video' group..."
    sudo usermod -aG video "${CURRENT_USER}"
    echo "     → You need to log out and back in for group change to take effect."
fi

# Áp dụng ngay cho session hiện tại
echo ""
echo "Applying permissions now..."
for bl in /sys/class/backlight/*/brightness; do
    if [ -f "$bl" ]; then
        sudo chmod g+w "$bl"
        sudo chgrp video "$bl"
        echo "  ✓ ${bl}"
    fi
done

echo ""
echo "=== Done! Brightness control should work from the dashboard now. ==="
echo "If running for the first time, please reboot: sudo reboot"
