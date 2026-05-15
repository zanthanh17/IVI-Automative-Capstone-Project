#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
    echo "[ERROR] Do not run this script as root."
    echo "        Run it as your normal user. The script will use sudo when needed."
    exit 1
fi

CAN_IFACE="${CAN_IFACE:-can0}"
CAN_BITRATE="${CAN_BITRATE:-500000}"
MCP_OSCILLATOR="${MCP_OSCILLATOR:-8000000}"
MCP_INTERRUPT_GPIO="${MCP_INTERRUPT_GPIO:-25}"
MCP_SPI_MAX_FREQ="${MCP_SPI_MAX_FREQ:-10000000}"
BOOT_CONFIG="/boot/firmware/config.txt"
if [[ ! -f "${BOOT_CONFIG}" ]]; then
    BOOT_CONFIG="/boot/config.txt"
fi

if [[ ! -f "${BOOT_CONFIG}" ]]; then
    echo "[ERROR] Raspberry Pi boot config not found at /boot/firmware/config.txt or /boot/config.txt"
    exit 1
fi

echo "[INFO] Installing SocketCAN utilities..."
sudo apt update
sudo apt install -y can-utils

append_once() {
    local line="$1"
    local file="$2"
    if grep -Fxq "${line}" "${file}"; then
        echo "[OK] Already present: ${line}"
    else
        echo "[INFO] Adding to ${file}: ${line}"
        echo "${line}" | sudo tee -a "${file}" >/dev/null
    fi
}

append_once "dtparam=spi=on" "${BOOT_CONFIG}"
append_once "dtoverlay=mcp2515-can0,oscillator=${MCP_OSCILLATOR},interrupt=${MCP_INTERRUPT_GPIO},spimaxfrequency=${MCP_SPI_MAX_FREQ}" "${BOOT_CONFIG}"

SERVICE_FILE="/etc/systemd/system/socketcan-${CAN_IFACE}.service"
TMP_SERVICE="$(mktemp)"
cat >"${TMP_SERVICE}" <<EOF
[Unit]
Description=Bring up SocketCAN ${CAN_IFACE}
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip link set ${CAN_IFACE} up type can bitrate ${CAN_BITRATE} restart-ms 100
ExecStop=/sbin/ip link set ${CAN_IFACE} down

[Install]
WantedBy=multi-user.target
EOF

echo "[INFO] Installing ${SERVICE_FILE}"
sudo install -m 0644 "${TMP_SERVICE}" "${SERVICE_FILE}"
rm -f "${TMP_SERVICE}"

sudo systemctl daemon-reload
sudo systemctl enable "socketcan-${CAN_IFACE}.service"

echo
echo "[DONE] MCP2515 SocketCAN boot configuration installed."
echo "[NEXT] Reboot Raspberry Pi, then verify with:"
echo "       ip -details link show ${CAN_IFACE}"
echo "       candump ${CAN_IFACE}"
