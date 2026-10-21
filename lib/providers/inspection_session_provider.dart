import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/inspection_session.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';

class InspectionSessionState {
  final InspectionSession? activeSession;
  final List<InspectionSession> sessionHistory;

  InspectionSessionState({this.activeSession, required this.sessionHistory});

  InspectionSessionState copyWith({
    InspectionSession? activeSession,
    List<InspectionSession>? sessionHistory,
    bool clearActiveSession = false,
  }) {
    return InspectionSessionState(
      activeSession: clearActiveSession
          ? null
          : (activeSession ?? this.activeSession),
      sessionHistory: sessionHistory ?? this.sessionHistory,
    );
  }
}

class InspectionSessionNotifier extends StateNotifier<InspectionSessionState> {
  final Ref ref;

  InspectionSessionNotifier(this.ref)
    : super(InspectionSessionState(sessionHistory: [])) {
    // Watch telemetry to update active session distance
    ref.listen(droneTelemetryProvider, (previous, next) {
      final telemetry = next.value;
      if (telemetry != null && state.activeSession != null) {
        state = state.copyWith(
          activeSession: state.activeSession!.copyWith(
            distanceTraveled: telemetry.distance,
          ),
        );
      }
    });

    // Watch detections to update active session typeCounts
    ref.listen(detectionProvider, (previous, next) {
      if (state.activeSession != null) {
        final currentDetections = next.detections
            .where((d) => d.missionId == state.activeSession!.id)
            .toList();
        final Map<DetectionType, int> counts = {};
        for (var d in currentDetections) {
          counts[d.type] = (counts[d.type] ?? 0) + 1;
        }
        state = state.copyWith(
          activeSession: state.activeSession!.copyWith(typeCounts: counts),
        );
      }
    });
  }

  void startSession(String title) {
    final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    final newSession = InspectionSession(
      id: sessionId,
      title: title,
      startTime: DateTime.now(),
      distanceTraveled: 0.0,
      typeCounts: {},
    );
    state = state.copyWith(activeSession: newSession);
  }

  void stopSession() {
    if (state.activeSession == null) return;
    final finishedSession = state.activeSession!.copyWith(
      endTime: DateTime.now(),
    );
    state = state.copyWith(
      clearActiveSession: true,
      sessionHistory: [finishedSession, ...state.sessionHistory],
    );
  }
}

final inspectionSessionProvider =
    StateNotifierProvider<InspectionSessionNotifier, InspectionSessionState>((
      ref,
    ) {
      return InspectionSessionNotifier(ref);
    });
