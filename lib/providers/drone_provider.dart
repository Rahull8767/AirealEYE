import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/services/mock_drone_service.dart';

final droneServiceProvider = Provider<MockDroneService>((ref) {
  final service = MockDroneService();
  ref.onDispose(() {
    service.disconnect();
  });
  return service;
});

final droneTelemetryProvider = StreamProvider<DroneTelemetry>((ref) {
  final service = ref.watch(droneServiceProvider);
  return service.telemetryStream;
});
