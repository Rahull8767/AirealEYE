import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

enum DetectionType {
  person,
  animal,
  pothole,
  waste,
  garbage, // Retained for backward-compatibility with earlier code
  roadCrack,
  waterLogging,
  obstacle,
  brokenRoadSign;

  static DetectionType fromString(String raw) {
    final lower = raw.trim().toLowerCase();
    switch (lower) {
      case 'person':
      case 'human':
      case 'pedestrian':
        return DetectionType.person;
      case 'animal':
      case 'dog':
      case 'cat':
      case 'cow':
      case 'cattle':
        return DetectionType.animal;
      case 'pothole':
      case 'pot_hole':
        return DetectionType.pothole;
      case 'waste':
      case 'garbage':
      case 'trash':
      case 'debris':
      case 'rubbish':
        return DetectionType.waste;
      case 'roadcrack':
      case 'road_crack':
      case 'crack':
        return DetectionType.roadCrack;
      case 'waterlogging':
      case 'water_logging':
      case 'puddle':
        return DetectionType.waterLogging;
      case 'brokenroadsign':
      case 'broken_road_sign':
      case 'sign':
        return DetectionType.brokenRoadSign;
      default:
        return DetectionType.obstacle;
    }
  }
}

class AiDetection {
  final String id;
  final String missionId;
  final DetectionType type;
  final double confidence; // 0.0 to 1.0
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude; // AGL altitude when detected
  final List<double>?
  boundingBox; // [xMin, yMin, xMax, yMax] normalized 0.0 to 1.0
  final String severity; // Low, Medium, High, Critical
  final String imagePath; // Local absolute path to saved image file
  final bool isSimulated;
  final int sequenceNumber; // Sequential detection event index (#1, #2, ...)

  AiDetection({
    required this.id,
    required this.missionId,
    required this.type,
    required this.confidence,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.boundingBox,
    required this.severity,
    required this.imagePath,
    this.isSimulated = false,
    this.sequenceNumber = 1,
  });

  String get typeLabel {
    switch (type) {
      case DetectionType.person:
        return 'Person';
      case DetectionType.animal:
        return 'Animal';
      case DetectionType.pothole:
        return 'Pothole';
      case DetectionType.waste:
      case DetectionType.garbage:
        return 'Waste';
      case DetectionType.roadCrack:
        return 'Road Crack';
      case DetectionType.waterLogging:
        return 'Water Logging';
      case DetectionType.obstacle:
        return 'Obstacle';
      case DetectionType.brokenRoadSign:
        return 'Broken Road Sign';
    }
  }

  Color get color {
    switch (type) {
      case DetectionType.person:
        return const Color(0xFF38BDF8); // Cyan / Sky Blue
      case DetectionType.animal:
        return const Color(0xFFF59E0B); // Amber / Orange
      case DetectionType.pothole:
        return const Color(0xFFEF4444); // Crimson Red
      case DetectionType.waste:
      case DetectionType.garbage:
        return const Color(0xFF10B981); // Emerald Green
      case DetectionType.roadCrack:
        return Colors.orange;
      case DetectionType.waterLogging:
        return Colors.blue;
      case DetectionType.obstacle:
        return Colors.purple;
      case DetectionType.brokenRoadSign:
        return Colors.yellow.shade800;
    }
  }

  IconData get icon {
    switch (type) {
      case DetectionType.person:
        return LucideIcons.user;
      case DetectionType.animal:
        return LucideIcons.dog;
      case DetectionType.pothole:
        return LucideIcons.alertCircle;
      case DetectionType.waste:
      case DetectionType.garbage:
        return LucideIcons.trash2;
      case DetectionType.roadCrack:
        return LucideIcons.gitCommit;
      case DetectionType.waterLogging:
        return LucideIcons.droplets;
      case DetectionType.obstacle:
        return LucideIcons.construction;
      case DetectionType.brokenRoadSign:
        return LucideIcons.alertOctagon;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'missionId': missionId,
      'type': type.name,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'boundingBox': boundingBox,
      'severity': severity,
      'imagePath': imagePath,
      'isSimulated': isSimulated,
      'sequenceNumber': sequenceNumber,
    };
  }

  factory AiDetection.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'obstacle';
    final parsedType = DetectionType.fromString(typeName);

    List<double>? box;
    if (json['boundingBox'] != null) {
      final rawBox = json['boundingBox'] as List<dynamic>;
      box = rawBox.map((e) => (e as num).toDouble()).toList();
    }

    return AiDetection(
      id:
          json['id'] as String? ??
          'det_${DateTime.now().millisecondsSinceEpoch}',
      missionId: json['missionId'] as String? ?? 'LIVE_SESSION',
      type: parsedType,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.80,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      boundingBox: box,
      severity: json['severity'] as String? ?? 'Medium',
      imagePath: json['imagePath'] as String? ?? '',
      isSimulated: json['isSimulated'] as bool? ?? false,
      sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 1,
    );
  }
}
