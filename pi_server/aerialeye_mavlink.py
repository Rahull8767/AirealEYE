#!/usr/bin/env python3
"""
AerialEYE MAVLink Router & Telemetry Bridge
Bidirectional relay between APM 2.8 flight controller (Serial UART/USB)
and AerialEYE Mobile App / Ground Control Station (UDP).

Designed for Raspberry Pi 3 Model A+ with ArduCopter 3.2.1 on APM 2.8.
Maintains single-owner serial access, handles MAVLink 1.0 / 2.0 framing,
prevents routing loops, auto-discovers mobile app UDP endpoint,
periodically requests telemetry streams (REQUEST_DATA_STREAM),
and writes live GPS & vehicle telemetry to shared memory (/dev/shm)
so camera and AI detection services have real-time GPS coordinates.
"""

import os
import sys
import time
import json
import socket
import select
import logging
import argparse
import tempfile
from typing import Optional, Tuple, Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [AerialEyeMAVLink] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("AerialEyeMAVLink")

# Determine shared memory path for Linux, with fallback to system temp
if os.path.exists("/dev/shm") and os.access("/dev/shm", os.W_OK):
    DEFAULT_SHM_TELEMETRY = "/dev/shm/aerialeye_telemetry.json"
else:
    DEFAULT_SHM_TELEMETRY = os.path.join(tempfile.gettempdir(), "aerialeye_telemetry.json")

# Candidate serial devices on Raspberry Pi
DEFAULT_SERIAL_CANDIDATES = [
    "/dev/serial0",   # Raspberry Pi primary UART (GPIO 14/15)
    "/dev/ttyAMA0",   # PL011 UART (when Bluetooth is disabled)
    "/dev/ttyACM0",   # APM 2.8 direct USB connection
    "/dev/ttyUSB0",   # FTDI / USB-to-UART bridge
]

# Flight mode mappings for ArduCopter 3.2.1
COPTER_MODES = {
    0: "STABILIZE",
    1: "ACRO",
    2: "ALT_HOLD",
    3: "AUTO",
    4: "GUIDED",
    5: "LOITER",
    6: "RTL",
    7: "CIRCLE",
    9: "LAND",
    11: "DRIFT",
    13: "SPORT",
    14: "FLIP",
    15: "AUTOTUNE",
    16: "POSHOLD",
    17: "BRAKE",
    18: "THROW",
}


class MavlinkTelemetryBridge:
    def __init__(
        self,
        serial_port: Optional[str] = None,
        baud_rate: int = 57600,
        udp_bind_host: str = "0.0.0.0",
        udp_port: int = 14550,
        target_ip: Optional[str] = None,
        target_port: int = 14550,
        telemetry_file: str = DEFAULT_SHM_TELEMETRY,
        stream_rate: int = 4,
        simulation: bool = False,
    ):
        self.requested_serial_port = serial_port
        self.baud_rate = baud_rate
        self.udp_bind_host = udp_bind_host
        self.udp_port = udp_port
        self.target_ip = target_ip
        self.target_port = target_port
        self.telemetry_file = telemetry_file
        self.stream_rate = stream_rate
        self.simulation = simulation

        self.running = False
        self.serial_conn = None
        self.udp_socket: Optional[socket.socket] = None
        self.last_client_addr: Optional[Tuple[str, int]] = (
            (target_ip, target_port) if target_ip else None
        )

        # Telemetry cache
        self.telemetry: Dict[str, Any] = {
            "connected": False,
            "last_heartbeat": 0.0,
            "system_id": 1,
            "component_id": 1,
            "vehicle_type": "Unknown",
            "autopilot": "ArduPilot",
            "flight_mode": "UNKNOWN",
            "armed": False,
            "lat": 0.0,
            "lon": 0.0,
            "alt": 0.0,
            "relative_alt": 0.0,
            "heading": 0.0,
            "groundspeed": 0.0,
            "airspeed": 0.0,
            "climb": 0.0,
            "roll": 0.0,
            "pitch": 0.0,
            "yaw": 0.0,
            "battery_voltage": 0.0,
            "battery_remaining": 0.0,
            "gps_fix": 0,
            "satellites": 0,
            "gps_time": 0.0,
            "last_status_text": "",
            "is_gps_valid": False,
            "gps_age_seconds": 999.0,
        }

        # Metrics
        self.serial_bytes_in = 0
        self.serial_bytes_out = 0
        self.udp_bytes_in = 0
        self.udp_bytes_out = 0
        self.packets_relayed_to_udp = 0
        self.packets_relayed_to_serial = 0
        self.last_stream_request_time = 0.0

    def find_serial_port(self) -> Optional[str]:
        """Resolves the best available serial port."""
        if self.requested_serial_port:
            if os.path.exists(self.requested_serial_port) or sys.platform == "win32":
                return self.requested_serial_port
            logger.warning(
                "Specified serial port %s not found on system.",
                self.requested_serial_port,
            )

        for candidate in DEFAULT_SERIAL_CANDIDATES:
            if os.path.exists(candidate):
                logger.info("Found serial candidate port: %s", candidate)
                return candidate

        return None

    def init_udp(self) -> bool:
        """Initializes the UDP socket for GCS / Flutter app communication."""
        try:
            self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            # Enable broadcast if needed
            self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.udp_socket.setblocking(False)
            self.udp_socket.bind((self.udp_bind_host, self.udp_port))
            logger.info(
                "UDP socket successfully bound on %s:%d",
                self.udp_bind_host,
                self.udp_port,
            )
            return True
        except Exception as e:
            logger.error("Failed to bind UDP socket on %s:%d: %s", self.udp_bind_host, self.udp_port, e)
            return False

    def init_serial(self) -> bool:
        """Initializes the physical serial MAVLink connection to APM 2.8."""
        if self.simulation:
            logger.info("Running in SIMULATION mode. Virtual MAVLink generator active.")
            return True

        from pymavlink import mavutil

        active_port = self.find_serial_port()
        if not active_port:
            logger.warning(
                "No physical serial port detected. Will retry periodically. (Candidates: %s)",
                ", ".join(DEFAULT_SERIAL_CANDIDATES),
            )
            return False

        try:
            logger.info("Opening serial port %s at %d baud...", active_port, self.baud_rate)
            # autoreconnect=True handles temporary USB unplug or serial reset
            self.serial_conn = mavutil.mavlink_connection(
                device=active_port,
                baud=self.baud_rate,
                autoreconnect=True,
                source_system=255,
                source_component=190,
            )
            logger.info("Serial port %s opened successfully.", active_port)
            return True
        except Exception as e:
            logger.error("Failed to open serial port %s: %s", active_port, e)
            self.serial_conn = None
            return False

    def request_data_streams(self) -> None:
        """
        Sends REQUEST_DATA_STREAM messages to APM 2.8.
        ArduCopter 3.2.1 requires stream requests to start sending GPS and sensor packets.
        """
        if self.serial_conn is None:
            return

        now = time.time()
        if now - self.last_stream_request_time < 5.0:
            return

        self.last_stream_request_time = now
        target_sys = self.telemetry.get("system_id", 1)
        target_comp = self.telemetry.get("component_id", 1)

        try:
            # Request all streams (stream_id = 0, MAV_DATA_STREAM_ALL)
            self.serial_conn.mav.request_data_stream_send(
                target_sys,
                target_comp,
                0,  # MAV_DATA_STREAM_ALL
                self.stream_rate,  # Rate in Hz
                1,  # Start sending
            )

            # Also explicitly request position stream (stream_id = 6, MAV_DATA_STREAM_POSITION)
            self.serial_conn.mav.request_data_stream_send(
                target_sys,
                target_comp,
                6,  # MAV_DATA_STREAM_POSITION
                self.stream_rate,
                1,
            )

            # Request extra sensors (stream_id = 10, MAV_DATA_STREAM_EXTRA1)
            self.serial_conn.mav.request_data_stream_send(
                target_sys,
                target_comp,
                10,  # MAV_DATA_STREAM_EXTRA1 (Attitude)
                self.stream_rate,
                1,
            )

            # Request VFR_HUD (stream_id = 11, MAV_DATA_STREAM_EXTRA2)
            self.serial_conn.mav.request_data_stream_send(
                target_sys,
                target_comp,
                11,  # MAV_DATA_STREAM_EXTRA2 (VFR_HUD)
                self.stream_rate,
                1,
            )
            logger.debug(
                "Sent REQUEST_DATA_STREAM (ALL, POSITION, EXTRA1, EXTRA2) at %d Hz to Sys=%d Comp=%d",
                self.stream_rate,
                target_sys,
                target_comp,
            )
        except Exception as e:
            logger.warning("Failed to send REQUEST_DATA_STREAM: %s", e)

    def update_telemetry_from_msg(self, msg: Any) -> None:
        """Parses MAVLink message fields to update onboard state."""
        msg_type = msg.get_type()
        now = time.time()

        if msg_type == "HEARTBEAT":
            self.telemetry["connected"] = True
            self.telemetry["last_heartbeat"] = now
            src_sys = msg.get_srcSystem()
            if src_sys != 0:
                self.telemetry["system_id"] = src_sys
            src_comp = msg.get_srcComponent()
            if src_comp != 0:
                self.telemetry["component_id"] = src_comp
            custom_mode = getattr(msg, "custom_mode", 0)
            self.telemetry["flight_mode"] = COPTER_MODES.get(
                custom_mode, f"MODE_{custom_mode}"
            )
            base_mode = getattr(msg, "base_mode", 0)
            self.telemetry["armed"] = bool(base_mode & 128)

        elif msg_type == "GLOBAL_POSITION_INT":
            self.telemetry["lat"] = msg.lat / 1e7
            self.telemetry["lon"] = msg.lon / 1e7
            self.telemetry["alt"] = msg.alt / 1000.0
            self.telemetry["relative_alt"] = msg.relative_alt / 1000.0
            self.telemetry["heading"] = msg.hdg / 100.0
            self.telemetry["gps_time"] = now
            if self.telemetry["lat"] != 0.0 or self.telemetry["lon"] != 0.0:
                self.telemetry["is_gps_valid"] = True

        elif msg_type == "GPS_RAW_INT":
            self.telemetry["gps_fix"] = getattr(msg, "fix_type", 0)
            self.telemetry["satellites"] = getattr(msg, "satellites_visible", 0)
            self.telemetry["gps_time"] = now
            if self.telemetry["gps_fix"] >= 2:
                self.telemetry["is_gps_valid"] = True

        elif msg_type == "ATTITUDE":
            import math
            self.telemetry["roll"] = round(math.degrees(msg.roll), 2)
            self.telemetry["pitch"] = round(math.degrees(msg.pitch), 2)
            self.telemetry["yaw"] = round(math.degrees(msg.yaw), 2)

        elif msg_type == "VFR_HUD":
            self.telemetry["airspeed"] = round(msg.airspeed, 2)
            self.telemetry["groundspeed"] = round(msg.groundspeed, 2)
            self.telemetry["climb"] = round(msg.climb, 2)
            if hasattr(msg, "alt"):
                baro_alt = round(float(msg.alt), 2)
                self.telemetry["alt"] = baro_alt
                # In GPS-free / AltHold operations, use barometer altitude for relative altitude
                if not self.telemetry.get("is_gps_valid", False) or self.telemetry.get("relative_alt", 0.0) == 0.0:
                    self.telemetry["relative_alt"] = baro_alt
            if hasattr(msg, "heading") and self.telemetry.get("heading", 0.0) == 0.0:
                self.telemetry["heading"] = float(msg.heading)

        elif msg_type == "SYS_STATUS":
            self.telemetry["battery_voltage"] = round(msg.voltage_battery / 1000.0, 2)
            self.telemetry["battery_remaining"] = msg.battery_remaining

        elif msg_type == "STATUSTEXT":
            text = getattr(msg, "text", "")
            if isinstance(text, bytes):
                text = text.decode("utf-8", errors="ignore")
            clean_text = text.strip("\x00").strip()
            self.telemetry["last_status_text"] = clean_text
            logger.info("Flight Controller StatusText: %s", clean_text)

    def write_shm_telemetry(self) -> None:
        """Writes live telemetry state atomically to shared memory for camera/AI services."""
        now = time.time()
        gps_time = self.telemetry.get("gps_time", 0.0)
        gps_age = round(now - gps_time, 2) if gps_time > 0 else 999.0
        self.telemetry["gps_age_seconds"] = gps_age

        # Check if GPS is stale (> 4 seconds without GPS position)
        if gps_age > 4.0:
            self.telemetry["is_gps_valid"] = False

        # Check connection staleness (> 4 seconds without heartbeat)
        hb_age = now - self.telemetry.get("last_heartbeat", 0.0)
        if hb_age > 4.0:
            self.telemetry["connected"] = False

        tmp_path = self.telemetry_file + ".tmp"
        try:
            with open(tmp_path, "w") as f:
                json.dump(self.telemetry, f, indent=2)
            os.replace(tmp_path, self.telemetry_file)
        except Exception as e:
            logger.debug("Failed writing telemetry to %s: %s", self.telemetry_file, e)

    def handle_udp_rx(self) -> None:
        """Receives incoming MAVLink packets from UDP (mobile app) and forwards to APM serial."""
        if not self.udp_socket:
            return

        try:
            while True:
                data, addr = self.udp_socket.recvfrom(2048)
                if not data:
                    break

                self.udp_bytes_in += len(data)

                # Remember sender address as the destination client
                if self.last_client_addr != addr:
                    self.last_client_addr = addr
                    logger.info("Auto-discovered active GCS/App client: %s:%d", addr[0], addr[1])

                # Forward packet to APM serial
                if self.serial_conn:
                    try:
                        # Write raw bytes to serial port
                        self.serial_conn.write(data)
                        self.serial_bytes_out += len(data)
                        self.packets_relayed_to_serial += 1
                    except Exception as e:
                        logger.warning("Serial write error: %s", e)
                elif self.simulation:
                    # In simulation mode, parse incoming commands and reply with COMMAND_ACK
                    try:
                        from pymavlink.dialects.v10 import ardupilotmega as mavlink1
                        mav_sim = mavlink1.MAVLink(
                            None,
                            srcSystem=self.telemetry.get("system_id", 1),
                            srcComponent=self.telemetry.get("component_id", 1),
                        )
                        for b in data:
                            msg = mav_sim.parse_char(bytes([b]))
                            if msg and msg.get_type() == "COMMAND_LONG":
                                cmd_id = getattr(msg, "command", 0)
                                ack = mav_sim.command_ack_encode(
                                    command=cmd_id,
                                    result=mavlink1.MAV_RESULT_ACCEPTED,
                                )
                                ack_bytes = ack.pack(mav_sim)
                                if self.udp_socket:
                                    self.udp_socket.sendto(ack_bytes, addr)
                                    self.udp_bytes_out += len(ack_bytes)
                                    self.packets_relayed_to_udp += 1
                                logger.info(
                                    "Simulated COMMAND_ACK for command %d sent to %s",
                                    cmd_id,
                                    addr,
                                )
                    except Exception as e:
                        logger.debug("Simulation command parse error: %s", e)

        except (BlockingIOError, socket.error):
            pass

    def handle_serial_rx(self) -> None:
        """Reads MAVLink packets from APM serial and forwards over UDP to the mobile app."""
        if not self.serial_conn:
            return

        try:
            while True:
                # recv_msg parses complete MAVLink frames
                msg = self.serial_conn.recv_msg()
                if msg is None:
                    break

                raw_bytes = msg.get_msgbuf()
                self.serial_bytes_in += len(raw_bytes)

                # Update internal telemetry
                self.update_telemetry_from_msg(msg)

                # Send REQUEST_DATA_STREAM if needed
                if msg.get_type() == "HEARTBEAT":
                    self.request_data_streams()

                # Relay packet to connected UDP client
                if self.udp_socket and self.last_client_addr:
                    try:
                        self.udp_socket.sendto(raw_bytes, self.last_client_addr)
                        self.udp_bytes_out += len(raw_bytes)
                        self.packets_relayed_to_udp += 1
                    except Exception as e:
                        logger.debug("UDP send error to %s: %s", self.last_client_addr, e)

        except Exception as e:
            logger.warning("Error reading from serial MAVLink connection: %s", e)

    def run_simulation_step(self) -> None:
        """Generates simulated telemetry for testing when hardware is absent."""
        from pymavlink.dialects.v10 import ardupilotmega as mavlink1

        now = time.time()
        mav = mavlink1.MAVLink(None, srcSystem=1, srcComponent=1)

        # Generate heartbeat every 1s
        if now - self.telemetry.get("last_heartbeat", 0.0) >= 1.0:
            hb = mav.heartbeat_encode(
                type=mavlink1.MAV_TYPE_QUADROTOR,
                autopilot=mavlink1.MAV_AUTOPILOT_ARDUPILOTMEGA,
                base_mode=mavlink1.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED | mavlink1.MAV_MODE_FLAG_SAFETY_ARMED,
                custom_mode=4,  # GUIDED
                system_status=mavlink1.MAV_STATE_ACTIVE,
                mavlink_version=3,
            )
            raw = hb.pack(mav)
            self.update_telemetry_from_msg(hb)
            if self.udp_socket and self.last_client_addr:
                try:
                    self.udp_socket.sendto(raw, self.last_client_addr)
                except Exception:
                    pass

        # Generate GPS position
        pos = mav.global_position_int_encode(
            time_boot_ms=int(now * 1000) & 0xFFFFFFFF,
            lat=int(12.9716 * 1e7),
            lon=int(77.5946 * 1e7),
            alt=30000,
            relative_alt=15000,
            vx=100,
            vy=0,
            vz=0,
            hdg=9000,
        )
        raw_pos = pos.pack(mav)
        self.update_telemetry_from_msg(pos)
        if self.udp_socket and self.last_client_addr:
            try:
                self.udp_socket.sendto(raw_pos, self.last_client_addr)
            except Exception:
                pass

    def run(self) -> None:
        """Main service loop."""
        self.running = True
        logger.info("Starting AerialEYE MAVLink Service...")
        logger.info("Telemetry output: %s", self.telemetry_file)

        if not self.init_udp():
            logger.error("Could not initialize UDP transport. Exiting.")
            return

        self.init_serial()

        last_status_log = time.time()
        last_shm_write = time.time()
        last_reconnect_attempt = time.time()

        try:
            while self.running:
                now = time.time()

                # Periodically attempt to reconnect serial if disconnected
                if not self.simulation and self.serial_conn is None:
                    if now - last_reconnect_attempt > 3.0:
                        last_reconnect_attempt = now
                        self.init_serial()

                # Process UDP incoming packets
                self.handle_udp_rx()

                # Process Serial incoming packets
                if self.serial_conn:
                    self.handle_serial_rx()
                elif self.simulation:
                    self.run_simulation_step()

                # Update shared memory telemetry at 5 Hz
                if now - last_shm_write >= 0.2:
                    last_shm_write = now
                    self.write_shm_telemetry()

                # Periodic status log every 10 seconds
                if now - last_status_log >= 10.0:
                    last_status_log = now
                    client_str = (
                        f"{self.last_client_addr[0]}:{self.last_client_addr[1]}"
                        if self.last_client_addr
                        else "None discovered yet"
                    )
                    logger.info(
                        "Status: Connected=%s | Mode=%s | Armed=%s | GPS=(%.5f, %.5f, alt=%.1fm) | "
                        "Client=%s | Relayed UDP->Serial=%d, Serial->UDP=%d",
                        self.telemetry["connected"],
                        self.telemetry["flight_mode"],
                        self.telemetry["armed"],
                        self.telemetry["lat"],
                        self.telemetry["lon"],
                        self.telemetry["relative_alt"],
                        client_str,
                        self.packets_relayed_to_serial,
                        self.packets_relayed_to_udp,
                    )

                time.sleep(0.01)

        except KeyboardInterrupt:
            logger.info("Received interrupt signal. Stopping MAVLink service...")
        finally:
            self.stop()

    def stop(self) -> None:
        self.running = False
        if self.udp_socket:
            try:
                self.udp_socket.close()
            except Exception:
                pass
            self.udp_socket = None

        if self.serial_conn:
            try:
                self.serial_conn.close()
            except Exception:
                pass
            self.serial_conn = None

        logger.info("AerialEYE MAVLink Service stopped.")


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="AerialEYE MAVLink Router & Telemetry Bridge for APM 2.8 and Raspberry Pi"
    )
    parser.add_argument(
        "--serial",
        type=str,
        default=None,
        help="Serial port for APM 2.8 (e.g. /dev/serial0, /dev/ttyACM0, /dev/ttyAMA0). Default: auto-detect",
    )
    parser.add_argument(
        "--baud",
        type=int,
        default=57600,
        help="Serial baud rate (default: 57600 for APM Telem, 115200 for USB)",
    )
    parser.add_argument(
        "--bind-host",
        type=str,
        default="0.0.0.0",
        help="UDP bind address (default: 0.0.0.0)",
    )
    parser.add_argument(
        "--udp-port",
        type=int,
        default=14550,
        help="Local UDP port to listen for GCS / AerialEYE App (default: 14550)",
    )
    parser.add_argument(
        "--target-ip",
        type=str,
        default=None,
        help="Specific target IP of AerialEYE app phone. If omitted, auto-discovered from incoming packets.",
    )
    parser.add_argument(
        "--target-port",
        type=int,
        default=14550,
        help="Target UDP port for AerialEYE app (default: 14550)",
    )
    parser.add_argument(
        "--telemetry-file",
        type=str,
        default=DEFAULT_SHM_TELEMETRY,
        help="Path to output live telemetry JSON for camera/detection server (default: /dev/shm/aerialeye_telemetry.json)",
    )
    parser.add_argument(
        "--stream-rate",
        type=int,
        default=4,
        help="Telemetry stream request rate in Hz (default: 4)",
    )
    parser.add_argument(
        "--sim",
        action="store_true",
        help="Run in virtual simulation mode without physical serial hardware",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_arguments()
    bridge = MavlinkTelemetryBridge(
        serial_port=args.serial,
        baud_rate=args.baud,
        udp_bind_host=args.bind_host,
        udp_port=args.udp_port,
        target_ip=args.target_ip,
        target_port=args.target_port,
        telemetry_file=args.telemetry_file,
        stream_rate=args.stream_rate,
        simulation=args.sim,
    )
    bridge.run()
