"""Shared helpers for drowsiness live camera apps."""

from __future__ import annotations

import csv
import os
import platform
import struct
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple, Union

import cv2


FRAME_MAGIC = b"FRAM"
FRAME_HEADER_SIZE = 8


def resolve_project_path(path_value: str | Path, root_dir: Path) -> Path:
    path = Path(path_value).expanduser()
    if path.is_absolute():
        return path
    return root_dir / path


METRIC_CSV_FIELDS = [
    "timestamp_iso",
    "elapsed_s",
    "frame",
    "camera_source",
    "backend",
    "fps",
    "latency_ms",
    "status",
    "alert",
    "fusion_score",
    "ear",
    "perclos",
    "mar",
    "eye_cnn_score",
    "yawn_cnn_score",
    "yawn_counter",
    "head_pose_score",
    "head_pitch",
    "head_yaw",
    "head_roll",
    "face_detected",
    "cpu_process_percent",
    "rss_mb",
    "temperature_c",
]


def _round_metric(value, digits: int = 4):
    if value is None or value == "":
        return ""
    try:
        return round(float(value), digits)
    except (TypeError, ValueError):
        return value


def _read_rss_mb():
    try:
        with open("/proc/self/status", "r", encoding="utf-8") as proc_status:
            for line in proc_status:
                if line.startswith("VmRSS:"):
                    parts = line.split()
                    if len(parts) >= 2:
                        return round(float(parts[1]) / 1024.0, 2)
    except OSError:
        pass
    return ""


def _read_temperature_c():
    for temp_path in ("/sys/class/thermal/thermal_zone0/temp",):
        try:
            raw_value = Path(temp_path).read_text(encoding="utf-8").strip()
            value = float(raw_value)
        except (OSError, ValueError):
            continue

        if value > 1000.0:
            value /= 1000.0
        return round(value, 2)
    return ""


class RuntimeMetricsSampler:
    def __init__(self):
        self.last_wall_s = None
        self.last_process_s = None

    def sample(self, now_s: float):
        process_s = sum(os.times()[:2])
        cpu_percent = ""
        if self.last_wall_s is not None and self.last_process_s is not None:
            wall_delta = now_s - self.last_wall_s
            process_delta = process_s - self.last_process_s
            if wall_delta > 0:
                cpu_percent = round((process_delta / wall_delta) * 100.0, 2)

        self.last_wall_s = now_s
        self.last_process_s = process_s

        return {
            "cpu_process_percent": cpu_percent,
            "rss_mb": _read_rss_mb(),
            "temperature_c": _read_temperature_c(),
        }


class MetricsCsvLogger:
    def __init__(self, csv_path: str, start_time_s: float | None = None):
        self.path = Path(csv_path).expanduser()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.file = self.path.open("w", encoding="utf-8", newline="")
        self.writer = csv.DictWriter(self.file, fieldnames=METRIC_CSV_FIELDS)
        self.writer.writeheader()
        self.file.flush()
        self.start_time_s = time.monotonic() if start_time_s is None else start_time_s
        self.sampler = RuntimeMetricsSampler()

    def write(self, result, fps, latency_ms, frame_counter, camera_source, backend_name):
        now_s = time.monotonic()
        pose = result.get("head_pose") or {}
        if not isinstance(pose, dict):
            pose = {}

        row = {
            "timestamp_iso": datetime.now().isoformat(timespec="milliseconds"),
            "elapsed_s": round(now_s - self.start_time_s, 3),
            "frame": frame_counter,
            "camera_source": str(camera_source),
            "backend": str(backend_name),
            "fps": _round_metric(fps, 2),
            "latency_ms": _round_metric(latency_ms, 2),
            "status": result.get("status", ""),
            "alert": int(bool(result.get("alert", False))),
            "fusion_score": _round_metric(result.get("fusion_score")),
            "ear": _round_metric(result.get("ear")),
            "perclos": _round_metric(result.get("perclos")),
            "mar": _round_metric(result.get("mar")),
            "eye_cnn_score": _round_metric(result.get("eye_cnn_score")),
            "yawn_cnn_score": _round_metric(result.get("yawn_cnn_score")),
            "yawn_counter": _round_metric(result.get("yawn_counter")),
            "head_pose_score": _round_metric(result.get("head_pose_score")),
            "head_pitch": _round_metric(pose.get("pitch"), 2),
            "head_yaw": _round_metric(pose.get("yaw"), 2),
            "head_roll": _round_metric(pose.get("roll"), 2),
            "face_detected": int(result.get("face_bbox") is not None),
        }
        row.update(self.sampler.sample(now_s))
        self.writer.writerow(row)
        self.file.flush()

    def close(self):
        self.file.close()


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
    primary_backends = _video_backends(backend_mode)
    # Always include DEFAULT as a fallback so FFMPEG/GStreamer can try when V4L2 fails
    fallback_backends = [] if backend_mode == "default" else [(None, "DEFAULT")]

    if camera_path:
        for backend, backend_name in primary_backends + fallback_backends:
            cap = _try_open(camera_path, backend, width, height, fps)
            if cap is not None:
                return cap, camera_path, backend_name
        return None, camera_path, "N/A"

    attempts = [camera_index]
    attempts.extend(i for i in range(scan_max + 1) if i != camera_index)

    for idx in attempts:
        for backend, backend_name in primary_backends + fallback_backends:
            cap = _try_open(idx, backend, width, height, fps)
            if cap is not None:
                return cap, idx, backend_name

    # Last resort on Linux: scan /dev/video* by string path (handles ISP node layouts on Pi)
    if platform.system().lower() == "linux":
        tried_indices = set(attempts)
        for node in list_linux_video_nodes():
            node_str = str(node)
            node_suffix = node.name[len("video"):]
            node_idx = int(node_suffix) if node_suffix.isdigit() else -1
            if node_idx in tried_indices:
                continue
            for backend, backend_name in fallback_backends or primary_backends:
                cap = _try_open(node_str, backend, width, height, fps)
                if cap is not None:
                    return cap, node_str, backend_name

    return None, camera_index, "N/A"


def status_color(status: str) -> Tuple[int, int, int]:
    if status == "drowsy":
        return (0, 0, 255)
    if status == "warning":
        return (0, 165, 255)
    return (0, 200, 0)


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
    face_color = (255, 220, 0)
    eye_color = (80, 255, 80)
    mouth_color = (255, 120, 0)

    _draw_bbox(frame, result.get("face_bbox"), face_color, "FACE")
    _draw_bbox(frame, result.get("eye_bbox"), eye_color, "EYES")
    _draw_bbox(frame, result.get("mouth_bbox"), mouth_color, "MOUTH")


def draw_overlay(
    frame,
    result,
    fps,
    cam_idx,
    backend_name,
    footer_text: str = "q: quit | r: reset detector state",
):
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
        footer_text,
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


def encode_jpeg(frame, quality: int) -> bytes | None:
    quality_clamped = max(1, min(100, int(quality)))
    ok, encoded = cv2.imencode(
        ".jpg",
        frame,
        [int(cv2.IMWRITE_JPEG_QUALITY), quality_clamped],
    )
    if not ok:
        return None
    return encoded.tobytes()


def encode_frame_packet(jpeg_payload: bytes) -> bytes:
    return FRAME_MAGIC + struct.pack("<I", len(jpeg_payload)) + jpeg_payload


def export_jpeg_atomic(frame, out_path: Path, quality: int) -> bool:
    jpeg_payload = encode_jpeg(frame, quality)
    if jpeg_payload is None:
        return False

    tmp_path = out_path.with_name(out_path.name + ".tmp")
    try:
        tmp_path.write_bytes(jpeg_payload)
        os.replace(tmp_path, out_path)
        return True
    except OSError:
        return False


def stream_jpeg_stdout(frame, quality: int) -> bool:
    jpeg_payload = encode_jpeg(frame, quality)
    if jpeg_payload is None:
        return False

    packet = encode_frame_packet(jpeg_payload)
    try:
        sys.stdout.buffer.write(packet)
        sys.stdout.buffer.flush()
        return True
    except (BrokenPipeError, OSError):
        return False
