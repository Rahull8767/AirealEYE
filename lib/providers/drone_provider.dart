import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';

// The drone service provider. In development, we use MavlinkDroneService by default.
final droneServiceProvider = Provider<DroneService>((ref) {
  final service = MavlinkDroneService();
  ref.onDispose(() {
    service.disconnect();
  });
  return service;
});

// Telemetry stream provider that UI widgets listen to.
final droneTelemetryProvider = StreamProvider<DroneTelemetry>((ref) {
  final service = ref.watch(droneServiceProvider);
  return service.telemetryStream;
});

// Connection state stream provider.
final droneConnectionStateProvider = StreamProvider<DroneConnectionState>((ref) {
  final service = ref.watch(droneServiceProvider);
  return service.connectionStateStream;
});

// Real-time link diagnostics stream provider.
final droneDiagnosticsProvider = StreamProvider<ConnectionDiagnostics>((ref) {
  final service = ref.watch(droneServiceProvider);
  return service.diagnosticsStream;
});
