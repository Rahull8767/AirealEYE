import 'package:flutter/material.dart';

enum DetectionType {
  pothole,
  roadCrack,
  garbage,
  waterLogging,
  animal,
  obstacle,
  brokenRoadSign,
}

class AiDetection {
  final String id;
  final String missionId;
  final DetectionType type;
  final double confidence; // 0.0 to 1.0
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String severity; // Low, Medium, High, Critical
  final String imagePath; // Local path or placeholder image

  AiDetection({
    required this.id,
    required this.missionId,
    required this.type,
    required this.confidence,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.imagePath,
  });

  String get typeLabel {
    switch (type) {
      case DetectionType.pothole:
        return 'Pothole';
      case DetectionType.roadCrack:
        return 'Road Crack';
      case DetectionType.garbage:
        return 'Garbage';
      case DetectionType.waterLogging:
        return 'Water Logging';
      case DetectionType.animal:
        return 'Animal';
      case DetectionType.obstacle:
        return 'Obstacle';
      case DetectionType.brokenRoadSign:
        return 'Broken Road Sign';
    }
  }

  Color get color {
    switch (type) {
      case DetectionType.pothole:
        return Colors.red;
      case DetectionType.roadCrack:
        return Colors.orange;
      case DetectionType.garbage:
        return Colors.green;
      case DetectionType.waterLogging:
        return Colors.blue;
      case DetectionType.animal:
        return Colors.cyan;
      case DetectionType.obstacle:
        return Colors.purple;
      case DetectionType.brokenRoadSign:
        return Colors.yellow.shade800;
    }
  }
}
