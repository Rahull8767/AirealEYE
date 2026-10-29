import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/services/pdf_report_service.dart';
import 'package:aerial_eye/services/video_recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('aerialeye_unit_tests_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return tempTestDir.path;
      },
    );
  });

  tearDownAll(() {
    try {
      tempTestDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('1. Detection Class Mapping Tests', () {
    test('Maps person, human, pedestrian to DetectionType.person', () {
      expect(DetectionType.fromString('person'), DetectionType.person);
      expect(DetectionType.fromString('Person'), DetectionType.person);
      expect(DetectionType.fromString('human'), DetectionType.person);
      expect(DetectionType.fromString('pedestrian'), DetectionType.person);
    });

    test('Maps animal, dog, cat, cow, cattle to DetectionType.animal', () {
      expect(DetectionType.fromString('animal'), DetectionType.animal);
      expect(DetectionType.fromString('dog'), DetectionType.animal);
      expect(DetectionType.fromString('cat'), DetectionType.animal);
      expect(DetectionType.fromString('cow'), DetectionType.animal);
      expect(DetectionType.fromString('cattle'), DetectionType.animal);
    });

    test('Maps pothole and pot_hole to DetectionType.pothole', () {
      expect(DetectionType.fromString('pothole'), DetectionType.pothole);
      expect(DetectionType.fromString('pot_hole'), DetectionType.pothole);
      expect(DetectionType.fromString('POTHOLE'), DetectionType.pothole);
    });

    test(
      'Maps waste, garbage, trash, litter, debris to DetectionType.waste',
      () {
        expect(DetectionType.fromString('waste'), DetectionType.waste);
        expect(DetectionType.fromString('garbage'), DetectionType.waste);
        expect(DetectionType.fromString('trash'), DetectionType.waste);
        expect(DetectionType.fromString('debris'), DetectionType.waste);
        expect(DetectionType.fromString('rubbish'), DetectionType.waste);
        expect(DetectionType.fromString('litter'), DetectionType.waste);
      },
    );

    test('Maps roadcrack, road_crack, crack to DetectionType.roadCrack', () {
      expect(DetectionType.fromString('roadcrack'), DetectionType.roadCrack);
      expect(DetectionType.fromString('road_crack'), DetectionType.roadCrack);
      expect(DetectionType.fromString('crack'), DetectionType.roadCrack);
    });

    test('Unknown labels map safely to DetectionType.obstacle', () {
      expect(
        DetectionType.fromString('unknown_object'),
        DetectionType.obstacle,
      );
      expect(DetectionType.fromString(''), DetectionType.obstacle);
    });
  });

  group('2. Evidence Metadata & Persistence Tests', () {
    test(
      'EvidenceItem serialization and deserialization retains all fields',
      () {
        final now = DateTime.now();
        final item = EvidenceItem(
          id: 'photo_1001',
          filePath: '/storage/test/photo_1001.jpg',
          mediaType: EvidenceMediaType.photo,
          timestamp: now,
          missionId: 'MISSION_ALPHA',
          detectionType: DetectionType.pothole,
          confidence: 0.92,
          hasValidGps: true,
          latitude: 19.0760,
          longitude: 72.8777,
          altitude: 25.5,
          flightMode: 'AUTO',
          fileSizeBytes: 204850,
          isSimulated: false,
          isManuallyVerified: true,
          notes: 'Verified surface pothole',
        );

        final json = item.toJson();
        final parsed = EvidenceItem.fromJson(json);

        expect(parsed.id, 'photo_1001');
        expect(parsed.mediaType, EvidenceMediaType.photo);
        expect(parsed.missionId, 'MISSION_ALPHA');
        expect(parsed.detectionType, DetectionType.pothole);
        expect(parsed.confidence, 0.92);
        expect(parsed.hasValidGps, true);
        expect(parsed.latitude, closeTo(19.0760, 0.0001));
        expect(parsed.longitude, closeTo(72.8777, 0.0001));
        expect(parsed.altitude, 25.5);
        expect(parsed.flightMode, 'AUTO');
        expect(parsed.fileSizeBytes, 204850);
        expect(parsed.isSimulated, false);
        expect(parsed.isManuallyVerified, true);
        expect(parsed.notes, 'Verified surface pothole');
      },
    );

    test('Video EvidenceItem retains duration and video formatting', () {
      final item = EvidenceItem(
        id: 'rec_2001',
        filePath: '/storage/test/rec_2001.mp4',
        mediaType: EvidenceMediaType.video,
        timestamp: DateTime.now(),
        missionId: 'MISSION_BETA',
        durationSeconds: 125, // 2 mins 5 secs
        fileSizeBytes: 4500000,
      );

      expect(item.formattedDuration, '02:05');
      expect(item.formattedSize, '4.3 MB');
      expect(item.mediaType, EvidenceMediaType.video);
    });

    test('Handles missing GPS without inventing fake coordinates', () {
      final item = EvidenceItem(
        id: 'photo_no_gps',
        filePath: '/storage/test/no_gps.jpg',
        mediaType: EvidenceMediaType.photo,
        timestamp: DateTime.now(),
        missionId: 'MANUAL_INSPECTION',
        hasValidGps: false,
        latitude: null,
        longitude: null,
      );

      expect(item.hasValidGps, false);
      expect(item.latitude, isNull);
      expect(item.longitude, isNull);
    });
  });

  group('3. Report Summaries & Class Breakdown Tests', () {
    test(
      'Calculates truthful class breakdown counts without fabrication',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('report_test_');
        final file1 = File('${tempDir.path}/p1.jpg')
          ..writeAsStringSync('dummy1');
        final file2 = File('${tempDir.path}/p2.jpg')
          ..writeAsStringSync('dummy2');
        final file3 = File('${tempDir.path}/p3.jpg')
          ..writeAsStringSync('dummy3');

        final evidence = [
          EvidenceItem(
            id: 'ev1',
            filePath: file1.path,
            mediaType: EvidenceMediaType.photo,
            timestamp: DateTime.now(),
            missionId: 'TEST_RUN',
            detectionType: DetectionType.pothole,
            confidence: 0.91,
            hasValidGps: true,
            latitude: 18.5204,
            longitude: 73.8567,
          ),
          EvidenceItem(
            id: 'ev2',
            filePath: file2.path,
            mediaType: EvidenceMediaType.photo,
            timestamp: DateTime.now(),
            missionId: 'TEST_RUN',
            detectionType: DetectionType.pothole,
            confidence: 0.84,
            hasValidGps: true,
            latitude: 18.5205,
            longitude: 73.8568,
          ),
          EvidenceItem(
            id: 'ev3',
            filePath: file3.path,
            mediaType: EvidenceMediaType.photo,
            timestamp: DateTime.now(),
            missionId: 'TEST_RUN',
            detectionType: DetectionType.roadCrack,
            confidence: 0.88,
            hasValidGps: false, // missing GPS
          ),
        ];

        final report = await PdfReportService.generateReport(
          missionId: 'TEST_RUN',
          missionName: 'Test Infrastructure Flight',
          inspectionDate: DateTime.now(),
          duration: const Duration(minutes: 8, seconds: 30),
          selectedEvidence: evidence,
          selectedClasses: {
            DetectionType.pothole,
            DetectionType.roadCrack,
            DetectionType.waste,
            DetectionType.person,
            DetectionType.animal,
          },
        );

        expect(report.totalImages, 3);
        expect(report.totalDetections, 3);
        expect(report.anomalyDistribution['Pothole'], 2);
        expect(report.anomalyDistribution['Road Crack'], 1);
        expect(report.anomalyDistribution['Waste'], 0);
        expect(report.anomalyDistribution['Person'], 0);
        expect(report.anomalyDistribution['Animal'], 0);

        // Verify unavailable telemetry section notes missing GPS
        expect(
          report.unavailableNotes.any(
            (n) => n.contains('GPS telemetry was unavailable'),
          ),
          isTrue,
        );
        // Verify PDF file was generated
        expect(report.pdfFilePath, isNotNull);
        expect(File(report.pdfFilePath!).existsSync(), isTrue);

        tempDir.deleteSync(recursive: true);
      },
    );

    test(
      'Gracefully handles inspection with zero detections or photos',
      () async {
        final report = await PdfReportService.generateReport(
          missionId: 'EMPTY_RUN',
          missionName: 'Empty Inspection',
          inspectionDate: DateTime.now(),
          duration: const Duration(minutes: 5),
          selectedEvidence: [],
          selectedClasses: {DetectionType.pothole},
        );

        expect(report.totalImages, 0);
        expect(report.totalDetections, 0);
        expect(report.anomalyDistribution['Pothole'], 0);
        expect(report.executiveSummary, contains('zero photographic evidence'));
      },
    );
  });

  group('4. Video Recording State Transitions Tests', () {
    test('Initial state is idle', () {
      final service = VideoRecordingService();
      expect(service.currentSnapshot.state, RecordingState.idle);
      expect(service.isRecording, false);
      expect(service.currentSnapshot.elapsedSeconds, 0);
      service.dispose();
    });

    test('Transitions from idle to recording and stops cleanly', () async {
      final service = VideoRecordingService();
      expect(service.currentSnapshot.state, RecordingState.idle);

      // Start recording
      await service.startRecording(
        baseUrl: 'http://127.0.0.1:8080',
        missionId: 'TEST_REC_MISSION',
      );

      expect(service.isRecording, true);
      expect(service.currentSnapshot.state, RecordingState.recording);

      // Stop recording
      final saved = await service.stopRecording(
        baseUrl: 'http://127.0.0.1:8080',
        missionId: 'TEST_REC_MISSION',
      );

      expect(service.currentSnapshot.state, RecordingState.idle);
      expect(service.isRecording, false);
      expect(saved, isNotNull);
      expect(saved!.mediaType, EvidenceMediaType.video);
      expect(File(saved.filePath).existsSync(), isTrue);
      expect(saved.fileSizeBytes, greaterThan(0));

      // Cleanup saved video
      try {
        File(saved.filePath).deleteSync();
      } catch (_) {}

      service.dispose();
    });

    test('Rejects duplicate start recording requests while active', () async {
      final service = VideoRecordingService();
      await service.startRecording(
        baseUrl: 'http://127.0.0.1:8080',
        missionId: 'SESSION_1',
      );
      expect(service.isRecording, true);

      // Second start attempt should be rejected without error
      await service.startRecording(
        baseUrl: 'http://127.0.0.1:8080',
        missionId: 'SESSION_2',
      );
      expect(service.isRecording, true);

      service.cancelRecording();
      expect(service.isRecording, false);
      service.dispose();
    });
  });
}
