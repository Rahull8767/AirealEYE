# AerialEYE — Raspberry Pi 3A+ Server Setup

This directory contains the Python scripts to run on your **Raspberry Pi 3 Model A+** with your **OV5647 camera module** and trained **YOLO NCNN model**.

---

## 1. Files
- `aerialeye_live.py`: Captures frames from OV5647 camera, runs trained YOLO NCNN inference (`person`, `animal`, `pothole`, `waste`), and stores latest frames & detection coordinates in shared memory (`/dev/shm`).
- `aerialeye_view.py`: Flask MJPEG server on port `8080` that serves the live video feed with embedded `X-Detections:` multipart headers and the `/detections` JSON API.

---

## 2. Deploying to the Raspberry Pi

From your laptop connected to the hotspot, copy both scripts to the Pi's home directory:

```bash
scp pi_server/aerialeye_live.py pi@10.174.17.87:~/
scp pi_server/aerialeye_view.py pi@10.174.17.87:~/
```

---

## 3. Starting the Server on the Pi

SSH into the Pi:
```bash
ssh pi@10.174.17.87
```

Install Flask and OpenCV if not already installed:
```bash
sudo apt-get update
sudo apt-get install -y python3-opencv python3-flask
```

Start the inference detector and streaming server:
```bash
# 1. Start live detector in background
python3 ~/aerialeye_live.py &

# 2. Start Flask viewing server on port 8080
python3 ~/aerialeye_view.py
```

---

## 4. How Detections Reach the AerialEYE App

1. `aerialeye_live.py` detects any of the 4 classes: **Person**, **Animal**, **Pothole**, **Waste**.
2. Bounding boxes are emitted through:
   - **Method A**: `X-Detections: [...]` HTTP header inside the MJPEG stream boundaries (zero latency, frame-synchronized).
   - **Method B**: `GET /detections` endpoint polled periodically by `RealDetectionService`.
3. In the AerialEYE app:
   - Bounding boxes and `#1 CLASS XX%` labels render live over the video viewport.
   - When a new qualifying detection appears, an image is auto-saved to the persistent Gallery along with timestamp, confidence, and GPS coordinates (from drone telemetry or phone GPS).
   - Duplicate saves are prevented using spatial-temporal IoU tracking.
