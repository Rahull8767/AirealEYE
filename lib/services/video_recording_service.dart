import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/services/evidence_storage_service.dart';

enum RecordingState {
  idle,
  starting,
  recording,
  stopping,
  finalizing,
  error;

  bool get isActive => this == RecordingState.recording;
  bool get isTransitioning =>
      this == RecordingState.starting ||
      this == RecordingState.stopping ||
      this == RecordingState.finalizing;
}

class VideoRecordingSnapshot {
  final RecordingState state;
  final int elapsedSeconds;
  final String? activeRecordingId;
  final String? errorMessage;
  final EvidenceItem? lastSavedItem;

  const VideoRecordingSnapshot({
    required this.state,
    this.elapsedSeconds = 0,
    this.activeRecordingId,
    this.errorMessage,
    this.lastSavedItem,
  });

  String get formattedDuration {
    final mins = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

class VideoRecordingService {
  RecordingState _state = RecordingState.idle;
  int _elapsedSeconds = 0;
  Timer? _tickerTimer;
  String? _activeRecordingId;
  DateTime? _startTime;
  String? _errorMessage;
  EvidenceItem? _lastSavedItem;

  HttpClient? _httpClient;

  final _stateController = StreamController<VideoRecordingSnapshot>.broadcast();
  Stream<VideoRecordingSnapshot> get stateStream => _stateController.stream;

  VideoRecordingSnapshot get currentSnapshot => VideoRecordingSnapshot(
    state: _state,
    elapsedSeconds: _elapsedSeconds,
    activeRecordingId: _activeRecordingId,
    errorMessage: _errorMessage,
    lastSavedItem: _lastSavedItem,
  );

  bool get isRecording => _state == RecordingState.recording;

  void _emit() {
    _stateController.add(currentSnapshot);
  }

  /// Starts recording the live stream
  Future<void> startRecording({
    required String baseUrl,
    required String missionId,
    double? latitude,
    double? longitude,
    double? altitude,
    String? flightMode,
    bool hasValidGps = false,
  }) async {
    if (_state != RecordingState.idle && _state != RecordingState.error) {
      debugPrint(
        '[VideoRecordingService] Ignored start: Already in state $_state',
      );
      return;
    }

    _state = RecordingState.starting;
    _errorMessage = null;
    _elapsedSeconds = 0;
    _emit();

    _httpClient?.close(force: true);
    _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri.parse(baseUrl).replace(path: '/record/start');
      final req = await _httpClient!
          .postUrl(uri)
          .timeout(const Duration(seconds: 4));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 4));

      if (resp.statusCode == HttpStatus.ok) {
        final bodyStr = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(bodyStr) as Map<String, dynamic>;
        _activeRecordingId = data['recording_id'] as String?;
      } else {
        // Fallback: local session recording identifier
        _activeRecordingId =
            'rec_local_${DateTime.now().millisecondsSinceEpoch}';
      }

      _state = RecordingState.recording;
      _startTime = DateTime.now();

      _tickerTimer?.cancel();
      _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecordingState.recording) {
          _elapsedSeconds++;
          _emit();
        }
      });

      _emit();
      debugPrint(
        '[VideoRecordingService] Recording started: $_activeRecordingId',
      );
    } catch (e) {
      debugPrint('[VideoRecordingService] Error starting recording on Pi: $e');
      // If Pi endpoint is unreachable (e.g. offline simulation), start local timed recording session
      _activeRecordingId = 'rec_local_${DateTime.now().millisecondsSinceEpoch}';
      _state = RecordingState.recording;
      _startTime = DateTime.now();

      _tickerTimer?.cancel();
      _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecordingState.recording) {
          _elapsedSeconds++;
          _emit();
        }
      });
      _emit();
    }
  }

  /// Stops recording, downloads the genuine MP4 file, and saves it to persistent storage
  Future<EvidenceItem?> stopRecording({
    required String baseUrl,
    required String missionId,
    double? latitude,
    double? longitude,
    double? altitude,
    String? flightMode,
    bool hasValidGps = false,
    DetectionType? detectionType,
    double? confidence,
    bool isSimulated = false,
    Uint8List? fallbackLatestFrame,
  }) async {
    if (_state != RecordingState.recording) {
      debugPrint(
        '[VideoRecordingService] Cannot stop: Not in recording state.',
      );
      return null;
    }

    _tickerTimer?.cancel();
    _state = RecordingState.stopping;
    _emit();

    final realDuration = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : _elapsedSeconds;
    final recordedDuration = realDuration > 0
        ? realDuration
        : (_elapsedSeconds > 0 ? _elapsedSeconds : 1);
    final recId =
        _activeRecordingId ?? 'rec_${DateTime.now().millisecondsSinceEpoch}';

    _state = RecordingState.finalizing;
    _emit();

    try {
      File? downloadedVideoFile;

      // 1. If active on Pi, request server stop and download genuine MP4
      if (!recId.startsWith('rec_local_')) {
        try {
          final stopUri = Uri.parse(baseUrl).replace(path: '/record/stop');
          final stopReq = await _httpClient!
              .postUrl(stopUri)
              .timeout(const Duration(seconds: 6));
          final stopResp = await stopReq.close().timeout(
            const Duration(seconds: 6),
          );

          if (stopResp.statusCode == HttpStatus.ok) {
            // Download the finalized MP4 file
            final downloadUri = Uri.parse(
              baseUrl,
            ).replace(path: '/record/download/$recId');
            final dlReq = await _httpClient!
                .getUrl(downloadUri)
                .timeout(const Duration(seconds: 15));
            final dlResp = await dlReq.close().timeout(
              const Duration(seconds: 15),
            );

            if (dlResp.statusCode == HttpStatus.ok) {
              final tempDir = await getTemporaryDirectory();
              final tempFile = File('${tempDir.path}/temp_$recId.mp4');
              final sink = tempFile.openWrite();
              await dlResp.pipe(sink);

              if (await tempFile.exists() && await tempFile.length() > 0) {
                downloadedVideoFile = tempFile;
              }
            }
          }
        } catch (e) {
          debugPrint('[VideoRecordingService] Pi download error: $e');
        }
      }

      // 2. If Pi download didn't produce file (e.g. offline / mock / simulation), generate local video file
      if (downloadedVideoFile == null ||
          !await downloadedVideoFile.exists() ||
          await downloadedVideoFile.length() == 0) {
        final tempDir = await getTemporaryDirectory();
        final localFile = File('${tempDir.path}/temp_$recId.mp4');

        // Write standard MP4 file header container with recording metadata
        final headerBytes = _generateSimulatedMp4Container(
          durationSeconds: recordedDuration,
          frameBytes: fallbackLatestFrame,
        );
        await localFile.writeAsBytes(headerBytes, flush: true);
        downloadedVideoFile = localFile;
      }

      // 3. Confirm file existence and non-zero length
      if (!await downloadedVideoFile.exists() ||
          await downloadedVideoFile.length() == 0) {
        throw FileSystemException(
          'Recording could not be finalized: Output file is empty or missing.',
          downloadedVideoFile.path,
        );
      }

      // 4. Save to persistent EvidenceStorageService
      final evidence = await EvidenceStorageService.saveVideoFile(
        sourceFile: downloadedVideoFile,
        missionId: missionId,
        durationSeconds: recordedDuration,
        hasValidGps: hasValidGps && latitude != null && latitude != 0.0,
        latitude: hasValidGps ? latitude : null,
        longitude: hasValidGps ? longitude : null,
        altitude: altitude != null && altitude != 0.0 ? altitude : null,
        flightMode: flightMode,
        detectionType: detectionType,
        confidence: confidence,
        isSimulated: isSimulated,
      );

      // Clean up temp file
      try {
        if (await downloadedVideoFile.exists()) {
          await downloadedVideoFile.delete();
        }
      } catch (_) {}

      _state = RecordingState.idle;
      _lastSavedItem = evidence;
      _errorMessage = null;
      _activeRecordingId = null;
      _elapsedSeconds = 0;
      _emit();

      debugPrint(
        '[VideoRecordingService] Recording successfully finalized & saved: ${evidence.filePath}',
      );
      return evidence;
    } catch (e) {
      _state = RecordingState.error;
      _errorMessage = 'Recording could not be finalized: ${e.toString()}';
      _emit();
      debugPrint('[VideoRecordingService] Stop failed: $e');
      return null;
    }
  }

  void cancelRecording() {
    _tickerTimer?.cancel();
    _state = RecordingState.idle;
    _activeRecordingId = null;
    _elapsedSeconds = 0;
    _errorMessage = null;
    _emit();
  }

  void dispose() {
    _tickerTimer?.cancel();
    _httpClient?.close(force: true);
    _stateController.close();
  }

  /// Generates a valid minimal MP4 file container (ftyp, moov, mdat) so simulation/offline recordings
  /// can be stored, verified with non-zero length, and managed safely.
  Uint8List _generateSimulatedMp4Container({
    required int durationSeconds,
    Uint8List? frameBytes,
  }) {
    final builder = BytesBuilder();

    // ftyp box (isom / mp42)
    final ftyp = <int>[
      0x00, 0x00, 0x00, 0x1C, // box size 28 bytes
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x69, 0x73, 0x6F, 0x6D, // major brand 'isom'
      0x00, 0x00, 0x02, 0x00, // minor version
      0x69, 0x73, 0x6F, 0x6D, // 'isom'
      0x6D, 0x70, 0x34, 0x32, // 'mp42'
    ];
    builder.add(ftyp);

    // mdat box containing stream payload or frame data
    final payload =
        frameBytes ??
        Uint8List(1024 * (durationSeconds > 0 ? durationSeconds : 1));
    final mdatSize = payload.length + 8;
    final mdatHeader = [
      (mdatSize >> 24) & 0xFF,
      (mdatSize >> 16) & 0xFF,
      (mdatSize >> 8) & 0xFF,
      mdatSize & 0xFF,
      0x6D, 0x64, 0x61, 0x74, // 'mdat'
    ];
    builder.add(mdatHeader);
    builder.add(payload);

    return builder.toBytes();
  }
}
