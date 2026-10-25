#!/usr/bin/env python3
"""
Test Suite for AerialEYE Raspberry Pi Server Components
Tests MAVLink parsing, bidirectional routing, shared memory IPC,
GPS telemetry enrichment, and Flask REST/streaming endpoints.
"""

import os
import sys
import time
import json
import socket
import unittest
import tempfile
import threading
from typing import Dict, Any

# Ensure pi_server directory is in sys.path
PI_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
if PI_SERVER_DIR not in sys.path:
    sys.path.insert(0, PI_SERVER_DIR)

from aerialeye_mavlink import MavlinkTelemetryBridge
import aerialeye_view


class TestMavlinkTelemetryBridge(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.telemetry_file = os.path.join(self.temp_dir, "test_telemetry.json")

    def tearDown(self):
        if os.path.exists(self.telemetry_file):
            try:
                os.remove(self.telemetry_file)
            except Exception:
                pass
        tmp = self.telemetry_file + ".tmp"
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except Exception:
                pass

    def test_bridge_initialization(self):
        bridge = MavlinkTelemetryBridge(
            udp_port=14599,
            telemetry_file=self.telemetry_file,
            simulation=True,
        )
        self.assertEqual(bridge.udp_port, 14599)
        self.assertEqual(bridge.telemetry["connected"], False)
        self.assertEqual(bridge.telemetry["armed"], False)
        self.assertEqual(bridge.telemetry["is_gps_valid"], False)

    def test_telemetry_message_parsing(self):
        from pymavlink.dialects.v10 import ardupilotmega as mavlink1

        bridge = MavlinkTelemetryBridge(
            telemetry_file=self.telemetry_file,
            simulation=True,
        )
        mav = mavlink1.MAVLink(None, srcSystem=1, srcComponent=1)

        # 1. Test Heartbeat (Armed, GUIDED mode)
        hb = mav.heartbeat_encode(
            type=mavlink1.MAV_TYPE_QUADROTOR,
            autopilot=mavlink1.MAV_AUTOPILOT_ARDUPILOTMEGA,
            base_mode=mavlink1.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED | mavlink1.MAV_MODE_FLAG_SAFETY_ARMED,
            custom_mode=4,  # GUIDED
            system_status=mavlink1.MAV_STATE_ACTIVE,
            mavlink_version=3,
        )
        raw = hb.pack(mav)
        parsed_hb = mav.parse_buffer(raw)[0]
        bridge.update_telemetry_from_msg(parsed_hb)
        self.assertTrue(bridge.telemetry["connected"])
        self.assertTrue(bridge.telemetry["armed"])
        self.assertEqual(bridge.telemetry["flight_mode"], "GUIDED")
        self.assertEqual(bridge.telemetry["system_id"], 1)

        # 2. Test Global Position Int (GPS coordinates & altitude)
        pos = mav.global_position_int_encode(
            time_boot_ms=10000,
            lat=int(12.971598 * 1e7),
            lon=int(77.594562 * 1e7),
            alt=920000,           # 920.0m MSL
            relative_alt=15500,   # 15.5m AGL
            vx=150,               # 1.5 m/s
            vy=0,
            vz=0,
            hdg=18000,            # 180.0 deg
        )
        bridge.update_telemetry_from_msg(pos)
        self.assertAlmostEqual(bridge.telemetry["lat"], 12.971598, places=5)
        self.assertAlmostEqual(bridge.telemetry["lon"], 77.594562, places=5)
        self.assertAlmostEqual(bridge.telemetry["alt"], 920.0, places=1)
        self.assertAlmostEqual(bridge.telemetry["relative_alt"], 15.5, places=1)
        self.assertAlmostEqual(bridge.telemetry["heading"], 180.0, places=1)
        self.assertTrue(bridge.telemetry["is_gps_valid"])

        # 3. Test GPS Raw Int (Fix type & Satellites)
        gps = mav.gps_raw_int_encode(
            time_usec=1000000,
            fix_type=3,  # 3D Fix
            lat=int(12.971598 * 1e7),
            lon=int(77.594562 * 1e7),
            alt=920000,
            eph=150,
            epv=200,
            vel=150,
            cog=18000,
            satellites_visible=14,
        )
        bridge.update_telemetry_from_msg(gps)
        self.assertEqual(bridge.telemetry["gps_fix"], 3)
        self.assertEqual(bridge.telemetry["satellites"], 14)

        # 4. Test Sys Status (Battery)
        sys_status = mav.sys_status_encode(
            onboard_control_sensors_present=0,
            onboard_control_sensors_enabled=0,
            onboard_control_sensors_health=0,
            load=500,
            voltage_battery=12450,  # 12.45V
            current_battery=1500,
            battery_remaining=85,   # 85%
            drop_rate_comm=0,
            errors_comm=0,
            errors_count1=0,
            errors_count2=0,
            errors_count3=0,
            errors_count4=0,
        )
        bridge.update_telemetry_from_msg(sys_status)
        self.assertAlmostEqual(bridge.telemetry["battery_voltage"], 12.45, places=2)
        self.assertEqual(bridge.telemetry["battery_remaining"], 85)

        # 5. Test StatusText (Pre-arm safety message)
        text_bytes = b"PreArm: GPS HDOP 1.4\x00"
        status_msg = mav.statustext_encode(severity=mavlink1.MAV_SEVERITY_NOTICE, text=text_bytes)
        bridge.update_telemetry_from_msg(status_msg)
        self.assertIn("PreArm: GPS HDOP 1.4", bridge.telemetry["last_status_text"])

    def test_shared_memory_telemetry_writer(self):
        bridge = MavlinkTelemetryBridge(
            telemetry_file=self.telemetry_file,
            simulation=True,
        )
        bridge.telemetry["connected"] = True
        bridge.telemetry["last_heartbeat"] = time.time()
        bridge.telemetry["lat"] = 13.0827
        bridge.telemetry["lon"] = 80.2707
        bridge.telemetry["relative_alt"] = 25.0
        bridge.telemetry["gps_time"] = time.time()
        bridge.telemetry["is_gps_valid"] = True

        bridge.write_shm_telemetry()
        self.assertTrue(os.path.exists(self.telemetry_file))

        with open(self.telemetry_file, "r") as f:
            saved = json.load(f)

        self.assertEqual(saved["connected"], True)
        self.assertAlmostEqual(saved["lat"], 13.0827, places=4)
        self.assertAlmostEqual(saved["lon"], 80.2707, places=4)
        self.assertAlmostEqual(saved["relative_alt"], 25.0, places=1)
        self.assertTrue(saved["is_gps_valid"])
        self.assertLess(saved["gps_age_seconds"], 2.0)

    def test_udp_socket_binding_and_client_discovery(self):
        # Pick an unreserved ephemeral port
        test_port = 14598
        bridge = MavlinkTelemetryBridge(
            udp_port=test_port,
            telemetry_file=self.telemetry_file,
            simulation=True,
        )
        self.assertTrue(bridge.init_udp())

        # Send test datagram to simulate Flutter app connecting
        test_sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        test_sender.sendto(b"\xfe\x00\x00\xff\xbe\x00\x00\x00", ("127.0.0.1", test_port))

        time.sleep(0.05)
        bridge.handle_udp_rx()

        self.assertIsNotNone(bridge.last_client_addr)
        self.assertEqual(bridge.last_client_addr[0], "127.0.0.1")
        self.assertGreater(bridge.udp_bytes_in, 0)

        test_sender.close()
        bridge.stop()

    def test_motor_test_command_and_ack(self):
        """Verifies MAV_CMD_DO_MOTOR_TEST (209) packet reception and COMMAND_ACK generation."""
        from pymavlink.dialects.v10 import ardupilotmega as mavlink1

        test_port = 14597
        bridge = MavlinkTelemetryBridge(
            udp_port=test_port,
            telemetry_file=self.telemetry_file,
            simulation=True,
        )
        self.assertTrue(bridge.init_udp())

        client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client_socket.bind(("127.0.0.1", 0))
        client_socket.settimeout(1.0)

        mav = mavlink1.MAVLink(None, srcSystem=255, srcComponent=190)
        # Encode MAV_CMD_DO_MOTOR_TEST (command 209)
        cmd = mav.command_long_encode(
            target_system=1,
            target_component=1,
            command=209,  # MAV_CMD_DO_MOTOR_TEST
            confirmation=0,
            param1=1.0,   # Motor 1
            param2=0.0,   # Throttle percentage (0)
            param3=15.0,  # 15% throttle
            param4=3.0,   # 3 seconds
            param5=1.0,   # Motor count = 1
            param6=0.0,
            param7=0.0,
        )
        cmd_bytes = cmd.pack(mav)

        client_socket.sendto(cmd_bytes, ("127.0.0.1", test_port))
        time.sleep(0.05)
        bridge.handle_udp_rx()

        # Receive the COMMAND_ACK
        data, _ = client_socket.recvfrom(2048)
        mav_rx = mavlink1.MAVLink(None, srcSystem=1, srcComponent=1)
        ack_msg = None
        for b in data:
            m = mav_rx.parse_char(bytes([b]))
            if m and m.get_type() == "COMMAND_ACK":
                ack_msg = m
                break

        self.assertIsNotNone(ack_msg, "Failed to receive COMMAND_ACK for motor test")
        self.assertEqual(ack_msg.command, 209)
        self.assertEqual(ack_msg.result, mavlink1.MAV_RESULT_ACCEPTED)

        client_socket.close()
        bridge.stop()


class TestFlaskViewEndpoints(unittest.TestCase):
    def setUp(self):
        self.app = aerialeye_view.app.test_client()
        self.app.testing = True

    def test_status_endpoint(self):
        response = self.app.get("/status")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data["status"], "online")
        self.assertIn("has_camera_frame", data)
        self.assertIn("active_detections", data)
        self.assertIn("mavlink_connected", data)
        self.assertIn("gps_fix_valid", data)

    def test_detections_endpoint(self):
        response = self.app.get("/detections")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn("timestamp", data)
        self.assertIn("count", data)
        self.assertIn("detections", data)

    def test_telemetry_endpoint(self):
        response = self.app.get("/telemetry")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn("timestamp", data)
        self.assertIn("telemetry", data)

    def test_web_index(self):
        response = self.app.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"AerialEYE Live Monitoring", response.data)


if __name__ == "__main__":
    unittest.main()
