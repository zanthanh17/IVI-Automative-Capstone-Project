#!/usr/bin/env python3
"""Script 12: Validate full fusion pipeline on test videos."""

import os, sys, time, json
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import cv2, yaml, numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pipeline.drowsiness_detector import DrowsinessDetectorV2

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

def validate_video(detector, video_path, expected_label):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"   ⚠ Cannot open {video_path}")
        return None

    frame_count = 0
    alert_frames = 0
    latencies = []
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    skip = max(1, total // 300)

    while True:
        ret, frame = cap.read()
        if not ret: break
        frame_count += 1
        if frame_count % skip != 0: continue

        t0 = time.perf_counter()
        result = detector.process_frame(frame)
        lat = (time.perf_counter() - t0) * 1000
        latencies.append(lat)

        if result.get("alert", False):
            alert_frames += 1

    cap.release()
    processed = len(latencies)
    if processed == 0:
        return None

    alert_ratio = alert_frames / processed
    avg_lat = np.mean(latencies)
    p95_lat = np.percentile(latencies, 95)
    fps = 1000.0 / avg_lat if avg_lat > 0 else 0

    if expected_label == "drowsy":
        correct = alert_ratio >= 0.5
    else:
        correct = alert_ratio < 0.5

    print(f"   {os.path.basename(video_path)}: alert_ratio={alert_ratio:.2f}, "
          f"avg_lat={avg_lat:.1f}ms, p95={p95_lat:.1f}ms, fps={fps:.1f}, "
          f"{'✅' if correct else '❌'}")

    return {
        "video": os.path.basename(video_path),
        "expected": expected_label,
        "alert_ratio": alert_ratio,
        "correct": correct,
        "avg_latency_ms": avg_lat,
        "p95_latency_ms": p95_lat,
        "fps": fps,
        "processed_frames": processed
    }

if __name__ == "__main__":
    print("=== Full Pipeline Validation ===")

    detector = DrowsinessDetectorV2(
        eye_model_path  ="models/eye_cnn/eye_model.tflite",
        yawn_model_path ="models/yawn_cnn/yawn_model.tflite",
        config_path     ="config.yaml"
    )

    test_videos = [
        ("data/raw/drowsy_data/Bao_awake.mp4",  "awake"),
        ("data/raw/drowsy_data/Bao_drowsy.mp4", "drowsy"),
        ("data/raw/drowsy_data/Thanh_awake.mp4", "awake"),
        ("data/raw/drowsy_data/Thanh_drowsy.mp4","drowsy"),
    ]

    results = []
    for vpath, label in test_videos:
        if os.path.exists(vpath):
            detector.reset()
            r = validate_video(detector, vpath, label)
            if r: results.append(r)

    if results:
        correct = sum(1 for r in results if r["correct"])
        total   = len(results)
        avg_fps = np.mean([r["fps"] for r in results])
        avg_lat = np.mean([r["avg_latency_ms"] for r in results])

        print(f"\n=== Summary ===")
        print(f"Accuracy: {correct}/{total} = {correct/total*100:.0f}%")
        print(f"Avg FPS: {avg_fps:.1f}")
        print(f"Avg Latency: {avg_lat:.1f}ms")

        target_lat = cfg["targets"]["latency_ms"]
        target_fps = cfg["targets"].get("min_fps", cfg["targets"].get("fps_rpi4", 12))
        print(f"Latency target ≤{target_lat}ms: {'✅' if avg_lat <= target_lat else '❌'}")
        print(f"FPS target ≥{target_fps}: {'✅' if avg_fps >= target_fps else '❌'}")

        os.makedirs("results", exist_ok=True)
        with open("results/pipeline_validation.json","w") as f:
            json.dump(results, f, indent=2)
        print("✅ Results saved to results/pipeline_validation.json")
    else:
        print("❌ No results")
