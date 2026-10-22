import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aerial_eye/models/pi_shutdown_config.dart';
import 'package:aerial_eye/models/pi_shutdown_state.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/pi_shutdown_storage.dart';

class PiShutdownService {
  PiShutdownConfig _config = PiShutdownConfig.defaultConfig();
  PiShutdownState _state = PiShutdownState.initial();

  final _stateController = StreamController<PiShutdownState>.broadcast();
  Stream<PiShutdownState> get stateStream => _stateController.stream;
  PiShutdownState get currentState => _state;
  PiShutdownConfig get config => _config;

  final DroneService? _droneService;
  HttpClient? _httpClient;
  Timer? _statusPollTimer;
  bool _userConfigured = false;

  PiShutdownService({
    DroneService? droneService,
    PiShutdownConfig? initialConfig,
  }) : _droneService = droneService {
    if (initialConfig != null) {
      _config = initialConfig;
      _userConfigured = true;
      _httpClient = HttpClient()
        ..connectionTimeout = Duration(seconds: _config.timeoutSeconds);
    }
    _init();
  }

  Future<void> _init() async {
    final loaded = await PiShutdownStorage.loadConfig();
    if (!_userConfigured) {
      _config = loaded;
      _httpClient?.close(force: true);
      _httpClient = HttpClient()
        ..connectionTimeout = Duration(seconds: _config.timeoutSeconds);
    }
  }

  void updateConfig(PiShutdownConfig newConfig) {
    _config = newConfig;
    _userConfigured = true;
    PiShutdownStorage.saveConfig(newConfig);
    _httpClient?.close(force: true);
    _httpClient = HttpClient()
      ..connectionTimeout = Duration(seconds: newConfig.timeoutSeconds);
    _updateState(_state.copyWith(clearError: true));
  }

  void _updateState(PiShutdownState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  /// Pings the Raspberry Pi shutdown daemon /status endpoint to check connectivity.
  Future<PiShutdownState> checkStatus({String? host, int? port}) async {
    final targetHost = host ?? _config.host;
    final targetPort = port ?? _config.port;

    _updateState(
      _state.copyWith(status: PiPowerStatus.checking, clearError: true),
    );

    try {
      final client = HttpClient()
        ..connectionTimeout = Duration(seconds: _config.timeoutSeconds);
      final uri = Uri.parse('http://$targetHost:$targetPort/status');
      final request = await client
          .getUrl(uri)
          .timeout(Duration(seconds: _config.timeoutSeconds));
      final response = await request.close().timeout(
        Duration(seconds: _config.timeoutSeconds),
      );

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final bool isShuttingDown =
            data['shutdown_in_progress'] as bool? ?? false;
        final String hostname = data['hostname'] as String? ?? 'aerialeye';
        final double? uptime = (data['uptime_seconds'] as num?)?.toDouble();

        final newState = _state.copyWith(
          status: isShuttingDown
              ? PiPowerStatus.shuttingDown
              : PiPowerStatus.online,
          hostname: hostname,
          uptimeSeconds: uptime,
          lastChecked: DateTime.now(),
          clearError: true,
        );
        _updateState(newState);
        client.close(force: true);
        return newState;
      } else {
        final newState = _state.copyWith(
          status: PiPowerStatus.error,
          errorMessage: 'Server returned HTTP ${response.statusCode}',
          lastChecked: DateTime.now(),
        );
        _updateState(newState);
        client.close(force: true);
        return newState;
      }
    } catch (e) {
      // If Pi is offline / unreachable
      final newState = _state.copyWith(
        status: _state.status == PiPowerStatus.shuttingDown
            ? PiPowerStatus.shutdownComplete
            : PiPowerStatus.offline,
        errorMessage: 'Raspberry Pi is unreachable ($e)',
        lastChecked: DateTime.now(),
      );
      _updateState(newState);
      return newState;
    }
  }

  /// Validates safety conditions prior to shutting down the companion computer.
  String? validateFlightSafety() {
    if (_droneService == null) return null;

    final DroneTelemetry telemetry = _droneService.currentTelemetry;

    // 1. Drone is Armed Check
    if (telemetry.armed) {
      return 'SAFETY BLOCK: Drone is currently ARMED. Disarm motors before shutting down the companion computer.';
    }

    // 2. Active Flight Check
    if (telemetry.relativeAltitude > 1.0 || telemetry.speed > 0.8) {
      return 'SAFETY BLOCK: Drone is in ACTIVE FLIGHT (altitude: ${telemetry.relativeAltitude.toStringAsFixed(1)}m, speed: ${telemetry.speed.toStringAsFixed(1)}m/s). Land and disarm first.';
    }

    // 3. Autonomous Mission Active Check
    if (telemetry.flightMode == 'AUTO' || telemetry.flightMode == 'GUIDED') {
      return 'SAFETY BLOCK: Drone is in ${telemetry.flightMode} mode. Switch to STABILIZE/LAND and disarm before shutdown.';
    }

    return null;
  }

  /// Sends authenticated POST /shutdown request to cleanly power off the Raspberry Pi.
  Future<PiShutdownResult> requestShutdown({bool force = false}) async {
    // 1. Verify flight safety
    if (!force) {
      final flightSafetyError = validateFlightSafety();
      if (flightSafetyError != null) {
        debugPrint('[PiShutdownService] $flightSafetyError');
        return PiShutdownResult.blocked(flightSafetyError);
      }
    }

    _updateState(
      _state.copyWith(
        status: PiPowerStatus.shuttingDown,
        message: 'Initiating safe system shutdown...',
        clearError: true,
      ),
    );

    try {
      final client = HttpClient()
        ..connectionTimeout = Duration(seconds: _config.timeoutSeconds);
      final uri = Uri.parse('http://${_config.host}:${_config.port}/shutdown');
      final request = await client
          .postUrl(uri)
          .timeout(Duration(seconds: _config.timeoutSeconds));

      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('X-AerialEye-Token', _config.secretToken);
      request.headers.set('Authorization', 'Bearer ${_config.secretToken}');
      request.write(jsonEncode({'token': _config.secretToken}));

      final response = await request.close().timeout(
        Duration(seconds: _config.timeoutSeconds),
      );
      final responseBody = await response.transform(utf8.decoder).join();
      client.close(force: true);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        final message =
            data['message'] as String? ??
            'Raspberry Pi safe shutdown initiated.';

        _updateState(
          _state.copyWith(
            status: PiPowerStatus.shuttingDown,
            message: message,
            lastChecked: DateTime.now(),
            clearError: true,
          ),
        );

        // Start confirmation poller: wait until the Pi goes offline
        _monitorShutdownCompletion();

        return PiShutdownResult.success(message, 200);
      } else if (response.statusCode == 401) {
        const err =
            'Authentication failed: Invalid shutdown secret token. Verify configuration.';
        _updateState(
          _state.copyWith(status: PiPowerStatus.error, errorMessage: err),
        );
        return PiShutdownResult.failure(err, 401);
      } else if (response.statusCode == 409) {
        const msg =
            'Shutdown is already in progress on the Raspberry Pi companion computer.';
        _updateState(
          _state.copyWith(status: PiPowerStatus.shuttingDown, message: msg),
        );
        return PiShutdownResult.success(msg, 409);
      } else {
        final err = 'Shutdown rejected by Pi: HTTP ${response.statusCode}';
        _updateState(
          _state.copyWith(status: PiPowerStatus.error, errorMessage: err),
        );
        return PiShutdownResult.failure(err, response.statusCode);
      }
    } catch (e) {
      final err = 'Network failure connecting to shutdown service: $e';
      _updateState(
        _state.copyWith(status: PiPowerStatus.error, errorMessage: err),
      );
      return PiShutdownResult.failure(err);
    }
  }

  /// Polls the Pi after shutdown has been acknowledged until it becomes unreachable,
  /// confirming system poweroff has completed.
  void _monitorShutdownCompletion() {
    _statusPollTimer?.cancel();
    int attempts = 0;
    const maxAttempts = 12;

    _statusPollTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      attempts++;
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 900);
        final uri = Uri.parse('http://${_config.host}:${_config.port}/status');
        final req = await client
            .getUrl(uri)
            .timeout(const Duration(milliseconds: 900));
        await req.close().timeout(const Duration(milliseconds: 900));
        client.close(force: true);

        // Still answering
        if (attempts >= maxAttempts) {
          timer.cancel();
        }
      } catch (_) {
        // Pi is no longer responding on network -> shutdown complete!
        timer.cancel();
        _updateState(
          _state.copyWith(
            status: PiPowerStatus.shutdownComplete,
            message:
                'Raspberry Pi 3A+ has powered down safely. Camera and AI services are stopped.',
            lastChecked: DateTime.now(),
            clearError: true,
          ),
        );
        debugPrint(
          '[PiShutdownService] Raspberry Pi poweroff confirmed (device offline).',
        );
      }
    });
  }

  void dispose() {
    _statusPollTimer?.cancel();
    _httpClient?.close(force: true);
    _stateController.close();
  }
}
