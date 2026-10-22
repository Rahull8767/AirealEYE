#!/usr/bin/env python3
"""
AerialEYE Raspberry Pi Safe Shutdown Daemon
A lightweight, secure, authenticated HTTP service that executes clean system shutdown
(equivalent to `systemctl poweroff`) upon receiving an authorized request from the AerialEYE Flutter app.

Runs as an unprivileged user (e.g. rahul) using a restricted sudoers rule.
Zero external dependencies (uses standard library http.server).
"""

import os
import sys
import time
import json
import socket
import logging
import argparse
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [AerialEyeShutdown] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("AerialEyeShutdown")

# Default configuration paths and settings
DEFAULT_PORT = 5005
DEFAULT_HOST = "0.0.0.0"
DEFAULT_TOKEN_FILE = "/etc/aerialeye/shutdown.conf"
USER_TOKEN_FILE = os.path.expanduser("~/.aerialeye_shutdown.conf")
DEFAULT_DEV_TOKEN = "aerialeye-safe-shutdown-secret-2026"

# Global state
shutdown_in_progress = False
shutdown_timer: Optional[threading.Timer] = None
start_time = time.time()


def load_auth_token(cli_token: Optional[str] = None) -> str:
    """
    Loads authentication token in order of precedence:
    1. CLI argument (--token)
    2. Environment variable (AERIALEYE_SHUTDOWN_TOKEN)
    3. System config file (/etc/aerialeye/shutdown.conf)
    4. User config file (~/.aerialeye_shutdown.conf)
    5. Default development token (with warning)
    """
    if cli_token:
        return cli_token.strip()

    env_token = os.environ.get("AERIALEYE_SHUTDOWN_TOKEN")
    if env_token:
        return env_token.strip()

    for path in [DEFAULT_TOKEN_FILE, USER_TOKEN_FILE]:
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    content = f.read().strip()
                    # Handle KEY=VALUE or raw token
                    if "=" in content:
                        for line in content.splitlines():
                            line = line.strip()
                            if line.startswith("AERIALEYE_SHUTDOWN_TOKEN="):
                                return line.split("=", 1)[1].strip().strip('"').strip("'")
                    elif content:
                        return content
            except Exception as e:
                logger.warning("Could not read token from %s: %s", path, e)

    logger.warning("No token configuration file found. Using default development secret.")
    logger.warning("For production security, set AERIALEYE_SHUTDOWN_TOKEN or create %s", DEFAULT_TOKEN_FILE)
    return DEFAULT_DEV_TOKEN


def is_private_ip(client_ip: str) -> bool:
    """Verifies client IP belongs to RFC 1918 private subnets or loopback."""
    if client_ip in ("127.0.0.1", "::1", "localhost"):
        return True
    try:
        parts = [int(p) for p in client_ip.split(".")]
        if len(parts) != 4:
            return False
        # 10.0.0.0/8 (Hotspot default)
        if parts[0] == 10:
            return True
        # 172.16.0.0/12
        if parts[0] == 172 and 16 <= parts[1] <= 31:
            return True
        # 192.168.0.0/16 (Home Wi-Fi default)
        if parts[0] == 192 and parts[1] == 168:
            return True
    except Exception:
        return False
    return False


def execute_system_shutdown(dry_run: bool = False) -> None:
    """Executes clean system shutdown via systemctl poweroff."""
    logger.critical("Initiating clean Raspberry Pi poweroff...")
    if dry_run:
        logger.info("[DRY-RUN] System shutdown command skipped (dry-run mode active).")
        return

    # Flush all disk caches before shutting down
    try:
        subprocess.run(["sync"], check=False)
    except Exception:
        pass

    # Execute systemctl poweroff
    commands = [
        ["sudo", "/bin/systemctl", "poweroff"],
        ["sudo", "systemctl", "poweroff"],
        ["/bin/systemctl", "poweroff"],
        ["sudo", "/sbin/shutdown", "-h", "now"],
    ]

    for cmd in commands:
        try:
            logger.info("Executing shutdown command: %s", " ".join(cmd))
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if res.returncode == 0:
                logger.info("Shutdown command accepted by system.")
                return
            else:
                logger.warning("Command %s failed: %s", " ".join(cmd), res.stderr)
        except Exception as e:
            logger.warning("Could not run %s: %s", " ".join(cmd), e)

    logger.critical("All shutdown commands failed. Check sudoers permissions for systemctl poweroff.")


class ShutdownRequestHandler(BaseHTTPRequestHandler):
    auth_token: str = DEFAULT_DEV_TOKEN
    dry_run: bool = False
    allow_any_ip: bool = False

    def log_message(self, format, *args):
        logger.info("%s - %s", self.address_string(), format % args)

    def send_json_response(self, status_code: int, data: dict):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-AerialEye-Token")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        """Handle CORS pre-flight requests."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-AerialEye-Token")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Connection", "close")
        self.end_headers()

    def do_GET(self):
        """Health and status check endpoint."""
        client_ip = self.client_address[0]
        if not self.allow_any_ip and not is_private_ip(client_ip):
            self.send_json_response(403, {
                "error": "Forbidden: Access restricted to local private network.",
                "client_ip": client_ip,
            })
            return

        if self.path in ("/status", "/health", "/"):
            uptime = round(time.time() - start_time, 1)
            hostname = socket.gethostname()
            self.send_json_response(200, {
                "status": "online",
                "service": "aerialeye-shutdown",
                "hostname": hostname,
                "uptime_seconds": uptime,
                "shutdown_in_progress": shutdown_in_progress,
                "timestamp": time.time(),
            })
        else:
            self.send_json_response(404, {"error": "Endpoint not found."})

    def do_POST(self):
        """Authenticated shutdown initiation endpoint."""
        global shutdown_in_progress, shutdown_timer

        client_ip = self.client_address[0]
        if not self.allow_any_ip and not is_private_ip(client_ip):
            logger.warning("Rejected shutdown request from non-private IP: %s", client_ip)
            self.send_json_response(403, {
                "error": "Forbidden: Access restricted to local private network.",
                "client_ip": client_ip,
            })
            return

        if self.path != "/shutdown":
            self.send_json_response(404, {"error": "Endpoint not found."})
            return

        # Always consume incoming body if present to avoid TCP RST on connection close
        body_json = {}
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 0:
            try:
                body_raw = self.rfile.read(content_length)
                body_json = json.loads(body_raw.decode("utf-8"))
            except Exception:
                pass

        # 1. Validate Authentication Token
        provided_token = None

        # Check X-AerialEye-Token header
        if "X-AerialEye-Token" in self.headers:
            provided_token = self.headers["X-AerialEye-Token"].strip()
        # Check Authorization: Bearer <token>
        elif "Authorization" in self.headers:
            auth_header = self.headers["Authorization"].strip()
            if auth_header.lower().startswith("bearer "):
                provided_token = auth_header[7:].strip()
        elif body_json:
            provided_token = body_json.get("token") or body_json.get("secret")

        if not provided_token or provided_token != self.auth_token:
            logger.warning("Unauthorized shutdown attempt from %s (invalid token)", client_ip)
            self.send_json_response(401, {
                "error": "Unauthorized: Invalid or missing authentication token.",
                "success": False,
            })
            return

        # 2. Check if shutdown is already underway
        if shutdown_in_progress:
            logger.warning("Duplicate shutdown request received while shutdown already active.")
            self.send_json_response(409, {
                "error": "Shutdown already in progress.",
                "status": "shutting_down",
                "success": True,
            })
            return

        # 3. Accept and acknowledge request
        shutdown_in_progress = True
        logger.warning("AUTHORIZED SHUTDOWN REQUEST ACCEPTED from %s", client_ip)

        # Respond immediately to client BEFORE pulling the power
        self.send_json_response(200, {
            "status": "acknowledged",
            "message": "Raspberry Pi clean poweroff initiated. Services will terminate cleanly in 1.5 seconds.",
            "success": True,
            "dry_run": self.dry_run,
            "timestamp": time.time(),
        })

        # 4. Schedule poweroff after response is fully transmitted (1.5s delay)
        shutdown_timer = threading.Timer(1.5, execute_system_shutdown, args=[self.dry_run])
        shutdown_timer.daemon = True
        shutdown_timer.start()


def run_server(
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    token: Optional[str] = None,
    dry_run: bool = False,
    allow_any_ip: bool = False,
):
    active_token = load_auth_token(token)

    ShutdownRequestHandler.auth_token = active_token
    ShutdownRequestHandler.dry_run = dry_run
    ShutdownRequestHandler.allow_any_ip = allow_any_ip

    server = HTTPServer((host, port), ShutdownRequestHandler)
    logger.info("==========================================================")
    logger.info(" AerialEYE Raspberry Pi Safe Shutdown Daemon")
    logger.info(" Listening on http://%s:%d", host, port)
    logger.info(" Status endpoint:   GET  http://%s:%d/status", host, port)
    logger.info(" Shutdown endpoint: POST http://%s:%d/shutdown", host, port)
    logger.info(" Dry-run mode:      %s", dry_run)
    logger.info("==========================================================")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down HTTP daemon...")
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description="AerialEYE Raspberry Pi Safe Shutdown Daemon")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"HTTP port (default: {DEFAULT_PORT})")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST, help=f"Bind host (default: {DEFAULT_HOST})")
    parser.add_argument("--token", type=str, default=None, help="Explicit authentication token")
    parser.add_argument("--dry-run", action="store_true", help="Simulate shutdown without halting system")
    parser.add_argument("--allow-any-ip", action="store_true", help="Allow connections outside private subnets (dev only)")
    args = parser.parse_args()

    run_server(
        host=args.host,
        port=args.port,
        token=args.token,
        dry_run=args.dry_run,
        allow_any_ip=args.allow_any_ip,
    )


if __name__ == "__main__":
    main()
