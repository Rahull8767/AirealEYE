import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/notification.dart';
import 'package:aerial_eye/models/real_detection_event.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/services/detection_storage_service.dart';
import 'package:aerial_eye/services/real_detection_service.dart';

class DetectionState {
  final List<AiDetection> detections;
  final double confidenceFilter;
  final DetectionType? typeFilter;
  final bool isLoading;

  DetectionState({
    required this.detections,
    required this.confidenceFilter,
    this.typeFilter,
    this.isLoading = false,
  });

  DetectionState copyWith({
    List<AiDetection>? detections,
    double? confidenceFilter,
    DetectionType? typeFilter,
    bool clearTypeFilter = false,
    bool? isLoading,
  }) {
    return DetectionState(
      detections: detections ?? this.detections,
      confidenceFilter: confidenceFilter ?? this.confidenceFilter,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Singleton provider for the Raspberry Pi RealDetectionService
final realDetectionServiceProvider = Provider<RealDetectionService>((ref) {
  final cameraService = ref.watch(piCameraServiceProvider);

  final service = RealDetectionService(
    getLatestFrameBytes: () => cameraService.latestFrame,
    getCurrentDroneTelemetry: () {
      final drone = ref.read(droneServiceProvider);
      final t = drone.currentTelemetry;
      return {'lat': t.latitude, 'lng': t.longitude, 'alt': t.altitude};
    },
  );

  // Hook frame detections callback from PiCameraService
  cameraService.onFrameDetectionsReceived = (rawDetections, frameBytes) {
    service.processIncomingDetections(rawDetections, frameBytes);
  };

  // Start polling service targeting configured Pi base URL
  service.start(cameraService.config.baseUrl);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Stream provider for genuine live bounding boxes for live camera overlays
final liveDetectionsStreamProvider = StreamProvider<List<RealDetectionEvent>>((
  ref,
) {
  final service = ref.watch(realDetectionServiceProvider);
  return service.liveDetectionsStream;
});

class DetectionNotifier extends StateNotifier<DetectionState> {
  final Ref ref;
  late final RealDetectionService _realService;
  Timer? _simulationTimer;

  DetectionNotifier(this.ref)
    : super(
        DetectionState(detections: [], confidenceFilter: 0.60, isLoading: true),
      ) {
    _realService = ref.read(realDetectionServiceProvider);

    // 1. Hook callback for auto-saved detections from the Raspberry Pi
    _realService.onNewSavedDetection = (AiDetection newDet) {
      addDetectionDirectly(newDet);
      ref
          .read(notificationProvider.notifier)
          .addNotification(
            'AI Detection Spot: #${newDet.sequenceNumber} ${newDet.typeLabel}',
            'Identified genuine ${newDet.typeLabel} (${(newDet.confidence * 100).toStringAsFixed(0)}%) with auto-saved photo frame.',
            newDet.severity == 'Critical'
                ? NotificationType.critical
                : NotificationType.warning,
          );
    };

    // 2. Load persisted detections from storage on startup
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    try {
      final persisted = await DetectionStorageService.loadPersistedDetections();
      state = state.copyWith(detections: persisted, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
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

  Future<void> deleteDetection(String id) async {
    final list = state.detections.where((d) => d.id != id).toList();
    state = state.copyWith(detections: list);
    await DetectionStorageService.deleteDetection(id);
  }

  void addDetectionDirectly(AiDetection detection) {
    // Avoid duplicates in memory
    if (state.detections.any((d) => d.id == detection.id)) return;
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

      final newDet = _realService.generateRandomDetection(
        lat,
        lng,
        missionId,
        alt,
      );

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
