#!/usr/bin/env bash
# ===========================================================================
#  debug_media_dbus.sh
#  Chẩn đoán chi tiết D-Bus BlueZ MediaPlayer1 metadata
#  Chạy script này KHI đang phát nhạc trên phone
# ===========================================================================

echo "========================================"
echo "  D-Bus BlueZ MediaPlayer1 Debug"
echo "========================================"

# 1. Tìm MediaPlayer1 path
echo ""
echo "[1] Tìm MediaPlayer1 objects..."
MANAGED=$(dbus-send --system --dest=org.bluez --print-reply / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null)

PLAYER_PATH=$(echo "${MANAGED}" | grep -oP 'object path "[^"]*player[^"]*"' | head -1 | grep -oP '"[^"]+"' | tr -d '"')

if [[ -z "${PLAYER_PATH}" ]]; then
    echo "  ✗ Không tìm thấy MediaPlayer1 path!"
    echo "  → Đảm bảo đang phát nhạc trên phone"
    exit 1
fi
echo "  ✓ Player path: ${PLAYER_PATH}"

# 2. GetAll properties
echo ""
echo "[2] Properties.GetAll org.bluez.MediaPlayer1..."
echo "---"
dbus-send --system --dest=org.bluez --print-reply \
    "${PLAYER_PATH}" \
    org.freedesktop.DBus.Properties.GetAll \
    string:"org.bluez.MediaPlayer1" 2>&1
echo "---"

# 3. Get Track specifically
echo ""
echo "[3] Properties.Get Track..."
echo "---"
dbus-send --system --dest=org.bluez --print-reply \
    "${PLAYER_PATH}" \
    org.freedesktop.DBus.Properties.Get \
    string:"org.bluez.MediaPlayer1" \
    string:"Track" 2>&1
echo "---"

# 4. Get Status specifically
echo ""
echo "[4] Properties.Get Status..."
echo "---"
dbus-send --system --dest=org.bluez --print-reply \
    "${PLAYER_PATH}" \
    org.freedesktop.DBus.Properties.Get \
    string:"org.bluez.MediaPlayer1" \
    string:"Status" 2>&1
echo "---"

# 5. Monitor PropertiesChanged in real-time (30 seconds)
echo ""
echo "[5] Monitoring PropertiesChanged cho 30 giây..."
echo "    *** QUAN TRỌNG: Chuyển sang bài HÁT KHÁC trên phone (không chỉ play/pause) ***"
echo "    Track metadata chỉ được gửi khi bài hát THAY ĐỔI."
echo "---"
timeout 30 dbus-monitor --system \
    "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='${PLAYER_PATH}'" 2>&1 || true
echo "---"

echo ""
echo "DONE. Copy toàn bộ output trên và gửi lại."
