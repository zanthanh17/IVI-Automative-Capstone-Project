#!/usr/bin/env bash
# ===========================================================================
#  diagnose_bluetooth.sh
#  Kiểm tra trạng thái Bluetooth Audio trên Raspberry Pi
#  Hỗ trợ cả PipeWire (Pi OS Bookworm+) và PulseAudio (legacy)
# ===========================================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

echo "========================================"
echo "  Bluetooth Audio Diagnostics"
echo "========================================"

# ---------- Detect audio backend ----------
AUDIO_BACKEND="unknown"
if systemctl --user is-active --quiet pipewire 2>/dev/null || \
   pgrep -x pipewire >/dev/null 2>&1; then
    AUDIO_BACKEND="pipewire"
elif pulseaudio --check 2>/dev/null || \
     systemctl --user is-active --quiet pulseaudio 2>/dev/null; then
    AUDIO_BACKEND="pulseaudio"
fi

echo ""
echo "[0] Audio Backend:"
if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
    pass "PipeWire detected (Pi OS Bookworm+)"
elif [[ "${AUDIO_BACKEND}" == "pulseaudio" ]]; then
    pass "PulseAudio detected"
else
    fail "No audio backend detected"
fi

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

    # Check device info for connected devices — profiles
    while IFS= read -r line; do
        MAC=$(echo "${line}" | awk '{print $2}')
        if [[ -n "${MAC}" ]]; then
            echo ""
            info "Profiles for ${MAC}:"
            bluetoothctl info "${MAC}" 2>/dev/null | grep -E "UUID:|Connected:|Paired:|Trusted:" | while read -r pline; do
                echo "       ${pline}"
            done
        fi
    done <<< "${CONNECTED}"
else
    fail "No connected devices"
    echo "     Connect phone first via Bluetooth settings"
fi

# 5. Audio system
echo ""
echo "[5] Audio System (${AUDIO_BACKEND}):"

if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
    # PipeWire checks
    if systemctl --user is-active --quiet pipewire 2>/dev/null; then
        pass "PipeWire service is running"
    else
        fail "PipeWire service is NOT running"
        echo "     Fix: systemctl --user start pipewire pipewire-pulse"
    fi

    if systemctl --user is-active --quiet wireplumber 2>/dev/null; then
        pass "WirePlumber (session manager) is running"
    else
        fail "WirePlumber is NOT running"
        echo "     Fix: systemctl --user start wireplumber"
    fi

    if systemctl --user is-active --quiet pipewire-pulse 2>/dev/null; then
        pass "PipeWire-Pulse bridge is running"
    else
        warn "PipeWire-Pulse bridge not running"
        echo "     Fix: systemctl --user start pipewire-pulse"
    fi

    # Check if SPA bluetooth plugin is installed
    if find /usr/lib -name "libspa-bluez5*" -o -name "bluez5" 2>/dev/null | grep -q .; then
        pass "SPA Bluetooth plugin (libspa-0.2-bluetooth) installed"
    elif dpkg -l libspa-0.2-bluetooth 2>/dev/null | grep -q "^ii"; then
        pass "SPA Bluetooth plugin (libspa-0.2-bluetooth) installed"
    else
        fail "SPA Bluetooth plugin NOT installed"
        echo "     Fix: sudo apt install libspa-0.2-bluetooth"
        echo "     Then restart: systemctl --user restart pipewire wireplumber"
    fi

    # Check if bluetooth device shows up in PipeWire
    PW_BT_NODES=$(pw-cli list-objects 2>/dev/null | grep -i "bluez\|bluetooth" || true)
    if [[ -n "${PW_BT_NODES}" ]]; then
        pass "Bluetooth nodes found in PipeWire"
    else
        warn "No Bluetooth nodes in PipeWire"
        echo "     Phone may not be streaming audio yet"
    fi

elif [[ "${AUDIO_BACKEND}" == "pulseaudio" ]]; then
    if pulseaudio --check 2>/dev/null; then
        pass "PulseAudio is running"
    else
        fail "PulseAudio is NOT running"
        echo "     Fix: pulseaudio --start"
    fi

    if pactl list modules short 2>/dev/null | grep -q "bluetooth"; then
        pass "PulseAudio bluetooth module loaded"
    else
        fail "PulseAudio bluetooth module NOT loaded"
        echo "     Fix: pactl load-module module-bluetooth-discover"
    fi
fi

# 6. Audio sinks
echo ""
echo "[6] Audio Sinks (outputs):"
SINKS=$(pactl list sinks short 2>/dev/null || true)
if [[ -n "${SINKS}" ]]; then
    BT_SINK_FOUND=false
    echo "${SINKS}" | while read -r line; do
        if echo "${line}" | grep -qi "bluetooth\|bluez"; then
            pass "Bluetooth sink: ${line}"
            BT_SINK_FOUND=true
        else
            echo "     ${line}"
        fi
    done

    # Separate check for bluetooth sinks
    if echo "${SINKS}" | grep -qi "bluetooth\|bluez"; then
        : # already shown
    else
        warn "No Bluetooth audio sink found"
        echo "     Phone is not streaming audio to Pi"
        echo "     → Ensure phone 'Media Audio' (A2DP) profile is enabled"
        if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
            echo "     → Check: sudo apt install libspa-0.2-bluetooth"
            echo "     → Restart: systemctl --user restart pipewire wireplumber"
        fi
    fi
else
    warn "No audio sinks found"
fi

# 7. BlueZ MediaPlayer1 (AVRCP)
echo ""
echo "[7] BlueZ MediaPlayer1 (AVRCP - media control):"
MANAGED_OBJECTS=$(dbus-send --system --dest=org.bluez --print-reply / \
    org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null || true)

MEDIA_PLAYER=$(echo "${MANAGED_OBJECTS}" | grep -o '"[^"]*MediaPlayer1[^"]*"' || true)
MEDIA_PLAYER_PATH=$(echo "${MANAGED_OBJECTS}" | \
    grep -oP 'object path "[^"]*player[^"]*"' | head -1 | \
    grep -oP '"[^"]+"' | tr -d '"' || true)

if [[ -n "${MEDIA_PLAYER}" ]]; then
    pass "MediaPlayer1 interface found (AVRCP active)"
    if [[ -n "${MEDIA_PLAYER_PATH}" ]]; then
        info "Player path: ${MEDIA_PLAYER_PATH}"
        # Try to get track info
        TRACK_INFO=$(dbus-send --system --dest=org.bluez --print-reply \
            "${MEDIA_PLAYER_PATH}" \
            org.freedesktop.DBus.Properties.Get \
            string:"org.bluez.MediaPlayer1" string:"Track" 2>/dev/null || true)
        STATUS_INFO=$(dbus-send --system --dest=org.bluez --print-reply \
            "${MEDIA_PLAYER_PATH}" \
            org.freedesktop.DBus.Properties.Get \
            string:"org.bluez.MediaPlayer1" string:"Status" 2>/dev/null || true)
        if [[ -n "${TRACK_INFO}" ]]; then
            TITLE=$(echo "${TRACK_INFO}" | grep -A1 '"Title"' | grep 'string' | \
                    sed 's/.*string "\(.*\)"/\1/' || echo "(unknown)")
            ARTIST=$(echo "${TRACK_INFO}" | grep -A1 '"Artist"' | grep 'string' | \
                     sed 's/.*string "\(.*\)"/\1/' || echo "(unknown)")
            info "Now playing: ${TITLE} - ${ARTIST}"
        fi
        if [[ -n "${STATUS_INFO}" ]]; then
            STATUS=$(echo "${STATUS_INFO}" | grep 'string' | tail -1 | \
                     sed 's/.*string "\(.*\)"/\1/' || echo "unknown")
            info "Status: ${STATUS}"
        fi
    fi
else
    warn "MediaPlayer1 NOT found"
    echo "     Phone may not have active media session"
    echo "     → Open YouTube/Spotify on phone first, then re-check"
    echo "     → iPhone: play music FIRST, then connect BT"
    echo "     → Some phones need AVRCP to be explicitly enabled"
fi

# 8. A2DP profile
echo ""
echo "[8] A2DP Audio Profile:"
A2DP=$(echo "${MANAGED_OBJECTS}" | grep -c "MediaTransport1" || true)

if [[ "${A2DP}" -gt 0 ]]; then
    pass "A2DP MediaTransport1 active (audio streaming)"
else
    fail "A2DP MediaTransport1 NOT found (no audio streaming)"
    echo "     → Phone is connected but not streaming audio"
    echo ""
    echo "     Cách fix:"
    echo "     a) Trên iPhone: Settings → Bluetooth → (i) next to Pi → enable Media Audio"
    echo "     b) Quên (Forget) thiết bị Pi trên phone, rồi pair LẠI"
    echo "        Khi pair, đảm bảo accept ALL profiles"
    echo "     c) Thử disconnect rồi reconnect:"
    echo "        bluetoothctl disconnect 20:1A:94:49:83:8E"
    echo "        sleep 2"
    echo "        bluetoothctl connect 20:1A:94:49:83:8E"
    echo "     d) Sau khi connect, phát nhạc trên phone rồi check lại"
    if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
        echo "     e) Kiểm tra libspa bluetooth:"
        echo "        sudo apt install libspa-0.2-bluetooth"
        echo "        systemctl --user restart pipewire wireplumber"
    fi
fi

# 9. BlueZ UUIDs — check supported profiles
echo ""
echo "[9] Bluetooth Profiles (UUIDs) on adapter:"
ADAPTER_UUIDS=$(bluetoothctl show 2>/dev/null | grep "UUID:" || true)
if echo "${ADAPTER_UUIDS}" | grep -qi "Audio Sink"; then
    pass "Audio Sink (A2DP Sink) profile supported"
else
    fail "Audio Sink profile NOT advertised"
    echo "     BlueZ may not be configured as audio sink"
    echo "     → Run: ./setup_bluetooth_audio.sh"
fi
if echo "${ADAPTER_UUIDS}" | grep -qi "A/V Remote Control"; then
    pass "A/V Remote Control (AVRCP) profile supported"
else
    warn "AVRCP profile not listed"
fi

echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "Audio backend: ${AUDIO_BACKEND}"
echo ""

if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
    echo "Nếu âm thanh phát trên điện thoại thay vì Pi:"
    echo "  1. Cài libspa bluetooth: sudo apt install libspa-0.2-bluetooth"
    echo "  2. Restart PipeWire: systemctl --user restart pipewire wireplumber"
    echo "  3. Trên phone: Settings → Bluetooth → Pi → bật 'Media Audio'"
    echo "  4. Quên Pi trên phone, pair lại, chọn accept ALL profiles"
    echo "  5. Chạy lại: ./diagnose_bluetooth.sh"
else
    echo "Nếu âm thanh phát trên điện thoại thay vì Pi:"
    echo "  1. Chạy: pactl load-module module-bluetooth-discover"
    echo "  2. Restart PulseAudio: pulseaudio -k && pulseaudio --start"
    echo "  3. Trên phone: Settings → Bluetooth → Pi → bật 'Media Audio'"
    echo "  4. Quên Pi trên phone, pair lại"
fi
echo ""
echo "Nếu dashboard không hiện thông tin bài hát:"
echo "  1. Đảm bảo phone hỗ trợ AVRCP 1.4+"
echo "  2. Phát nhạc trên phone trước khi check"
echo "  3. iPhone: phát nhạc TRƯỚC khi kết nối BT"
echo "  4. Một số phone cần bật 'Media scanning' trong BT settings"
echo ""
