import 'package:aerial_eye/models/waypoint.dart';

enum MissionStatus {
  idle,
  editing,
  uploading,
  uploaded,
  starting,
  running,
  paused,
  completed,
  failed,
  cancelled,
  planned, // Backward compatible alias for idle/editing
}

enum InspectionType {
  generalSurvey,
  animalSurvey,
  roadInspection,
  wasteInspection,
}

extension InspectionTypeExtension on InspectionType {
  String get label {
    switch (this) {
      case InspectionType.generalSurvey:
        return 'General Survey';
      case InspectionType.animalSurvey:
        return 'Animal Survey';
      case InspectionType.roadInspection:
        return 'Road Inspection (Potholes/Cracks)';
      case InspectionType.wasteInspection:
        return 'Waste & Litter Survey';
    }
  }
}

class Mission {
  final String id;
  final String name;
  final DateTime date;
  final Duration duration;
  final double distance; // in kilometers
  final MissionStatus status;
  final InspectionType inspectionType;
  final List<Waypoint> waypoints;
  final int currentWaypointIndex;

  Mission({
    required this.id,
    required this.name,
    required this.date,
    required this.duration,
    required this.distance,
    required this.status,
    this.inspectionType = InspectionType.generalSurvey,
    required this.waypoints,
    this.currentWaypointIndex = 0,
  });

  Mission copyWith({
    String? id,
    String? name,
    DateTime? date,
    Duration? duration,
    double? distance,
    MissionStatus? status,
    InspectionType? inspectionType,
    List<Waypoint>? waypoints,
    int? currentWaypointIndex,
  }) {
    return Mission(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      duration: duration ?? this.duration,
      distance: distance ?? this.distance,
      status: status ?? this.status,
      inspectionType: inspectionType ?? this.inspectionType,
      waypoints: waypoints ?? this.waypoints,
      currentWaypointIndex: currentWaypointIndex ?? this.currentWaypointIndex,
    );
  }
}

