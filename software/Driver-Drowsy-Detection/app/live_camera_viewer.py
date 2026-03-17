#!/usr/bin/env python3
"""Lightweight viewer for frames streamed by live_camera_daemon.py."""

from __future__ import annotations

import argparse
import socket
import sys
import time
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
    parser.add_argument("--window-width", type=int, default=1024)
    parser.add_argument("--window-height", type=int, default=600)
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


def point_in_rect(x: int, y: int, rect) -> bool:
    if rect is None:
        return False
    left, top, right, bottom = rect
    return left <= x <= right and top <= y <= bottom


def set_status_message(state: dict[str, object], message: str, duration: float = 2.0) -> None:
    state["status_message"] = message
    state["status_until"] = time.monotonic() + max(0.1, duration)


def current_status_message(state: dict[str, object]) -> str:
    status_until = float(state.get("status_until", 0.0))
    if time.monotonic() < status_until:
        return str(state.get("status_message", "")).strip()
    return "Touch RESET to clear detector state or CLOSE to exit viewer"


def draw_button(canvas, rect, label: str, fill_color) -> None:
    left, top, right, bottom = rect
    cv2.rectangle(canvas, (left, top), (right, bottom), fill_color, -1)
    cv2.rectangle(canvas, (left, top), (right, bottom), (240, 240, 240), 2)

    text_size, baseline = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.9, 2)
    text_x = left + max(0, (right - left - text_size[0]) // 2)
    text_y = top + max(text_size[1] + 8, (bottom - top + text_size[1]) // 2)
    cv2.putText(
        canvas,
        label,
        (text_x, min(bottom - baseline - 8, text_y)),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.9,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )


def render_canvas(
    frame,
    window_width: int,
    window_height: int,
    status_text: str,
    state: dict[str, object],
):
    canvas = np.full((window_height, window_width, 3), 12, dtype=np.uint8)
    toolbar_height = max(110, min(140, window_height // 5 + 10))
    toolbar_top = window_height - toolbar_height
    padding = 18
    video_width = window_width - (padding * 2)
    video_height = toolbar_top - (padding * 2)

    if frame is not None and video_width > 0 and video_height > 0:
        frame_height, frame_width = frame.shape[:2]
        scale = min(video_width / frame_width, video_height / frame_height)
        scale = max(scale, 0.01)
        target_width = max(1, int(round(frame_width * scale)))
        target_height = max(1, int(round(frame_height * scale)))
        interpolation = cv2.INTER_LINEAR if scale >= 1.0 else cv2.INTER_AREA
        resized = cv2.resize(frame, (target_width, target_height), interpolation=interpolation)
        offset_x = (window_width - target_width) // 2
        offset_y = max(padding, (toolbar_top - target_height) // 2)
        canvas[offset_y:offset_y + target_height, offset_x:offset_x + target_width] = resized
    else:
        placeholder = "Connecting to camera stream..."
        text_size, baseline = cv2.getTextSize(placeholder, cv2.FONT_HERSHEY_SIMPLEX, 0.9, 2)
        text_x = max(16, (window_width - text_size[0]) // 2)
        text_y = max(48, (toolbar_top + text_size[1]) // 2)
        cv2.putText(
            canvas,
            placeholder,
            (text_x, min(toolbar_top - baseline - 20, text_y)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.9,
            (220, 220, 220),
            2,
            cv2.LINE_AA,
        )

    cv2.rectangle(canvas, (0, toolbar_top), (window_width, window_height), (28, 28, 28), -1)
    cv2.line(canvas, (0, toolbar_top), (window_width, toolbar_top), (72, 72, 72), 2)

    button_gap = 18
    button_width = min(230, max(180, (window_width - (padding * 2) - button_gap) // 3))
    button_height = min(76, max(60, toolbar_height - 34))
    button_top = toolbar_top + (toolbar_height - button_height) // 2
    close_rect = (
        window_width - padding - button_width,
        button_top,
        window_width - padding,
        button_top + button_height,
    )
    reset_rect = (
        close_rect[0] - button_gap - button_width,
        button_top,
        close_rect[0] - button_gap,
        button_top + button_height,
    )
    state["reset_rect"] = reset_rect
    state["close_rect"] = close_rect

    status_x = padding
    status_y = toolbar_top + 36
    cv2.putText(
        canvas,
        status_text,
        (status_x, status_y),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (235, 235, 235),
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        canvas,
        f"Viewer {window_width}x{window_height}",
        (status_x, status_y + 34),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (170, 170, 170),
        1,
        cv2.LINE_AA,
    )

    draw_button(canvas, reset_rect, "RESET", (0, 146, 255))
    draw_button(canvas, close_rect, "CLOSE", (58, 58, 220))
    return canvas


def handle_mouse(event, x: int, y: int, _flags, state: dict[str, object]) -> None:
    if event != cv2.EVENT_LBUTTONUP:
        return

    if point_in_rect(x, y, state.get("reset_rect")):
        state["reset_requested"] = True
        return

    if point_in_rect(x, y, state.get("close_rect")):
        state["quit_requested"] = True


def main() -> int:
    args = parse_args()
    socket_path = resolve_socket_path(args.socket_path)
    window_width = max(320, args.window_width)
    window_height = max(240, args.window_height)
    controls: dict[str, object] = {
        "reset_requested": False,
        "quit_requested": False,
        "reset_rect": None,
        "close_rect": None,
        "status_message": "",
        "status_until": 0.0,
    }

    cv2.namedWindow(args.window_title, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(args.window_title, window_width, window_height)
    cv2.setMouseCallback(args.window_title, handle_mouse, controls)
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
            last_frame = None

            while True:
                if controls["reset_requested"]:
                    controls["reset_requested"] = False
                    try:
                        send_command(socket_path, "reset", timeout=1.0)
                        set_status_message(controls, "Detector state reset.")
                    except Exception:
                        set_status_message(controls, "Reset command failed.", duration=2.5)

                if controls["quit_requested"]:
                    break

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
                        last_frame = frame

                canvas = render_canvas(
                    last_frame,
                    window_width,
                    window_height,
                    current_status_message(controls),
                    controls,
                )
                cv2.imshow(args.window_title, canvas)

                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    break
                if key == ord("r"):
                    controls["reset_requested"] = True
    except OSError as exc:
        print(f"Viewer connection failed: {exc}", file=sys.stderr)
        return 1
    finally:
        cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
