#!/usr/bin/env bash
# ===========================================================================
#  setup_bluetooth_audio.sh
#  Cấu hình Raspberry Pi làm Bluetooth Audio Sink (A2DP)
#  Hỗ trợ cả PipeWire (Pi OS Bookworm+) và PulseAudio (legacy)
#  Điện thoại pair → phát nhạc → âm thanh ra Pi speaker/HDMI
# ===========================================================================
set -euo pipefail

echo "========================================"
echo "  Bluetooth A2DP Audio Sink Setup"
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
echo "[INFO] Detected audio backend: ${AUDIO_BACKEND}"

# 1. Cài đặt packages cần thiết
echo "[1/7] Installing Bluetooth packages..."
sudo apt update
sudo apt install -y \
    bluez \
    bluez-tools

if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
    echo "[1/7] PipeWire detected — installing PipeWire Bluetooth modules..."
    sudo apt install -y \
        pipewire \
        pipewire-pulse \
        wireplumber \
        libspa-0.2-bluetooth
else
    echo "[1/7] PulseAudio detected — installing PulseAudio Bluetooth modules..."
    sudo apt install -y \
        pulseaudio \
        pulseaudio-module-bluetooth
fi

# 2. Enable và start services
echo "[2/7] Enabling Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# 3. Cấu hình BlueZ cho A2DP Sink + AVRCP
echo "[3/7] Configuring BlueZ for A2DP Sink + AVRCP..."

BLUEZ_CONF="/etc/bluetooth/main.conf"
if [[ -f "${BLUEZ_CONF}" ]]; then
    sudo cp "${BLUEZ_CONF}" "${BLUEZ_CONF}.bak.$(date +%s)"
fi

# Class = 0x200414 (Audio device, Loudspeaker)
# DiscoverableTimeout = 0 (luôn discoverable)
sudo tee "${BLUEZ_CONF}" > /dev/null << 'BLUEZ_EOF'
[General]
Class = 0x200414
DiscoverableTimeout = 0
PairableTimeout = 0
Name = IVI-Dashboard-%h
Enable = Source,Sink,Media,Socket

[Policy]
AutoEnable = true
BLUEZ_EOF

# 4. Cấu hình audio backend cho Bluetooth
echo "[4/7] Configuring audio backend for Bluetooth..."

if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
    # ---- PipeWire: cấu hình WirePlumber bluetooth policy ----
    WP_BT_DIR="${HOME}/.config/wireplumber/bluetooth.lua.d"
    mkdir -p "${WP_BT_DIR}"

    # Enable A2DP Sink role + auto-connect + AVRCP
    cat > "${WP_BT_DIR}/51-ivi-bluetooth.lua" << 'WP_EOF'
-- IVI Dashboard: enable bluetooth audio sink role
-- Allow phone to stream A2DP audio to this device

bluetooth_policy = {}
bluetooth_policy.roles = { "a2dp_sink" }

rule = {
  matches = {
    {
      { "device.name", "matches", "bluez_card.*" },
    },
  },
  apply_properties = {
    -- Prefer A2DP Sink profile so phone audio plays on Pi
    ["bluez5.auto-connect"]  = "[ a2dp_sink hfp_hf ]",
    ["bluez5.hw-volume"]     = "[ a2dp_sink ]",
  },
}
table.insert(alsa_monitor.rules, rule)
WP_EOF

    # PipeWire bluetooth SPA config — ensure module is loaded
    PW_BT_DIR="${HOME}/.config/pipewire/pipewire.conf.d"
    mkdir -p "${PW_BT_DIR}"

    cat > "${PW_BT_DIR}/51-ivi-bluetooth.conf" << 'PW_EOF'
# IVI Dashboard: Ensure Bluetooth SPA plugin is loaded
context.modules = [
    {   name = libpipewire-module-protocol-pulse
        args = { }
    }
]

context.spa-libs = {
    api.bluez5.* = support/libspa-bluez5
}
PW_EOF

    # Restart PipeWire + WirePlumber
    echo "     Restarting PipeWire + WirePlumber..."
    systemctl --user restart wireplumber 2>/dev/null || true
    systemctl --user restart pipewire pipewire-pulse 2>/dev/null || true

else
    # ---- PulseAudio: cấu hình bluetooth modules ----
    PA_USER_CONF="${HOME}/.config/pulse/default.pa"
    mkdir -p "${HOME}/.config/pulse"

    cat > "${PA_USER_CONF}" << 'PA_EOF'
.include /etc/pulse/default.pa

### Bluetooth A2DP support
load-module module-bluetooth-policy
load-module module-bluetooth-discover

### Tự động switch sang bluetooth sink khi phone kết nối
load-module module-switch-on-connect
PA_EOF

    pulseaudio -k 2>/dev/null || true
    sleep 1
    pulseaudio --start 2>/dev/null || true
fi

# 5. Cấu hình BlueZ profile: bật A2DP Sink + AVRCP
echo "[5/7] Configuring Bluetooth profiles (A2DP Sink + AVRCP)..."

BT_INPUT_CONF="/etc/bluetooth/input.conf"
if [[ ! -f "${BT_INPUT_CONF}" ]]; then
    sudo tee "${BT_INPUT_CONF}" > /dev/null << 'INPUT_EOF'
[General]
UserspaceHID=true
INPUT_EOF
fi

# Ensure audio.conf enables AVRCP + A2DP
BT_AUDIO_CONF="/etc/bluetooth/audio.conf"
sudo tee "${BT_AUDIO_CONF}" > /dev/null << 'AUDIO_EOF'
[General]
Enable = Source,Sink,Media,Socket
AutoConnect = true

[A2DP]
SBCSources = 1
SBCSinks = 1
AUDIO_EOF

# 6. Tạo bluetooth agent tự động accept pairing
echo "[6/7] Creating Bluetooth auto-accept agent..."

AGENT_SCRIPT="/usr/local/bin/bt-agent-auto.sh"
sudo tee "${AGENT_SCRIPT}" > /dev/null << 'AGENT_EOF'
#!/usr/bin/env bash
# Bluetooth agent tự động accept connections
# Chạy background khi boot

# Đợi bluetooth service ready
sleep 3

bluetoothctl << BTEOF
power on
discoverable on
pairable on
agent NoInputNoOutput
default-agent
BTEOF

# Giữ agent chạy
while true; do
    sleep 60
    # Re-enable discoverable nếu bị tắt
    bluetoothctl discoverable on 2>/dev/null || true
done
AGENT_EOF

sudo chmod +x "${AGENT_SCRIPT}"

# Tạo systemd service cho bt-agent
sudo tee /etc/systemd/system/bt-agent.service > /dev/null << 'SVC_EOF'
[Unit]
Description=Bluetooth Auto-Accept Agent
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bt-agent-auto.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVC_EOF

sudo systemctl daemon-reload
sudo systemctl enable bt-agent
sudo systemctl start bt-agent

# 7. Restart services
echo "[7/7] Restarting Bluetooth service..."
sudo systemctl restart bluetooth
sleep 2

# Ensure audio backend is running
if [[ "${AUDIO_BACKEND}" == "pipewire" ]]; then
    systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
else
    pulseaudio -k 2>/dev/null || true
    sleep 1
    pulseaudio --start 2>/dev/null || true
fi

echo ""
echo "========================================"
echo "  Setup Complete! (backend: ${AUDIO_BACKEND})"
echo "========================================"
echo ""
echo "Bước tiếp theo:"
echo "  1. Ngắt kết nối Bluetooth cũ trên phone (nếu có)"
echo "  2. Quên (Forget) thiết bị Pi trên phone"
echo "  3. Pair lại: tìm 'IVI-Dashboard-xxx' trên phone"
echo "  4. Khi pair, BẬT CẢ 2 profile: 'Media Audio' (A2DP) + 'Phone Audio' (HFP)"
echo "  5. Mở YouTube/Spotify trên phone → âm thanh sẽ phát qua Pi"
echo "  6. Dashboard sẽ hiển thị tên bài hát + controls"
echo ""
echo "Nếu đã pair rồi mà vẫn không có audio:"
echo "  1. Trên phone: Settings → Bluetooth → Pi device → bật 'Media Audio'"
echo "  2. Hoặc chạy:"
echo "     bluetoothctl disconnect <MAC>"
echo "     bluetoothctl connect <MAC>"
echo "  3. Sau đó phát nhạc và chạy: ./diagnose_bluetooth.sh"
echo ""
echo "Kiểm tra:"
echo "  bluetoothctl devices          # xem devices đã pair"
echo "  pactl list sinks short        # xem audio outputs"
echo "  ./diagnose_bluetooth.sh       # full diagnostics"
echo ""
