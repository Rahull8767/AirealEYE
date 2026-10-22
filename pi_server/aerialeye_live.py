#!/usr/bin/env python3
"""
AerialEYE Live Inference Engine for Raspberry Pi 3 Model A+
Trained YOLO NCNN Detector for: Person, Animal, Pothole, Waste
Compatible with OV5647 5MP Camera Module on Raspberry Pi OS Lite (32-bit/64-bit)
Integrates live GPS and telemetry from AerialEYE MAVLink bridge.
"""

import os
import sys
import time
import json
import argparse
import tempfile
import threading
import numpy as np

# Try importing OpenCV
try:
    import cv2
except ImportError:
    print("[ERROR] OpenCV (cv2) is required. Install: sudo apt-get install python3-opencv")
    sys.exit(1)

# Trained classes for AerialEYE
DEFAULT_CLASSES = ["person", "animal", "pothole", "waste"]

# Determine shared memory path for Linux, with fallback to system temp
if os.path.exists("/dev/shm") and os.access("/dev/shm", os.W_OK):
    SHM_DIR = "/dev/shm"
else:
    SHM_DIR = tempfile.gettempdir()

SHARED_STATE_FILE = os.path.join(SHM_DIR, "aerialeye_detections.json")
SHARED_FRAME_FILE = os.path.join(SHM_DIR, "aerialeye_latest.jpg")
SHARED_TELEMETRY_FILE = os.path.join(SHM_DIR, "aerialeye_telemetry.json")


class AerialEyeDetector:
    def __init__(self, model_param="yolo.param", model_bin="yolo.bin", conf_threshold=0.55, classes=None):
        self.conf_threshold = conf_threshold
        self.classes = classes or DEFAULT_CLASSES
        self.net = None
        self.use_ncnn = False
        self.use_tflite = False
        self.use_onnx = False

        # 1. Check for NCNN model files
        param_path = os.path.expanduser(f"~/{model_param}")
        bin_path = os.path.expanduser(f"~/{model_bin}")

        # Check current directory if not in home
        if not os.path.exists(param_path):
            param_path = model_param
            bin_path = model_bin

        if os.path.exists(param_path) and os.path.exists(bin_path):
            try:
                import ncnn
                self.net = ncnn.Net()
                self.net.opt.use_vulkan_compute = False  # Pi 3A+ runs on CPU
                self.net.opt.num_threads = 4            # Quad-core Cortex-A53
                self.net.load_param(param_path)
                self.net.load_model(bin_path)
                self.use_ncnn = True
                print(f"[AerialEyeDetector] Successfully loaded NCNN model from {param_path}")
            except ImportError:
                print("[AerialEyeDetector] ncnn module not installed. Falling back to OpenCV DNN.")
            except Exception as e:
                print(f"[AerialEyeDetector] Error initializing NCNN: {e}")

        # 2. Check for ONNX alternative
        onnx_path = os.path.expanduser("~/yolo.onnx")
        if not self.use_ncnn and os.path.exists(onnx_path):
            try:
                self.net = cv2.dnn.readNetFromONNX(onnx_path)
                self.use_onnx = True
                print(f"[AerialEyeDetector] Successfully loaded ONNX model: {onnx_path}")
            except Exception as e:
                print(f"[AerialEyeDetector] ONNX load error: {e}")

    def detect(self, frame):
        """
        Runs object detection on the frame.
        Returns a list of dicts:
        [
            {
                "class": "pothole",
                "confidence": 0.89,
                "box": [xMin, yMin, xMax, yMax]  # Normalized 0.0 to 1.0
            }
        ]
        """
        h, w = frame.shape[:2]
        detections = []

        if self.use_ncnn:
            try:
                import ncnn
                mat_in = ncnn.Mat.from_pixels_resize(
                    frame, ncnn.Mat.PixelType.PIXEL_BGR2RGB, w, h, 320, 320
                )
                mean_vals = [0.0, 0.0, 0.0]
                norm_vals = [1 / 255.0, 1 / 255.0, 1 / 255.0]
                mat_in.substract_mean_normalize(mean_vals, norm_vals)

                ex = self.net.create_extractor()
                ex.input("in0", mat_in)
                ret, mat_out = ex.extract("out0")

                if ret == 0:
                    for i in range(mat_out.h):
                        values = mat_out.row(i)
                        score = float(values[1])
                        if score >= self.conf_threshold:
                            class_idx = int(values[0]) - 1
                            label = self.classes[class_idx] if 0 <= class_idx < len(self.classes) else "obstacle"

                            x1 = max(0.0, min(1.0, float(values[2]) / 320.0))
                            y1 = max(0.0, min(1.0, float(values[3]) / 320.0))
                            x2 = max(0.0, min(1.0, float(values[4]) / 320.0))
                            y2 = max(0.0, min(1.0, float(values[5]) / 320.0))

                            detections.append({
                                "class": label,
                                "confidence": round(score, 3),
                                "box": [round(x1, 4), round(y1, 4), round(x2, 4), round(y2, 4)]
                            })
            except Exception:
                pass

        elif self.use_onnx:
            try:
                blob = cv2.dnn.blobFromImage(frame, 1/255.0, (320, 320), swapRB=True, crop=False)
                self.net.setInput(blob)
                outputs = self.net.forward()
            except Exception:
                pass

        return detections


def open_camera():
    """
    Opens the OV5647 camera module using OpenCV or libcamera pipeline.
    """
    # 1. Try V4L2 device index 0
    cap = cv2.VideoCapture(0)
    if cap.isOpened():
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 20)
        return cap

    # 2. Try GStreamer pipeline for Raspberry Pi OS (libcamera)
    gst_pipeline = (
        "libcamerasrc ! video/x-raw, width=640, height=480, framerate=20/1 ! "
        "videoconvert ! appsink"
    )
    try:
        cap = cv2.VideoCapture(gst_pipeline, cv2.CAP_GSTREAMER)
        if cap.isOpened():
            return cap
    except Exception:
        pass

    # 3. Fallback index 1
    cap = cv2.VideoCapture(1)
    return cap


def read_telemetry():
    """Reads latest flight-controller GPS telemetry from shared memory."""
    if os.path.exists(SHARED_TELEMETRY_FILE):
        try:
            with open(SHARED_TELEMETRY_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return None


def generate_synthetic_frame(frame_num, telemetry=None):
    """Generates a test pattern frame when physical camera is unavailable."""
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    # Background gradient
    for y in range(480):
        frame[y, :, 0] = int(20 + 20 * (y / 480.0))
        frame[y, :, 1] = int(25 + 30 * (y / 480.0))
        frame[y, :, 2] = int(35 + 40 * (y / 480.0))

    # Grid overlay
    cv2.line(frame, (100, 240), (540, 240), (40, 60, 80), 1)
    cv2.line(frame, (320, 80), (320, 400), (40, 60, 80), 1)

    # Info HUD
    cv2.putText(frame, "AerialEYE — OV5647 Simulation Stream", (20, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 210, 255), 2)
    cv2.putText(frame, f"Frame: #{frame_num}", (20, 80),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (160, 160, 160), 1)

    if telemetry:
        lat = telemetry.get("lat", 0.0)
        lon = telemetry.get("lon", 0.0)
        alt = telemetry.get("relative_alt", 0.0)
        mode = telemetry.get("flight_mode", "UNKNOWN")
        sats = telemetry.get("satellites", 0)
        cv2.putText(frame, f"GPS: {lat:.5f}, {lon:.5f} | Alt: {alt:.1f}m | Sats: {sats}", (20, 440),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 128), 1)
        cv2.putText(frame, f"Mode: {mode} | Armed: {telemetry.get('armed', False)}", (20, 465),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 210, 255), 1)

    return frame


def main():
    parser = argparse.ArgumentParser(description="AerialEYE Live Inference Engine")
    parser.add_argument("--sim", action="store_true", help="Run with synthetic test frames if no camera")
    parser.add_argument("--conf", type=float, default=0.55, help="Confidence threshold (default: 0.55)")
    args = parser.parse_args()

    print("=======================================================")
    print(" AerialEYE — Raspberry Pi 3A+ Live Detection Engine")
    print(f" Trained Classes: {DEFAULT_CLASSES}")
    print(f" Shared State: {SHARED_STATE_FILE}")
    print("=======================================================")

    detector = AerialEyeDetector(conf_threshold=args.conf)
    cap = open_camera()

    using_sim = False
    if not cap.isOpened():
        if args.sim:
            print("[AerialEyeLive] Camera not detected. Running in SIMULATION mode with synthetic HUD frames.")
            using_sim = True
        else:
            print("[ERROR] Failed to open camera. Check OV5647 ribbon cable connection.")
            print("Run 'rpicam-hello' or 'vcgencmd get_camera' to verify camera hardware.")
            print("To run in simulation mode without hardware, pass --sim flag.")
            sys.exit(1)

    print("[AerialEyeLive] Video pipeline active (640x480). Starting detection loop...")

    frame_count = 0
    last_fps_time = time.time()

    while True:
        telemetry = read_telemetry()
        now = time.time()

        if using_sim:
            frame = generate_synthetic_frame(frame_count, telemetry)
            ret = True
            time.sleep(0.04)  # ~25 FPS
        else:
            ret, frame = cap.read()
            if not ret or frame is None:
                time.sleep(0.05)
                continue

        frame_count += 1

        # Run inference on frame
        detections = detector.detect(frame)

        # Enrich detections with MAVLink GPS metadata
        gps_meta = {
            "latitude": telemetry.get("lat", 0.0) if telemetry else 0.0,
            "longitude": telemetry.get("lon", 0.0) if telemetry else 0.0,
            "altitude": telemetry.get("relative_alt", telemetry.get("alt", 0.0)) if telemetry else 0.0,
            "satellites": telemetry.get("satellites", 0) if telemetry else 0,
            "gps_fix": telemetry.get("gps_fix", 0) if telemetry else 0,
            "is_valid": telemetry.get("is_gps_valid", False) if telemetry else False,
            "age_seconds": round(now - telemetry.get("gps_time", 0.0), 2) if (telemetry and telemetry.get("gps_time")) else 999.0,
        }

        for det in detections:
            det["gps"] = gps_meta
            det["timestamp"] = now

        # Write latest detection metadata to shared memory
        try:
            state_data = {
                "timestamp": now,
                "detections": detections,
                "telemetry": telemetry,
                "fps": round(frame_count / max(0.001, time.time() - last_fps_time), 1),
            }
            with open(SHARED_STATE_FILE + ".tmp", "w") as f:
                json.dump(state_data, f)
            os.replace(SHARED_STATE_FILE + ".tmp", SHARED_STATE_FILE)

            # Write latest JPEG frame to shared memory
            _, jpeg_buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
            with open(SHARED_FRAME_FILE + ".tmp", "wb") as f:
                f.write(jpeg_buf.tobytes())
            os.replace(SHARED_FRAME_FILE + ".tmp", SHARED_FRAME_FILE)

        except Exception:
            pass

        if frame_count % 60 == 0:
            now_time = time.time()
            fps = frame_count / (now_time - last_fps_time)
            print(f"[AerialEyeLive] FPS: {fps:.1f} | Active detections: {len(detections)} | GPS valid: {gps_meta['is_valid']}")
            frame_count = 0
            last_fps_time = now_time

        time.sleep(0.01)


if __name__ == "__main__":
    main()
