import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/services/detection_service.dart';
import 'package:aerial_eye/services/mock_detection_service.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/models/notification.dart';

class DetectionState {
  final List<AiDetection> detections;
  final double confidenceFilter;
  final DetectionType? typeFilter;

  DetectionState({
    required this.detections,
    required this.confidenceFilter,
    this.typeFilter,
  });

  DetectionState copyWith({
    List<AiDetection>? detections,
    double? confidenceFilter,
    DetectionType? typeFilter,
    bool clearTypeFilter = false,
  }) {
    return DetectionState(
      detections: detections ?? this.detections,
      confidenceFilter: confidenceFilter ?? this.confidenceFilter,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
    );
  }
}

class DetectionNotifier extends StateNotifier<DetectionState> {
  final Ref ref;
  final DetectionService _service = MockDetectionService();
  Timer? _simulationTimer;

  DetectionNotifier(this.ref)
    : super(DetectionState(detections: [], confidenceFilter: 0.70)) {
    final initialList = _service.generateInitialDetections();
    state = state.copyWith(detections: List.from(initialList));
  }

  void updateConfidenceFilter(double value) {
    state = state.copyWith(confidenceFilter: value);
  }

  void updateTypeFilter(DetectionType? type) {
    if (type == null) {
      state = state.copyWith(clearTypeFilter: true);
    } else {
      state = state.copyWith(typeFilter: type);
    }
  }

  void deleteDetection(String id) {
    final list = state.detections.where((d) => d.id != id).toList();
    state = state.copyWith(detections: list);
  }

  void addDetectionDirectly(AiDetection detection) {
    state = state.copyWith(detections: [detection, ...state.detections]);
  }

  void startSimulationForMission(String missionId) {
    _simulationTimer?.cancel();

    _simulationTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      final droneService = ref.read(droneServiceProvider);
      if (!droneService.currentTelemetry.isConnected ||
          droneService.currentTelemetry.flightMode != 'AUTO') {
        return;
      }

      final lat = droneService.currentTelemetry.latitude;
      final lng = droneService.currentTelemetry.longitude;
      final alt = droneService.currentTelemetry.altitude;

      final newDet = _service.generateRandomDetection(lat, lng, missionId, alt);

      state = state.copyWith(detections: [newDet, ...state.detections]);

      ref
          .read(notificationProvider.notifier)
          .addNotification(
            'AI Anomaly Spotted',
            'Discovered: ${newDet.typeLabel} (Severity: ${newDet.severity}) at [${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}].',
            newDet.severity == 'Critical'
                ? NotificationType.critical
                : NotificationType.warning,
          );
    });
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}

final detectionProvider =
    StateNotifierProvider<DetectionNotifier, DetectionState>((ref) {
      return DetectionNotifier(ref);
    });
