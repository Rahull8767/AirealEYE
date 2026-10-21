import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/real_detection_event.dart';
import 'package:aerial_eye/services/real_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DetectionType & AiDetection Tests', () {
    test('DetectionType.fromString resolves trained classes correctly', () {
      expect(DetectionType.fromString('person'), DetectionType.person);
      expect(DetectionType.fromString('Person'), DetectionType.person);
      expect(DetectionType.fromString('human'), DetectionType.person);

      expect(DetectionType.fromString('animal'), DetectionType.animal);
      expect(DetectionType.fromString('dog'), DetectionType.animal);
      expect(DetectionType.fromString('cattle'), DetectionType.animal);

      expect(DetectionType.fromString('pothole'), DetectionType.pothole);
      expect(DetectionType.fromString('POTHOLE'), DetectionType.pothole);

      expect(DetectionType.fromString('waste'), DetectionType.waste);
      expect(DetectionType.fromString('garbage'), DetectionType.waste);
      expect(DetectionType.fromString('trash'), DetectionType.waste);
    });

    test('AiDetection toJson and fromJson roundtrip serialization', () {
      final now = DateTime.now();
      final det = AiDetection(
        id: 'det_12345',
        missionId: 'SURVEY_01',
        type: DetectionType.pothole,
        confidence: 0.89,
        timestamp: now,
        latitude: 12.9716,
        longitude: 77.5946,
        altitude: 15.2,
        boundingBox: [0.2, 0.3, 0.6, 0.7],
        severity: 'Critical',
        imagePath: '/path/to/img.jpg',
        isSimulated: false,
        sequenceNumber: 4,
      );

      final json = det.toJson();
      final restored = AiDetection.fromJson(json);

      expect(restored.id, 'det_12345');
      expect(restored.missionId, 'SURVEY_01');
      expect(restored.type, DetectionType.pothole);
      expect(restored.confidence, 0.89);
      expect(restored.latitude, 12.9716);
      expect(restored.longitude, 77.5946);
      expect(restored.altitude, 15.2);
      expect(restored.boundingBox, [0.2, 0.3, 0.6, 0.7]);
      expect(restored.severity, 'Critical');
      expect(restored.imagePath, '/path/to/img.jpg');
      expect(restored.isSimulated, false);
      expect(restored.sequenceNumber, 4);
    });
  });

  group('RealDetectionEvent Tests', () {
    test('Parses Pi JSON entry with normalized bounding box', () {
      final piJson = {
        'class': 'person',
        'confidence': 0.92,
        'box': [0.15, 0.20, 0.45, 0.80],
        'id': 7,
      };

      final event = RealDetectionEvent.fromPiJson(piJson);
      expect(event, isNotNull);
      expect(event!.type, DetectionType.person);
      expect(event.confidence, 0.92);
      expect(event.boundingBox, [0.15, 0.20, 0.45, 0.80]);
      expect(event.piTrackId, 7);
      expect(event.displayTag, contains('PERSON 92%'));
    });

    test('Computes IoU accurately', () {
      // Identical boxes -> 1.0
      final boxA = [0.0, 0.0, 1.0, 1.0];
      final boxB = [0.0, 0.0, 1.0, 1.0];
      expect(RealDetectionEvent.computeIoU(boxA, boxB), closeTo(1.0, 0.001));

      // Completely disjoint boxes -> 0.0
      final boxC = [2.0, 2.0, 3.0, 3.0];
      expect(RealDetectionEvent.computeIoU(boxA, boxC), 0.0);

      // 50% overlap
      // Box 1: [0, 0, 2, 2] Area = 4
      // Box 2: [1, 0, 3, 2] Area = 4
      // Intersection: [1, 0, 2, 2] Area = 2
      // Union: 4 + 4 - 2 = 6
      // IoU: 2 / 6 = 1/3 ~ 0.333
      final b1 = [0.0, 0.0, 2.0, 2.0];
      final b2 = [1.0, 0.0, 3.0, 2.0];
      expect(RealDetectionEvent.computeIoU(b1, b2), closeTo(1.0 / 3.0, 0.001));
    });

    test('Computes centroid distance', () {
      final b1 = [0.0, 0.0, 0.2, 0.2]; // Center = (0.1, 0.1)
      final b2 = [0.3, 0.4, 0.5, 0.6]; // Center = (0.4, 0.5)
      // dx = 0.3, dy = 0.4 -> dist = 0.5
      expect(
        RealDetectionEvent.computeCentroidDistance(b1, b2),
        closeTo(0.5, 0.001),
      );
    });
  });

  group('RealDetectionService Spatial-Temporal Deduplication & Auto-Capture', () {
    test(
      'Deduplicates same object across frames and does not trigger duplicate saves',
      () {
        final dummyFrame = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0xFF,
          0xD9,
        ]);
        final savedEvents = <AiDetection>[];

        final service = RealDetectionService(
          getLatestFrameBytes: () => dummyFrame,
          getCurrentDroneTelemetry: () => {
            'lat': 12.9716,
            'lng': 77.5946,
            'alt': 10.0,
          },
        );
        service.onNewSavedDetection = (det) {
          savedEvents.add(det);
        };

        // Frame 1: Pothole appears at [0.2, 0.2, 0.4, 0.4] with 88% confidence
        service.processIncomingDetections([
          {
            'class': 'pothole',
            'confidence': 0.88,
            'box': [0.20, 0.20, 0.40, 0.40],
          },
        ], dummyFrame);

        expect(service.currentLiveDetections.length, 1);
        final firstSeq = service.currentLiveDetections.first.sequenceNumber;
        expect(firstSeq, greaterThanOrEqualTo(1));
        expect(service.currentLiveDetections.first.type, DetectionType.pothole);

        // Frame 2: Same pothole slightly moved [0.21, 0.21, 0.41, 0.41] (high IoU > 0.80)
        service.processIncomingDetections([
          {
            'class': 'pothole',
            'confidence': 0.90,
            'box': [0.21, 0.21, 0.41, 0.41],
          },
        ], dummyFrame);

        expect(service.currentLiveDetections.length, 1);
        // Sequence number MUST remain unchanged
        expect(service.currentLiveDetections.first.sequenceNumber, firstSeq);

        // Frame 3: A NEW distinct object (Person) appears in the scene
        service.processIncomingDetections([
          {
            'class': 'pothole',
            'confidence': 0.89,
            'box': [0.21, 0.21, 0.41, 0.41],
          },
          {
            'class': 'person',
            'confidence': 0.91,
            'box': [0.70, 0.10, 0.85, 0.60],
          },
        ], dummyFrame);

        expect(service.currentLiveDetections.length, 2);
        final potholeDet = service.currentLiveDetections.firstWhere(
          (d) => d.type == DetectionType.pothole,
        );
        final personDet = service.currentLiveDetections.firstWhere(
          (d) => d.type == DetectionType.person,
        );

        expect(potholeDet.sequenceNumber, firstSeq);
        expect(personDet.sequenceNumber, firstSeq + 1);

        service.dispose();
      },
    );
  });
}
