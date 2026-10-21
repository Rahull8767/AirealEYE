import 'dart:math';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/services/detection_service.dart';

class MockDetectionService implements DetectionService {
  final List<AiDetection> _allDetections = [];
  final _random = Random();

  List<AiDetection> get allDetections => _allDetections;

  @override
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
        altitude: 30.0,
        boundingBox: [0.15, 0.20, 0.45, 0.55],
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
        altitude: 30.0,
        boundingBox: [0.30, 0.35, 0.70, 0.75],
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
        altitude: 35.0,
        boundingBox: [0.10, 0.10, 0.90, 0.90],
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
        altitude: 35.0,
        boundingBox: [0.20, 0.25, 0.80, 0.85],
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
        altitude: 40.0,
        boundingBox: [0.40, 0.40, 0.60, 0.60],
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
        altitude: 40.0,
        boundingBox: [0.05, 0.05, 0.95, 0.95],
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
        altitude: 30.0,
        boundingBox: [0.25, 0.15, 0.75, 0.85],
        severity: 'Low',
        imagePath: 'sign',
      ),
    ];

    _allDetections.addAll(list);
    return _allDetections;
  }

  @override
  AiDetection generateRandomDetection(
    double lat,
    double lng,
    String missionId,
    double altitude,
  ) {
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
      case DetectionType.person:
        img = 'person';
        break;
      case DetectionType.pothole:
        img = 'pothole';
        break;
      case DetectionType.waste:
      case DetectionType.garbage:
        img = 'garbage';
        break;
      case DetectionType.roadCrack:
        img = 'crack';
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

    // Generate simulated bounding box coordinates
    final xMin = 0.1 + _random.nextDouble() * 0.3;
    final yMin = 0.1 + _random.nextDouble() * 0.3;
    final xMax = xMin + 0.2 + _random.nextDouble() * 0.3;
    final yMax = yMin + 0.2 + _random.nextDouble() * 0.3;

    final newDetection = AiDetection(
      id: id,
      missionId: missionId,
      type: type,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      timestamp: now,
      latitude: lat,
      longitude: lng,
      altitude: altitude,
      boundingBox: [xMin, yMin, xMax, yMax],
      severity: severity,
      imagePath: img,
      isSimulated: true,
    );

    _allDetections.insert(0, newDetection);
    return newDetection;
  }
}
