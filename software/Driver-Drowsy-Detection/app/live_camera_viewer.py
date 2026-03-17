#!/usr/bin/env python3
"""Lightweight viewer for frames streamed by live_camera_daemon.py."""

from __future__ import annotations

import argparse
import socket
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.drowsy_ipc import resolve_socket_path, send_command
from app.live_camera_common import FRAME_HEADER_SIZE, FRAME_MAGIC


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="View frames from the drowsy camera daemon.")
    parser.add_argument("--socket-path", default="")
    parser.add_argument("--window-title", default="Drowsiness Detection Live")
    parser.add_argument("--fullscreen", action="store_true")
    return parser.parse_args()


def decode_packets(buffer: bytearray):
    frames = []
    while True:
        if len(buffer) < FRAME_HEADER_SIZE:
            break

        if buffer[:4] != FRAME_MAGIC:
            sync_index = buffer.find(FRAME_MAGIC)
            if sync_index < 0:
                buffer.clear()
                break
            del buffer[:sync_index]
            if len(buffer) < FRAME_HEADER_SIZE:
                break

        payload_size = int.from_bytes(buffer[4:8], "little")
        packet_size = FRAME_HEADER_SIZE + payload_size
        if payload_size <= 0 or len(buffer) < packet_size:
            break

        payload = bytes(buffer[FRAME_HEADER_SIZE:packet_size])
        del buffer[:packet_size]
        frames.append(payload)
    return frames


def main() -> int:
    args = parse_args()
    socket_path = resolve_socket_path(args.socket_path)

    cv2.namedWindow(args.window_title, cv2.WINDOW_NORMAL)
    if args.fullscreen:
        cv2.setWindowProperty(
            args.window_title,
            cv2.WND_PROP_FULLSCREEN,
            cv2.WINDOW_FULLSCREEN,
        )

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(1.0)
            sock.connect(socket_path)
            sock.sendall(b'{"cmd":"stream"}\n')
            buffer = bytearray()

            while True:
                try:
                    chunk = sock.recv(65536)
                    if not chunk:
                        break
                    buffer.extend(chunk)
                except socket.timeout:
                    pass

                for payload in decode_packets(buffer):
                    frame_data = np.frombuffer(payload, dtype=np.uint8)
                    frame = cv2.imdecode(frame_data, cv2.IMREAD_COLOR)
                    if frame is not None:
                        cv2.imshow(args.window_title, frame)

                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    break
                if key == ord("r"):
                    try:
                        send_command(socket_path, "reset", timeout=1.0)
                    except Exception:
                        pass
    except OSError as exc:
        print(f"Viewer connection failed: {exc}", file=sys.stderr)
        return 1
    finally:
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
