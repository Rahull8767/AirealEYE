import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/report.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';

final reportProvider = Provider<List<InspectionReport>>((ref) {
  final missionState = ref.watch(missionProvider);
  final detectionState = ref.watch(detectionProvider);

  // Group detections by mission
  final Map<String, List<dynamic>> detectionsByMission = {};
  for (var det in detectionState.detections) {
    detectionsByMission.putIfAbsent(det.missionId, () => []).add(det);
  }

  final List<InspectionReport> reports = [];
  for (var m in missionState.missionHistory) {
    final missionDets = detectionsByMission[m.id] ?? [];

    final Map<String, int> distribution = {
      'Pothole': 0,
      'Road Crack': 0,
      'Garbage': 0,
      'Water Logging': 0,
      'Animal': 0,
      'Obstacle': 0,
      'Broken Road Sign': 0,
    };

    for (var d in missionDets) {
      final label = d.typeLabel;
      distribution[label] = (distribution[label] ?? 0) + 1;
    }

    double coverage = 100.0;
    if (m.status == MissionStatus.failed) {
      coverage = 42.0;
    } else {
      coverage = 95.0 + (m.id.hashCode % 5);
    }

    reports.add(InspectionReport(
      id: 'rep_${m.id}',
      missionId: m.id,
      missionName: m.name,
      date: m.date,
      coveragePercent: coverage,
      totalDistanceKm: m.distance > 0 ? m.distance : 1.2,
      duration: m.duration,
      totalImages: missionDets.length * 4 + 8,
      totalDetections: missionDets.length,
      anomalyDistribution: distribution,
    ));
  }

  return reports;
});
