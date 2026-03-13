#!/usr/bin/env python3
"""
Feature Extractor: EAR, MAR, Head Pose from MediaPipe FaceMesh landmarks.
"""

import numpy as np

# ── MediaPipe FaceMesh Landmark Indices ──
LEFT_EYE_IDX  = [362, 385, 387, 263, 373, 380]
RIGHT_EYE_IDX = [33, 160, 158, 133, 153, 144]

UPPER_LIP_IDX  = [13, 312, 311, 310, 82, 81, 80]
LOWER_LIP_IDX  = [14, 317, 316, 315, 87, 86, 85]
MOUTH_IDX      = [61, 291, 13, 14, 78, 308, 82, 312, 87, 317, 80, 310, 85, 315]

# 3D canonical face model points for solvePnP
FACE_3D_MODEL = np.array([
    (0.0,    0.0,    0.0),      # Nose tip (1)
    (0.0,   -330.0, -65.0),     # Chin (152)
    (-225.0, 170.0, -135.0),    # Left eye left corner (263)
    (225.0,  170.0, -135.0),    # Right eye right corner (33)
    (-150.0,-150.0, -125.0),    # Left mouth corner (61)
    (150.0, -150.0, -125.0),    # Right mouth corner (291)
], dtype=np.float64)

FACE_2D_IDX = [1, 152, 263, 33, 61, 291]


def _dist(p1, p2):
    return np.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)


def calc_ear(landmarks, h, w):
    """
    Calculate Eye Aspect Ratio (EAR) from MediaPipe FaceMesh landmarks.
    Average of left and right eye EAR.
    """
    def _eye_ear(idx):
        pts = [(landmarks[i].x * w, landmarks[i].y * h) for i in idx]
        # p1-p5: top-left corner CW
        v1 = _dist(pts[1], pts[5])
        v2 = _dist(pts[2], pts[4])
        hor = _dist(pts[0], pts[3])
        return (v1 + v2) / (2.0 * hor + 1e-6)

    left_ear  = _eye_ear(LEFT_EYE_IDX)
    right_ear = _eye_ear(RIGHT_EYE_IDX)
    return (left_ear + right_ear) / 2.0


def calc_mar(landmarks, h, w):
    """
    Calculate Mouth Aspect Ratio (MAR) from MediaPipe FaceMesh landmarks.
    """
    pts = [(landmarks[i].x * w, landmarks[i].y * h) for i in [13, 14, 78, 308]]
    # 13 = upper lip center, 14 = lower lip center
    # 78 = left corner, 308 = right corner
    vertical   = _dist(pts[0], pts[1])
    horizontal = _dist(pts[2], pts[3])
    return vertical / (horizontal + 1e-6)


def crop_region(img, landmarks, indices, size, padding=0.3):
    """
    Crop a region from the image defined by landmark indices, with padding.
    """
    import cv2
    h, w = img.shape[:2]
    xs = [landmarks[i].x * w for i in indices]
    ys = [landmarks[i].y * h for i in indices]

    xmin, xmax = min(xs), max(xs)
    ymin, ymax = min(ys), max(ys)

    pw = (xmax - xmin) * padding
    ph = (ymax - ymin) * padding

    x1 = max(0, int(xmin - pw))
    y1 = max(0, int(ymin - ph))
    x2 = min(w, int(xmax + pw))
    y2 = min(h, int(ymax + ph))

    region = img[y1:y2, x1:x2]
    if region.size == 0:
        return None
    return cv2.resize(region, (size, size))


def get_face_2d_points(landmarks, h, w):
    """
    Get 2D face points for solvePnP head pose estimation.
    """
    points = []
    for idx in FACE_2D_IDX:
        lm = landmarks[idx]
        points.append((lm.x * w, lm.y * h))
    return np.array(points, dtype=np.float64)
