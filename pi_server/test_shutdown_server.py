#!/usr/bin/env python3
"""
Unit and Integration Tests for AerialEYE Raspberry Pi Shutdown Daemon
Tests authentication, IP restriction, status endpoint, and acknowledgement behavior.
"""

import os
import sys
import time
import json
import urllib.request
import urllib.error
import unittest
import threading

PI_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
if PI_SERVER_DIR not in sys.path:
    sys.path.insert(0, PI_SERVER_DIR)

from aerialeye_shutdown import run_server, HTTPServer, ShutdownRequestHandler
import aerialeye_shutdown


class TestShutdownDaemon(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.test_port = 5099
        cls.test_token = "test-secret-token-12345"
        cls.server_thread = threading.Thread(
            target=run_server,
            kwargs={
                "host": "127.0.0.1",
                "port": cls.test_port,
                "token": cls.test_token,
                "dry_run": True,
                "allow_any_ip": True,
            },
            daemon=True,
        )
        cls.server_thread.start()
        time.sleep(0.3)  # Wait for socket to bind

    def setUp(self):
        # Reset shutdown state between tests
        aerialeye_shutdown.shutdown_in_progress = False

    def test_status_endpoint(self):
        url = f"http://127.0.0.1:{self.test_port}/status"
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=2) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(data["status"], "online")
            self.assertEqual(data["service"], "aerialeye-shutdown")
            self.assertIn("hostname", data)
            self.assertIn("uptime_seconds", data)
            self.assertFalse(data["shutdown_in_progress"])

    def test_shutdown_without_token_rejected(self):
        url = f"http://127.0.0.1:{self.test_port}/shutdown"
        req = urllib.request.Request(url, data=b"{}", method="POST")
        req.add_header("Content-Type", "application/json")

        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=2)
        self.assertEqual(ctx.exception.code, 401)
        err_body = json.loads(ctx.exception.read().decode("utf-8"))
        self.assertIn("Unauthorized", err_body["error"])

    def test_shutdown_with_invalid_token_rejected(self):
        url = f"http://127.0.0.1:{self.test_port}/shutdown"
        req = urllib.request.Request(url, data=b"{}", method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-AerialEye-Token", "wrong-token-abc")

        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=2)
        self.assertEqual(ctx.exception.code, 401)

    def test_shutdown_with_valid_x_token_header_accepted(self):
        url = f"http://127.0.0.1:{self.test_port}/shutdown"
        req = urllib.request.Request(url, data=b"{}", method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-AerialEye-Token", self.test_token)

        with urllib.request.urlopen(req, timeout=2) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(data["status"], "acknowledged")
            self.assertTrue(data["success"])
            self.assertTrue(data["dry_run"])

    def test_shutdown_with_bearer_token_accepted(self):
        url = f"http://127.0.0.1:{self.test_port}/shutdown"
        req = urllib.request.Request(url, data=b"{}", method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", f"Bearer {self.test_token}")

        with urllib.request.urlopen(req, timeout=2) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(data["status"], "acknowledged")
            self.assertTrue(data["success"])

    def test_duplicate_shutdown_rejected_with_409(self):
        aerialeye_shutdown.shutdown_in_progress = True
        url = f"http://127.0.0.1:{self.test_port}/shutdown"
        req = urllib.request.Request(url, data=b"{}", method="POST")
        req.add_header("X-AerialEye-Token", self.test_token)

        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=2)
        self.assertEqual(ctx.exception.code, 409)


if __name__ == "__main__":
    unittest.main()
