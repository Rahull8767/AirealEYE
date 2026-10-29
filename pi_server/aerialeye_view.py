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
import threading
from flask import Flask, Response, jsonify, send_file, request

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


@app.route("/capture")
@app.route("/snapshot")
def capture_endpoint():
    """
    Returns the latest high-resolution single JPEG frame.
    Attaches current detection and telemetry metadata in headers.
    """
    frame_bytes, detections, telemetry = get_latest_data()
    if frame_bytes is not None:
        response = Response(frame_bytes, mimetype="image/jpeg")
        response.headers["X-Detections"] = json.dumps(detections)
        if telemetry:
            response.headers["X-Telemetry"] = json.dumps(telemetry)
        return response
    return jsonify({"error": "No camera frame currently available"}), 503


# Video recording state management
RECORDINGS_DIR = os.path.join(tempfile.gettempdir(), "aerialeye_recordings")
os.makedirs(RECORDINGS_DIR, exist_ok=True)

recording_lock = threading.Lock()
active_recording = {
    "is_recording": False,
    "recording_id": None,
    "file_path": None,
    "start_time": None,
    "stop_event": None,
    "thread": None,
    "frame_count": 0,
    "error": None,
}


def _record_worker(file_path, stop_event, fps=20.0):
    try:
        import cv2
        import numpy as np
        writer = None
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')

        while not stop_event.is_set():
            t0 = time.time()
            frame_bytes, _, _ = get_latest_data()
            if frame_bytes is not None:
                nparr = np.frombuffer(frame_bytes, np.uint8)
                img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                if img is not None:
                    h, w = img.shape[:2]
                    if writer is None:
                        writer = cv2.VideoWriter(file_path, fourcc, fps, (w, h))
                    writer.write(img)
                    with recording_lock:
                        active_recording["frame_count"] += 1

            dt = time.time() - t0
            sleep_time = max(0.001, (1.0 / fps) - dt)
            time.sleep(sleep_time)

        if writer is not None:
            writer.release()
    except Exception as e:
        with recording_lock:
            active_recording["error"] = str(e)


@app.route("/record/start", methods=["POST"])
def record_start():
    with recording_lock:
        if active_recording["is_recording"]:
            return jsonify({
                "error": "A recording is already active.",
                "recording_id": active_recording["recording_id"],
                "start_time": active_recording["start_time"],
            }), 409

        rec_id = f"rec_{int(time.time())}"
        file_path = os.path.join(RECORDINGS_DIR, f"{rec_id}.mp4")
        stop_event = threading.Event()
        worker = threading.Thread(
            target=_record_worker,
            args=(file_path, stop_event),
            daemon=True,
        )

        active_recording["is_recording"] = True
        active_recording["recording_id"] = rec_id
        active_recording["file_path"] = file_path
        active_recording["start_time"] = time.time()
        active_recording["stop_event"] = stop_event
        active_recording["thread"] = worker
        active_recording["frame_count"] = 0
        active_recording["error"] = None

        worker.start()

        return jsonify({
            "status": "recording_started",
            "recording_id": rec_id,
            "start_time": active_recording["start_time"],
        })


@app.route("/record/status", methods=["GET"])
def record_status():
    with recording_lock:
        is_rec = active_recording["is_recording"]
        duration = time.time() - active_recording["start_time"] if is_rec and active_recording["start_time"] else 0.0
        return jsonify({
            "is_recording": is_rec,
            "recording_id": active_recording["recording_id"],
            "duration_seconds": round(duration, 1),
            "frame_count": active_recording["frame_count"],
            "error": active_recording["error"],
        })


@app.route("/record/stop", methods=["POST"])
def record_stop():
    with recording_lock:
        if not active_recording["is_recording"]:
            return jsonify({"error": "No recording is currently active."}), 400

        rec_id = active_recording["recording_id"]
        file_path = active_recording["file_path"]
        active_recording["stop_event"].set()
        thread = active_recording["thread"]

    # Wait for writer to release
    if thread is not None:
        thread.join(timeout=3.0)

    size = os.path.getsize(file_path) if os.path.exists(file_path) else 0
    duration = time.time() - active_recording["start_time"] if active_recording["start_time"] else 0.0
    frames = active_recording["frame_count"]

    with recording_lock:
        active_recording["is_recording"] = False
        active_recording["thread"] = None
        active_recording["stop_event"] = None

    return jsonify({
        "status": "recording_stopped",
        "recording_id": rec_id,
        "file_name": f"{rec_id}.mp4",
        "size_bytes": size,
        "duration_seconds": round(duration, 1),
        "frame_count": frames,
        "download_url": f"/record/download/{rec_id}",
    })


@app.route("/record/download/<recording_id>", methods=["GET"])
def record_download(recording_id):
    # Sanitize id
    safe_id = os.path.basename(recording_id)
    if not safe_id.endswith(".mp4"):
        safe_id = f"{safe_id}.mp4"
    path = os.path.join(RECORDINGS_DIR, safe_id)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return jsonify({"error": f"Recording {recording_id} not found on server."}), 404

    from flask import send_file
    return send_file(
        path,
        mimetype="video/mp4",
        as_attachment=True,
        download_name=safe_id,
    )


@app.route("/record/list", methods=["GET"])
def record_list():
    recordings = []
    if os.path.exists(RECORDINGS_DIR):
        for fname in sorted(os.listdir(RECORDINGS_DIR), reverse=True):
            if fname.endswith(".mp4"):
                full_path = os.path.join(RECORDINGS_DIR, fname)
                try:
                    stat = os.stat(full_path)
                    recordings.append({
                        "id": os.path.splitext(fname)[0],
                        "file_name": fname,
                        "size_bytes": stat.st_size,
                        "created_at": stat.st_mtime,
                        "download_url": f"/record/download/{os.path.splitext(fname)[0]}",
                    })
                except Exception:
                    pass
    return jsonify({"count": len(recordings), "recordings": recordings})


@app.route("/record/<recording_id>", methods=["DELETE"])
def record_delete(recording_id):
    safe_id = os.path.basename(recording_id)
    if not safe_id.endswith(".mp4"):
        safe_id = f"{safe_id}.mp4"
    path = os.path.join(RECORDINGS_DIR, safe_id)
    if os.path.exists(path):
        try:
            os.remove(path)
            return jsonify({"status": "deleted", "recording_id": recording_id})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    return jsonify({"error": "Recording not found"}), 404


def main():
    print("=======================================================")
    print(" AerialEYE — Flask MJPEG, Recording & Detection Server")
    print(" Video Feed:  http://0.0.0.0:8080/video_feed")
    print(" Capture:     http://0.0.0.0:8080/capture")
    print(" Record:      http://0.0.0.0:8080/record/start")
    print(" Detections:  http://0.0.0.0:8080/detections")
    print(" Status:      http://0.0.0.0:8080/status")
    print("=======================================================")

    app.run(host="0.0.0.0", port=8080, threaded=True, debug=False)


if __name__ == "__main__":
    main()
