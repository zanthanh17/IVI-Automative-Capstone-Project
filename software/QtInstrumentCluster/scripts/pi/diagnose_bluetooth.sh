#!/usr/bin/env bash
# ===========================================================================
#  diagnose_bluetooth.sh
#  Kiểm tra trạng thái Bluetooth Audio trên Raspberry Pi
# ===========================================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo "========================================"
echo "  Bluetooth Audio Diagnostics"
echo "========================================"

# 1. Bluetooth service
echo ""
echo "[1] Bluetooth Service:"
if systemctl is-active --quiet bluetooth; then
    pass "bluetooth.service is running"
else
    fail "bluetooth.service is NOT running"
    echo "     Fix: sudo systemctl start bluetooth"
fi

# 2. Bluetooth adapter
echo ""
echo "[2] Bluetooth Adapter:"
if command -v bluetoothctl >/dev/null 2>&1; then
    POWERED=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    if [[ "${POWERED}" == "yes" ]]; then
        pass "Bluetooth adapter powered on"
    else
        fail "Bluetooth adapter powered off"
        echo "     Fix: bluetoothctl power on"
    fi

    DISCOVERABLE=$(bluetoothctl show 2>/dev/null | grep "Discoverable:" | awk '{print $2}')
    if [[ "${DISCOVERABLE}" == "yes" ]]; then
        pass "Discoverable: yes"
    else
        warn "Discoverable: no (phone cannot find Pi)"
        echo "     Fix: bluetoothctl discoverable on"
    fi
else
    fail "bluetoothctl not found"
fi

# 3. Paired devices
echo ""
echo "[3] Paired Devices:"
PAIRED=$(bluetoothctl devices Paired 2>/dev/null || bluetoothctl paired-devices 2>/dev/null || true)
if [[ -n "${PAIRED}" ]]; then
    pass "Found paired devices:"
    echo "${PAIRED}" | while read -r line; do
        echo "     ${line}"
    done
else
    warn "No paired devices found"
fi

# 4. Connected devices
echo ""
echo "[4] Connected Devices:"
CONNECTED=$(bluetoothctl devices Connected 2>/dev/null || true)
if [[ -n "${CONNECTED}" ]]; then
    pass "Connected devices:"
    echo "${CONNECTED}" | while read -r line; do
        echo "     ${line}"
    done
else
    fail "No connected devices"
    echo "     Connect phone first via Bluetooth settings"
fi

# 5. PulseAudio
echo ""
echo "[5] PulseAudio:"
if pulseaudio --check 2>/dev/null; then
    pass "PulseAudio is running"
else
    fail "PulseAudio is NOT running"
    echo "     Fix: pulseaudio --start"
fi

# Bluetooth module loaded?
if pactl list modules short 2>/dev/null | grep -q "bluetooth"; then
    pass "PulseAudio bluetooth module loaded"
else
    fail "PulseAudio bluetooth module NOT loaded"
    echo "     Fix: pactl load-module module-bluetooth-discover"
fi

# 6. Audio sinks
echo ""
echo "[6] Audio Sinks (outputs):"
SINKS=$(pactl list sinks short 2>/dev/null || true)
if [[ -n "${SINKS}" ]]; then
    echo "${SINKS}" | while read -r line; do
        if echo "${line}" | grep -qi "bluetooth\|bluez"; then
            pass "Bluetooth sink: ${line}"
        else
            echo "     ${line}"
        fi
    done
else
    warn "No audio sinks found"
fi

# 7. BlueZ MediaPlayer1 (AVRCP)
echo ""
echo "[7] BlueZ MediaPlayer1 (AVRCP - media control):"
MEDIA_PLAYER=$(dbus-send --system --dest=org.bluez --print-reply / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | \
    grep -o '"[^"]*MediaPlayer1[^"]*"' || true)

if [[ -n "${MEDIA_PLAYER}" ]]; then
    pass "MediaPlayer1 interface found (AVRCP active)"
    echo "     ${MEDIA_PLAYER}"
else
    warn "MediaPlayer1 NOT found"
    echo "     Phone may not have active media session"
    echo "     → Open YouTube/Spotify on phone first, then re-check"
fi

# 8. A2DP profile
echo ""
echo "[8] A2DP Audio Profile:"
A2DP=$(dbus-send --system --dest=org.bluez --print-reply / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | \
    grep -c "MediaTransport1" || true)

if [[ "${A2DP}" -gt 0 ]]; then
    pass "A2DP MediaTransport1 active (audio streaming)"
else
    fail "A2DP MediaTransport1 NOT found (no audio streaming)"
    echo "     → Phone is connected but not streaming audio"
    echo "     → Play a song on phone to activate A2DP"
fi

echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Nếu âm thanh phát trên điện thoại thay vì Pi:"
echo "  1. Kiểm tra phone settings → Bluetooth → đã bật 'Media Audio' profile"
echo "  2. Trên phone: Settings → Bluetooth → Pi device → bật 'A2DP' hoặc 'Media Audio'"
echo "  3. Chạy: pactl load-module module-bluetooth-discover"
echo "  4. Restart PulseAudio: pulseaudio -k && pulseaudio --start"
echo ""
echo "Nếu dashboard không hiện thông tin bài hát:"
echo "  1. Đảm bảo phone hỗ trợ AVRCP 1.4+"
echo "  2. Phát nhạc trên phone trước khi check"
echo "  3. Một số phone (Xiaomi, Samsung) cần bật 'Media scanning' trong BT settings"
echo ""
