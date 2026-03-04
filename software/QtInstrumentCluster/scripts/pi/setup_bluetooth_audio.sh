#!/usr/bin/env bash
# ===========================================================================
#  setup_bluetooth_audio.sh
#  Cấu hình Raspberry Pi làm Bluetooth Audio Sink (A2DP)
#  Điện thoại pair → phát nhạc → âm thanh ra Pi speaker/HDMI
# ===========================================================================
set -euo pipefail

echo "========================================"
echo "  Bluetooth A2DP Audio Sink Setup"
echo "========================================"

# 1. Cài đặt packages cần thiết
echo "[1/6] Installing Bluetooth + PulseAudio packages..."
sudo apt update
sudo apt install -y \
    bluez \
    bluez-tools \
    pulseaudio \
    pulseaudio-module-bluetooth \
    pavucontrol

# 2. Enable và start services
echo "[2/6] Enabling Bluetooth & PulseAudio services..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Đảm bảo PulseAudio chạy cho user hiện tại
if ! pulseaudio --check 2>/dev/null; then
    pulseaudio --start --log-target=syslog 2>/dev/null || true
fi

# 3. Cấu hình BlueZ cho A2DP Sink
echo "[3/6] Configuring BlueZ for A2DP Sink..."

# Backup và sửa main.conf
BLUEZ_CONF="/etc/bluetooth/main.conf"
if [[ -f "${BLUEZ_CONF}" ]]; then
    sudo cp "${BLUEZ_CONF}" "${BLUEZ_CONF}.bak.$(date +%s)"
fi

# Đảm bảo Class = 0x200414 (Audio device, Loudspeaker)
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

# 4. Cấu hình PulseAudio bluetooth module
echo "[4/6] Configuring PulseAudio Bluetooth module..."

PA_SYSTEM_CONF="/etc/pulse/default.pa"
PA_USER_CONF="${HOME}/.config/pulse/default.pa"

# Thêm module bluetooth vào PulseAudio nếu chưa có
mkdir -p "${HOME}/.config/pulse"

# Tạo user pulse config
cat > "${PA_USER_CONF}" << 'PA_EOF'
.include /etc/pulse/default.pa

### Bluetooth A2DP support
load-module module-bluetooth-policy
load-module module-bluetooth-discover

### Tự động switch sang bluetooth sink khi phone kết nối
load-module module-switch-on-connect
PA_EOF

# 5. Tạo bluetooth agent tự động accept pairing
echo "[5/6] Creating Bluetooth auto-accept agent..."

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

# 6. Restart services
echo "[6/6] Restarting services..."
sudo systemctl restart bluetooth
sleep 2
pulseaudio -k 2>/dev/null || true
sleep 1
pulseaudio --start 2>/dev/null || true

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Bước tiếp theo:"
echo "  1. Trên điện thoại, bật Bluetooth"
echo "  2. Tìm thiết bị 'IVI-Dashboard-xxx'"
echo "  3. Pair và kết nối"
echo "  4. Mở YouTube/Spotify → âm thanh sẽ phát qua Pi"
echo "  5. Dashboard sẽ hiển thị tên bài hát + controls"
echo ""
echo "Kiểm tra:"
echo "  bluetoothctl devices          # xem devices đã pair"
echo "  pactl list sinks short        # xem audio outputs"
echo "  pactl list sources short      # xem audio inputs (bluetooth)"
echo ""
echo "Nếu âm thanh không qua Pi:"
echo "  pactl set-default-sink \$(pactl list sinks short | head -1 | cut -f1)"
echo "  hoặc dùng: pavucontrol"
echo ""
