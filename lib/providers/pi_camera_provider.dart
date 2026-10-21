import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/camera_connection_config.dart';
import 'package:aerial_eye/models/camera_diagnostics.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/services/pi_camera_service.dart';

/// The singleton Raspberry Pi camera service provider.
final piCameraServiceProvider = Provider<PiCameraService>((ref) {
  final service = PiCameraService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Stream provider for camera connection status and metrics (FPS, Latency, Error info).
final piCameraStateProvider = StreamProvider<CameraStreamState>((ref) {
  final service = ref.watch(piCameraServiceProvider);
  return service.stateStream;
});

/// Stream provider for decoded live camera frames as Uint8List.
final piCameraFrameProvider = StreamProvider<Uint8List>((ref) {
  final service = ref.watch(piCameraServiceProvider);
  return service.frameStream;
});

/// Stream provider for real-time camera diagnostics.
final piCameraDiagnosticsProvider = StreamProvider<CameraDiagnosticsResult>((
  ref,
) {
  final service = ref.watch(piCameraServiceProvider);
  return service.diagnosticsStream;
});

/// Stream provider for synchronized detections emitted directly with frame headers.
final piCameraDetectionsProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) {
  final service = ref.watch(piCameraServiceProvider);
  return service.detectionsStream;
});
