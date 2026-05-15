#!/usr/bin/env python3
"""
Head Pose Estimation using solvePnP with MediaPipe landmarks.
"""

import numpy as np
import cv2

from pipeline.feature_extractor import FACE_3D_MODEL, get_face_2d_points


class HeadPoseEstimator:
    """Estimate head pose (pitch, yaw, roll) using OpenCV solvePnP."""

    def __init__(self):
        self._rvec = None
        self._tvec = None

    def estimate(self, landmarks, h, w):
        """
        Estimate head pose from face landmarks.

        Returns:
            dict with 'pitch', 'yaw', 'roll' in degrees,
            or None if estimation fails.
        """
        # Camera matrix (approximate)
        focal_length = w
        center = (w / 2.0, h / 2.0)
        camera_matrix = np.array([
            [focal_length, 0, center[0]],
            [0, focal_length, center[1]],
            [0, 0, 1]
        ], dtype=np.float64)

        dist_coeffs = np.zeros((4, 1), dtype=np.float64)

        # 2D points from landmarks
        image_points = get_face_2d_points(landmarks, h, w)

        # Solve PnP
        flags = cv2.SOLVEPNP_ITERATIVE
        if self._rvec is not None:
            success, rvec, tvec = cv2.solvePnP(
                FACE_3D_MODEL, image_points,
                camera_matrix, dist_coeffs,
                rvec=self._rvec.copy(), tvec=self._tvec.copy(),
                useExtrinsicGuess=True, flags=flags
            )
        else:
            success, rvec, tvec = cv2.solvePnP(
                FACE_3D_MODEL, image_points,
                camera_matrix, dist_coeffs,
                flags=flags
            )

        if not success:
            return None

        self._rvec = rvec
        self._tvec = tvec

        # Convert to rotation matrix and extract Euler angles
        rmat, _ = cv2.Rodrigues(rvec)
        angles, _, _, _, _, _ = cv2.RQDecomp3x3(rmat)

        pitch = angles[0]  # Nod: positive = looking down
        yaw   = angles[1]  # Turn: positive = looking right
        roll  = angles[2]  # Tilt: positive = tilting right

        return {
            "pitch": float(pitch),
            "yaw":   float(yaw),
            "roll":  float(roll),
        }

    def get_drowsiness_score(self, pose):
        """
        Calculate head pose drowsiness score.
        High score = likely drowsy (head dropping forward or tilting).

        Returns: float in [0, 1]
        """
        if pose is None:
            return 0.0

        pitch = pose["pitch"]
        yaw   = abs(pose["yaw"])
        roll  = abs(pose["roll"])

        score = 0.0

        # Forward head nod (pitch > 15° → drowsy, > 25° → very drowsy)
        if pitch > 15:
            score += min(1.0, (pitch - 15) / 20.0) * 0.6
        # Backward tilt (less common but possible)
        if pitch < -20:
            score += min(1.0, (-pitch - 20) / 20.0) * 0.3

        # Head turning away (yaw > 30°)
        if yaw > 30:
            score += min(1.0, (yaw - 30) / 30.0) * 0.2

        # Head tilting (roll > 20°)
        if roll > 20:
            score += min(1.0, (roll - 20) / 20.0) * 0.2

        return min(1.0, score)
