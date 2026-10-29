import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/services/video_recording_service.dart';

final videoRecordingServiceProvider = Provider<VideoRecordingService>((ref) {
  final service = VideoRecordingService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final videoRecordingSnapshotProvider = StreamProvider<VideoRecordingSnapshot>((
  ref,
) {
  final service = ref.watch(videoRecordingServiceProvider);
  return service.stateStream;
});
