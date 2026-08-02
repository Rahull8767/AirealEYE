import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/models/waypoint.dart';
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

  MissionPlannerState({
    required this.plannedWaypoints,
    required this.undoHistory,
    required this.redoHistory,
    required this.missionHistory,
    this.activeMission,
    this.isUploaded = false,
  });

  factory MissionPlannerState.initial() {
    return MissionPlannerState(
      plannedWaypoints: [],
      undoHistory: [],
      redoHistory: [],
      missionHistory: [
        Mission(
          id: 'miss_101',
          name: 'Oak St. Roadway Survey',
          date: DateTime.now().subtract(const Duration(hours: 2)),
          duration: const Duration(minutes: 12, seconds: 40),
          distance: 1.8,
          status: MissionStatus.completed,
          waypoints: [],
        ),
        Mission(
          id: 'miss_102',
          name: 'Mission Street Pothole Log',
          date: DateTime.now().subtract(const Duration(days: 1)),
          duration: const Duration(minutes: 25, seconds: 15),
          distance: 3.4,
          status: MissionStatus.completed,
          waypoints: [],
        ),
        Mission(
          id: 'miss_103',
          name: 'Airport Runway Inspection',
          date: DateTime.now().subtract(const Duration(days: 2)),
          duration: const Duration(minutes: 8, seconds: 45),
          distance: 0.9,
          status: MissionStatus.failed,
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
    bool clearActiveMission = false,
  }) {
    return MissionPlannerState(
      plannedWaypoints: plannedWaypoints ?? this.plannedWaypoints,
      undoHistory: undoHistory ?? this.undoHistory,
      redoHistory: redoHistory ?? this.redoHistory,
      missionHistory: missionHistory ?? this.missionHistory,
      activeMission: clearActiveMission ? null : (activeMission ?? this.activeMission),
      isUploaded: isUploaded ?? this.isUploaded,
    );
  }
}

class MissionNotifier extends StateNotifier<MissionPlannerState> {
  final Ref ref;

  MissionNotifier(this.ref) : super(MissionPlannerState.initial());

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
    );
  }

  void deleteWaypoint(int id) {
    _saveToUndoHistory();
    final list = state.plannedWaypoints.where((w) => w.id != id).toList();
    // Re-index waypoints
    final reindexed = List.generate(list.length, (index) {
      return list[index].copyWith(id: index + 1);
    });
    state = state.copyWith(
      plannedWaypoints: reindexed,
      redoHistory: [],
      isUploaded: false,
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
    );
  }

  void clearMission() {
    _saveToUndoHistory();
    state = state.copyWith(
      plannedWaypoints: [],
      redoHistory: [],
      isUploaded: false,
    );
  }

  void _saveToUndoHistory() {
    state = state.copyWith(
      undoHistory: List.from(state.plannedWaypoints),
    );
  }

  void uploadMission() {
    if (state.plannedWaypoints.isEmpty) return;
    state = state.copyWith(isUploaded: true);
    ref.read(notificationProvider.notifier).addNotification(
          'Mission Uploaded',
          'Successfully uploaded ${state.plannedWaypoints.length} waypoints to Pixhawk MAVLink buffer.',
          NotificationType.success,
        );
  }

  void startMission() {
    if (!state.isUploaded || state.plannedWaypoints.isEmpty) return;
    final droneService = ref.read(droneServiceProvider);

    final newMission = Mission(
      id: 'miss_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Inspection Route ${state.missionHistory.length + 1}',
      date: DateTime.now(),
      duration: Duration.zero,
      distance: 0.0,
      status: MissionStatus.running,
      waypoints: List.from(state.plannedWaypoints),
    );

    state = state.copyWith(
      activeMission: newMission,
    );

    droneService.startMission(state.plannedWaypoints);

    ref.read(notificationProvider.notifier).addNotification(
          'Mission Started',
          'Autopilot running waypoint grid at ${state.plannedWaypoints.first.altitude}m altitude.',
          NotificationType.info,
        );

    ref.read(detectionProvider.notifier).startSimulationForMission(newMission.id);
  }

  void stopMission(MissionStatus endStatus) {
    if (state.activeMission == null) return;
    final droneService = ref.read(droneServiceProvider);

    if (endStatus == MissionStatus.completed) {
      droneService.land();
    } else {
      droneService.returnToLaunch();
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
