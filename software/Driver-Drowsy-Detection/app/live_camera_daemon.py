#!/usr/bin/env python3
"""Headless drowsiness detector daemon with local IPC and on-demand viewer."""

from __future__ import annotations

import argparse
import json
import os
import platform
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import cv2

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.drowsy_ipc import ensure_socket_parent, resolve_socket_path
from app.live_camera_common import (
    draw_overlay,
    encode_frame_packet,
    encode_jpeg,
    list_linux_video_nodes,
    looks_like_wsl,
    open_camera,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run drowsiness detection as a background daemon."
    )
    parser.add_argument("--camera-index", type=int, default=0)
    parser.add_argument("--camera-path", default="")
    parser.add_argument("--backend", choices=["auto", "v4l2", "default"], default="auto")
    parser.add_argument("--fallback-scan-max", type=int, default=4)
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--no-mirror", action="store_true")
    parser.add_argument("--eye-model", default="models/eye_cnn/eye_model.tflite")
    parser.add_argument("--yawn-model", default="models/yawn_cnn/yawn_model.tflite")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--save-video", default="")
    parser.add_argument("--socket-path", default="")
    parser.add_argument("--jpeg-quality", type=int, default=70)
    parser.add_argument("--stream-every-n", type=int, default=1)
    parser.add_argument("--metrics-every-n", type=int, default=10)
    parser.add_argument(
        "--viewer-script",
        default="app/live_camera_viewer.py",
        help="Relative or absolute path to the viewer script.",
    )
    parser.add_argument(
        "--viewer-title",
        default="Drowsiness Detection Live",
        help="Window title passed to the viewer.",
    )
    parser.add_argument(
        "--viewer-fullscreen",
        action="store_true",
        help="Launch viewer in fullscreen mode.",
    )
    parser.add_argument(
        "--viewer-width",
        type=int,
        default=1024,
        help="Viewer window width in normal windowed mode.",
    )
    parser.add_argument(
        "--viewer-height",
        type=int,
        default=600,
        help="Viewer window height in normal windowed mode.",
    )
    return parser.parse_args()


class DrowsyCameraDaemon:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.socket_path = resolve_socket_path(args.socket_path)
        self.viewer_script = self._resolve_viewer_script(args.viewer_script)
        self.viewer_env: dict[str, str] = {}
        self.viewer_process: subprocess.Popen | None = None
        self.viewer_lock = threading.Lock()
        self.stream_clients: set[socket.socket] = set()
        self.stream_lock = threading.Lock()
        self.status_lock = threading.Lock()
        self.stop_event = threading.Event()
        self.server_socket: socket.socket | None = None
        self.server_thread: threading.Thread | None = None
        self.detector = None
        self.writer = None
        self.frame_counter = 0
        self.actual_index = "N/A"
        self.backend_name = "N/A"
        self.start_time = time.monotonic()
        self.status = {
            "ok": True,
            "running": False,
            "viewer_running": False,
            "fps": 0.0,
            "latency_ms": 0.0,
            "status": "starting",
            "alert": False,
            "camera_source": "N/A",
            "backend": "N/A",
            "frame_counter": 0,
            "uptime_s": 0.0,
        }

    def log(self, message: str) -> None:
        print(message, flush=True)

    def _resolve_viewer_script(self, viewer_script: str) -> Path:
        path = Path(viewer_script)
        if path.is_absolute():
            return path
        return (ROOT_DIR / path).resolve()

    def _status_snapshot(self) -> dict[str, object]:
        with self.status_lock:
            snapshot = dict(self.status)
        snapshot["viewer_running"] = self._viewer_running()
        snapshot["stream_clients"] = self._stream_client_count()
        snapshot["uptime_s"] = round(time.monotonic() - self.start_time, 2)
        return snapshot

    def _update_status(self, **kwargs: object) -> None:
        with self.status_lock:
            self.status.update(kwargs)

    def _stream_client_count(self) -> int:
        with self.stream_lock:
            return len(self.stream_clients)

    def _viewer_running(self) -> bool:
        with self.viewer_lock:
            if self.viewer_process is None:
                return False
            if self.viewer_process.poll() is None:
                return True
            self.viewer_process = None
            return False

    def _viewer_env_from_request(self, request: dict[str, object]) -> dict[str, str]:
        allowed_keys = (
            "DISPLAY",
            "WAYLAND_DISPLAY",
            "XAUTHORITY",
            "XDG_RUNTIME_DIR",
            "DBUS_SESSION_BUS_ADDRESS",
            "XDG_SESSION_TYPE",
            "QT_QPA_PLATFORM",
        )
        viewer_env: dict[str, str] = {}
        for key in allowed_keys:
            value = request.get(key)
            if value is None:
                continue
            text = str(value).strip()
            if text:
                viewer_env[key] = text
        return viewer_env

    def ensure_viewer(
        self,
        viewer_env: dict[str, str] | None = None,
        viewer_title: str | None = None,
        viewer_fullscreen: bool | None = None,
        viewer_width: int | None = None,
        viewer_height: int | None = None,
    ) -> tuple[bool, str]:
        with self.viewer_lock:
            if self.viewer_process is not None and self.viewer_process.poll() is None:
                return True, "viewer-already-running"

            if not self.viewer_script.exists():
                return False, f"viewer script not found: {self.viewer_script}"

            if viewer_env:
                self.viewer_env = dict(viewer_env)

            window_title = viewer_title or self.args.viewer_title
            fullscreen = self.args.viewer_fullscreen if viewer_fullscreen is None else viewer_fullscreen
            window_width = max(320, self.args.viewer_width if viewer_width is None else int(viewer_width))
            window_height = max(240, self.args.viewer_height if viewer_height is None else int(viewer_height))

            cmd = [
                sys.executable,
                str(self.viewer_script),
                "--socket-path",
                self.socket_path,
                "--window-title",
                window_title,
                "--window-width",
                str(window_width),
                "--window-height",
                str(window_height),
            ]
            if fullscreen:
                cmd.append("--fullscreen")

            process_env = os.environ.copy()
            process_env.update(self.viewer_env)

            self.viewer_process = subprocess.Popen(
                cmd,
                cwd=str(ROOT_DIR),
                env=process_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return True, "viewer-started"

    def stop_viewer(self) -> tuple[bool, str]:
        with self.viewer_lock:
            if self.viewer_process is None or self.viewer_process.poll() is not None:
                self.viewer_process = None
                return True, "viewer-not-running"

            self.viewer_process.terminate()
            try:
                self.viewer_process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.viewer_process.kill()
            self.viewer_process = None
            return True, "viewer-stopped"

    def reset_detector(self) -> None:
        if self.detector is not None:
            self.detector.reset()

    def remove_stream_client(self, client: socket.socket) -> None:
        with self.stream_lock:
            if client in self.stream_clients:
                self.stream_clients.remove(client)
        try:
            client.close()
        except OSError:
            pass

    def broadcast_frame(self, frame, quality: int) -> None:
        with self.stream_lock:
            clients = list(self.stream_clients)
        if not clients:
            return

        jpeg_payload = encode_jpeg(frame, quality)
        if jpeg_payload is None:
            return

        packet = encode_frame_packet(jpeg_payload)
        for client in clients:
            try:
                client.sendall(packet)
            except OSError:
                self.remove_stream_client(client)

    def _control_response(self, command: str, request: dict[str, object]) -> dict[str, object]:
        if command == "status":
            return self._status_snapshot()
        if command == "show":
            viewer_title_value = str(request.get("viewer_title", "")).strip()
            viewer_title = viewer_title_value or None
            viewer_fullscreen_value = request.get("viewer_fullscreen")
            viewer_fullscreen = None
            if viewer_fullscreen_value is not None:
                viewer_fullscreen = bool(viewer_fullscreen_value)
            viewer_width = request.get("viewer_width")
            viewer_height = request.get("viewer_height")
            ok, detail = self.ensure_viewer(
                viewer_env=self._viewer_env_from_request(request),
                viewer_title=viewer_title,
                viewer_fullscreen=viewer_fullscreen,
                viewer_width=viewer_width if viewer_width is None else int(viewer_width),
                viewer_height=viewer_height if viewer_height is None else int(viewer_height),
            )
            response = self._status_snapshot()
            response.update({"ok": ok, "detail": detail})
            return response
        if command == "hide":
            ok, detail = self.stop_viewer()
            response = self._status_snapshot()
            response.update({"ok": ok, "detail": detail})
            return response
        if command == "reset":
            self.reset_detector()
            response = self._status_snapshot()
            response.update({"ok": True, "detail": "detector-reset"})
            return response
        if command == "stop":
            self.stop_event.set()
            response = self._status_snapshot()
            response.update({"ok": True, "detail": "daemon-stopping"})
            return response
        return {"ok": False, "error": f"unknown command: {command}"}

    def _handle_client(self, conn: socket.socket) -> None:
        try:
            conn.settimeout(3.0)
            raw = bytearray()
            while b"\n" not in raw:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                raw.extend(chunk)
            if not raw:
                return

            request = json.loads(raw.split(b"\n", 1)[0].decode("utf-8"))
            command = str(request.get("cmd", "")).strip().lower()
            if command == "stream":
                conn.settimeout(1.0)
                with self.stream_lock:
                    self.stream_clients.add(conn)
                while not self.stop_event.is_set():
                    try:
                        chunk = conn.recv(1)
                        if not chunk:
                            break
                    except socket.timeout:
                        continue
                    except OSError:
                        break
                self.remove_stream_client(conn)
                return

            response = self._control_response(command, request)
            conn.sendall((json.dumps(response, separators=(",", ":")) + "\n").encode("utf-8"))
        except Exception as exc:  # pragma: no cover - defensive path
            try:
                error_payload = {"ok": False, "error": str(exc)}
                conn.sendall((json.dumps(error_payload, separators=(",", ":")) + "\n").encode("utf-8"))
            except OSError:
                pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _server_loop(self) -> None:
        assert self.server_socket is not None
        self.server_socket.settimeout(1.0)
        while not self.stop_event.is_set():
            try:
                conn, _ = self.server_socket.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._handle_client, args=(conn,), daemon=True).start()

    def start_server(self) -> None:
        ensure_socket_parent(self.socket_path)
        socket_file = Path(self.socket_path)
        if socket_file.exists():
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
                    probe.settimeout(0.5)
                    probe.connect(self.socket_path)
                raise SystemExit(f"Daemon already running on socket: {self.socket_path}")
            except OSError:
                socket_file.unlink(missing_ok=True)

        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(self.socket_path)
        self.server_socket.listen(8)
        self.server_thread = threading.Thread(target=self._server_loop, daemon=True)
        self.server_thread.start()
        self.log(f"Daemon control socket: {self.socket_path}")

    def shutdown(self) -> None:
        self.stop_event.set()
        self.stop_viewer()
        with self.stream_lock:
            clients = list(self.stream_clients)
            self.stream_clients.clear()
        for client in clients:
            try:
                client.close()
            except OSError:
                pass

        if self.writer is not None:
            self.writer.release()
            self.writer = None

        if self.server_socket is not None:
            try:
                self.server_socket.close()
            except OSError:
                pass
            self.server_socket = None

        try:
            Path(self.socket_path).unlink(missing_ok=True)
        except OSError:
            pass

    def run(self) -> int:
        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
        self.start_server()

        try:
            from pipeline.drowsiness_detector import DrowsinessDetectorV2
        except ModuleNotFoundError as exc:
            self.log(f"Missing dependency: {exc.name}")
            self.log("Install dependencies first: pip install -r requirements.txt")
            return 1

        self.detector = DrowsinessDetectorV2(
            eye_model_path=self.args.eye_model,
            yawn_model_path=self.args.yawn_model,
            config_path=self.args.config,
        )

        camera_path = self.args.camera_path
        
        # Bypass V4L2 string capture bug by converting /dev/videoX to integer index X
        if camera_path.startswith("/dev/video") and camera_path[10:].isdigit():
            extracted_idx = int(camera_path[10:])
            self.log(f"Translating {camera_path} to index {extracted_idx} for V4L2 compatibility.")
            self.args.camera_index = extracted_idx
            camera_path = ""
        # if platform.system().lower() == "linux" and not camera_path:
        #     nodes = list_linux_video_nodes()
        #     if nodes:
        #         self.log("Detected camera nodes: " + ", ".join(str(n) for n in nodes))
        #         # camera_path = str(nodes[0])
        #     else:
        #         self.log("No /dev/video* device found.")
        #         if looks_like_wsl():
        #             self.log("WSL2 detected. Attach USB webcam to WSL first (usbipd), then run again.")
        #         else:
        #             self.log("Check webcam connection and permissions, then retry.")

        cap, actual_index, backend_name = open_camera(
            camera_index=self.args.camera_index,
            scan_max=self.args.fallback_scan_max,
            width=self.args.width,
            height=self.args.height,
            fps=self.args.fps,
            camera_path=camera_path,
            backend_mode=self.args.backend,
        )
        if cap is None:
            if camera_path:
                self.log(f"Cannot open camera path: {camera_path}")
            else:
                self.log("Cannot open camera.")
            return 1

        self.actual_index = actual_index
        self.backend_name = backend_name
        self._update_status(
            running=True,
            status="awake",
            alert=False,
            camera_source=str(actual_index),
            backend=backend_name,
        )
        self.log(f"Daemon started on camera {actual_index} ({backend_name})")

        if self.args.save_video:
            out_path = Path(self.args.save_video)
            out_path.parent.mkdir(parents=True, exist_ok=True)
            fourcc = cv2.VideoWriter_fourcc(*"mp4v")
            self.writer = cv2.VideoWriter(
                str(out_path),
                fourcc,
                float(self.args.fps),
                (self.args.width, self.args.height),
            )
            if not self.writer.isOpened():
                self.log(f"Warning: cannot open output writer: {out_path}")
                self.writer = None

        export_every_n = max(1, self.args.stream_every_n)
        metrics_every_n = max(1, self.args.metrics_every_n)
        fps_smooth = 0.0

        try:
            while not self.stop_event.is_set():
                ok, frame = cap.read()
                if not ok or frame is None:
                    self.log("Camera frame read failed.")
                    break

                if not self.args.no_mirror:
                    frame = cv2.flip(frame, 1)

                t0 = time.perf_counter()
                result = self.detector.process_frame(frame)
                latency_ms = (time.perf_counter() - t0) * 1000.0
                instant_fps = 1000.0 / latency_ms if latency_ms > 0 else 0.0
                fps_smooth = instant_fps if fps_smooth == 0 else (0.9 * fps_smooth + 0.1 * instant_fps)
                self.frame_counter += 1

                draw_overlay(
                    frame,
                    result,
                    fps_smooth,
                    actual_index,
                    backend_name,
                    footer_text="Touch RESET or CLOSE in the control bar below",
                )

                if self.writer is not None:
                    if (frame.shape[1], frame.shape[0]) != (self.args.width, self.args.height):
                        frame_to_write = cv2.resize(frame, (self.args.width, self.args.height))
                    else:
                        frame_to_write = frame
                    self.writer.write(frame_to_write)

                if self.frame_counter % export_every_n == 0:
                    self.broadcast_frame(frame, self.args.jpeg_quality)

                if self.frame_counter % metrics_every_n == 0:
                    self.log(
                        "[METRIC] "
                        f"fps={fps_smooth:.2f} "
                        f"latency_ms={latency_ms:.2f} "
                        f"status={result['status']} "
                        f"alert={int(result['alert'])}"
                    )

                self._update_status(
                    running=True,
                    viewer_running=self._viewer_running(),
                    fps=round(fps_smooth, 2),
                    latency_ms=round(latency_ms, 2),
                    status=result["status"],
                    alert=bool(result["alert"]),
                    camera_source=str(actual_index),
                    backend=backend_name,
                    frame_counter=self.frame_counter,
                )
        finally:
            cap.release()
            self._update_status(running=False, viewer_running=self._viewer_running())
            self.shutdown()

        return 0


def main() -> int:
    args = parse_args()
    daemon = DrowsyCameraDaemon(args)

    def _request_stop(signum, _frame):
        daemon.log(f"Received signal {signum}, shutting down daemon.")
        daemon.stop_event.set()

    signal.signal(signal.SIGINT, _request_stop)
    signal.signal(signal.SIGTERM, _request_stop)

    return daemon.run()


if __name__ == "__main__":
    raise SystemExit(main())
