import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/pi_shutdown_config.dart';
import 'package:aerial_eye/models/pi_shutdown_state.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/services/pi_shutdown_service.dart';

/// The singleton Raspberry Pi Safe Shutdown service provider.
final piShutdownServiceProvider = Provider<PiShutdownService>((ref) {
  final droneService = ref.watch(droneServiceProvider);
  final cameraService = ref.watch(piCameraServiceProvider);

  final service = PiShutdownService(droneService: droneService);

  // Sync initial host from camera configuration if host matches IP format
  if (cameraService.config.host.isNotEmpty) {
    service.updateConfig(
      service.config.copyWith(host: cameraService.config.host),
    );
  }

  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Stream provider for Raspberry Pi power & shutdown state.
final piShutdownStateProvider = StreamProvider<PiShutdownState>((ref) {
  final service = ref.watch(piShutdownServiceProvider);
  return service.stateStream;
});
