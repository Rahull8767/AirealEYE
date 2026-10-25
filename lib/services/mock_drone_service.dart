import 'dart:async';
import 'dart:math';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/models/motor_test_state.dart';
import 'package:aerial_eye/services/drone_service.dart';

class MockDroneService implements DroneService {
  final _telemetryController = StreamController<DroneTelemetry>.broadcast();
  final _connectionStateController =
      StreamController<DroneConnectionState>.broadcast();
  final _diagnosticsController =
      StreamController<ConnectionDiagnostics>.broadcast();

  MavlinkConnectionConfig _config = MavlinkConnectionConfig.defaultConfig();
  DroneTelemetry _currentTelemetry = DroneTelemetry.initial();
  DroneConnectionState _connectionState = DroneConnectionState.disconnected;
  ConnectionDiagnostics _currentDiagnostics = ConnectionDiagnostics.initial();
  DroneConnectionMode _connectionMode = DroneConnectionMode.simulation;

  @override
  DroneConnectionMode get connectionMode => _connectionMode;

  @override
  set connectionMode(DroneConnectionMode mode) {
    _connectionMode = mode;
  }

  @override
  MavlinkConnectionConfig get config => _config;

  @override
  void updateConfig(MavlinkConnectionConfig newConfig) {
    _config = newConfig;
  }

  Timer? _telemetryTimer;
  Timer? _missionTimer;
  Timer? _connectTimer;
  int _currentWaypointIndex = 0;
  List<Waypoint> _activeWaypoints = [];
  bool _isMissionActive = false;

  @override
  Stream<DroneTelemetry> get telemetryStream => _telemetryController.stream;

  @override
  DroneTelemetry get currentTelemetry => _currentTelemetry;

  @override
  Stream<DroneConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  DroneConnectionState get connectionState => _connectionState;

  @override
  Stream<ConnectionDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

  @override
  ConnectionDiagnostics get currentDiagnostics => _currentDiagnostics;

  @override
  Future<MavlinkTestResult> testConnection(
    MavlinkConnectionConfig testConfig,
  ) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return const MavlinkTestResult(
      success: true,
      message: 'Simulated MAVLink vehicle heartbeat detected.',
      systemId: 1,
      componentId: 1,
      vehicleType: 'ArduCopter (Simulated)',
      autopilotType: 'ArduPilot',
      remoteAddress: '127.0.0.1:14550',
    );
  }

  @override
  void connect() {
    _telemetryTimer?.cancel();
    _connectTimer?.cancel();
    _connectionState = DroneConnectionState.connecting;
    _connectionStateController.add(_connectionState);

    _connectTimer = Timer(const Duration(milliseconds: 500), () {
      _connectionState = DroneConnectionState.connected;
      _connectionStateController.add(_connectionState);

      _currentTelemetry = _currentTelemetry.copyWith(
        isConnected: true,
        armed: false,
        flightMode: 'GUIDED',
        satellites: 18,
        rssi: 95.0,
        batteryPercent: 1.0,
        batteryPercentage: 100.0,
        batteryVoltage: 16.8,
        latitude: 37.7749,
        longitude: -122.4194,
        hasReceivedGps: true,
        hasReceivedBattery: true,
        hasReceivedPosition: true,
        hasReceivedAttitude: true,
        hasReceivedVfrHud: true,
      );
      _telemetryController.add(_currentTelemetry);
      _updateMockDiagnostics();

      _telemetryTimer = Timer.periodic(const Duration(milliseconds: 500), (
        timer,
      ) {
        if (!_currentTelemetry.isConnected) return;

        final random = Random();
        double newPercent = _currentTelemetry.batteryPercent;
        double newVoltage = _currentTelemetry.batteryVoltage;

        if (_isMissionActive) {
          newPercent -= 0.0008;
          newVoltage -= 0.003;
        } else {
          newPercent -= 0.0001;
          newVoltage -= 0.0005;
        }

        if (newPercent < 0.0) newPercent = 0.0;
        if (newVoltage < 10.0) newVoltage = 10.0;

        final double jitterLat = (random.nextDouble() - 0.5) * 0.00002;
        final double jitterLng = (random.nextDouble() - 0.5) * 0.00002;

        _currentTelemetry = _currentTelemetry.copyWith(
          batteryPercent: newPercent,
          batteryPercentage: newPercent * 100.0,
          batteryVoltage: double.parse(newVoltage.toStringAsFixed(2)),
          latitude: _currentTelemetry.latitude + jitterLat,
          longitude: _currentTelemetry.longitude + jitterLng,
          satellites: 15 + random.nextInt(5),
          rssi: (90.0 + random.nextDouble() * 10).clamp(0, 100),
          heading:
              (_currentTelemetry.heading + (random.nextDouble() - 0.5) * 2) %
              360,
          hasReceivedGps: true,
          hasReceivedBattery: true,
          hasReceivedPosition: true,
        );

        _telemetryController.add(_currentTelemetry);
        _updateMockDiagnostics();
      });
    });
  }

  void _updateMockDiagnostics() {
    _currentDiagnostics = ConnectionDiagnostics(
      connectionState: _connectionState,
      socketStatus: _connectionState == DroneConnectionState.connected
          ? 'BOUND'
          : 'CLOSED',
      localAddress: _config.bindAddress,
      localPort: _config.localPort,
      remoteAddress: '127.0.0.1:14550 (Mock)',
      discoveredSystemId: 1,
      discoveredComponentId: 1,
      vehicleType: 'ArduCopter (Mock)',
      autopilotType: 'ArduPilot',
      flightMode: _currentTelemetry.flightMode,
      armed: _currentTelemetry.armed,
      heartbeatHealth: _connectionState == DroneConnectionState.connected
          ? LinkHealth.live
          : LinkHealth.notAvailable,
      lastHeartbeatTime: DateTime.now(),
      telemetryHealth: _connectionState == DroneConnectionState.connected
          ? LinkHealth.live
          : LinkHealth.notAvailable,
      lastTelemetryTime: DateTime.now(),
      packetsReceived: 420,
      packetsPerSecond: 10.0,
      satellites: _currentTelemetry.satellites,
      batteryVoltage: _currentTelemetry.batteryVoltage,
    );
    _diagnosticsController.add(_currentDiagnostics);
  }

  @override
  void disconnect() {
    _connectTimer?.cancel();
    _telemetryTimer?.cancel();
    _missionTimer?.cancel();
    _mockMotorTestTimer?.cancel();
    _isMissionActive = false;

    _connectionState = DroneConnectionState.disconnected;
    _connectionStateController.add(_connectionState);

    _currentTelemetry = DroneTelemetry.initial();
    _telemetryController.add(_currentTelemetry);
    _updateMockDiagnostics();
  }

  @override
  Future<bool> arm() async {
    _currentTelemetry = _currentTelemetry.copyWith(armed: true);
    _telemetryController.add(_currentTelemetry);
    return true;
  }

  @override
  Future<bool> disarm() async {
    _currentTelemetry = _currentTelemetry.copyWith(armed: false);
    _telemetryController.add(_currentTelemetry);
    return true;
  }

  @override
  Future<bool> setFlightMode(String mode) async {
    final modeUpper = mode.toUpperCase();
    final supportedModes = [
      'STABILIZE',
      'GUIDED',
      'LOITER',
      'AUTO',
      'RTL',
      'LAND',
    ];
    if (!supportedModes.contains(modeUpper)) {
      throw ArgumentError("Unsupported flight mode: $mode");
    }
    _currentTelemetry = _currentTelemetry.copyWith(flightMode: modeUpper);
    _telemetryController.add(_currentTelemetry);
    return true;
  }

  @override
  Future<bool> takeoff(double altitudeMeters) async {
    if (!_currentTelemetry.isConnected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_currentTelemetry.armed) {
      throw StateError("Vehicle must be armed before takeoff.");
    }
    if (_currentTelemetry.flightMode != 'GUIDED') {
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'GUIDED');
    }
    _currentTelemetry = _currentTelemetry.copyWith(
      altitude: altitudeMeters,
      relativeAltitude: altitudeMeters,
    );
    _telemetryController.add(_currentTelemetry);
    return true;
  }

  @override
  List<Waypoint> get activeWaypoints => _activeWaypoints;

  @override
  Future<bool> uploadMission(List<Waypoint> waypoints) async {
    _activeWaypoints = waypoints;
    _currentWaypointIndex = 0;
    return true;
  }

  @override
  Future<bool> startMission() async {
    if (!_currentTelemetry.isConnected || _activeWaypoints.isEmpty) {
      return false;
    }
    _currentWaypointIndex = 0;
    _isMissionActive = true;

    _currentTelemetry = _currentTelemetry.copyWith(
      flightMode: 'AUTO',
      speed: _activeWaypoints.first.speed,
      altitude: _activeWaypoints.first.altitude,
      latitude: _activeWaypoints.first.latitude,
      longitude: _activeWaypoints.first.longitude,
    );
    _telemetryController.add(_currentTelemetry);

    _missionTimer?.cancel();
    _missionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isMissionActive) return;

      if (_currentWaypointIndex >= _activeWaypoints.length) {
        _isMissionActive = false;
        _missionTimer?.cancel();
        _currentTelemetry = _currentTelemetry.copyWith(
          flightMode: 'LOITER',
          speed: 0.0,
        );
        _telemetryController.add(_currentTelemetry);
        return;
      }

      final target = _activeWaypoints[_currentWaypointIndex];
      final double currentLat = _currentTelemetry.latitude;
      final double currentLng = _currentTelemetry.longitude;

      final double distLat = target.latitude - currentLat;
      final double distLng = target.longitude - currentLng;
      final double dist = sqrt(distLat * distLat + distLng * distLng);

      if (dist < 0.00015) {
        _currentWaypointIndex++;
        if (_currentWaypointIndex < _activeWaypoints.length) {
          _currentTelemetry = _currentTelemetry.copyWith(
            altitude: _activeWaypoints[_currentWaypointIndex].altitude,
            speed: _activeWaypoints[_currentWaypointIndex].speed,
          );
        }
      } else {
        final double stepLat = (distLat / dist) * 0.00015;
        final double stepLng = (distLng / dist) * 0.00015;

        double angle = atan2(distLng, distLat) * 180 / pi;
        if (angle < 0) angle += 360;

        _currentTelemetry = _currentTelemetry.copyWith(
          latitude: currentLat + stepLat,
          longitude: currentLng + stepLng,
          heading: angle,
          distance: _currentTelemetry.distance + 8.5,
        );
      }
      _telemetryController.add(_currentTelemetry);
    });
    return true;
  }

  @override
  Future<bool> pauseMission() async {
    _isMissionActive = false;
    _currentTelemetry = _currentTelemetry.copyWith(
      flightMode: 'LOITER',
      speed: 0.0,
    );
    _telemetryController.add(_currentTelemetry);
    return true;
  }

  @override
  Future<bool> resumeMission() async {
    if (_activeWaypoints.isNotEmpty) {
      _isMissionActive = true;
      _currentTelemetry = _currentTelemetry.copyWith(
        flightMode: 'AUTO',
        speed: 5.0,
      );
      _telemetryController.add(_currentTelemetry);
      return true;
    }
    return false;
  }

  @override
  Future<bool> returnToLaunch() async {
    _isMissionActive = false;
    _missionTimer?.cancel();
    _currentTelemetry = _currentTelemetry.copyWith(
      flightMode: 'RTL',
      speed: 8.0,
    );
    _telemetryController.add(_currentTelemetry);

    Timer(const Duration(seconds: 6), () {
      _currentTelemetry = _currentTelemetry.copyWith(
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 0.0,
        speed: 0.0,
        flightMode: 'LANDED',
      );
      _telemetryController.add(_currentTelemetry);
    });
    return true;
  }

  @override
  Future<bool> land() async {
    _isMissionActive = false;
    _missionTimer?.cancel();
    _currentTelemetry = _currentTelemetry.copyWith(
      flightMode: 'LAND',
      speed: 1.2,
    );
    _telemetryController.add(_currentTelemetry);

    Timer(const Duration(seconds: 5), () {
      _currentTelemetry = _currentTelemetry.copyWith(
        altitude: 0.0,
        speed: 0.0,
        flightMode: 'LANDED',
      );
      _telemetryController.add(_currentTelemetry);
    });
    return true;
  }

  @override
  Future<bool> clearMission() async {
    _isMissionActive = false;
    _missionTimer?.cancel();
    _activeWaypoints = [];
    _currentWaypointIndex = 0;
    return true;
  }

  @override
  void requestDataStreams({int? rateHz}) {}

  Timer? _mockMotorTestTimer;
  bool _isMockMotorTesting = false;

  @override
  Future<MotorTestResult> testMotor({
    required int motorInstance,
    required double throttlePercent,
    required int durationSeconds,
    bool testAll = false,
  }) async {
    if (testAll) {
      return testAllMotors(
        throttlePercent: throttlePercent,
        durationSeconds: durationSeconds,
      );
    }

    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (_currentTelemetry.armed) {
      throw StateError("Safety Block: Drone is armed. Motor test is only permitted when disarmed.");
    }
    if (_isMockMotorTesting) {
      throw StateError("A motor test is already in progress.");
    }

    _isMockMotorTesting = true;
    _mockMotorTestTimer?.cancel();
    _mockMotorTestTimer = Timer(Duration(seconds: durationSeconds), () {
      _isMockMotorTesting = false;
    });

    await Future.delayed(const Duration(milliseconds: 100));

    return MotorTestResult(
      success: true,
      ackResult: 0,
      message: "Simulated Motor $motorInstance test accepted and running for ${durationSeconds}s",
      commandId: 209,
      motorIndex: motorInstance,
      testAll: false,
      throttlePercent: throttlePercent,
      durationSeconds: durationSeconds,
      isSimulated: true,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<MotorTestResult> testAllMotors({
    required double throttlePercent,
    required int durationSeconds,
  }) async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (_currentTelemetry.armed) {
      throw StateError("Safety Block: Drone is armed. Motor test is only permitted when disarmed.");
    }
    if (_isMockMotorTesting) {
      throw StateError("A motor test is already in progress.");
    }

    _isMockMotorTesting = true;
    _mockMotorTestTimer?.cancel();
    _mockMotorTestTimer = Timer(Duration(seconds: durationSeconds), () {
      _isMockMotorTesting = false;
    });

    await Future.delayed(const Duration(milliseconds: 100));

    return MotorTestResult(
      success: true,
      ackResult: 0,
      message: "Simulated simultaneous test of all 4 motors accepted and running for ${durationSeconds}s",
      commandId: 209,
      motorIndex: 1,
      testAll: true,
      throttlePercent: throttlePercent,
      durationSeconds: durationSeconds,
      isSimulated: true,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<MotorTestResult> stopMotorTest() async {
    _mockMotorTestTimer?.cancel();
    _isMockMotorTesting = false;
    return MotorTestResult(
      success: true,
      ackResult: 0,
      message: "Motor test stopped (throttle cut to 0%)",
      commandId: 209,
      motorIndex: 1,
      throttlePercent: 0.0,
      durationSeconds: 0,
      isSimulated: true,
      timestamp: DateTime.now(),
    );
  }
}
