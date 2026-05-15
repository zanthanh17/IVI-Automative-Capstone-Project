#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_FILE="${UNIT_DIR}/drowsy-camera-daemon.service"
RUN_SCRIPT="${ROOT_DIR}/scripts/pi4_run_daemon.sh"

mkdir -p "${UNIT_DIR}"

cat >"${UNIT_FILE}" <<EOF
[Unit]
Description=Drowsiness camera daemon
After=default.target

[Service]
Type=simple
WorkingDirectory=${ROOT_DIR}
Environment=PYTHONUNBUFFERED=1
ExecStart=${RUN_SCRIPT}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

echo "Installed user service: ${UNIT_FILE}"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now drowsy-camera-daemon.service
  echo "Service enabled and started: drowsy-camera-daemon.service"
  echo "Status:"
  systemctl --user --no-pager --full status drowsy-camera-daemon.service || true
else
  echo "systemctl not found. Start manually with:"
  echo "  ${RUN_SCRIPT}"
fi

echo
echo "For auto-start after boot without an active shell login, enable linger once:"
echo "  sudo loginctl enable-linger ${USER}"
