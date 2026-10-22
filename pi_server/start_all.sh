#!/bin/bash
# ==============================================================================
# AerialEYE — Start All Onboard Services on Raspberry Pi 3A+
# ==============================================================================

set -e

echo "=========================================================="
echo " Starting AerialEYE Drone Companion Stack"
echo "=========================================================="

# Check if running as systemd services or directly
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "aerialeye-mavlink.service"; then
    echo "[1/3] Starting systemd services..."
    sudo systemctl restart aerialeye-mavlink.service
    sudo systemctl restart aerialeye-live.service
    sudo systemctl restart aerialeye-view.service
    echo "Services started via systemd."
    echo "Check status with: sudo systemctl status aerialeye-mavlink.service aerialeye-live.service aerialeye-view.service"
else
    echo "[1/3] Starting MAVLink Router (Serial <-> UDP 14550)..."
    python3 ~/aerialeye_mavlink.py --serial /dev/serial0 --baud 57600 --udp-port 14550 > ~/aerialeye_mavlink.log 2>&1 &
    MAV_PID=$!
    echo "      MAVLink Router running (PID: $MAV_PID)"

    echo "[2/3] Starting Live OV5647 Camera & YOLO Inference Engine..."
    python3 ~/aerialeye_live.py > ~/aerialeye_live.log 2>&1 &
    LIVE_PID=$!
    echo "      Live Detector running (PID: $LIVE_PID)"

    echo "[3/3] Starting Flask Video Streamer & Detection API (Port 8080)..."
    python3 ~/aerialeye_view.py > ~/aerialeye_view.log 2>&1 &
    VIEW_PID=$!
    echo "      Viewing Server running (PID: $VIEW_PID)"

    echo ""
    echo "All AerialEYE services started successfully in background!"
    echo "Logs available at:"
    echo "  - ~/aerialeye_mavlink.log"
    echo "  - ~/aerialeye_live.log"
    echo "  - ~/aerialeye_view.log"
fi

echo "=========================================================="
