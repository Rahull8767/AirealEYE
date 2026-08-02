import 'dart:math';
import 'package:aerial_eye/models/detection.dart';

class MockDetectionService {
  final List<AiDetection> _allDetections = [];
  final _random = Random();

  List<AiDetection> get allDetections => _allDetections;

  List<AiDetection> generateInitialDetections() {
    _allDetections.clear();
    final now = DateTime.now();
    
    // Seed initial historical inspections
    final list = [
      AiDetection(
        id: 'det_1',
        missionId: 'miss_101',
        type: DetectionType.pothole,
        confidence: 0.94,
        timestamp: now.subtract(const Duration(hours: 2)),
        latitude: 37.7749 + 0.002,
        longitude: -122.4194 - 0.001,
        severity: 'High',
        imagePath: 'pothole',
      ),
      AiDetection(
        id: 'det_2',
        missionId: 'miss_101',
        type: DetectionType.roadCrack,
        confidence: 0.88,
        timestamp: now.subtract(const Duration(hours: 2, minutes: 10)),
        latitude: 37.7749 - 0.0015,
        longitude: -122.4194 + 0.0025,
        severity: 'Medium',
        imagePath: 'crack',
      ),
      AiDetection(
        id: 'det_3',
        missionId: 'miss_102',
        type: DetectionType.garbage,
        confidence: 0.91,
        timestamp: now.subtract(const Duration(days: 1)),
        latitude: 37.7749 + 0.0005,
        longitude: -122.4194 + 0.0010,
        severity: 'Low',
        imagePath: 'garbage',
      ),
      AiDetection(
        id: 'det_4',
        missionId: 'miss_102',
        type: DetectionType.waterLogging,
        confidence: 0.87,
        timestamp: now.subtract(const Duration(days: 1, minutes: 30)),
        latitude: 37.7749 + 0.0030,
        longitude: -122.4194 - 0.0020,
        severity: 'High',
        imagePath: 'water',
      ),
      AiDetection(
        id: 'det_5',
        missionId: 'miss_103',
        type: DetectionType.animal,
        confidence: 0.95,
        timestamp: now.subtract(const Duration(days: 2)),
        latitude: 37.7749 - 0.0030,
        longitude: -122.4194 + 0.0015,
        severity: 'Medium',
        imagePath: 'animal',
      ),
      AiDetection(
        id: 'det_6',
        missionId: 'miss_103',
        type: DetectionType.obstacle,
        confidence: 0.98,
        timestamp: now.subtract(const Duration(days: 2, minutes: 5)),
        latitude: 37.7749 - 0.0025,
        longitude: -122.4194 - 0.0030,
        severity: 'Critical',
        imagePath: 'obstacle',
      ),
      AiDetection(
        id: 'det_7',
        missionId: 'miss_104',
        type: DetectionType.brokenRoadSign,
        confidence: 0.89,
        timestamp: now.subtract(const Duration(days: 3)),
        latitude: 37.7749 + 0.0012,
        longitude: -122.4194 - 0.0005,
        severity: 'Low',
        imagePath: 'sign',
      ),
    ];
    
    _allDetections.addAll(list);
    return _allDetections;
  }

  AiDetection generateRandomDetection(double lat, double lng, String missionId) {
    final now = DateTime.now();
    final id = 'det_${now.millisecondsSinceEpoch}';
    final typeIndex = _random.nextInt(DetectionType.values.length);
    final type = DetectionType.values[typeIndex];
    final confidence = 0.75 + _random.nextDouble() * 0.23; // 75% to 98%
    
    String severity = 'Low';
    if (confidence > 0.92) {
      severity = 'Critical';
    } else if (confidence > 0.85) {
      severity = 'High';
    } else if (confidence > 0.80) {
      severity = 'Medium';
    }

    String img = 'pothole';
    switch (type) {
      case DetectionType.pothole:
        img = 'pothole';
        break;
      case DetectionType.roadCrack:
        img = 'crack';
        break;
      case DetectionType.garbage:
        img = 'garbage';
        break;
      case DetectionType.waterLogging:
        img = 'water';
        break;
      case DetectionType.animal:
        img = 'animal';
        break;
      case DetectionType.obstacle:
        img = 'obstacle';
        break;
      case DetectionType.brokenRoadSign:
        img = 'sign';
        break;
    }

    final newDetection = AiDetection(
      id: id,
      missionId: missionId,
      type: type,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      timestamp: now,
      latitude: lat,
      longitude: lng,
      severity: severity,
      imagePath: img,
    );

    _allDetections.insert(0, newDetection);
    return newDetection;
  }
}
