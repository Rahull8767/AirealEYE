import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/models/notification.dart';

class MissionPlannerState {
  final List<Waypoint> plannedWaypoints;
  final List<Waypoint> undoHistory;
  final List<Waypoint> redoHistory;
  final List<Mission> missionHistory;
  final Mission? activeMission;
  final bool isUploaded;
  final MissionStatus missionStatus;
  final InspectionType selectedInspectionType;
  final String? validationError;

  MissionPlannerState({
    required this.plannedWaypoints,
    required this.undoHistory,
    required this.redoHistory,
    required this.missionHistory,
    this.activeMission,
    this.isUploaded = false,
    this.missionStatus = MissionStatus.idle,
    this.selectedInspectionType = InspectionType.generalSurvey,
    this.validationError,
  });

  factory MissionPlannerState.initial() {
    return MissionPlannerState(
      plannedWaypoints: [],
      undoHistory: [],
      redoHistory: [],
      missionStatus: MissionStatus.idle,
      selectedInspectionType: InspectionType.generalSurvey,
      missionHistory: [
        Mission(
          id: 'miss_101',
          name: 'Oak St. Roadway Survey',
          date: DateTime.now().subtract(const Duration(hours: 2)),
          duration: const Duration(minutes: 12, seconds: 40),
          distance: 1.8,
          status: MissionStatus.completed,
          inspectionType: InspectionType.roadInspection,
          waypoints: [],
        ),
        Mission(
          id: 'miss_102',
          name: 'Mission Street Pothole Log',
          date: DateTime.now().subtract(const Duration(days: 1)),
          duration: const Duration(minutes: 25, seconds: 15),
          distance: 3.4,
          status: MissionStatus.completed,
          inspectionType: InspectionType.roadInspection,
          waypoints: [],
        ),
        Mission(
          id: 'miss_103',
          name: 'Airport Perimeter Wildlife Survey',
          date: DateTime.now().subtract(const Duration(days: 2)),
          duration: const Duration(minutes: 8, seconds: 45),
          distance: 0.9,
          status: MissionStatus.failed,
          inspectionType: InspectionType.animalSurvey,
          waypoints: [],
        ),
      ],
    );
  }

  MissionPlannerState copyWith({
    List<Waypoint>? plannedWaypoints,
    List<Waypoint>? undoHistory,
    List<Waypoint>? redoHistory,
    List<Mission>? missionHistory,
    Mission? activeMission,
    bool? isUploaded,
    MissionStatus? missionStatus,
    InspectionType? selectedInspectionType,
    String? validationError,
    bool clearActiveMission = false,
    bool clearValidationError = false,
  }) {
    return MissionPlannerState(
      plannedWaypoints: plannedWaypoints ?? this.plannedWaypoints,
      undoHistory: undoHistory ?? this.undoHistory,
      redoHistory: redoHistory ?? this.redoHistory,
      missionHistory: missionHistory ?? this.missionHistory,
      activeMission: clearActiveMission ? null : (activeMission ?? this.activeMission),
      isUploaded: isUploaded ?? this.isUploaded,
      missionStatus: missionStatus ?? this.missionStatus,
      selectedInspectionType: selectedInspectionType ?? this.selectedInspectionType,
      validationError: clearValidationError ? null : (validationError ?? this.validationError),
    );
  }
}

class MissionNotifier extends StateNotifier<MissionPlannerState> {
  final Ref ref;

  MissionNotifier(this.ref) : super(MissionPlannerState.initial()) {
    // Listen to telemetry updates to track active mission progress and waypoint transitions
    ref.listen(droneTelemetryProvider, (previous, next) {
      final telemetry = next.value;
      if (telemetry != null && state.activeMission != null) {
        if (telemetry.currentWaypoint != state.activeMission!.currentWaypointIndex) {
          state = state.copyWith(
            activeMission: state.activeMission!.copyWith(
              currentWaypointIndex: telemetry.currentWaypoint,
            ),
          );
        }
      }
    });
  }

  /// Validates the current planned mission against safety rules.
  /// Returns null if valid, or a descriptive error message if invalid.
  String? validateMission({bool checkConnection = true}) {
    if (state.plannedWaypoints.isEmpty) {
      return 'Mission must have at least 1 waypoint.';
    }

    if (checkConnection) {
      final droneService = ref.read(droneServiceProvider);
      if (droneService.connectionState != DroneConnectionState.connected) {
        return 'Drone is not connected. Establish MAVLink connection first.';
      }
    }

    for (int i = 0; i < state.plannedWaypoints.length; i++) {
      final wp = state.plannedWaypoints[i];
      if (wp.latitude < -90.0 || wp.latitude > 90.0) {
        return 'Waypoint #${wp.id} has invalid latitude (${wp.latitude}).';
      }
      if (wp.longitude < -180.0 || wp.longitude > 180.0) {
        return 'Waypoint #${wp.id} has invalid longitude (${wp.longitude}).';
      }
      if (wp.altitude <= 0.0) {
        return 'Waypoint #${wp.id} altitude must be positive (> 0m).';
      }
      if (wp.altitude > 500.0) {
        return 'Waypoint #${wp.id} altitude (${wp.altitude}m) exceeds safe limit (500m).';
      }
      if (wp.speed <= 0.0 || wp.speed > 30.0) {
        return 'Waypoint #${wp.id} transit speed must be between 1 and 30 m/s.';
      }
    }

    return null;
  }

  void setInspectionType(InspectionType type) {
    state = state.copyWith(selectedInspectionType: type);
  }

  void addWaypoint(double lat, double lng) {
    _saveToUndoHistory();
    final newId = state.plannedWaypoints.length + 1;
    final wp = Waypoint(
      id: newId,
      latitude: lat,
      longitude: lng,
      altitude: 30.0,
      speed: 5.0,
      hoverTime: 2,
    );
    state = state.copyWith(
      plannedWaypoints: [...state.plannedWaypoints, wp],
      redoHistory: [],
      isUploaded: false,
      missionStatus: MissionStatus.editing,
      clearValidationError: true,
    );
  }

  void updateWaypoint(Waypoint updatedWp) {
    _saveToUndoHistory();
    final list = state.plannedWaypoints.map((w) {
      return w.id == updatedWp.id ? updatedWp : w;
    }).toList();
    state = state.copyWith(
      plannedWaypoints: list,
      redoHistory: [],
      isUploaded: false,
      missionStatus: MissionStatus.editing,
      clearValidationError: true,
    );
  }

  void deleteWaypoint(int id) {
    _saveToUndoHistory();
    final list = state.plannedWaypoints.where((w) => w.id != id).toList();
    // Re-index waypoints sequentially
    final reindexed = List.generate(list.length, (index) {
      return list[index].copyWith(id: index + 1);
    });
    state = state.copyWith(
      plannedWaypoints: reindexed,
      redoHistory: [],
      isUploaded: false,
      missionStatus: reindexed.isEmpty ? MissionStatus.idle : MissionStatus.editing,
      clearValidationError: true,
    );
  }

  void reorderWaypoints(int oldIndex, int newIndex) {
    _saveToUndoHistory();
    final list = List<Waypoint>.from(state.plannedWaypoints);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    // Re-index IDs sequentially
    final reindexed = List.generate(list.length, (index) {
      return list[index].copyWith(id: index + 1);
    });

    state = state.copyWith(
      plannedWaypoints: reindexed,
      redoHistory: [],
      isUploaded: false,
      missionStatus: MissionStatus.editing,
      clearValidationError: true,
    );
  }

  void undo() {
    if (state.undoHistory.isEmpty) return;
    final current = state.plannedWaypoints;
    state = state.copyWith(
      plannedWaypoints: List.from(state.undoHistory),
      undoHistory: [],
      redoHistory: List.from(current),
      isUploaded: false,
      missionStatus: MissionStatus.editing,
    );
  }

  void redo() {
    if (state.redoHistory.isEmpty) return;
    final current = state.plannedWaypoints;
    state = state.copyWith(
      plannedWaypoints: List.from(state.redoHistory),
      redoHistory: [],
      undoHistory: List.from(current),
      isUploaded: false,
      missionStatus: MissionStatus.editing,
    );
  }

  Future<void> clearMission() async {
    _saveToUndoHistory();
    state = state.copyWith(
      plannedWaypoints: [],
      redoHistory: [],
      isUploaded: false,
      missionStatus: MissionStatus.idle,
      clearValidationError: true,
    );
    try {
      await ref.read(droneServiceProvider).clearMission();
    } catch (_) {}
  }

  void _saveToUndoHistory() {
    state = state.copyWith(
      undoHistory: List.from(state.plannedWaypoints),
    );
  }

  Future<bool> uploadMission() async {
    final validationError = validateMission();
    if (validationError != null) {
      state = state.copyWith(validationError: validationError);
      ref.read(notificationProvider.notifier).addNotification(
            'Mission Validation Failed',
            validationError,
            NotificationType.critical,
          );
      return false;
    }

    state = state.copyWith(
      missionStatus: MissionStatus.uploading,
      clearValidationError: true,
    );

    final droneService = ref.read(droneServiceProvider);
    try {
      final success = await droneService.uploadMission(state.plannedWaypoints);
      if (success) {
        state = state.copyWith(
          isUploaded: true,
          missionStatus: MissionStatus.uploaded,
        );
        ref.read(notificationProvider.notifier).addNotification(
              'Mission Uploaded',
              'Successfully uploaded ${state.plannedWaypoints.length} waypoints to ArduPilot buffer.',
              NotificationType.success,
            );
        return true;
      } else {
        state = state.copyWith(missionStatus: MissionStatus.failed);
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        missionStatus: MissionStatus.failed,
        validationError: 'Upload failed: $e',
      );
      ref.read(notificationProvider.notifier).addNotification(
            'Upload Failed',
            'Failed to upload mission: $e',
            NotificationType.critical,
          );
      return false;
    }
  }

  Future<bool> startMission() async {
    if (!state.isUploaded || state.plannedWaypoints.isEmpty) {
      ref.read(notificationProvider.notifier).addNotification(
            'Mission Not Ready',
            'Upload waypoints to vehicle before starting.',
            NotificationType.warning,
          );
      return false;
    }

    final droneService = ref.read(droneServiceProvider);
    if (droneService.connectionState != DroneConnectionState.connected) {
      ref.read(notificationProvider.notifier).addNotification(
            'Vehicle Disconnected',
            'Cannot start mission: MAVLink connection lost.',
            NotificationType.critical,
          );
      return false;
    }

    state = state.copyWith(missionStatus: MissionStatus.starting);

    final newMission = Mission(
      id: 'miss_${DateTime.now().millisecondsSinceEpoch}',
      name: '${state.selectedInspectionType.label} ${state.missionHistory.length + 1}',
      date: DateTime.now(),
      duration: Duration.zero,
      distance: 0.0,
      status: MissionStatus.running,
      inspectionType: state.selectedInspectionType,
      waypoints: List.from(state.plannedWaypoints),
    );

    state = state.copyWith(
      activeMission: newMission,
      missionStatus: MissionStatus.running,
    );

    try {
      final success = await droneService.startMission();
      if (success) {
        ref.read(notificationProvider.notifier).addNotification(
              'Mission Started',
              'Autopilot executing ${state.selectedInspectionType.label} at ${state.plannedWaypoints.first.altitude}m.',
              NotificationType.info,
            );
        ref.read(detectionProvider.notifier).startSimulationForMission(newMission.id);
        return true;
      } else {
        state = state.copyWith(missionStatus: MissionStatus.failed);
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        missionStatus: MissionStatus.failed,
        validationError: 'Start failed: $e',
      );
      ref.read(notificationProvider.notifier).addNotification(
            'Start Failed',
            'Failed to start mission: $e',
            NotificationType.critical,
          );
      return false;
    }
  }

  Future<void> pauseMission() async {
    final droneService = ref.read(droneServiceProvider);
    try {
      await droneService.pauseMission();
      state = state.copyWith(missionStatus: MissionStatus.paused);
      ref.read(notificationProvider.notifier).addNotification(
            'Mission Paused',
            'Vehicle holding position in LOITER mode.',
            NotificationType.warning,
          );
    } catch (e) {
      ref.read(notificationProvider.notifier).addNotification(
            'Pause Failed',
            '$e',
            NotificationType.critical,
          );
    }
  }

  Future<void> resumeMission() async {
    final droneService = ref.read(droneServiceProvider);
    try {
      await droneService.resumeMission();
      state = state.copyWith(missionStatus: MissionStatus.running);
      ref.read(notificationProvider.notifier).addNotification(
            'Mission Resumed',
            'Vehicle continuing mission route in AUTO mode.',
            NotificationType.info,
          );
    } catch (e) {
      ref.read(notificationProvider.notifier).addNotification(
            'Resume Failed',
            '$e',
            NotificationType.critical,
          );
    }
  }

  void generateGrid(double centerLat, double centerLng) {
    _saveToUndoHistory();
    final List<Waypoint> gridWaypoints = [];
    final double latSpacing = 0.00025; // approx 25 meters
    final double lngSpacing = 0.00025; // approx 25 meters
    int id = 1;

    for (int sweep = -1; sweep <= 1; sweep++) {
      final double currentLat = centerLat + (sweep * latSpacing);
      if (sweep % 2 == 0) {
        for (int p = -1; p <= 1; p++) {
          gridWaypoints.add(Waypoint(
            id: id++,
            latitude: currentLat,
            longitude: centerLng + (p * lngSpacing),
            altitude: 30.0,
            speed: 5.0,
            hoverTime: 2,
          ));
        }
      } else {
        for (int p = 1; p >= -1; p--) {
          gridWaypoints.add(Waypoint(
            id: id++,
            latitude: currentLat,
            longitude: centerLng + (p * lngSpacing),
            altitude: 30.0,
            speed: 5.0,
            hoverTime: 2,
          ));
        }
      }
    }

    state = state.copyWith(
      plannedWaypoints: gridWaypoints,
      redoHistory: [],
      isUploaded: false,
      missionStatus: MissionStatus.editing,
      clearValidationError: true,
    );

    ref.read(notificationProvider.notifier).addNotification(
          'Grid Generated',
          'Lawnmower sweep grid generated with ${gridWaypoints.length} waypoints.',
          NotificationType.success,
        );
  }

  void saveCurrentMission(String name) {
    if (state.plannedWaypoints.isEmpty) return;
    final newSaved = Mission(
      id: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      date: DateTime.now(),
      duration: Duration(minutes: (state.plannedWaypoints.length * 1.5).ceil()),
      distance: state.plannedWaypoints.length * 0.28,
      status: MissionStatus.completed,
      inspectionType: state.selectedInspectionType,
      waypoints: List.from(state.plannedWaypoints),
    );
    state = state.copyWith(
      missionHistory: [newSaved, ...state.missionHistory],
    );
    ref.read(notificationProvider.notifier).addNotification(
          'Mission Saved',
          'Saved "$name" local mission template successfully.',
          NotificationType.success,
        );
  }

  void loadMission(Mission mission) {
    _saveToUndoHistory();
    state = state.copyWith(
      plannedWaypoints: List.from(mission.waypoints),
      selectedInspectionType: mission.inspectionType,
      redoHistory: [],
      isUploaded: false,
      missionStatus: MissionStatus.editing,
      clearValidationError: true,
    );
    ref.read(notificationProvider.notifier).addNotification(
          'Mission Loaded',
          'Loaded "${mission.name}" template with ${mission.waypoints.length} points.',
          NotificationType.info,
        );
  }

  Future<void> stopMission(MissionStatus endStatus) async {
    if (state.activeMission == null) return;
    final droneService = ref.read(droneServiceProvider);

    if (endStatus == MissionStatus.completed) {
      await droneService.land();
    } else {
      await droneService.returnToLaunch();
    }

    final double finalDistance = double.parse((droneService.currentTelemetry.distance / 1000).toStringAsFixed(2));
    final Duration finalDuration = Duration(seconds: (droneService.currentTelemetry.distance ~/ 5).clamp(10, 3600));

    final finishedMission = state.activeMission!.copyWith(
      status: endStatus,
      duration: finalDuration,
      distance: finalDistance,
    );

    ref.read(detectionProvider.notifier).stopSimulation();

    state = state.copyWith(
      clearActiveMission: true,
      missionStatus: endStatus,
      missionHistory: [finishedMission, ...state.missionHistory],
    );

    ref.read(notificationProvider.notifier).addNotification(
          endStatus == MissionStatus.completed ? 'Mission Completed' : 'Mission Cancelled',
          endStatus == MissionStatus.completed
              ? 'Drone successfully completed path. Data logged.'
              : 'RTL (Return to Launch) sequence active.',
          endStatus == MissionStatus.completed ? NotificationType.success : NotificationType.warning,
        );
  }
}

final missionProvider = StateNotifierProvider<MissionNotifier, MissionPlannerState>((ref) {
  return MissionNotifier(ref);
});
