#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv-pi}"

if [[ ! -x "$VENV_DIR/bin/python3" ]]; then
  echo "ERROR: venv not found at $VENV_DIR"
  echo "Run setup first: bash \"$ROOT_DIR/scripts/pi4_setup.sh\""
  exit 1
fi

# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 <show|hide|status|reset|stop> [extra args]"
  exit 1
fi

exec python3 "$ROOT_DIR/app/drowsy_camera_ctl.py" "$@"
