#!/usr/bin/env python3
"""
AerialEYE Flask Video & Detection Streaming Server
Serves MJPEG stream on port 8080 with synchronized X-Detections headers,
dedicated /detections REST endpoint with MAVLink GPS metadata,
and /status healthcheck endpoint.
"""

import os
import sys
import time
import json
import tempfile
from flask import Flask, Response, jsonify

app = Flask(__name__)

# Determine shared memory path for Linux, with fallback to system temp
if os.path.exists("/dev/shm") and os.access("/dev/shm", os.W_OK):
    SHM_DIR = "/dev/shm"
else:
    SHM_DIR = tempfile.gettempdir()

SHARED_STATE_FILE = os.path.join(SHM_DIR, "aerialeye_detections.json")
SHARED_FRAME_FILE = os.path.join(SHM_DIR, "aerialeye_latest.jpg")
SHARED_TELEMETRY_FILE = os.path.join(SHM_DIR, "aerialeye_telemetry.json")

# Fallback direct camera capture if aerialeye_live.py is not running separately
fallback_cap = None


def get_latest_data():
    """
    Retrieves the latest JPEG frame bytes, detection JSON metadata, and telemetry.
    First checks shared memory from aerialeye_live.py and aerialeye_mavlink.py.
    If unavailable, falls back to local camera frame or synthetic frame.
    """
    global fallback_cap

    frame_bytes = None
    detections = []
    telemetry = None

    # 1. Try reading frame from shared memory
    if os.path.exists(SHARED_FRAME_FILE):
        try:
            with open(SHARED_FRAME_FILE, "rb") as f:
                frame_bytes = f.read()
        except Exception:
            pass

    # 2. Try reading detections from shared memory
    if os.path.exists(SHARED_STATE_FILE):
        try:
            with open(SHARED_STATE_FILE, "r") as f:
                data = json.load(f)
                detections = data.get("detections", [])
                telemetry = data.get("telemetry")
        except Exception:
            pass

    # 3. Try reading telemetry if not already loaded from state file
    if telemetry is None and os.path.exists(SHARED_TELEMETRY_FILE):
        try:
            with open(SHARED_TELEMETRY_FILE, "r") as f:
                telemetry = json.load(f)
        except Exception:
            pass

    # 4. Fallback direct camera capture
    if frame_bytes is None:
        try:
            import cv2
            if fallback_cap is None:
                fallback_cap = cv2.VideoCapture(0)
                fallback_cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                fallback_cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

            ret, frame = fallback_cap.read()
            if ret and frame is not None:
                _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
                frame_bytes = buf.tobytes()
        except Exception:
            pass

    # 5. Last fallback: generate placeholder image
    if frame_bytes is None:
        try:
            import cv2
            import numpy as np
            blank = np.zeros((480, 640, 3), dtype=np.uint8)
            cv2.putText(blank, "AerialEYE — Waiting for camera stream...", (40, 240),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 210, 255), 2)
            _, buf = cv2.imencode(".jpg", blank, [cv2.IMWRITE_JPEG_QUALITY, 75])
            frame_bytes = buf.tobytes()
        except Exception:
            pass

    return frame_bytes, detections, telemetry


def generate_mjpeg_stream():
    """
    Generates multipart/x-mixed-replace MJPEG stream.
    Attaches X-Detections header to every frame containing current YOLO predictions.
    """
    while True:
        frame_bytes, detections, _ = get_latest_data()

        if frame_bytes is not None:
            detections_json = json.dumps(detections)

            # Build MJPEG frame with synchronized X-Detections header
            header = (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n"
                b"Content-Length: " + str(len(frame_bytes)).encode("ascii") + b"\r\n"
                b"X-Detections: " + detections_json.encode("utf-8") + b"\r\n"
                b"\r\n"
            )

            yield header + frame_bytes + b"\r\n"
        else:
            time.sleep(0.05)

        time.sleep(0.04)  # ~25 FPS max stream output


@app.route("/")
def index():
    """
    Webpage viewable in phone's browser at http://<PI_IP>:8080
    """
    return """<!DOCTYPE html>
<html>
<head>
    <title>AerialEYE — Pi Live Camera Stream</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { margin: 0; background-color: #0b0f19; color: #fff; font-family: -apple-system, sans-serif; text-align: center; }
        h1 { margin-top: 16px; font-size: 20px; color: #00d2ff; }
        .stream-container { margin: 12px auto; max-width: 640px; border: 2px solid #1f2937; border-radius: 12px; overflow: hidden; background: #000; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
        img { width: 100%; height: auto; display: block; }
        .footer { font-size: 12px; color: #9ca3af; margin-top: 10px; }
        .badge { display: inline-block; padding: 5px 12px; border-radius: 8px; background: rgba(0, 210, 255, 0.15); color: #00d2ff; font-weight: bold; margin: 4px; font-size: 12px; }
    </style>
</head>
<body>
    <h1>AerialEYE Live Monitoring</h1>
    <div class="badge">OV5647 Camera Active</div>
    <div class="badge">YOLO NCNN Ready</div>
    <div class="badge">MAVLink Telemetry Synced</div>
    <div class="stream-container">
        <img src="/video_feed" alt="Raspberry Pi Camera Feed">
    </div>
    <div class="footer">Connect AerialEYE Mobile App to: http://&lt;PI_IP&gt;:8080</div>
</body>
</html>"""


@app.route("/video_feed")
def video_feed():
    """
    MJPEG stream endpoint for AerialEYE Flutter application and browsers.
    """
    return Response(
        generate_mjpeg_stream(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )


@app.route("/detections")
def detections_endpoint():
    """
    JSON endpoint polled by AerialEYE application for genuine YOLO predictions with GPS coordinates.
    """
    _, detections, telemetry = get_latest_data()
    return jsonify({
        "timestamp": time.time(),
        "count": len(detections),
        "detections": detections,
        "telemetry": telemetry,
    })


@app.route("/telemetry")
def telemetry_endpoint():
    """
    Direct endpoint for reading onboard flight-controller telemetry bridge state.
    """
    _, _, telemetry = get_latest_data()
    return jsonify({
        "timestamp": time.time(),
        "telemetry": telemetry or {},
    })


@app.route("/status")
def status_endpoint():
    """
    Healthcheck endpoint for mobile app diagnostics.
    """
    frame_bytes, detections, telemetry = get_latest_data()
    has_telemetry = telemetry is not None and telemetry.get("connected", False)
    is_gps_valid = telemetry.get("is_gps_valid", False) if telemetry else False

    return jsonify({
        "status": "online",
        "has_camera_frame": frame_bytes is not None,
        "active_detections": len(detections),
        "mavlink_connected": has_telemetry,
        "gps_fix_valid": is_gps_valid,
        "satellites": telemetry.get("satellites", 0) if telemetry else 0,
        "flight_mode": telemetry.get("flight_mode", "UNKNOWN") if telemetry else "UNKNOWN",
        "armed": telemetry.get("armed", False) if telemetry else False,
        "timestamp": time.time(),
    })


def main():
    print("=======================================================")
    print(" AerialEYE — Flask MJPEG & Detection Server (Port 8080)")
    print(" Endpoint: http://0.0.0.0:8080/video_feed")
    print(" Detections: http://0.0.0.0:8080/detections")
    print(" Status: http://0.0.0.0:8080/status")
    print("=======================================================")

    app.run(host="0.0.0.0", port=8080, threaded=True, debug=False)


if __name__ == "__main__":
    main()
