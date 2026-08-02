import 'package:aerial_eye/models/waypoint.dart';

enum MissionStatus {
  planned,
  running,
  completed,
  failed,
}

class Mission {
  final String id;
  final String name;
  final DateTime date;
  final Duration duration;
  final double distance; // in kilometers
  final MissionStatus status;
  final List<Waypoint> waypoints;

  Mission({
    required this.id,
    required this.name,
    required this.date,
    required this.duration,
    required this.distance,
    required this.status,
    required this.waypoints,
  });

  Mission copyWith({
    String? id,
    String? name,
    DateTime? date,
    Duration? duration,
    double? distance,
    MissionStatus? status,
    List<Waypoint>? waypoints,
  }) {
    return Mission(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      duration: duration ?? this.duration,
      distance: distance ?? this.distance,
      status: status ?? this.status,
      waypoints: waypoints ?? this.waypoints,
    );
  }
}
