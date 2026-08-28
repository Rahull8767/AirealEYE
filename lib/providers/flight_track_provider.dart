import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/services/flight_track_service.dart';
import 'package:aerial_eye/providers/drone_provider.dart';

class FlightTrackState {
  final List<FlightBreadcrumb> breadcrumbs;
  final List<LatLng> polylinePoints;
  final double totalDistanceMeters;
  final bool isRecording;

  const FlightTrackState({
    required this.breadcrumbs,
    required this.polylinePoints,
    required this.totalDistanceMeters,
    this.isRecording = true,
  });

  factory FlightTrackState.initial() {
    return const FlightTrackState(
      breadcrumbs: [],
      polylinePoints: [],
      totalDistanceMeters: 0.0,
      isRecording: true,
    );
  }

  FlightTrackState copyWith({
    List<FlightBreadcrumb>? breadcrumbs,
    List<LatLng>? polylinePoints,
    double? totalDistanceMeters,
    bool? isRecording,
  }) {
    return FlightTrackState(
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      polylinePoints: polylinePoints ?? this.polylinePoints,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      isRecording: isRecording ?? this.isRecording,
    );
  }
}

class FlightTrackNotifier extends StateNotifier<FlightTrackState> {
  final Ref ref;
  final FlightTrackService _service = FlightTrackService();

  FlightTrackNotifier(this.ref) : super(FlightTrackState.initial()) {
    // Listen to telemetry updates from existing MAVLink drone service
    ref.listen(droneTelemetryProvider, (previous, next) {
      final telemetry = next.value;
      if (telemetry != null) {
        final added = _service.ingestTelemetry(telemetry);
        if (added) {
          state = state.copyWith(
            breadcrumbs: _service.breadcrumbs,
            polylinePoints: _service.polylinePoints,
            totalDistanceMeters: _service.totalDistanceMeters,
          );
        }
      }
    });
  }

  void clearTrack() {
    _service.clear();
    state = state.copyWith(
      breadcrumbs: [],
      polylinePoints: [],
      totalDistanceMeters: 0.0,
    );
  }

  void toggleRecording([bool? recording]) {
    final rec = recording ?? !_service.isRecording;
    _service.isRecording = rec;
    state = state.copyWith(isRecording: rec);
  }
}

final flightTrackProvider = StateNotifierProvider<FlightTrackNotifier, FlightTrackState>((ref) {
  return FlightTrackNotifier(ref);
});
