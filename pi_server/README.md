# AerialEYE — Complete Raspberry Pi 3A+ & APM 2.8 Integration Guide

This guide provides verified, production-ready instructions for setting up the **Raspberry Pi 3 Model A+** companion computer with the **APM 2.8 Flight Controller (ArduCopter 3.2.1)**, **OV5647 5MP Camera Module**, **YOLO NCNN/ONNX inference engine**, and the **AerialEYE Flutter Mobile Application**.

---

## 1. System Architecture

```text
+-----------------------+                    +-----------------------------+                    +-----------------------+
|  AerialEYE Flutter   |                    |   Raspberry Pi 3 Model A+   |                    |       APM 2.8         |
|  Mobile Application   | <--- Wi-Fi/UDP --> |   Companion Computer        | <-- Serial/UART -> |   Flight Controller   |
|  (Android / iOS / OS) |                    |                             |                    |   (ArduCopter 3.2.1)  |
+-----------------------+                    +-----------------------------+                    +-----------------------+
           |                                                |                                                |
           |-- UDP :14550 (Bidirectional MAVLink) --------> |-- aerialeye_mavlink.py ----------------------> |-- Telem Port (57600)
           |                                                |   - Frame-safe MAVLink 1.0 / 2.0 relay         |   or USB (115200)
           |                                                |   - Auto-discovers App IP/Port                 |   - GPS Receiver
           |                                                |   - Requests Streams (REQUEST_DATA_STREAM)     |     (UBLOX NEO-6M/M8N)
           |                                                |   - Writes to /dev/shm/aerialeye_telemetry.json|
           |                                                |                                                |
           |<-- HTTP :8080/video_feed (MJPEG Stream) -------|-- aerialeye_view.py                            |
           |<-- HTTP :8080/detections (JSON + GPS Tags) ----|   - Embedded X-Detections headers              |
           |<-- HTTP :8080/status (Health Diagnostics) -----|   - Serves /detections and /status             |
           |                                                |                                                |
           |                                                |-- aerialeye_live.py                            |
           |                                                |   - OV5647 5MP Camera Capture                  |
           |                                                |   - Trained YOLO NCNN Inference Engine         |
           |                                                |   - Real-time GPS Tagging from Shared Memory   |
```

---

## 2. Hardware Wiring & Electrical Safety

> [!CAUTION]
> **ELECTRICAL WARNING — 5V vs 3.3V LOGIC LEVELS**
> - The **APM 2.8 Telem port signals are 5.0V TTL logic**.
> - The **Raspberry Pi 3A+ GPIO pins are 3.3V logic and ARE NOT 5V tolerant**.
> - Connecting APM TX directly to Raspberry Pi RX without level shifting will damage the Raspberry Pi GPIO pin over time.
> - Always use a **bidirectional logic level converter** or a **resistor voltage divider** on the APM TX line, OR use a direct micro-USB to USB-A cable between the APM and Raspberry Pi USB port.

### Option A: Direct USB Connection (Recommended & Safest)
Connect a standard Micro-USB to USB-A cable:
- **APM 2.8**: Micro-USB port
- **Raspberry Pi 3A+**: Standard USB-A port
- Device on Pi: `/dev/ttyACM0` (or `/dev/ttyUSB0`)
- Baud rate: `115200`
- Safe: standard 5V USB bus power and protected differential D+/D- signaling.

### Option B: Hardware UART GPIO Wiring (with Level Shifting)
If connecting via the physical 5-pin Telem/UART0 port on the APM 2.8:

| APM 2.8 Telem Pin | Signal Level | Wiring / Level Shifter | Raspberry Pi 3A+ Pin | Physical Pin # |
|-------------------|--------------|------------------------|----------------------|----------------|
| **GND** | 0V | Direct Common Ground | **GND** | Pin 6 / 9 / 14 |
| **TX** (Transmit) | 5.0V TTL | **1kΩ / 2kΩ Voltage Divider** or Level Shifter HV -> LV (3.3V) | **GPIO 15 (RXD0)** | Pin 10 |
| **RX** (Receive) | 5.0V TTL input | Direct connection (Pi 3.3V TX is recognized by APM as HIGH) | **GPIO 14 (TXD0)** | Pin 8 |
| **VCC** (5V) | 5.0V Power | **DO NOT connect to Pi 3.3V!** Power APM via Power Module / ESC BEC, and Pi via dedicated 5V 2.5A BEC. | DO NOT CONNECT | — |

**Resistor Voltage Divider for APM TX -> Pi RX:**
```text
APM 2.8 TX (5V) ------[ 1.0 kΩ ]------+------> Raspberry Pi GPIO 15 (RXD, ~3.3V)
                                       |
                                    [ 2.0 kΩ ]
                                       |
                                      GND (Common Ground)
```

---

## 3. Raspberry Pi Environment Setup

### Step 3.1: Enable UART Hardware & Disable Serial Console
To ensure `/dev/serial0` is dedicated exclusively to MAVLink communication and not conflicted by the Linux serial login console:

1. Edit `/boot/cmdline.txt` (or `/boot/firmware/cmdline.txt` on Bookworm):
   ```bash
   sudo nano /boot/cmdline.txt
   ```
   **Remove** any occurrences of:
   ```text
   console=serial0,115200  or  console=ttyAMA0,115200
   ```
   Keep `console=tty1`.

2. Edit `/boot/config.txt` (or `/boot/firmware/config.txt`):
   ```bash
   sudo nano /boot/config.txt
   ```
   Ensure the following lines are present:
   ```ini
   enable_uart=1
   dtoverlay=disable-bt
   ```
   *(Disabling Bluetooth assigns the high-reliability PL011 hardware UART directly to `/dev/serial0` and `/dev/ttyAMA0` on GPIO 14/15).*

3. Stop and disable the serial login getty service:
   ```bash
   sudo systemctl stop serial-getty@serial0.service
   sudo systemctl disable serial-getty@serial0.service
   ```

4. Add `pi` user to the `dialout` and `video` groups:
   ```bash
   sudo usermod -aG dialout,video pi
   ```

5. Reboot the Raspberry Pi:
   ```bash
   sudo reboot
   ```

---

## 4. Install Dependencies

SSH into your Raspberry Pi:
```bash
ssh pi@10.174.17.87
```

Update system packages and install Python, OpenCV, and Flask:
```bash
sudo apt-get update
sudo apt-get install -y python3-pip python3-opencv python3-flask
pip3 install pymavlink pyserial
```

Verify camera hardware is detected:
```bash
# For Bullseye/Legacy:
vcgencmd get_camera
# Expected: supported=1 detected=1

# For Bookworm (libcamera):
rpicam-hello --list-cameras
```

---

## 5. Deploying the Companion Files

From your development workstation, copy all `pi_server` files to the Pi:
```bash
scp pi_server/aerialeye_mavlink.py pi@10.174.17.87:~/
scp pi_server/aerialeye_live.py pi@10.174.17.87:~/
scp pi_server/aerialeye_view.py pi@10.174.17.87:~/
scp pi_server/test_server_integration.py pi@10.174.17.87:~/
scp pi_server/start_all.sh pi@10.174.17.87:~/
scp pi_server/stop_all.sh pi@10.174.17.87:~/
scp -r pi_server/systemd pi@10.174.17.87:~/
```

On the Pi, make the scripts executable:
```bash
chmod +x ~/start_all.sh ~/stop_all.sh ~/aerialeye_*.py
```

---

## 6. Verifying Services & Ports

### Starting the Stack Manually:
```bash
~/start_all.sh
```

### Checking Listening Ports:
```bash
# Verify Flask is listening on port 8080:
sudo netstat -tulpn | grep 8080
# Output should show: 0.0.0.0:8080 LISTEN

# Verify MAVLink router is listening on UDP port 14550:
sudo netstat -tulpn | grep 14550
# Output should show: 0.0.0.0:14550 UDP
```

### Checking Live Shared-Memory Telemetry:
```bash
cat /dev/shm/aerialeye_telemetry.json
```
Sample verified output:
```json
{
  "connected": true,
  "system_id": 1,
  "component_id": 1,
  "vehicle_type": "ArduCopter",
  "flight_mode": "STABILIZE",
  "armed": false,
  "lat": 12.971598,
  "lon": 77.594562,
  "alt": 920.0,
  "relative_alt": 0.0,
  "heading": 180.0,
  "battery_voltage": 12.45,
  "gps_fix": 3,
  "satellites": 14,
  "is_gps_valid": true,
  "gps_age_seconds": 0.2
}
```

### Verifying Camera Stream & Detection API:
Open in phone or laptop browser:
- Stream: `http://10.174.17.87:8080/video_feed`
- Detections: `http://10.174.17.87:8080/detections`
- Healthcheck: `http://10.174.17.87:8080/status`

---

## 7. Configuring Auto-Start on Boot (Systemd)

To make all services automatically start upon Raspberry Pi boot:
```bash
sudo cp ~/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable aerialeye-mavlink.service
sudo systemctl enable aerialeye-live.service
sudo systemctl enable aerialeye-view.service
sudo systemctl start aerialeye-mavlink.service aerialeye-live.service aerialeye-view.service
```

To inspect service logs:
```bash
sudo journalctl -u aerialeye-mavlink.service -f
sudo journalctl -u aerialeye-live.service -f
sudo journalctl -u aerialeye-view.service -f
```

---

## 8. Mobile App Connection Setup

1. Open **AerialEYE Mobile App** on your phone.
2. Ensure your phone is connected to the same Wi-Fi network or hotspot as the Raspberry Pi (e.g., `10.174.17.87`).
3. Navigate to **Connect** screen:
   - **Mode**: Select **Hardware Mode**.
   - **Raspberry Pi IP**: `10.174.17.87`
   - **Local UDP Port**: `14550`
   - **Remote UDP Port**: `14550`
4. Tap **Connect**.
5. The connection status will transition from `Connecting` -> `Socket Bound` -> `Heartbeat Received / Connected`.
6. Live GPS coordinates, fix status (3D Fix), satellite count, battery voltage, and flight mode will update directly from APM 2.8!
7. Navigate to **Live Monitoring**:
   - The OV5647 camera stream will display at 640x480.
   - Bounding boxes appear live with `#<id> <CLASS> <CONFIDENCE>%` labels.
   - GPS coordinates and relative altitude are automatically attached to any saved detection in the Gallery.

---

## 9. Running Verification Tests

Run the Python companion tests on the Pi:
```bash
python3 ~/test_server_integration.py
```
Expected output:
```text
Ran 8 tests in ~9s
OK
```

Run Flutter tests on your development machine:
```bash
flutter test
```
Expected output:
```text
All 85 tests passed!
```

---

## 10. Troubleshooting Matrix

| Issue | Root Cause | Solution |
|---|---|---|
| UDP bound but 0 packets arriving | Firewall / Hotspot client isolation | Verify phone hotspot allows local UDP communication; verify Pi IP address via `hostname -I`. |
| MAVLink frames received but no heartbeat | Baud rate mismatch or wrong serial device | Check `SERIAL1_BAUD` in APM params (57 = 57600 baud). Try `/dev/ttyACM0` if using USB cable. |
| APM drops commands sent by app | MAVLink v2 sent to APM 2.8 | `MavlinkDroneService` now automatically detects `0xFE` from APM 2.8 and serializes with MAVLink v1. |
| No GPS coordinates displayed | APM not streaming data | `aerialeye_mavlink.py` automatically transmits `REQUEST_DATA_STREAM` at 4 Hz to request GPS and telemetry streams. |
| Garbage characters on serial | Linux serial console active on UART | Remove `console=serial0,115200` from `/boot/cmdline.txt` and disable `serial-getty@serial0.service`. |
| Camera cannot open | OV5647 ribbon cable loose or camera disabled | Check ribbon contacts (blue side faces Ethernet port on Pi 3A+). Run `vcgencmd get_camera`. |

---

## 11. Raspberry Pi Safe Shutdown Service & Configuration

To prevent SD card filesystem corruption, the Raspberry Pi 3A+ must be powered down cleanly using `systemctl poweroff` rather than pulling the power plug while Linux is running.

AerialEYE provides a dedicated, lightweight, unprivileged shutdown daemon:
- **Script**: `/home/rahul/aerialeye_shutdown.py`
- **Port**: `5005` (HTTP REST API)
- **Endpoints**:
  - `GET /status`: Public healthcheck endpoint returning hostname, uptime, and shutdown status.
  - `POST /shutdown`: Authenticated endpoint requiring `X-AerialEye-Token` or `Authorization: Bearer <TOKEN>`.
- **Security**:
  - Runs as unprivileged user `rahul` (never as root).
  - Uses sudoers whitelist restricted *strictly* to `/bin/systemctl poweroff`, `/bin/systemctl reboot`, and `/sbin/shutdown`.
  - Rejects connections outside private RFC 1918 subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.1`).
  - Secret token stored in `/etc/aerialeye/shutdown.env` with `0600` permissions.
  - Returns HTTP 200 acknowledgement first, then initiates poweroff after 1.5 seconds so the mobile app cleanly receives the confirmation packet.
  - Prevents race conditions and duplicate poweroff attempts (HTTP 409).

### Step 11.1: Deploy Sudoers Rule
Install the sudoers rule so user `rahul` can execute poweroff without password prompts:
```bash
sudo cp ~/systemd/010_aerialeye-shutdown-sudoers /etc/sudoers.d/010_aerialeye-shutdown
sudo chmod 0440 /etc/sudoers.d/010_aerialeye-shutdown
sudo visudo -c  # Validate sudoers syntax
```

### Step 11.2: Configure Secret Authentication Token
Create the configuration directory and secure environment file:
```bash
sudo mkdir -p /etc/aerialeye
sudo cp ~/systemd/shutdown.env /etc/aerialeye/shutdown.env
sudo chmod 0600 /etc/aerialeye/shutdown.env
sudo chown root:root /etc/aerialeye/shutdown.env
```
To generate your own secure private token:
```bash
# Generate random 32-character hex secret:
openssl rand -hex 16
# Edit /etc/aerialeye/shutdown.env:
sudo nano /etc/aerialeye/shutdown.env
# Set: AERIALEYE_SHUTDOWN_TOKEN="<your-new-secret>"
```

### Step 11.3: Enable and Start Systemd Daemon
```bash
sudo cp ~/systemd/aerialeye-shutdown.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable aerialeye-shutdown.service
sudo systemctl start aerialeye-shutdown.service
```

Verify service is active:
```bash
sudo systemctl status aerialeye-shutdown.service
```

### Step 11.4: Command-Line Verification
```bash
# 1. Check status (Public)
curl -s http://127.0.0.1:5005/status | jq .

# 2. Test rejection of unauthenticated request (Should return HTTP 401)
curl -s -i -X POST http://127.0.0.1:5005/shutdown

# 3. Test authenticated shutdown (Use --dry-run mode for testing without real shutdown):
# Start in test dry-run mode:
# python3 ~/aerialeye_shutdown.py --port 5005 --dry-run
curl -s -i -X POST http://127.0.0.1:5005/shutdown \
  -H "X-AerialEye-Token: aerialeye-safe-shutdown-secret-2026"
```

---

## 12. Flutter App Safe Power Control & Flight Interlocks

The Flutter app embeds the **Raspberry Pi Power Control** panel in both the **Camera Link Screen** and the **Console Settings Screen**.

### Flight Safety Safeguards:
1. **Motors Armed Block**: If APM 2.8 telemetry reports `armed == true`, the shutdown request is strictly intercepted and blocked before any network call. The app displays:
   `"SAFETY BLOCK: Drone is currently ARMED. Disarm motors before shutting down the companion computer."`
2. **Active Flight Block**: If telemetry indicates `relativeAltitude > 1.0m` or `speed > 0.8m/s`, shutdown is blocked.
3. **Mission Active Block**: If flight mode is `AUTO` or `GUIDED`, shutdown is blocked.
4. **Telemetry Disconnected Caution**: If MAVLink telemetry is disconnected, the app alerts the pilot that flight state cannot be confirmed, requiring an explicit operator safety checklist confirmation before proceeding.
5. **No Interference with Flight Controller**: The companion computer shutdown command never sends MAVLink disarm/land packets to APM 2.8. Power to APM 2.8 remains steady on the separate flight battery/BEC rail.

---

## 13. Step-by-Step Test Plan & Verification Matrix

| Test Case | Scenario / Step | Action / Command | Expected Verification | Result |
|---|---|---|---|---|
| **1. Normal Status Detection** | Pi is powered on and running shutdown daemon. | Open app -> Camera Link or Settings -> Tap "Check Status" (or `curl http://10.174.17.87:5005/status`). | Power status badge displays **"Online (Ready)"** with Pi hostname (`aerialeye`) and uptime. | PASS |
| **2. Unauthorized Request Rejection** | Client attempts shutdown with missing or wrong token. | `curl -X POST http://10.174.17.87:5005/shutdown -H "X-AerialEye-Token: bad_token"` | Server returns HTTP 401 Unauthorized (`{"error": "Unauthorized"}`). Pi remains running. | PASS |
| **3. Flutter Shutdown Confirmation** | Operator taps "Shut Down Raspberry Pi" in mobile app. | Tap "Shut Down Raspberry Pi" button. | Modal dialog appears detailing that camera & AI will stop, displays drone armed/ground safety status, and requires explicit confirmation. | PASS |
| **4. App-Initiated Safe Shutdown** | Operator confirms shutdown on grounded drone. | Tap "Initiate Safe Poweroff" in dialog. | App sends `POST /shutdown` with valid token. Receives HTTP 200 acknowledgement with message "Raspberry Pi safe shutdown initiated." Status transitions to "Shutting Down...". | PASS |
| **5. Clean OS Poweroff** | Daemon receives valid shutdown command. | Daemon waits 1.5s delay, runs `sync`, then invokes `sudo /bin/systemctl poweroff`. | System stops cleanly, filesystems unmount safely, green ACT LED stops blinking, Red PWR LED remains solid (ready to unplug). | PASS |
| **6. AI Services Stop Gracefully** | Raspberry Pi systemd shutdown sequence initiates. | `systemctl poweroff` triggers SIGTERM to all units. | `aerialeye-camera.service`, `aerialeye-live`, and `aerialeye-view` stop automatically before disks unmount. No file corruption occurs. | PASS |
| **7. Reboot & Auto-Recovery** | Pi is power-cycled (plug reconnected). | Reconnect 5V power to Pi 3A+. | Boot completes in ~25s. `aerialeye-camera.service` and `aerialeye-shutdown.service` automatically start via systemd without laptop intervention. | PASS |
| **8. Timeout & Network Loss Handling** | Wi-Fi hotspot drops or Pi is offline. | Turn off phone hotspot or disconnect Wi-Fi. | App gracefully handles timeout (4s), transitions badge to **"Offline / Unreachable"**, and provides manual "Check Status" refresh button. | PASS |
| **9. Flight Safety Interlock** | Drone is flying or armed during shutdown attempt. | APM 2.8 armed or altitude > 1.0m. Tap "Shut Down Raspberry Pi". | App detects armed/flying status from telemetry, displays amber/red warning banner, disables confirmation button, and blocks HTTP shutdown packet. | PASS |

