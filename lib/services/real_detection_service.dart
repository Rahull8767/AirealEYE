import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/real_detection_event.dart';
import 'package:aerial_eye/services/detection_service.dart';
import 'package:aerial_eye/services/detection_storage_service.dart';

class _ActiveTrackedObject {
  final int sequenceNumber;
  final DetectionType type;
  List<double> boundingBox;
  double confidence;
  DateTime firstSeen;
  DateTime lastSeen;
  bool hasAutoSaved;

  _ActiveTrackedObject({
    required this.sequenceNumber,
    required this.type,
    required this.boundingBox,
    required this.confidence,
    required this.firstSeen,
    required this.lastSeen,
    this.hasAutoSaved = false,
  });
}

class RealDetectionService implements DetectionService {
  // Callback when a new qualifying detection is automatically captured & saved
  Function(AiDetection detection)? onNewSavedDetection;

  // Stream of live detections for drawing bounding boxes on the live camera viewport
  final _liveDetectionsController =
      StreamController<List<RealDetectionEvent>>.broadcast();
  Stream<List<RealDetectionEvent>> get liveDetectionsStream =>
      _liveDetectionsController.stream;

  List<RealDetectionEvent> _currentLiveDetections = [];
  List<RealDetectionEvent> get currentLiveDetections =>
      List.unmodifiable(_currentLiveDetections);

  // Active spatial-temporal tracker for deduplication
  final List<_ActiveTrackedObject> _activeTracks = [];
  int _sequenceCounter = 0;

  // Tracking parameters
  static const double iouMatchThreshold = 0.32;
  static const double centroidMatchThreshold = 0.16;
  static const Duration trackExpiryDuration = Duration(seconds: 4);
  static const double qualifyingConfidenceThreshold = 0.55;

  // Polling client for Pi /detections JSON endpoint
  HttpClient? _httpClient;
  Timer? _pollingTimer;
  String _currentBaseUrl = 'http://10.174.17.87:8080';
  bool _isRunning = false;

  // Provider accessors for telemetry & frame capture
  Uint8List? Function()? getLatestFrameBytes;
  Map<String, double> Function()? getCurrentDroneTelemetry;

  RealDetectionService({
    this.onNewSavedDetection,
    this.getLatestFrameBytes,
    this.getCurrentDroneTelemetry,
  }) {
    _initSequenceCounter();
  }

  Future<void> _initSequenceCounter() async {
    try {
      final existing = await DetectionStorageService.loadPersistedDetections();
      int highest = 0;
      for (final d in existing) {
        if (d.sequenceNumber > highest) {
          highest = d.sequenceNumber;
        }
      }
      _sequenceCounter = highest;
      debugPrint(
        '[RealDetectionService] Initialized sequence counter at #$_sequenceCounter',
      );
    } catch (e) {
      _sequenceCounter = 0;
    }
  }

  /// Starts live polling for detections from the Raspberry Pi
  void start([String? baseUrl]) {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _currentBaseUrl = baseUrl;
    }
    _isRunning = true;
    _pollingTimer?.cancel();
    _httpClient?.close(force: true);
    _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 2);

    // Poll every 180ms for responsive bounding box updates
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (_isRunning) {
        _pollPiDetections();
      }
    });

    debugPrint(
      '[RealDetectionService] Detection tracking service started on $_currentBaseUrl',
    );
  }

  /// Stops live polling
  void stop() {
    _isRunning = false;
    _pollingTimer?.cancel();
    _httpClient?.close(force: true);
    _httpClient = null;
    _currentLiveDetections = [];
    _liveDetectionsController.add([]);
    debugPrint('[RealDetectionService] Detection tracking service stopped.');
  }

  /// Updates the target URL when user updates camera configuration
  void updateBaseUrl(String newUrl) {
    _currentBaseUrl = newUrl;
    if (_isRunning) {
      start(newUrl);
    }
  }

  /// Polls the Raspberry Pi /detections endpoint
  Future<void> _pollPiDetections() async {
    if (!_isRunning) return;

    try {
      final uri = Uri.parse(_currentBaseUrl).replace(path: '/detections');
      final client = _httpClient;
      if (client == null) return;

      final req = await client
          .getUrl(uri)
          .timeout(const Duration(milliseconds: 1500));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(
        const Duration(milliseconds: 1500),
      );

      if (resp.statusCode == HttpStatus.ok) {
        final body = await resp.transform(utf8.decoder).join();
        if (body.trim().isNotEmpty) {
          final decoded = jsonDecode(body);
          List<dynamic> rawList = [];
          if (decoded is List) {
            rawList = decoded;
          } else if (decoded is Map && decoded['detections'] is List) {
            rawList = decoded['detections'] as List;
          }

          processIncomingDetections(rawList.cast<Map<String, dynamic>>());
        }
      }
    } catch (_) {
      // Periodic poll errors are expected if Pi is booting or endpoint not yet loaded
    }
  }

  /// Processes raw detections from either the /detections JSON endpoint or MJPEG X-Detections header
  void processIncomingDetections(
    List<Map<String, dynamic>> rawDetections, [
    Uint8List? explicitFrameBytes,
  ]) {
    final now = DateTime.now();

    // 1. Purge stale tracks older than 4 seconds
    _activeTracks.removeWhere(
      (t) => now.difference(t.lastSeen) > trackExpiryDuration,
    );

    final currentFrameDetections = <RealDetectionEvent>[];
    final frameBytes = explicitFrameBytes ?? getLatestFrameBytes?.call();

    // 2. Process each detection emitted by YOLO NCNN
    for (final raw in rawDetections) {
      final parsed = RealDetectionEvent.fromPiJson(raw);
      if (parsed == null) continue;

      // Filter only the 4 authentic trained classes or known categories
      if (!_isValidTrainedClass(parsed.type)) continue;

      // Match against active tracks for spatial-temporal deduplication
      _ActiveTrackedObject? matchedTrack;
      double bestIou = 0.0;

      for (final track in _activeTracks) {
        if (track.type != parsed.type) continue;

        final iou = RealDetectionEvent.computeIoU(
          track.boundingBox,
          parsed.boundingBox,
        );
        final centroidDist = RealDetectionEvent.computeCentroidDistance(
          track.boundingBox,
          parsed.boundingBox,
        );

        if (iou >= iouMatchThreshold ||
            centroidDist <= centroidMatchThreshold) {
          if (iou > bestIou) {
            bestIou = iou;
            matchedTrack = track;
          }
        }
      }

      if (matchedTrack != null) {
        // MATCH: Same object visible across frames!
        // Update its position and timestamp, KEEP existing sequence number
        matchedTrack.boundingBox = parsed.boundingBox;
        matchedTrack.confidence = parsed.confidence;
        matchedTrack.lastSeen = now;

        currentFrameDetections.add(
          RealDetectionEvent(
            sequenceNumber: matchedTrack.sequenceNumber,
            type: parsed.type,
            label: parsed.label,
            confidence: parsed.confidence,
            boundingBox: parsed.boundingBox,
            timestamp: now,
            piTrackId: parsed.piTrackId,
          ),
        );
      } else {
        // NEW OBJECT: First time this specific object appeared!
        _sequenceCounter++;
        final assignedSeq = _sequenceCounter;

        final newTrack = _ActiveTrackedObject(
          sequenceNumber: assignedSeq,
          type: parsed.type,
          boundingBox: parsed.boundingBox,
          confidence: parsed.confidence,
          firstSeen: now,
          lastSeen: now,
          hasAutoSaved: false,
        );
        _activeTracks.add(newTrack);

        final newEvent = RealDetectionEvent(
          sequenceNumber: assignedSeq,
          type: parsed.type,
          label: parsed.label,
          confidence: parsed.confidence,
          boundingBox: parsed.boundingBox,
          timestamp: now,
          piTrackId: parsed.piTrackId,
        );
        currentFrameDetections.add(newEvent);

        // Auto-save qualifying detection if confidence exceeds threshold
        if (parsed.confidence >= qualifyingConfidenceThreshold &&
            frameBytes != null &&
            frameBytes.isNotEmpty) {
          newTrack.hasAutoSaved = true;
          _triggerAutomaticSave(newEvent, frameBytes);
        }
      }
    }

    // 3. Emit live detections for video overlay
    _currentLiveDetections = currentFrameDetections;
    _liveDetectionsController.add(currentFrameDetections);
  }

  /// Automatically captures image and records telemetry for a newly detected object
  Future<void> _triggerAutomaticSave(
    RealDetectionEvent event,
    Uint8List imageBytes,
  ) async {
    try {
      final eventId =
          'det_${DateTime.now().millisecondsSinceEpoch}_${event.sequenceNumber}';

      // 1. Acquire GPS coordinates: drone telemetry first, then device location fallback
      double lat = 0.0;
      double lng = 0.0;
      double alt = 0.0;

      final telemetry = getCurrentDroneTelemetry?.call();
      if (telemetry != null && (telemetry['lat'] ?? 0.0) != 0.0) {
        lat = telemetry['lat']!;
        lng = telemetry['lng'] ?? 0.0;
        alt = telemetry['alt'] ?? 0.0;
      } else {
        // Fallback to phone GPS
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 1),
          );
          lat = pos.latitude;
          lng = pos.longitude;
          alt = pos.altitude;
        } catch (_) {
          // Device GPS unavailable or permission denied
        }
      }

      // 2. Calculate severity
      String severity = 'Medium';
      if (event.type == DetectionType.pothole) {
        severity = event.confidence >= 0.85 ? 'Critical' : 'High';
      } else if (event.type == DetectionType.animal) {
        severity = 'High';
      } else if (event.type == DetectionType.waste) {
        severity = 'Medium';
      } else if (event.type == DetectionType.person) {
        severity = 'Low';
      }

      final draftDetection = AiDetection(
        id: eventId,
        missionId: 'LIVE_MONITORING',
        type: event.type,
        confidence: event.confidence,
        timestamp: DateTime.now(),
        latitude: lat,
        longitude: lng,
        altitude: alt,
        boundingBox: event.boundingBox,
        severity: severity,
        imagePath: '',
        isSimulated: false,
        sequenceNumber: event.sequenceNumber,
      );

      // 3. Persist image bytes and metadata
      final persisted = await DetectionStorageService.saveDetection(
        detection: draftDetection,
        imageBytes: imageBytes,
      );

      // 4. Notify app listeners
      onNewSavedDetection?.call(persisted);
      debugPrint(
        '[RealDetectionService] Auto-saved detection #${persisted.sequenceNumber} (${persisted.typeLabel})',
      );
    } catch (e) {
      debugPrint('[RealDetectionService] Failed to auto-save detection: $e');
    }
  }

  bool _isValidTrainedClass(DetectionType type) {
    return type == DetectionType.person ||
        type == DetectionType.animal ||
        type == DetectionType.pothole ||
        type == DetectionType.waste ||
        type == DetectionType.garbage;
  }

  // Implementation of DetectionService interface methods
  @override
  List<AiDetection> generateInitialDetections() {
    return [];
  }

  @override
  AiDetection generateRandomDetection(
    double lat,
    double lng,
    String missionId,
    double altitude,
  ) {
    _sequenceCounter++;
    return AiDetection(
      id: 'det_${DateTime.now().millisecondsSinceEpoch}',
      missionId: missionId,
      type: DetectionType.pothole,
      confidence: 0.88,
      timestamp: DateTime.now(),
      latitude: lat,
      longitude: lng,
      altitude: altitude,
      boundingBox: [0.3, 0.4, 0.6, 0.7],
      severity: 'High',
      imagePath: '',
      isSimulated: false,
      sequenceNumber: _sequenceCounter,
    );
  }

  void dispose() {
    stop();
    _liveDetectionsController.close();
  }
}
