import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/models/survey_area.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/services/survey_grid_service.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/models/notification.dart';

class SurveyState {
  final bool isDrawing;
  final SurveyArea activeArea;
  final List<Waypoint> generatedGrid;
  final bool isGridGenerated;

  const SurveyState({
    required this.isDrawing,
    required this.activeArea,
    this.generatedGrid = const [],
    this.isGridGenerated = false,
  });

  factory SurveyState.initial() {
    return SurveyState(
      isDrawing: false,
      activeArea: SurveyArea.empty(),
      generatedGrid: const [],
      isGridGenerated: false,
    );
  }

  SurveyState copyWith({
    bool? isDrawing,
    SurveyArea? activeArea,
    List<Waypoint>? generatedGrid,
    bool? isGridGenerated,
  }) {
    return SurveyState(
      isDrawing: isDrawing ?? this.isDrawing,
      activeArea: activeArea ?? this.activeArea,
      generatedGrid: generatedGrid ?? this.generatedGrid,
      isGridGenerated: isGridGenerated ?? this.isGridGenerated,
    );
  }
}

class SurveyNotifier extends StateNotifier<SurveyState> {
  final Ref ref;
  final SurveyGridService _gridService = SurveyGridService();

  SurveyNotifier(this.ref) : super(SurveyState.initial());

  void startDrawing() {
    state = state.copyWith(
      isDrawing: true,
      activeArea: SurveyArea.empty(),
      generatedGrid: const [],
      isGridGenerated: false,
    );
  }

  void addVertex(double lat, double lng) {
    if (!state.isDrawing && state.activeArea.vertices.isEmpty) {
      // Auto start drawing if first vertex added
      state = state.copyWith(isDrawing: true);
    }

    final newVertices = [...state.activeArea.vertices, LatLng(lat, lng)];
    state = state.copyWith(
      activeArea: state.activeArea.copyWith(vertices: newVertices),
      isGridGenerated: false,
    );
  }

  void undoVertex() {
    if (state.activeArea.vertices.isEmpty) return;
    final updated = List<LatLng>.from(state.activeArea.vertices)..removeLast();
    state = state.copyWith(
      activeArea: state.activeArea.copyWith(vertices: updated, isClosed: false),
      isGridGenerated: false,
    );
  }

  void finishPolygon() {
    if (state.activeArea.vertices.length < 3) {
      ref.read(notificationProvider.notifier).addNotification(
            'Survey Polygon Incomplete',
            'Define at least 3 vertices to enclose a survey area.',
            NotificationType.warning,
          );
      return;
    }

    state = state.copyWith(
      isDrawing: false,
      activeArea: state.activeArea.copyWith(isClosed: true),
    );

    ref.read(notificationProvider.notifier).addNotification(
          'Survey Area Defined',
          'Enclosed ${state.activeArea.formattedArea} with ${state.activeArea.vertices.length} vertices.',
          NotificationType.info,
        );
  }

  void clearPolygon() {
    state = state.copyWith(
      isDrawing: false,
      activeArea: SurveyArea.empty(),
      generatedGrid: const [],
      isGridGenerated: false,
    );
  }

  void updateParameters(SurveyParameters params) {
    state = state.copyWith(
      activeArea: state.activeArea.copyWith(parameters: params),
    );
    if (state.isGridGenerated) {
      generateSurveyGrid();
    }
  }

  List<Waypoint> generateSurveyGrid() {
    if (state.activeArea.vertices.length < 3) {
      ref.read(notificationProvider.notifier).addNotification(
            'Cannot Generate Grid',
            'Draw a polygon survey boundary first.',
            NotificationType.warning,
          );
      return [];
    }

    final waypoints = _gridService.generateSurveyGrid(surveyArea: state.activeArea);

    state = state.copyWith(
      generatedGrid: waypoints,
      isGridGenerated: waypoints.isNotEmpty,
    );

    if (waypoints.isNotEmpty) {
      ref.read(notificationProvider.notifier).addNotification(
            'Survey Grid Generated',
            'Computed ${waypoints.length} flight waypoints at ${state.activeArea.parameters.flightAltitude.toStringAsFixed(0)}m AGL.',
            NotificationType.success,
          );
    }

    return waypoints;
  }

  /// Sends the generated survey grid to the main mission planner
  void applyGridToMissionPlanner() {
    final grid = state.generatedGrid.isNotEmpty ? state.generatedGrid : generateSurveyGrid();
    if (grid.isEmpty) return;

    final missionNotifier = ref.read(missionProvider.notifier);
    // Clear and populate planner with survey waypoints
    missionNotifier.clearMission();
    for (final wp in grid) {
      missionNotifier.addWaypoint(wp.latitude, wp.longitude);
    }

    ref.read(notificationProvider.notifier).addNotification(
          'Grid Loaded to Mission',
          'Transferred ${grid.length} survey waypoints to active mission queue.',
          NotificationType.success,
        );
  }
}

final surveyProvider = StateNotifierProvider<SurveyNotifier, SurveyState>((ref) {
  return SurveyNotifier(ref);
});
