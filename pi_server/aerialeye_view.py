#!/usr/bin/env python3
"""
AerialEYE Flask Video & Detection Streaming Server
Serves MJPEG stream on port 8080 with synchronized X-Detections headers
and provides dedicated /detections REST endpoint.
Works across single-phone mobile hotspot (http://10.174.17.87:8080)
"""

import os
import sys
import time
import json
from flask import Flask, Response, jsonify

app = Flask(__name__)

SHARED_STATE_FILE = "/dev/shm/aerialeye_detections.json"
SHARED_FRAME_FILE = "/dev/shm/aerialeye_latest.jpg"

# Fallback direct camera capture if aerialeye_live.py is not running separately
fallback_cap = None

def get_latest_data():
    """
    Retrieves the latest JPEG frame bytes and detection JSON metadata.
    First checks shared memory from aerialeye_live.py.
    If unavailable, falls back to local camera frame.
    """
    global fallback_cap

    frame_bytes = None
    detections = []

    # 1. Try reading from shared memory written by aerialeye_live.py
    if os.path.exists(SHARED_FRAME_FILE):
        try:
            with open(SHARED_FRAME_FILE, "rb") as f:
                frame_bytes = f.read()
        except Exception:
            pass

    if os.path.exists(SHARED_STATE_FILE):
        try:
            with open(SHARED_STATE_FILE, "r") as f:
                data = json.load(f)
                detections = data.get("detections", [])
        except Exception:
            pass

    # 2. Fallback: If live script isn't running, capture directly via OpenCV
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
        except Exception as e:
            pass

    return frame_bytes, detections

def generate_mjpeg_stream():
    """
    Generates multipart/x-mixed-replace MJPEG stream.
    Attaches X-Detections header to every frame containing the current YOLO predictions.
    """
    while True:
        frame_bytes, detections = get_latest_data()

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

        time.sleep(0.04) # ~25 FPS max stream output

@app.route("/")
def index():
    """
    Webpage viewable in phone's Chrome browser at http://10.174.17.87:8080
    """
    return """<!DOCTYPE html>
<html>
<head>
    <title>AerialEYE — Pi Live Camera Stream</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { margin: 0; background-color: #0b0f19; color: #fff; font-family: monospace; text-align: center; }
        h1 { margin-top: 16px; font-size: 18px; color: #00d2ff; }
        .stream-container { margin: 12px auto; max-width: 640px; border: 2px solid #1f2937; border-radius: 12px; overflow: hidden; background: #000; }
        img { width: 100%; height: auto; display: block; }
        .footer { font-size: 11px; color: #9ca3af; margin-top: 8px; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 8px; background: rgba(0, 210, 255, 0.15); color: #00d2ff; font-weight: bold; margin: 4px; }
    </style>
</head>
<body>
    <h1>AerialEYE Live Monitoring</h1>
    <div class="badge">OV5647 Camera Active</div>
    <div class="badge">YOLO NCNN Ready</div>
    <div class="stream-container">
        <img src="/video_feed" alt="Raspberry Pi Camera Feed">
    </div>
    <div class="footer">Connect AerialEYE Mobile App to: http://10.174.17.87:8080</div>
</body>
</html>"""

@app.route("/video_feed")
def video_feed():
    """
    MJPEG stream endpoint for AerialEYE Flutter application and browsers.
    """
    return Response(
        generate_mjpeg_stream(),
        mimetype="multipart/x-mixed-replace; boundary=frame"
    )

@app.route("/detections")
def detections_endpoint():
    """
    JSON endpoint polled by AerialEYE application for genuine YOLO predictions.
    """
    _, detections = get_latest_data()
    return jsonify({
        "timestamp": time.time(),
        "count": len(detections),
        "detections": detections
    })

@app.route("/status")
def status_endpoint():
    """
    Healthcheck endpoint.
    """
    frame_bytes, detections = get_latest_data()
    return jsonify({
        "status": "online",
        "has_camera_frame": frame_bytes is not None,
        "active_detections": len(detections),
        "timestamp": time.time()
    })

def main():
    print("=======================================================")
    print(" AerialEYE — Flask MJPEG & Detection Server (Port 8080)")
    print(" Endpoint: http://0.0.0.0:8080/video_feed")
    print(" Detections: http://0.0.0.0:8080/detections")
    print("=======================================================")
    
    # Run with threaded=True so multiple HTTP requests don't block each other
    app.run(host="0.0.0.0", port=8080, threaded=True, debug=False)

if __name__ == "__main__":
    main()
