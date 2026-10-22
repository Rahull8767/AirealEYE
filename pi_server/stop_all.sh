#!/bin/bash
# ==============================================================================
# AerialEYE — Stop All Onboard Services on Raspberry Pi 3A+
# ==============================================================================

echo "=========================================================="
echo " Stopping AerialEYE Drone Companion Stack"
echo "=========================================================="

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "aerialeye-mavlink.service"; then
    echo "Stopping systemd services..."
    sudo systemctl stop aerialeye-view.service || true
    sudo systemctl stop aerialeye-live.service || true
    sudo systemctl stop aerialeye-mavlink.service || true
    echo "Services stopped."
fi

# Kill any manual background instances
echo "Stopping any running Python instances..."
pkill -f "aerialeye_mavlink.py" || true
pkill -f "aerialeye_live.py" || true
pkill -f "aerialeye_view.py" || true

echo "All AerialEYE companion services stopped."
echo "=========================================================="
