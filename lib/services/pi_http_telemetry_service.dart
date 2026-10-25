import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/services/drone_service.dart';

/// Service responsible for polling and deserializing telemetry from the
/// onboard Raspberry Pi 3A+ Flask HTTP API (e.g., http://10.174.17.87:8081).
class PiHttpTelemetryService {
  MavlinkConnectionConfig _config;

  final _telemetryController = StreamController<DroneTelemetry>.broadcast();
  DroneTelemetry _currentTelemetry = DroneTelemetry.initial();

  final _stateController = StreamController<DroneConnectionState>.broadcast();
  DroneConnectionState _connectionState = DroneConnectionState.disconnected;

  final _diagnosticsController =
      StreamController<ConnectionDiagnostics>.broadcast();
  ConnectionDiagnostics _currentDiagnostics = ConnectionDiagnostics.initial();

  Stream<DroneTelemetry> get telemetryStream => _telemetryController.stream;
  DroneTelemetry get currentTelemetry => _currentTelemetry;

  Stream<DroneConnectionState> get connectionStateStream =>
      _stateController.stream;
  DroneConnectionState get connectionState => _connectionState;

  Stream<ConnectionDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;
  ConnectionDiagnostics get currentDiagnostics => _currentDiagnostics;

  Timer? _pollingTimer;
  Timer? _staleCheckTimer;
  HttpClient? _httpClient;
  bool _isPollingActive = false;
  bool _isRequestInFlight = false;
  DateTime? _lastSuccessTime;
  int _consecutiveFailures = 0;
  int _telemetryPacketsReceived = 0;

  // Diagnostics and ring log buffer
  final List<String> _recentLogs = [];
  static const int _maxRecentLogs = 50;

  PiHttpTelemetryService({MavlinkConnectionConfig? config})
      : _config = config ?? MavlinkConnectionConfig.defaultConfig() {
    _httpClient = HttpClient()
      ..connectionTimeout = Duration(seconds: _config.httpTimeoutSeconds);
  }

  void updateConfig(MavlinkConnectionConfig newConfig) {
    final baseUrlChanged = _config.httpBaseUrl != newConfig.httpBaseUrl;
    final intervalChanged =
        _config.httpPollingIntervalMs != newConfig.httpPollingIntervalMs;
    final timeoutChanged =
        _config.httpTimeoutSeconds != newConfig.httpTimeoutSeconds;

    _config = newConfig;

    if (timeoutChanged) {
      _httpClient?.close(force: true);
      _httpClient = HttpClient()
        ..connectionTimeout = Duration(seconds: _config.httpTimeoutSeconds);
    }

    if (_isPollingActive && (baseUrlChanged || intervalChanged)) {
      _restartPolling();
    }
  }

  void _logDiagnostic(String message) {
    final timeStr = DateTime.now().toIso8601String().substring(11, 19);
    final formatted = '[$timeStr] $message';

    if (_recentLogs.length >= _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }
    _recentLogs.add(formatted);

    if (_config.debugLogging) {
      debugPrint('[PI-HTTP] $message');
    }
  }

  void _setConnectionState(DroneConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _stateController.add(_connectionState);
      _logDiagnostic(
          'Connection state transitioned to: ${newState.name.toUpperCase()}');
      _updateDiagnostics();
    }
  }

  void _updateDiagnostics({
    int? latencyMs,
    String? lastError,
  }) {
    _currentDiagnostics = _currentDiagnostics.copyWith(
      rawDatagramsReceived: _telemetryPacketsReceived,
      mavlinkFramesReceived: _telemetryPacketsReceived,
      vehicleType: 'APM 2.8 via Flask API',
      autopilotType: 'ArduCopter 3.2.1',
      mavlinkProtocolVersion: 'Flask REST (HTTP/JSON)',
      packetsPerSecond: _isPollingActive ? 1.0 : 0.0,
      packetsDropped: _consecutiveFailures,
      lastDatagramTime: _lastSuccessTime,
      lastPacketTime: _lastSuccessTime,
      lastHeartbeatTime: _lastSuccessTime,
      lastRawSender: _config.httpBaseUrl,
      lastReceivedMessageType: 'JSON_TELEMETRY',
      socketStatus: _isPollingActive ? 'HTTP POLLING' : 'IDLE',
      recentLogs: List.unmodifiable(_recentLogs),
    );
    _diagnosticsController.add(_currentDiagnostics);
  }

  /// Starts polling the Raspberry Pi Flask telemetry endpoint.
  void start() {
    if (_isPollingActive) return;
    _isPollingActive = true;
    _consecutiveFailures = 0;
    _telemetryPacketsReceived = 0;
    _lastSuccessTime = null;

    _setConnectionState(DroneConnectionState.connecting);
    _logDiagnostic(
        'Starting HTTP telemetry polling on ${_config.httpBaseUrl} (every ${_config.httpPollingIntervalMs}ms)');

    _pollCycle();

    _pollingTimer = Timer.periodic(
      Duration(milliseconds: _config.httpPollingIntervalMs),
      (_) => _pollCycle(),
    );

    // Watchdog timer checking for telemetry staleness (> 3.5s without update)
    _staleCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkLiveness(),
    );
  }

  void _restartPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      Duration(milliseconds: _config.httpPollingIntervalMs),
      (_) => _pollCycle(),
    );
  }

  /// Stops all active HTTP polling and resets connection state to disconnected.
  void stop() {
    _isPollingActive = false;
    _isRequestInFlight = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _staleCheckTimer?.cancel();
    _staleCheckTimer = null;

    _setConnectionState(DroneConnectionState.disconnected);

    _currentTelemetry = DroneTelemetry.initial();
    _telemetryController.add(_currentTelemetry);

    _logDiagnostic('HTTP telemetry polling stopped. State reset to disconnected.');
    _updateDiagnostics();
  }

  /// Single poll execution: polls /telemetry.
  Future<void> _pollCycle() async {
    if (!_isPollingActive || _isRequestInFlight) {
      return; // Skip overlapping requests
    }

    _isRequestInFlight = true;
    final stopwatch = Stopwatch()..start();

    try {
      final client = _httpClient ?? HttpClient();
      final cleanBaseUrl = _config.httpBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$cleanBaseUrl/telemetry');

      final request = await client
          .getUrl(uri)
          .timeout(Duration(seconds: _config.httpTimeoutSeconds));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request
          .close()
          .timeout(Duration(seconds: _config.httpTimeoutSeconds));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final dynamic decoded = jsonDecode(body);

        if (decoded is Map<String, dynamic>) {
          _handleSuccessfulPayload(decoded, stopwatch.elapsedMilliseconds);
        } else {
          _handlePollFailure('Invalid JSON response: expected JSON object');
        }
      } else {
        _handlePollFailure('Server returned HTTP ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      _handlePollFailure('HTTP request failed: $e');
    } finally {
      _isRequestInFlight = false;
    }
  }

  void _handleSuccessfulPayload(Map<String, dynamic> data, int latencyMs) {
    final now = DateTime.now();
    _lastSuccessTime = now;
    _consecutiveFailures = 0;
    _telemetryPacketsReceived++;

    // Check if flight controller reported connected / heartbeat
    final bool fcConnected = data['connected'] as bool? ?? false;
    final bool fcHeartbeat = data['heartbeat'] as bool? ?? false;

    if (!fcConnected || !fcHeartbeat) {
      if (_connectionState != DroneConnectionState.udpPacketsNoMavlink &&
          _connectionState != DroneConnectionState.mavlinkNoHeartbeat) {
        _setConnectionState(DroneConnectionState.mavlinkNoHeartbeat);
        _logDiagnostic(
            'API reachable, but APM 2.8 FC heartbeat is missing (connected=$fcConnected, heartbeat=$fcHeartbeat)');
      }
    } else {
      if (_connectionState != DroneConnectionState.connected) {
        _setConnectionState(DroneConnectionState.connected);
        _logDiagnostic('Connected: Active APM 2.8 telemetry stream received via HTTP.');
      }
    }

    _currentTelemetry = parseJson(
      data,
      previousTelemetry: _currentTelemetry,
      receivedTime: now,
    );
    _telemetryController.add(_currentTelemetry);

    _updateDiagnostics(latencyMs: latencyMs);
  }

  void _handlePollFailure(String reason) {
    _consecutiveFailures++;
    _logDiagnostic('[POLL ERROR] $reason (Consecutive failures: $_consecutiveFailures)');

    // After 3 consecutive failed polls or > 4s, mark stale/degraded
    if (_consecutiveFailures >= 3) {
      if (_connectionState == DroneConnectionState.connected) {
        _setConnectionState(DroneConnectionState.telemetryStale);
        _currentTelemetry = _currentTelemetry.copyWith(isStale: true);
        _telemetryController.add(_currentTelemetry);
      } else if (_connectionState == DroneConnectionState.connecting) {
        _setConnectionState(DroneConnectionState.error);
      }
    }

    _updateDiagnostics(lastError: reason);
  }

  void _checkLiveness() {
    if (!_isPollingActive || _lastSuccessTime == null) return;

    final elapsedSinceLastSuccess =
        DateTime.now().difference(_lastSuccessTime!).inMilliseconds;

    if (elapsedSinceLastSuccess > 3500 &&
        _connectionState == DroneConnectionState.connected) {
      _logDiagnostic('Telemetry watchdog: no updates received for ${elapsedSinceLastSuccess}ms. Marking stale.');
      _setConnectionState(DroneConnectionState.telemetryStale);
      _currentTelemetry = _currentTelemetry.copyWith(isStale: true);
      _telemetryController.add(_currentTelemetry);
    }
  }

  /// Parses Flask JSON response into standard [DroneTelemetry].
  ///
  /// Conforms strictly to mapping rules:
  /// - `mode` -> `flightMode`
  /// - `armed` -> `armed`
  /// - `relative_altitude_m` -> `relativeAltitude`
  /// - `altitude_m` -> `altitude`
  /// - `heading_deg` -> `heading` and `yaw`
  /// - `latitude` / `longitude` -> valid only if `gps_valid: true` and `gps_fix >= 2`
  /// - `satellites` -> `satellites`
  /// - `roll_deg` -> `roll`, `pitch_deg` -> `pitch`
  /// - `battery_voltage_v` -> `batteryVoltage`
  /// - `battery_remaining_pct` -> `batteryPercentage` / `batteryPercent`. If `null`, marked unavailable (not 0%).
  /// - `last_update` unix timestamp -> Dart [DateTime].
  static DroneTelemetry parseJson(
    Map<String, dynamic> json, {
    DroneTelemetry? previousTelemetry,
    DateTime? receivedTime,
  }) {
    final now = receivedTime ?? DateTime.now();
    final prev = previousTelemetry ?? DroneTelemetry.initial();

    // 1. Connection & Heartbeat
    final bool isFcConnected = json['connected'] as bool? ?? false;
    final bool hasHeartbeat = json['heartbeat'] as bool? ?? false;
    final bool overallConnected = isFcConnected && hasHeartbeat;

    // 2. Flight Mode & Arm Status
    final String mode = (json['mode'] as String?)?.trim().toUpperCase() ??
        prev.flightMode;
    final bool armed = json['armed'] as bool? ?? prev.armed;

    // 3. Altitudes (meters)
    final double? altM = (json['altitude_m'] as num?)?.toDouble();
    final double? relAltM = (json['relative_altitude_m'] as num?)?.toDouble();

    final double altitude = altM ?? prev.altitude;
    final double relativeAltitude = relAltM ?? (altM ?? prev.relativeAltitude);

    // 4. Attitude & Heading (degrees)
    final double? headingDeg = (json['heading_deg'] as num?)?.toDouble();
    final double? rollDeg = (json['roll_deg'] as num?)?.toDouble();
    final double? pitchDeg = (json['pitch_deg'] as num?)?.toDouble();

    final double heading = headingDeg ?? prev.heading;
    final double yaw = headingDeg ?? prev.yaw;
    final double roll = rollDeg ?? prev.roll;
    final double pitch = pitchDeg ?? prev.pitch;
    final bool hasAttitude = rollDeg != null || pitchDeg != null || headingDeg != null;

    // 5. GPS & Coordinates
    final bool gpsValid = json['gps_valid'] as bool? ?? false;
    final int gpsFix = (json['gps_fix'] as num?)?.toInt() ??
        (json['fix'] as num?)?.toInt() ??
        0;
    final int satellites = (json['satellites'] as num?)?.toInt() ??
        (json['gps_satellites'] as num?)?.toInt() ??
        0;

    final double? rawLat = (json['latitude'] as num?)?.toDouble();
    final double? rawLon = (json['longitude'] as num?)?.toDouble();

    // STRICT SAFETY RULE: Never treat gps_valid == false or gps_fix < 2 as valid GPS position
    final bool isPositionValid =
        gpsValid && gpsFix >= 2 && rawLat != null && rawLon != null && (rawLat != 0.0 || rawLon != 0.0);

    final double latitude = isPositionValid ? rawLat : prev.latitude;
    final double longitude = isPositionValid ? rawLon : prev.longitude;

    // 6. Battery Telemetry
    final double? battV = (json['battery_voltage_v'] as num?)?.toDouble();
    final num? battPctNum = json['battery_remaining_pct'] as num?;

    final bool hasBatteryVoltage = battV != null && battV > 0;
    final double batteryVoltage = battV ?? prev.batteryVoltage;

    // STRICT SAFETY RULE: Treat null battery percentage as unavailable, NOT 0%
    double batteryPercentage;
    double batteryPercent;
    bool hasBatteryPercentage;

    if (battPctNum != null) {
      batteryPercentage = battPctNum.toDouble().clamp(0.0, 100.0);
      batteryPercent = (batteryPercentage / 100.0).clamp(0.0, 1.0);
      hasBatteryPercentage = true;
    } else {
      // Unavailable from APM 2.8 (APM 2.8 voltage-only sensors do not report remaining percentage)
      batteryPercentage = -1.0;
      batteryPercent = -1.0;
      hasBatteryPercentage = false;
    }

    // 7. Speed & Distance
    final double? speedMs = (json['groundspeed_m_s'] as num?)?.toDouble() ??
        (json['speed_m_s'] as num?)?.toDouble();
    final double speed = speedMs ?? prev.speed;
    final double groundSpeed = speedMs ?? prev.groundSpeed;

    // 8. Timestamp parsing
    DateTime? lastUpdate = now;
    final dynamic rawTs = json['last_update'] ?? json['timestamp'];
    if (rawTs is num) {
      // If in seconds (Unix timestamp < 1e11), multiply by 1000
      final millis = rawTs < 100000000000 ? (rawTs * 1000).toInt() : rawTs.toInt();
      lastUpdate = DateTime.fromMillisecondsSinceEpoch(millis);
    } else if (rawTs is String) {
      lastUpdate = DateTime.tryParse(rawTs) ?? now;
    }

    return prev.copyWith(
      isConnected: overallConnected,
      isStale: false,
      flightMode: mode,
      armed: armed,
      altitude: altitude,
      relativeAltitude: relativeAltitude,
      heading: heading,
      yaw: yaw,
      roll: roll,
      pitch: pitch,
      latitude: latitude,
      longitude: longitude,
      gpsFix: gpsFix,
      satellites: satellites,
      batteryVoltage: batteryVoltage,
      batteryPercentage: batteryPercentage,
      batteryPercent: batteryPercent,
      speed: speed,
      groundSpeed: groundSpeed,
      lastUpdate: lastUpdate,
      hasReceivedGps: isPositionValid || satellites > 0,
      hasReceivedPosition: isPositionValid,
      hasReceivedAttitude: hasAttitude || prev.hasReceivedAttitude,
      hasReceivedBattery: hasBatteryVoltage || hasBatteryPercentage || prev.hasReceivedBattery,
      hasReceivedVfrHud: speedMs != null || altM != null || prev.hasReceivedVfrHud,
      lastHeartbeat: overallConnected ? now : prev.lastHeartbeat,
      lastGpsUpdate: isPositionValid ? now : prev.lastGpsUpdate,
      lastBatteryUpdate: hasBatteryVoltage ? now : prev.lastBatteryUpdate,
      lastAttitudeUpdate: hasAttitude ? now : prev.lastAttitudeUpdate,
    );
  }

  /// Step-by-step diagnostic test against the Raspberry Pi Flask endpoints.
  /// Tests `/health` and `/telemetry`, measuring latency and validating JSON structure.
  Future<MavlinkTestResult> testEndpoint(
    String baseUrl, {
    int timeoutSeconds = 3,
  }) async {
    final cleanBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(cleanBaseUrl);

    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const MavlinkTestResult(
        success: false,
        message: 'Invalid URL. Must begin with http:// or https://',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = Duration(seconds: timeoutSeconds);
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Probe /health endpoint
      final healthUri = Uri.parse('$cleanBaseUrl/health');
      final healthReq =
          await client.getUrl(healthUri).timeout(Duration(seconds: timeoutSeconds));
      final healthResp =
          await healthReq.close().timeout(Duration(seconds: timeoutSeconds));

      if (healthResp.statusCode != 200) {
        client.close(force: true);
        return MavlinkTestResult(
          success: false,
          message:
              'Raspberry Pi /health returned HTTP ${healthResp.statusCode}',
          remoteAddress: uri.host,
        );
      }

      // 2. Probe /telemetry endpoint
      final telemUri = Uri.parse('$cleanBaseUrl/telemetry');
      final telemReq =
          await client.getUrl(telemUri).timeout(Duration(seconds: timeoutSeconds));
      final telemResp =
          await telemReq.close().timeout(Duration(seconds: timeoutSeconds));
      stopwatch.stop();

      if (telemResp.statusCode == 200) {
        final body = await telemResp.transform(utf8.decoder).join();
        final dynamic decoded = jsonDecode(body);
        client.close(force: true);

        if (decoded is Map<String, dynamic>) {
          final mode = decoded['mode'] ?? 'UNKNOWN';
          final armed = decoded['armed'] == true ? 'ARMED' : 'DISARMED';
          final battV = decoded['battery_voltage_v'] != null
              ? '${(decoded['battery_voltage_v'] as num).toStringAsFixed(1)}V'
              : 'N/A';
          final sats = decoded['satellites'] ?? 0;

          return MavlinkTestResult(
            success: true,
            message:
                'Raspberry Pi Telemetry API OK (${stopwatch.elapsedMilliseconds}ms) — Mode: $mode ($armed), Batt: $battV, Sats: $sats',
            vehicleType: 'APM 2.8 (ArduCopter)',
            autopilotType: 'Flask REST API',
            protocolVersion: 'HTTP/JSON',
            remoteAddress: uri.host,
            rawDatagramsReceived: 1,
            mavlinkFramesReceived: 1,
          );
        } else {
          return MavlinkTestResult(
            success: false,
            message: 'Endpoint responded, but payload was not a JSON object.',
            remoteAddress: uri.host,
          );
        }
      } else {
        client.close(force: true);
        return MavlinkTestResult(
          success: false,
          message:
              'Raspberry Pi /telemetry returned HTTP ${telemResp.statusCode}',
          remoteAddress: uri.host,
        );
      }
    } catch (e) {
      stopwatch.stop();
      client.close(force: true);
      return MavlinkTestResult(
        success: false,
        message: 'Could not connect to Raspberry Pi at $cleanBaseUrl: $e',
        remoteAddress: uri.host,
      );
    }
  }

  void dispose() {
    stop();
    _httpClient?.close(force: true);
    _telemetryController.close();
    _stateController.close();
    _diagnosticsController.close();
  }
}
