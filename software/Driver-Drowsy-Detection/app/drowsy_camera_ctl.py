#!/usr/bin/env python3
"""Control utility for the drowsy camera daemon."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.drowsy_ipc import resolve_socket_path, send_command, wait_for_socket


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Control the drowsy camera daemon.")
    parser.add_argument("command", choices=["show", "hide", "status", "reset", "stop"])
    parser.add_argument("--socket-path", default="")
    parser.add_argument("--start-daemon-if-needed", action="store_true")
    parser.add_argument("--start-timeout", type=float, default=8.0)
    parser.add_argument("--camera-index", type=int, default=0)
    parser.add_argument("--camera-path", default="")
    parser.add_argument("--backend", choices=["auto", "v4l2", "default"], default="v4l2")
    parser.add_argument("--fallback-scan-max", type=int, default=6)
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--height", type=int, default=540)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--no-mirror", action="store_true")
    parser.add_argument("--jpeg-quality", type=int, default=70)
    parser.add_argument("--stream-every-n", type=int, default=1)
    parser.add_argument("--metrics-every-n", type=int, default=10)
    parser.add_argument("--viewer-fullscreen", action="store_true")
    parser.add_argument("--viewer-title", default="Drowsiness Detection Live")
    return parser.parse_args()


def daemon_script_path() -> Path:
    return (ROOT_DIR / "app" / "live_camera_daemon.py").resolve()


def viewer_env_payload() -> dict[str, str]:
    payload: dict[str, str] = {}
    for key in (
        "DISPLAY",
        "WAYLAND_DISPLAY",
        "XAUTHORITY",
        "XDG_RUNTIME_DIR",
        "DBUS_SESSION_BUS_ADDRESS",
        "XDG_SESSION_TYPE",
        "QT_QPA_PLATFORM",
    ):
        value = os.environ.get(key, "").strip()
        if value:
            payload[key] = value
    return payload


def spawn_daemon(args: argparse.Namespace, socket_path: str) -> None:
    script_path = daemon_script_path()
    cmd = [
        sys.executable,
        str(script_path),
        "--socket-path",
        socket_path,
        "--backend",
        args.backend,
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--fps",
        str(args.fps),
        "--fallback-scan-max",
        str(args.fallback_scan_max),
        "--jpeg-quality",
        str(args.jpeg_quality),
        "--stream-every-n",
        str(args.stream_every_n),
        "--metrics-every-n",
        str(args.metrics_every_n),
        "--viewer-title",
        args.viewer_title,
    ]
    if args.camera_path:
        cmd.extend(["--camera-path", args.camera_path])
    else:
        cmd.extend(["--camera-index", str(args.camera_index)])
    if args.no_mirror:
        cmd.append("--no-mirror")
    if args.viewer_fullscreen:
        cmd.append("--viewer-fullscreen")

    subprocess.Popen(
        cmd,
        cwd=str(ROOT_DIR),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def main() -> int:
    args = parse_args()
    socket_path = resolve_socket_path(args.socket_path)

    if args.start_daemon_if_needed:
        try:
            send_command(socket_path, "status", timeout=0.5)
        except Exception:
            spawn_daemon(args, socket_path)
            if not wait_for_socket(socket_path, timeout=args.start_timeout):
                print(
                    json.dumps({"ok": False, "error": "daemon-start-timeout"}),
                    file=sys.stderr,
                )
                return 1

    try:
        payload = {}
        if args.command == "show":
            payload.update(viewer_env_payload())
            payload["viewer_title"] = args.viewer_title
            payload["viewer_fullscreen"] = args.viewer_fullscreen
        response = send_command(
            socket_path,
            args.command,
            timeout=max(args.start_timeout, 3.0),
            **payload,
        )
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1

    print(json.dumps(response, ensure_ascii=True))
    return 0 if response.get("ok", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
