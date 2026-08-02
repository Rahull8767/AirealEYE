import 'dart:async';
import 'dart:math';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/waypoint.dart';

class MockDroneService {
  final _telemetryController = StreamController<DroneTelemetry>.broadcast();
  DroneTelemetry _currentTelemetry = DroneTelemetry.initial();
  Timer? _telemetryTimer;
  Timer? _missionTimer;
  int _currentWaypointIndex = 0;
  List<Waypoint> _activeWaypoints = [];
  bool _isMissionActive = false;

  Stream<DroneTelemetry> get telemetryStream => _telemetryController.stream;
  DroneTelemetry get currentTelemetry => _currentTelemetry;

  void connect() {
    _telemetryTimer?.cancel();
    _currentTelemetry = _currentTelemetry.copyWith(
      isConnected: true,
      flightMode: 'GUIDED',
      satellites: 18,
      rssi: 95.0,
      batteryPercent: 1.0,
      batteryVoltage: 16.8,
      latitude: 37.7749,
      longitude: -122.4194,
    );
    _telemetryController.add(_currentTelemetry);

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_currentTelemetry.isConnected) return;

      final random = Random();
      double newPercent = _currentTelemetry.batteryPercent;
      double newVoltage = _currentTelemetry.batteryVoltage;

      // Simulate battery discharge
      if (_isMissionActive) {
        newPercent -= 0.0008; // discharge under load
        newVoltage -= 0.003;
      } else {
        newPercent -= 0.0001; // idle discharge
        newVoltage -= 0.0005;
      }

      if (newPercent < 0.0) newPercent = 0.0;
      if (newVoltage < 10.0) newVoltage = 10.0;

      final double jitterLat = (random.nextDouble() - 0.5) * 0.00002;
      final double jitterLng = (random.nextDouble() - 0.5) * 0.00002;

      _currentTelemetry = _currentTelemetry.copyWith(
        batteryPercent: newPercent,
        batteryVoltage: double.parse(newVoltage.toStringAsFixed(2)),
        latitude: _currentTelemetry.latitude + jitterLat,
        longitude: _currentTelemetry.longitude + jitterLng,
        satellites: 15 + random.nextInt(5),
        rssi: (90.0 + random.nextDouble() * 10).clamp(0, 100),
        heading: (_currentTelemetry.heading + (random.nextDouble() - 0.5) * 2) % 360,
      );

      _telemetryController.add(_currentTelemetry);
    });
  }

  void disconnect() {
    _telemetryTimer?.cancel();
    _missionTimer?.cancel();
    _isMissionActive = false;
    _currentTelemetry = DroneTelemetry.initial();
    _telemetryController.add(_currentTelemetry);
  }

  void startMission(List<Waypoint> waypoints) {
    if (!_currentTelemetry.isConnected || waypoints.isEmpty) return;
    _activeWaypoints = waypoints;
    _currentWaypointIndex = 0;
    _isMissionActive = true;

    _currentTelemetry = _currentTelemetry.copyWith(
      flightMode: 'AUTO',
      speed: waypoints.first.speed,
      altitude: waypoints.first.altitude,
      latitude: waypoints.first.latitude,
      longitude: waypoints.first.longitude,
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

      // Distance to next waypoint
      final double distLat = target.latitude - currentLat;
      final double distLng = target.longitude - currentLng;
      final double dist = sqrt(distLat * distLat + distLng * distLng);

      // Threshold to arrive (approx 10 meters)
      if (dist < 0.00015) {
        _currentWaypointIndex++;
        if (_currentWaypointIndex < _activeWaypoints.length) {
          _currentTelemetry = _currentTelemetry.copyWith(
            altitude: _activeWaypoints[_currentWaypointIndex].altitude,
            speed: _activeWaypoints[_currentWaypointIndex].speed,
          );
        }
      } else {
        // Interpolate movement
        final double stepLat = (distLat / dist) * 0.00015;
        final double stepLng = (distLng / dist) * 0.00015;

        double angle = atan2(distLng, distLat) * 180 / pi;
        if (angle < 0) angle += 360;

        _currentTelemetry = _currentTelemetry.copyWith(
          latitude: currentLat + stepLat,
          longitude: currentLng + stepLng,
          heading: angle,
          distance: _currentTelemetry.distance + 8.5, // simulate distance traveled
        );
      }
      _telemetryController.add(_currentTelemetry);
    });
  }

  void pauseMission() {
    _isMissionActive = false;
    _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'LOITER', speed: 0.0);
    _telemetryController.add(_currentTelemetry);
  }

  void resumeMission() {
    if (_activeWaypoints.isNotEmpty) {
      _isMissionActive = true;
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'AUTO', speed: 5.0);
      _telemetryController.add(_currentTelemetry);
    }
  }

  void returnToLaunch() {
    _isMissionActive = false;
    _missionTimer?.cancel();
    _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'RTL', speed: 8.0);
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
  }

  void land() {
    _isMissionActive = false;
    _missionTimer?.cancel();
    _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'LAND', speed: 1.2);
    _telemetryController.add(_currentTelemetry);

    Timer(const Duration(seconds: 5), () {
      _currentTelemetry = _currentTelemetry.copyWith(
        altitude: 0.0,
        speed: 0.0,
        flightMode: 'LANDED',
      );
      _telemetryController.add(_currentTelemetry);
    });
  }
}
