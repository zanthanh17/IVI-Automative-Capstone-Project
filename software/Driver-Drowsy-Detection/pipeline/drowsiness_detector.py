#!/usr/bin/env python3
"""
DrowsinessDetectorV2 — Multi-Feature Fusion Pipeline.

Combines:
  1. Eye CNN (MobileNetV2 TFLite) → eye closed probability
  2. EAR rule-based PERCLOS (90-frame window)
  3. Yawn CNN (MobileNetV2 TFLite) → yawn probability
  4. Head Pose (solvePnP) → nod/tilt score

Fusion:
  score = w_eye*eye_cnn + w_ear*ear_perclos + w_yawn*yawn_counter + w_head*head_pose

Temporal Smoother:
  sliding_window = 30 frames, alert if drowsy_counter >= 20
"""

import os, yaml, time, collections
import numpy as np
import cv2
import mediapipe as mp

from pipeline.feature_extractor import (
    calc_ear, calc_mar, crop_region,
    LEFT_EYE_IDX, RIGHT_EYE_IDX, MOUTH_IDX
)
from pipeline.head_pose import HeadPoseEstimator


class DrowsinessDetectorV2:
    """Full fusion drowsiness detection pipeline."""

    def __init__(self, eye_model_path, yawn_model_path, config_path="config.yaml"):
        with open(config_path) as f:
            self.cfg = yaml.safe_load(f)

        # Thresholds
        thr = self.cfg["thresholds"]
        self.ear_thr       = thr["ear"]
        self.mar_thr       = thr["mar"]
        self.fusion_alert  = thr["fusion_alert"]

        # Fusion weights
        fw = self.cfg["fusion_weights"]
        self.w_eye   = fw.get("eye_cnn", 0.15)
        self.w_ear   = fw.get("ear_perclos", 0.45)
        self.w_yawn  = fw.get("yawn_counter", fw.get("yawn_combined", 0.15))
        self.w_head  = fw.get("head_pose", 0.25)

        # Normalize weights to sum to 1.0
        w_sum = self.w_eye + self.w_ear + self.w_yawn + self.w_head
        if w_sum > 0:
            self.w_eye  /= w_sum
            self.w_ear  /= w_sum
            self.w_yawn /= w_sum
            self.w_head /= w_sum

        # Region size
        self.img_size = self.cfg["data"]["img_size_region"]
        self.eye_all_idx = sorted(set(LEFT_EYE_IDX + RIGHT_EYE_IDX))

        # Load TFLite models
        self.eye_interp  = self._load_tflite(eye_model_path)
        self.yawn_interp = self._load_tflite(yawn_model_path)

        # MediaPipe FaceMesh
        self.mp_mesh = mp.solutions.face_mesh
        self.face_mesh = self.mp_mesh.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.6,
            min_tracking_confidence=0.5
        )

        # Head Pose
        self.head_pose = HeadPoseEstimator()

        # ── Temporal state ──
        # PERCLOS: % of frames eyes closed in 90-frame window
        self.perclos_window = 90
        self.eye_closed_history = collections.deque(maxlen=self.perclos_window)

        # Yawn decay counter (rises fast, decays slow)
        self.yawn_counter = 0.0
        self.yawn_rise_rate  = 0.3
        self.yawn_decay_rate = 0.05

        # Temporal smoother
        self.smoother_window = 30
        self.fusion_history = collections.deque(maxlen=self.smoother_window)
        self.drowsy_counter = 0

    def _landmark_bbox(self, landmarks, indices, h, w, padding=0.0):
        """
        Build (x1, y1, x2, y2) bbox in pixel coords from landmark indices.
        Returns None if bbox is invalid.
        """
        xs = [landmarks[i].x * w for i in indices]
        ys = [landmarks[i].y * h for i in indices]

        xmin, xmax = min(xs), max(xs)
        ymin, ymax = min(ys), max(ys)

        pad_w = (xmax - xmin) * padding
        pad_h = (ymax - ymin) * padding

        x1 = max(0, int(xmin - pad_w))
        y1 = max(0, int(ymin - pad_h))
        x2 = min(w - 1, int(xmax + pad_w))
        y2 = min(h - 1, int(ymax + pad_h))

        if x2 <= x1 or y2 <= y1:
            return None
        return (x1, y1, x2, y2)

    def _load_tflite(self, model_path):
        """Load TFLite interpreter."""
        if not os.path.exists(model_path):
            print(f"⚠ TFLite model not found: {model_path}")
            return None

        try:
            import tflite_runtime.interpreter as tflite
            try:
                interp = tflite.Interpreter(model_path=model_path)
            except Exception as exc:
                msg = str(exc)
                if "_ARRAY_API" in msg or "multiarray failed to import" in msg:
                    raise RuntimeError(
                        "tflite-runtime is incompatible with current NumPy. "
                        "Use NumPy 1.x (e.g. 1.26.4) and reinstall tflite-runtime."
                    ) from exc
                raise
        except ImportError:
            import tensorflow as tf
            interp = tf.lite.Interpreter(model_path=model_path)

        interp.allocate_tensors()
        return interp

    def _infer_tflite(self, interp, img_crop):
        """Run TFLite inference on a cropped region (expects BGR input from OpenCV)."""
        if interp is None:
            return 0.5

        inp_details = interp.get_input_details()
        out_details = interp.get_output_details()

        # Resize to expected input size
        inp_shape = inp_details[0]['shape']
        h, w = inp_shape[1], inp_shape[2]
        img = cv2.resize(img_crop, (w, h))

        # Convert BGR → RGB (model was trained on RGB images)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        # Handle quantized vs float input
        dtype = inp_details[0]['dtype']
        if dtype == np.uint8:
            img = img.astype(np.uint8)
        else:
            img = (img.astype(np.float32) / 127.5) - 1.0

        img = np.expand_dims(img, 0)
        interp.set_tensor(inp_details[0]['index'], img)
        interp.invoke()

        output = interp.get_tensor(out_details[0]['index'])

        # Dequantize if needed
        if out_details[0]['dtype'] == np.uint8:
            scale = out_details[0]['quantization_parameters']['scales'][0]
            zp    = out_details[0]['quantization_parameters']['zero_points'][0]
            output = (output.astype(np.float32) - zp) * scale

        return float(output.flatten()[0])

    def process_frame(self, frame):
        """
        Process a single video frame.

        Returns dict:
            - status: "awake" | "warning" | "drowsy"
            - alert: bool
            - fusion_score: float [0,1]
            - ear: float
            - mar: float
            - head_pose: dict or None
            - eye_cnn_score: float
            - yawn_cnn_score: float
            - face_bbox: (x1, y1, x2, y2) | None
            - eye_bbox: (x1, y1, x2, y2) | None
            - mouth_bbox: (x1, y1, x2, y2) | None
        """
        h, w = frame.shape[:2]
        result = {
            "status": "awake",
            "alert": False,
            "fusion_score": 0.0,
            "ear": 0.0,
            "mar": 0.0,
            "head_pose": None,
            "eye_cnn_score": 0.0,
            "yawn_cnn_score": 0.0,
            "face_bbox": None,
            "eye_bbox": None,
            "mouth_bbox": None,
        }

        # Run FaceMesh
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mesh_result = self.face_mesh.process(rgb)
        if not mesh_result.multi_face_landmarks:
            return result

        lms = mesh_result.multi_face_landmarks[0].landmark
        result["face_bbox"] = self._landmark_bbox(
            lms, range(len(lms)), h, w, padding=0.08
        )
        result["eye_bbox"] = self._landmark_bbox(
            lms, self.eye_all_idx, h, w, padding=0.5
        )
        result["mouth_bbox"] = self._landmark_bbox(
            lms, MOUTH_IDX, h, w, padding=0.4
        )

        # ── 1. EAR ──
        ear = calc_ear(lms, h, w)
        result["ear"] = ear
        eye_closed = ear < self.ear_thr
        self.eye_closed_history.append(1 if eye_closed else 0)

        # PERCLOS: fraction of eye-closed frames in window
        if len(self.eye_closed_history) > 0:
            perclos = sum(self.eye_closed_history) / len(self.eye_closed_history)
        else:
            perclos = 0.0

        # ── 2. Eye CNN ──
        # Output: 0=closed, 1=open. Invert for drowsiness score.
        eye_crop = crop_region(frame, lms, self.eye_all_idx, self.img_size, padding=0.5)
        eye_cnn_raw = 0.5
        if eye_crop is not None:
            eye_cnn_raw = self._infer_tflite(self.eye_interp, eye_crop)
        eye_cnn_score = 1.0 - eye_cnn_raw   # Invert: high = eyes closed = drowsy
        result["eye_cnn_score"] = eye_cnn_score

        # ── 3. MAR + Yawn CNN ──
        mar = calc_mar(lms, h, w)
        result["mar"] = mar

        mouth_crop = crop_region(frame, lms, MOUTH_IDX, self.img_size, padding=0.4)
        yawn_cnn_score = 0.0
        if mouth_crop is not None:
            yawn_cnn_score = self._infer_tflite(self.yawn_interp, mouth_crop)
        result["yawn_cnn_score"] = yawn_cnn_score

        # Yawn decay counter
        if yawn_cnn_score > 0.5 or mar > self.mar_thr:
            self.yawn_counter = min(1.0, self.yawn_counter + self.yawn_rise_rate)
        else:
            self.yawn_counter = max(0.0, self.yawn_counter - self.yawn_decay_rate)

        # ── 4. Head Pose ──
        pose = self.head_pose.estimate(lms, h, w)
        result["head_pose"] = pose
        head_score = self.head_pose.get_drowsiness_score(pose)

        # ── Weighted Fusion ──
        fusion_score = (
            self.w_eye  * eye_cnn_score +
            self.w_ear  * perclos +
            self.w_yawn * self.yawn_counter +
            self.w_head * head_score
        )
        result["fusion_score"] = fusion_score

        # ── Temporal Smoother ──
        self.fusion_history.append(fusion_score)

        if fusion_score > self.fusion_alert:
            self.drowsy_counter = min(self.smoother_window, self.drowsy_counter + 1)
        else:
            self.drowsy_counter = max(0, self.drowsy_counter - 1)

        # Status determination
        if self.drowsy_counter >= 20:
            result["status"] = "drowsy"
            result["alert"] = True
        elif fusion_score > 0.35:
            result["status"] = "warning"
        else:
            result["status"] = "awake"

        return result

    def reset(self):
        """Reset temporal state (e.g., between videos)."""
        self.eye_closed_history.clear()
        self.yawn_counter = 0.0
        self.fusion_history.clear()
        self.drowsy_counter = 0
