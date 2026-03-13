#!/usr/bin/env python3
"""Live camera app for DrowsinessDetectorV2 (USB webcam ready)."""

from __future__ import annotations

import argparse
import os
import platform
import struct
import sys
import time
from pathlib import Path
from typing import Optional, Tuple, Union

import cv2


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))


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


def _try_open(
    source: Union[int, str],
    backend: Optional[int],
    width: int,
    height: int,
    fps: int,
):
    cap = cv2.VideoCapture(source, backend) if backend is not None else cv2.VideoCapture(source)
    if not cap.isOpened():
        cap.release()
        return None

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    cap.set(cv2.CAP_PROP_FPS, fps)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    for _ in range(10):
        ok, frame = cap.read()
        if ok and frame is not None and frame.size > 0:
            return cap
        time.sleep(0.02)

    cap.release()
    return None


def _video_backends(backend_mode: str):
    if backend_mode == "default":
        return [(None, "DEFAULT")]
    if backend_mode == "v4l2":
        if platform.system().lower() != "linux" or not hasattr(cv2, "CAP_V4L2"):
            return [(None, "DEFAULT")]
        return [(cv2.CAP_V4L2, "V4L2")]
    if platform.system().lower() == "linux" and hasattr(cv2, "CAP_V4L2"):
        return [(cv2.CAP_V4L2, "V4L2")]
    return [(None, "DEFAULT")]


def list_linux_video_nodes():
    if platform.system().lower() != "linux":
        return []
    return sorted(Path("/dev").glob("video*"), key=lambda p: p.name)


def looks_like_wsl() -> bool:
    if platform.system().lower() != "linux":
        return False
    release = platform.release().lower()
    return "microsoft" in release or "wsl" in release


def open_camera(
    camera_index: int,
    scan_max: int,
    width: int,
    height: int,
    fps: int,
    camera_path: str,
    backend_mode: str,
):
    backend_candidates = _video_backends(backend_mode)

    if camera_path:
        for backend, backend_name in backend_candidates:
            cap = _try_open(camera_path, backend, width, height, fps)
            if cap is not None:
                return cap, camera_path, backend_name
        return None, camera_path, "N/A"

    attempts = [camera_index]
    attempts.extend(i for i in range(scan_max + 1) if i != camera_index)

    for idx in attempts:
        for backend, backend_name in backend_candidates:
            cap = _try_open(idx, backend, width, height, fps)
            if cap is not None:
                return cap, idx, backend_name

    return None, camera_index, "N/A"


def status_color(status: str) -> Tuple[int, int, int]:
    if status == "drowsy":
        return (0, 0, 255)  # red
    if status == "warning":
        return (0, 165, 255)  # orange
    return (0, 200, 0)  # green


def _draw_bbox(frame, bbox, color, label):
    if not bbox:
        return
    x1, y1, x2, y2 = bbox
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
    text_y = max(20, y1 - 8)
    cv2.putText(
        frame,
        label,
        (x1, text_y),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        color,
        2,
        cv2.LINE_AA,
    )


def draw_detection_boxes(frame, result):
    face_color = (255, 220, 0)   # cyan-like
    eye_color = (80, 255, 80)    # green
    mouth_color = (255, 120, 0)  # orange

    _draw_bbox(frame, result.get("face_bbox"), face_color, "FACE")
    _draw_bbox(frame, result.get("eye_bbox"), eye_color, "EYES")
    _draw_bbox(frame, result.get("mouth_bbox"), mouth_color, "MOUTH")


def draw_overlay(frame, result, fps, cam_idx, backend_name):
    color = status_color(result["status"])
    h, w = frame.shape[:2]

    draw_detection_boxes(frame, result)

    cv2.putText(
        frame,
        f"CAM {cam_idx} ({backend_name})  FPS: {fps:.1f}",
        (16, 30),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        f"STATUS: {result['status'].upper()}",
        (16, 62),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.9,
        color,
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        f"Fusion: {result['fusion_score']:.3f}  EAR: {result['ear']:.3f}  MAR: {result['mar']:.3f}",
        (16, 92),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (220, 220, 220),
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        f"EyeCNN(closed): {result['eye_cnn_score']:.3f}  YawnCNN: {result['yawn_cnn_score']:.3f}",
        (16, 122),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (220, 220, 220),
        2,
        cv2.LINE_AA,
    )

    pose = result.get("head_pose")
    if pose:
        cv2.putText(
            frame,
            (
                f"Head Pose  pitch:{pose['pitch']:.1f}  "
                f"yaw:{pose['yaw']:.1f}  roll:{pose['roll']:.1f}"
            ),
            (16, 152),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (220, 220, 220),
            2,
            cv2.LINE_AA,
        )
    else:
        cv2.putText(
            frame,
            "Head Pose: N/A (face not found)",
            (16, 152),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (140, 140, 140),
            2,
            cv2.LINE_AA,
        )

    cv2.putText(
        frame,
        "q: quit | r: reset detector state",
        (16, h - 16),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (190, 190, 190),
        2,
        cv2.LINE_AA,
    )

    if result["alert"]:
        overlay = frame.copy()
        cv2.rectangle(overlay, (0, 0), (w, 170), (0, 0, 255), -1)
        cv2.addWeighted(overlay, 0.2, frame, 0.8, 0, frame)
        cv2.putText(
            frame,
            "DROWSINESS ALERT! PLEASE REST!",
            (16, 158),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.95,
            (255, 255, 255),
            3,
            cv2.LINE_AA,
        )


def _export_jpeg_atomic(frame, out_path: Path, quality: int) -> bool:
    quality_clamped = max(1, min(100, int(quality)))
    ok, encoded = cv2.imencode(
        ".jpg",
        frame,
        [int(cv2.IMWRITE_JPEG_QUALITY), quality_clamped],
    )
    if not ok:
        return False

    tmp_path = out_path.with_name(out_path.name + ".tmp")
    try:
        tmp_path.write_bytes(encoded.tobytes())
        os.replace(tmp_path, out_path)
        return True
    except OSError:
        return False


def _stream_jpeg_stdout(frame, quality: int) -> bool:
    quality_clamped = max(1, min(100, int(quality)))
    ok, encoded = cv2.imencode(
        ".jpg",
        frame,
        [int(cv2.IMWRITE_JPEG_QUALITY), quality_clamped],
    )
    if not ok:
        return False

    payload = encoded.tobytes()
    header = b"FRAM" + struct.pack("<I", len(payload))

    try:
        sys.stdout.buffer.write(header)
        sys.stdout.buffer.write(payload)
        sys.stdout.buffer.flush()
        return True
    except (BrokenPipeError, OSError):
        return False


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
                if not _stream_jpeg_stdout(frame, args.export_quality):
                    log("Stream consumer disconnected. Stopping.")
                    break

            if export_path is not None and (frame_counter % export_every_n == 0):
                _export_jpeg_atomic(frame, export_path, args.export_quality)

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
