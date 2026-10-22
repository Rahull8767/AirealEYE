import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';

enum DroneConnectionState {
  disconnected,
  socketNotBound, // Socket not bound
  socketBoundWaiting, // Socket bound / waiting for packets
  udpPacketsNoMavlink, // UDP packets received but no valid MAVLink
  mavlinkNoHeartbeat, // MAVLink packets received but no heartbeat
  connected, // Heartbeat received / connected
  telemetryStale, // Telemetry stale
  connecting, // Transitioning/binding
  listening, // Backward compatible alias for socketBoundWaiting
  degraded,
  stale, // Backward compatible alias for telemetryStale
  connectionLost, // Backward compatible alias for telemetryStale
  reconnecting,
  error,
}

enum DroneConnectionMode { real, simulation }

class MavlinkTestResult {
  final bool success;
  final String message;
  final String? vehicleType;
  final String? autopilotType;
  final int? systemId;
  final int? componentId;
  final String? remoteAddress;
  final int rawDatagramsReceived;
  final int mavlinkFramesReceived;
  final String protocolVersion;

  const MavlinkTestResult({
    required this.success,
    required this.message,
    this.vehicleType,
    this.autopilotType,
    this.systemId,
    this.componentId,
    this.remoteAddress,
    this.rawDatagramsReceived = 0,
    this.mavlinkFramesReceived = 0,
    this.protocolVersion = 'None',
  });
}

abstract class DroneService {
  Stream<DroneTelemetry> get telemetryStream;
  DroneTelemetry get currentTelemetry;

  Stream<DroneConnectionState> get connectionStateStream;
  DroneConnectionState get connectionState;

  Stream<ConnectionDiagnostics> get diagnosticsStream;
  ConnectionDiagnostics get currentDiagnostics;

  DroneConnectionMode get connectionMode;
  set connectionMode(DroneConnectionMode mode);

  MavlinkConnectionConfig get config;
  void updateConfig(MavlinkConnectionConfig newConfig);

  void connect();
  void disconnect();

  Future<MavlinkTestResult> testConnection(MavlinkConnectionConfig testConfig);

  Future<bool> arm();
  Future<bool> disarm();
  Future<bool> setFlightMode(String mode);
  Future<bool> takeoff(double altitudeMeters);
  Future<bool> land();
  Future<bool> returnToLaunch();

  List<Waypoint> get activeWaypoints;
  Future<bool> uploadMission(List<Waypoint> waypoints);
  Future<bool> startMission();
  Future<bool> pauseMission();
  Future<bool> resumeMission();
  Future<bool> clearMission();
  void requestDataStreams({int? rateHz});
}
