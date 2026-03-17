#!/usr/bin/env python3
"""Live camera app for DrowsinessDetectorV2 (USB webcam ready)."""

from __future__ import annotations

import argparse
import os
import platform
import sys
import time
from pathlib import Path

import cv2


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.live_camera_common import (
    draw_overlay,
    export_jpeg_atomic,
    list_linux_video_nodes,
    looks_like_wsl,
    open_camera,
    stream_jpeg_stdout,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run drowsiness detection from live USB camera."
    )
    parser.add_argument(
        "--camera-index",
        type=int,
        default=0,
        help="Camera index fallback (default: 0).",
    )
    parser.add_argument(
        "--camera-path",
        default="",
        help="Open camera by device path (Linux), e.g. /dev/video0.",
    )
    parser.add_argument(
        "--backend",
        choices=["auto", "v4l2", "default"],
        default="auto",
        help="VideoCapture backend selection.",
    )
    parser.add_argument(
        "--fallback-scan-max",
        type=int,
        default=4,
        help="If selected index fails, scan camera indices from 0..N.",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=1280,
        help="Requested camera width.",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=720,
        help="Requested camera height.",
    )
    parser.add_argument(
        "--fps",
        type=int,
        default=30,
        help="Requested camera FPS.",
    )
    parser.add_argument(
        "--no-mirror",
        action="store_true",
        help="Disable horizontal mirror view.",
    )
    parser.add_argument(
        "--eye-model",
        default="models/eye_cnn/eye_model.tflite",
        help="Path to eye TFLite model.",
    )
    parser.add_argument(
        "--yawn-model",
        default="models/yawn_cnn/yawn_model.tflite",
        help="Path to yawn TFLite model.",
    )
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to config.yaml.",
    )
    parser.add_argument(
        "--save-video",
        default="",
        help="Optional output video path (e.g. results/live_demo.mp4).",
    )
    parser.add_argument(
        "--no-display",
        action="store_true",
        help="Disable cv2.imshow() for headless integration (Qt or service mode).",
    )
    parser.add_argument(
        "--export-frame",
        default="",
        help="Optional JPEG path exported per N frames for Qt preview.",
    )
    parser.add_argument(
        "--export-quality",
        type=int,
        default=70,
        help="JPEG quality (1..100) for --export-frame and --stream-jpeg-stdout.",
    )
    parser.add_argument(
        "--export-every-n",
        type=int,
        default=1,
        help="Export JPEG every N processed frames.",
    )
    parser.add_argument(
        "--metrics-every-n",
        type=int,
        default=10,
        help="Print a compact metric line every N processed frames.",
    )
    parser.add_argument(
        "--stream-jpeg-stdout",
        action="store_true",
        help="Stream JPEG frames via stdout (binary packet protocol) for Qt image provider.",
    )
    return parser.parse_args()

def main() -> int:
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    args = parse_args()
    log_stream = sys.stderr if args.stream_jpeg_stdout else sys.stdout

    def log(message: str):
        print(message, file=log_stream, flush=True)

    try:
        from pipeline.drowsiness_detector import DrowsinessDetectorV2
    except ModuleNotFoundError as exc:
        log(f"Missing dependency: {exc.name}")
        log("Install dependencies first: pip install -r requirements.txt")
        return 1

    detector = DrowsinessDetectorV2(
        eye_model_path=args.eye_model,
        yawn_model_path=args.yawn_model,
        config_path=args.config,
    )

    camera_path = args.camera_path

    if platform.system().lower() == "linux" and not camera_path:
        nodes = list_linux_video_nodes()
        if nodes:
            log("Detected camera nodes: " + ", ".join(str(n) for n in nodes))
            camera_path = str(nodes[0])
            log(f"Using camera path: {camera_path}")
        else:
            log("No /dev/video* device found.")
            if looks_like_wsl():
                log(
                    "WSL2 detected. Attach USB webcam to WSL first (usbipd), then run again."
                )
                log("PowerShell (Admin): usbipd list")
                log("PowerShell (Admin): usbipd bind --busid <BUSID>")
                log("PowerShell (Admin): usbipd attach --wsl --busid <BUSID>")
                log("WSL: sudo modprobe uvcvideo")
                log("WSL: ls /dev/video*")
            else:
                log("Check webcam connection and permissions, then retry.")

    cap, actual_index, backend_name = open_camera(
        camera_index=args.camera_index,
        scan_max=args.fallback_scan_max,
        width=args.width,
        height=args.height,
        fps=args.fps,
        camera_path=camera_path,
        backend_mode=args.backend,
    )
    if cap is None:
        if camera_path:
            log(f"Cannot open camera path: {camera_path}")
            log("Check path exists and your user has read/write access.")
        else:
            log("Cannot open camera.")
            log("Try --camera-index 0, or set --camera-path /dev/video0 (Linux).")
            log("You can also increase scan range: --fallback-scan-max 10")
        return 1

    writer = None
    if args.save_video:
        out_path = Path(args.save_video)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(
            str(out_path),
            fourcc,
            float(args.fps),
            (args.width, args.height),
        )
        if not writer.isOpened():
            log(f"Warning: cannot open output writer: {out_path}")
            writer = None

    export_path = Path(args.export_frame).expanduser() if args.export_frame else None
    if export_path is not None:
        export_path.parent.mkdir(parents=True, exist_ok=True)

    export_every_n = max(1, args.export_every_n)
    metrics_every_n = max(1, args.metrics_every_n)

    if args.no_display:
        log(
            f"Live started on camera index {actual_index} ({backend_name}) in headless mode."
        )
    else:
        log(
            f"Live started on camera index {actual_index} ({backend_name}). "
            "Press 'q' to quit, 'r' to reset."
        )

    fps_smooth = 0.0
    frame_counter = 0

    try:
        while True:
            ok, frame = cap.read()
            if not ok or frame is None:
                log("Camera frame read failed.")
                break

            if not args.no_mirror:
                frame = cv2.flip(frame, 1)

            t0 = time.perf_counter()
            result = detector.process_frame(frame)
            latency_ms = (time.perf_counter() - t0) * 1000.0
            instant_fps = 1000.0 / latency_ms if latency_ms > 0 else 0.0
            fps_smooth = instant_fps if fps_smooth == 0 else (0.9 * fps_smooth + 0.1 * instant_fps)
            frame_counter += 1

            draw_overlay(frame, result, fps_smooth, actual_index, backend_name)

            if writer is not None:
                if (frame.shape[1], frame.shape[0]) != (args.width, args.height):
                    frame_to_write = cv2.resize(frame, (args.width, args.height))
                else:
                    frame_to_write = frame
                writer.write(frame_to_write)

            if args.stream_jpeg_stdout and (frame_counter % export_every_n == 0):
                if not stream_jpeg_stdout(frame, args.export_quality):
                    log("Stream consumer disconnected. Stopping.")
                    break

            if export_path is not None and (frame_counter % export_every_n == 0):
                export_jpeg_atomic(frame, export_path, args.export_quality)

            if frame_counter % metrics_every_n == 0:
                log(
                    "[METRIC] "
                    f"fps={fps_smooth:.2f} "
                    f"latency_ms={latency_ms:.2f} "
                    f"status={result['status']} "
                    f"alert={int(result['alert'])}",
                )

            if not args.no_display:
                cv2.imshow("Drowsiness Detection Live", frame)
                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):
                    break
                if key == ord("r"):
                    detector.reset()
                    log("Detector state reset.")

    finally:
        cap.release()
        if writer is not None:
            writer.release()
        if not args.no_display:
            cv2.destroyAllWindows()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
