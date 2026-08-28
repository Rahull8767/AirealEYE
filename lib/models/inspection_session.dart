import 'package:aerial_eye/models/detection.dart';

class InspectionSession {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final double distanceTraveled; // in meters
  final Map<DetectionType, int> typeCounts;

  InspectionSession({
    required this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    required this.distanceTraveled,
    required this.typeCounts,
  });

  bool get isActive => endTime == null;

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  InspectionSession copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    double? distanceTraveled,
    Map<DetectionType, int>? typeCounts,
  }) {
    return InspectionSession(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distanceTraveled: distanceTraveled ?? this.distanceTraveled,
      typeCounts: typeCounts ?? this.typeCounts,
    );
  }
}
