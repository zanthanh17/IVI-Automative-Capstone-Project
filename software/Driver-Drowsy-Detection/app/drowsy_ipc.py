"""Local IPC helpers for the drowsy camera daemon/viewer flow."""

from __future__ import annotations

import json
import os
import socket
import tempfile
import time
from pathlib import Path
from typing import Any


DEFAULT_SOCKET_BASENAME = "drowsy-camera-daemon.sock"


def default_runtime_dir() -> Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        return Path(runtime_dir)
    return Path(tempfile.gettempdir())


def default_socket_path() -> str:
    return str(default_runtime_dir() / DEFAULT_SOCKET_BASENAME)


def resolve_socket_path(explicit_path: str = "") -> str:
    explicit = explicit_path.strip()
    return explicit or os.environ.get("DROWSY_DAEMON_SOCKET", "").strip() or default_socket_path()


def ensure_socket_parent(socket_path: str) -> None:
    Path(socket_path).expanduser().resolve().parent.mkdir(parents=True, exist_ok=True)


def _json_line(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")


def send_json_line(sock: socket.socket, payload: dict[str, Any]) -> None:
    sock.sendall(_json_line(payload))


def recv_json_line(sock: socket.socket, timeout: float = 3.0) -> dict[str, Any]:
    sock.settimeout(timeout)
    chunks = bytearray()
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        chunks.extend(chunk)
        if b"\n" in chunk:
            break

    if not chunks:
        raise RuntimeError("No response from daemon.")

    line = chunks.split(b"\n", 1)[0]
    return json.loads(line.decode("utf-8"))


def send_command(socket_path: str, command: str, timeout: float = 3.0, **payload: Any) -> dict[str, Any]:
    message = {"cmd": command}
    message.update(payload)

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(socket_path)
        send_json_line(sock, message)
        return recv_json_line(sock, timeout=timeout)


def wait_for_socket(socket_path: str, timeout: float = 5.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not Path(socket_path).exists():
            time.sleep(0.1)
            continue
        try:
            send_command(socket_path, "status", timeout=0.5)
            return True
        except Exception:
            time.sleep(0.1)
    return False
