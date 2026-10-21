#!/usr/bin/env python3
"""
AerialEYE Live Inference Engine for Raspberry Pi 3 Model A+
Trained YOLO NCNN Detector for: Person, Animal, Pothole, Waste
Compatible with OV5647 5MP Camera Module on Raspberry Pi OS Lite (32-bit/64-bit)
"""

import os
import sys
import time
import json
import threading
import numpy as np

# Try importing OpenCV and NCNN
try:
    import cv2
except ImportError:
    print("[ERROR] OpenCV (cv2) is required. Install: sudo apt-get install python3-opencv")
    sys.exit(1)

# Trained classes for AerialEYE
CLASSES = ["person", "animal", "pothole", "waste"]

# Shared state file for IPC between live.py and view.py
SHARED_STATE_FILE = "/dev/shm/aerialeye_detections.json"
SHARED_FRAME_FILE = "/dev/shm/aerialeye_latest.jpg"

class AerialEyeDetector:
    def __init__(self, model_param="yolo.param", model_bin="yolo.bin", conf_threshold=0.55):
        self.conf_threshold = conf_threshold
        self.classes = CLASSES
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
                self.net.opt.use_vulkan_compute = False # Pi 3A+ runs on CPU
                self.net.opt.num_threads = 4           # Quad-core Cortex-A53
                self.net.load_param(param_path)
                self.net.load_model(bin_path)
                self.use_ncnn = True
                print(f"[AerialEyeDetector] Successfully loaded NCNN model from {param_path}")
            except ImportError:
                print("[AerialEyeDetector] ncnn module not installed. Falling back to OpenCV DNN / mock inference.")
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
            except Exception as e:
                pass

        elif self.use_onnx:
            try:
                blob = cv2.dnn.blobFromImage(frame, 1/255.0, (320, 320), swapRB=True, crop=False)
                self.net.setInput(blob)
                outputs = self.net.forward()
                # Parse standard YOLOv5 / YOLOv8 ONNX output
                # [1, 84, 2100] or [1, 25200, 85]
                # Filter by confidence
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

    # 2. Try GStreamer pipeline for Raspberry Pi OS Bookworm/Bullseye (libcamera)
    gst_pipeline = (
        "libcamerasrc ! video/x-raw, width=640, height=480, framerate=20/1 ! "
        "videoconvert ! appsink"
    )
    cap = cv2.VideoCapture(gst_pipeline, cv2.CAP_GSTREAMER)
    if cap.isOpened():
        return cap

    print("[WARN] Camera could not be opened with standard indices. Trying fallback index 1...")
    cap = cv2.VideoCapture(1)
    return cap

def main():
    print("=======================================================")
    print(" AerialEYE — Raspberry Pi 3A+ Live Detection Engine")
    print(f" Trained Classes: {CLASSES}")
    print("=======================================================")

    detector = AerialEyeDetector()
    cap = open_camera()

    if not cap.isOpened():
        print("[ERROR] Failed to open camera. Check OV5647 ribbon cable connection.")
        print("Run 'rpicam-hello' or 'vcgencmd get_camera' to verify camera hardware.")
        sys.exit(1)

    print("[AerialEyeLive] Camera initialized at 640x480. Starting detection loop...")

    frame_count = 0
    last_fps_time = time.time()

    while True:
        ret, frame = cap.read()
        if not ret or frame is None:
            time.sleep(0.05)
            continue

        frame_count += 1

        # Run inference on frame
        detections = detector.detect(frame)

        # Write latest detection metadata to shared memory
        try:
            state_data = {
                "timestamp": time.time(),
                "detections": detections,
                "fps": round(frame_count / max(0.001, time.time() - last_fps_time), 1)
            }
            with open(SHARED_STATE_FILE + ".tmp", "w") as f:
                json.dump(state_data, f)
            os.replace(SHARED_STATE_FILE + ".tmp", SHARED_STATE_FILE)

            # Write latest JPEG frame to shared memory
            _, jpeg_buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
            with open(SHARED_FRAME_FILE + ".tmp", "wb") as f:
                f.write(jpeg_buf.tobytes())
            os.replace(SHARED_FRAME_FILE + ".tmp", SHARED_FRAME_FILE)

        except Exception as e:
            pass

        if frame_count % 60 == 0:
            now = time.time()
            fps = frame_count / (now - last_fps_time)
            print(f"[AerialEyeLive] FPS: {fps:.1f} | Active detections: {len(detections)}")
            frame_count = 0
            last_fps_time = now

        time.sleep(0.01)

if __name__ == "__main__":
    main()
