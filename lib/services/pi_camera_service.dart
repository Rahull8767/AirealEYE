import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:aerial_eye/models/camera_connection_config.dart';
import 'package:aerial_eye/models/camera_diagnostics.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/services/pi_camera_config_storage.dart';

class PiCameraService {
  CameraConnectionConfig _config = CameraConnectionConfig.defaultConfig();
  CameraStreamState _currentState = CameraStreamState.initial();
  Uint8List? _latestFrame;

  final _stateController = StreamController<CameraStreamState>.broadcast();
  final _frameController = StreamController<Uint8List>.broadcast();
  final _diagnosticsController =
      StreamController<CameraDiagnosticsResult>.broadcast();
  final _detectionsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  HttpClient? _httpClient;
  StreamSubscription<List<int>>? _streamSubscription;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  bool _userExplicitlyDisconnected = false;

  /// Callback when a frame arrives with synchronized X-Detections headers
  void Function(List<Map<String, dynamic>> detections, Uint8List frameBytes)?
  onFrameDetectionsReceived;

  // Stream performance tracking
  int _framesInCurrentSecond = 0;
  DateTime _lastFpsCalculationTime = DateTime.now();
  DateTime? _previousFrameTime;

  PiCameraService() {
    _loadPersistedConfig();
  }

  // Streams
  Stream<CameraStreamState> get stateStream => _stateController.stream;
  Stream<Uint8List> get frameStream => _frameController.stream;
  Stream<CameraDiagnosticsResult> get diagnosticsStream =>
      _diagnosticsController.stream;
  Stream<List<Map<String, dynamic>>> get detectionsStream =>
      _detectionsController.stream;

  // Getters
  CameraStreamState get currentState => _currentState;
  Uint8List? get latestFrame => _latestFrame;
  CameraConnectionConfig get config => _config;

  Future<void> _loadPersistedConfig() async {
    try {
      final loaded = await PiCameraConfigStorage.loadConfig();
      _config = loaded;
      if (_config.autoConnect) {
        connect();
      }
    } catch (e) {
      debugPrint('[PiCameraService] Error loading config: $e');
    }
  }

  void updateConfig(CameraConnectionConfig newConfig) {
    _config = newConfig;
    PiCameraConfigStorage.saveConfig(_config);
  }

  /// Initiates connection to the configured Raspberry Pi camera stream
  Future<void> connect([CameraConnectionConfig? customConfig]) async {
    if (customConfig != null) {
      _config = customConfig;
      PiCameraConfigStorage.saveConfig(_config);
    }

    _userExplicitlyDisconnected = false;
    _reconnectTimer?.cancel();
    await _closeActiveStream();

    // 1. URL validation
    final validation = CameraConnectionConfig.validateUrl(_config.baseUrl);
    if (!validation.isValid) {
      _updateState(
        _currentState.copyWith(
          status: CameraStatus.error,
          errorCategory: CameraErrorCategory.invalidUrl,
          errorMessage: validation.errorMessage ?? 'Invalid camera URL.',
          diagnosticDetails:
              'Please verify the IP and port in Camera Settings.',
        ),
      );
      return;
    }

    final targetUrl = validation.normalizedUrl!;
    _updateState(
      _currentState.copyWith(
        status: CameraStatus.connecting,
        connectedUrl: targetUrl,
        errorCategory: CameraErrorCategory.none,
        errorMessage: null,
        diagnosticDetails: 'Connecting to $targetUrl...',
        retryAttempt: 0,
      ),
    );

    await _startStreaming(targetUrl);
  }

  Future<void> _startStreaming(String initialUrl) async {
    _httpClient?.close(force: true);
    _httpClient = HttpClient()
      ..connectionTimeout = Duration(seconds: _config.connectionTimeoutSeconds);

    final client = _httpClient!;
    Uri uri = Uri.parse(initialUrl);

    try {
      final request = await client
          .getUrl(uri)
          .timeout(
            Duration(seconds: _config.connectionTimeoutSeconds),
            onTimeout: () {
              throw TimeoutException(
                'Connection timed out after ${_config.connectionTimeoutSeconds}s reaching $uri',
              );
            },
          );

      request.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace, image/jpeg, text/html, */*',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'AerialEYE-Flutter/1.0');

      final response = await request.close().timeout(
        Duration(seconds: _config.connectionTimeoutSeconds),
        onTimeout: () {
          throw TimeoutException(
            'Timed out waiting for HTTP response from $uri',
          );
        },
      );

      if (response.statusCode != HttpStatus.ok) {
        _handleError(
          CameraErrorCategory.httpError,
          'HTTP Server returned status ${response.statusCode} (${response.reasonPhrase})',
          'Endpoint returned non-200 status code. Verify aerialeye_view.py routes.',
        );
        return;
      }

      final contentType = response.headers.contentType?.mimeType ?? '';

      // If the endpoint is an HTML page embedding a stream
      if (contentType == 'text/html') {
        final bodyString = await response.transform(utf8.decoder).join();
        final streamUrl = extractStreamUrlFromHtml(bodyString, uri);
        if (streamUrl != null && streamUrl != uri.toString()) {
          debugPrint(
            '[PiCameraService] Detected embedded stream in HTML: $streamUrl',
          );
          await _startStreaming(streamUrl);
          return;
        } else {
          _handleError(
            CameraErrorCategory.invalidMimeType,
            'Endpoint returned HTML without a recognized stream source.',
            'The URL $uri returned a webpage, but no <img> tag or MJPEG stream was found.',
          );
          return;
        }
      }

      // Read stream and parse JPEG frames
      _processMjpegStream(response, uri.toString());
    } on SocketException catch (e) {
      _classifySocketException(e, uri);
    } on HandshakeException catch (e) {
      _handleError(
        CameraErrorCategory.networkUnreachable,
        'SSL/TLS Handshake failed: ${e.message}',
        'Local Raspberry Pi streaming uses standard cleartext HTTP (http://).',
      );
    } on TimeoutException catch (e) {
      _handleError(
        CameraErrorCategory.timeout,
        'Connection timed out: ${e.message}',
        'The Raspberry Pi at ${uri.host}:${uri.port} did not respond. Check if Pi is powered and connected to hotspot.',
      );
    } catch (e) {
      if (!_userExplicitlyDisconnected && !_isDisposed) {
        _handleError(
          CameraErrorCategory.unknown,
          'Streaming failed: ${e.toString()}',
          'Unexpected error while communicating with camera server.',
        );
      }
    }
  }

  void _processMjpegStream(HttpClientResponse response, String actualUrl) {
    final buffer = BytesBuilder(copy: false);
    _framesInCurrentSecond = 0;
    _lastFpsCalculationTime = DateTime.now();
    _previousFrameTime = null;

    _streamSubscription = response.listen(
      (chunk) {
        if (_isDisposed || _userExplicitlyDisconnected) return;
        buffer.add(chunk);

        // Process all complete JPEG frames currently in buffer
        final bytes = buffer.toBytes();
        final frames = extractJpegFrames(bytes);

        if (frames.isNotEmpty) {
          // Take the newest frame to render, keeping latency minimal
          final newest = frames.last;
          final latestDecoded = newest.bytes;
          _onNewFrameReceived(latestDecoded, actualUrl, frames.length);

          // If frame carries synchronized X-Detections header, notify listeners
          if (newest.detections != null && newest.detections!.isNotEmpty) {
            _detectionsController.add(newest.detections!);
            onFrameDetectionsReceived?.call(newest.detections!, latestDecoded);
          }

          // Keep remaining unparsed bytes (if any)
          buffer.clear();
          final remainingIndex = newest.endIndex;
          if (remainingIndex < bytes.length) {
            buffer.add(bytes.sublist(remainingIndex));
          }
        } else if (buffer.length > 5 * 1024 * 1024) {
          // Buffer safety guard: if more than 5MB accumulated with no valid JPEG marker, reset
          buffer.clear();
          debugPrint(
            '[PiCameraService] Buffer exceeded 5MB without JPEG markers. Resetting buffer.',
          );
        }
      },
      onError: (error) {
        if (!_userExplicitlyDisconnected && !_isDisposed) {
          _handleStreamSevered(error.toString());
        }
      },
      onDone: () {
        if (!_userExplicitlyDisconnected && !_isDisposed) {
          _handleStreamSevered(
            'Raspberry Pi camera stream terminated by remote server.',
          );
        }
      },
      cancelOnError: true,
    );
  }

  void _onNewFrameReceived(
    Uint8List frameBytes,
    String url,
    int framesExtracted,
  ) {
    _latestFrame = frameBytes;
    _frameController.add(frameBytes);

    final now = DateTime.now();
    int latency = 0;
    if (_previousFrameTime != null) {
      latency = now.difference(_previousFrameTime!).inMilliseconds;
    }
    _previousFrameTime = now;

    _framesInCurrentSecond += framesExtracted;
    final diffMs = now.difference(_lastFpsCalculationTime).inMilliseconds;
    double currentFps = _currentState.fps;
    if (diffMs >= 1000) {
      currentFps = (_framesInCurrentSecond * 1000.0) / max(diffMs, 1);
      _framesInCurrentSecond = 0;
      _lastFpsCalculationTime = now;
    }

    // Parse image dimensions if possible from JPEG header
    final dimensions = getJpegDimensions(frameBytes);

    _updateState(
      _currentState.copyWith(
        status: CameraStatus.connected,
        errorCategory: CameraErrorCategory.none,
        errorMessage: null,
        diagnosticDetails: 'Active stream receiving frames smoothly.',
        connectedUrl: url,
        fps: double.parse(currentFps.toStringAsFixed(1)),
        latencyMs: latency,
        totalFramesReceived:
            _currentState.totalFramesReceived + framesExtracted,
        totalBytesReceived:
            _currentState.totalBytesReceived + frameBytes.length,
        lastFrameTime: now,
        retryAttempt: 0,
        imageWidth: dimensions?.width ?? _currentState.imageWidth,
        imageHeight: dimensions?.height ?? _currentState.imageHeight,
      ),
    );
  }

  void _handleStreamSevered(String reason) {
    debugPrint('[PiCameraService] Stream severed: $reason');
    if (_config.autoReconnect &&
        _currentState.retryAttempt < _config.maxRetries) {
      final nextAttempt = _currentState.retryAttempt + 1;
      _updateState(
        _currentState.copyWith(
          status: CameraStatus.reconnecting,
          errorCategory: CameraErrorCategory.streamSevered,
          errorMessage: 'Camera connection lost. Reconnecting...',
          diagnosticDetails: reason,
          retryAttempt: nextAttempt,
        ),
      );

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(
        Duration(seconds: _config.reconnectIntervalSeconds),
        () {
          if (!_userExplicitlyDisconnected && !_isDisposed) {
            _startStreaming(_config.baseUrl);
          }
        },
      );
    } else {
      _updateState(
        _currentState.copyWith(
          status: CameraStatus.error,
          errorCategory: CameraErrorCategory.streamSevered,
          errorMessage: 'Camera stream disconnected.',
          diagnosticDetails: reason,
        ),
      );
    }
  }

  void _classifySocketException(SocketException e, Uri uri) {
    final msg = e.message.toLowerCase();
    final osError = e.osError?.message.toLowerCase() ?? '';

    if (msg.contains('connection refused') ||
        osError.contains('connection refused')) {
      _handleError(
        CameraErrorCategory.connectionRefused,
        'Connection refused on port ${uri.port}',
        'Raspberry Pi at ${uri.host} is reachable, but nothing is listening on port ${uri.port}. Make sure aerialeye_view.py is running on the Pi.',
      );
    } else if (msg.contains('cleartext') || osError.contains('cleartext')) {
      _handleError(
        CameraErrorCategory.cleartextTrafficBlocked,
        'Cleartext HTTP traffic blocked by Android OS',
        'Android network policy blocked unencrypted HTTP to ${uri.host}.',
      );
    } else if (msg.contains('network is unreachable') ||
        osError.contains('network is unreachable')) {
      _handleError(
        CameraErrorCategory.networkUnreachable,
        'Local network is unreachable',
        'Phone hotspot or Wi-Fi network routing error. Confirm Pi is on same hotspot network.',
      );
    } else if (msg.contains('no route to host') ||
        osError.contains('no route to host')) {
      _handleError(
        CameraErrorCategory.networkUnreachable,
        'No route to Raspberry Pi at ${uri.host}',
        'The Pi IP may have changed after reconnecting to the mobile hotspot.',
      );
    } else {
      _handleError(
        CameraErrorCategory.networkUnreachable,
        'Unable to reach Raspberry Pi: ${e.message}',
        'Check that the phone hotspot is on, Pi is connected, and IP matches ${uri.host}.',
      );
    }
  }

  void _handleError(
    CameraErrorCategory category,
    String message,
    String details,
  ) {
    debugPrint('[PiCameraService Error] $category: $message ($details)');
    _updateState(
      _currentState.copyWith(
        status: CameraStatus.error,
        errorCategory: category,
        errorMessage: message,
        diagnosticDetails: details,
      ),
    );
  }

  /// Explicitly disconnects from the camera stream
  Future<void> disconnect() async {
    _userExplicitlyDisconnected = true;
    _reconnectTimer?.cancel();
    await _closeActiveStream();

    _updateState(
      _currentState.copyWith(
        status: CameraStatus.disconnected,
        errorMessage: null,
        diagnosticDetails: 'Stream disconnected by operator.',
        fps: 0.0,
        latencyMs: 0,
      ),
    );
  }

  /// Retries connecting to the current configured URL
  Future<void> retry() async {
    await connect(_config);
  }

  Future<void> _closeActiveStream() async {
    try {
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      _httpClient?.close(force: true);
      _httpClient = null;
    } catch (e) {
      debugPrint('[PiCameraService] Error closing stream: $e');
    }
  }

  void _updateState(CameraStreamState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }

  /// Runs a comprehensive connection diagnostic without interrupting current live session
  Future<CameraDiagnosticsResult> testConnection([
    CameraConnectionConfig? testConfig,
  ]) async {
    final cfg = testConfig ?? _config;
    final logs = <String>[];
    final stopwatch = Stopwatch()..start();

    logs.add('[1/5] Validating URL syntax: ${cfg.baseUrl}');
    final validation = CameraConnectionConfig.validateUrl(cfg.baseUrl);
    if (!validation.isValid) {
      logs.add('FAILED: ${validation.errorMessage}');
      final res = CameraDiagnosticsResult(
        isSuccess: false,
        stage: 'URL Validation',
        message: validation.errorMessage ?? 'Invalid URL format',
        technicalDetails:
            'Provide a valid IPv4 address and port, e.g. http://10.174.17.87:8080',
        stepLogs: logs,
        timestamp: DateTime.now(),
      );
      _diagnosticsController.add(res);
      return res;
    }
    logs.add(
      'PASSED: Target Host = ${validation.host}, Port = ${validation.port}',
    );

    final host = validation.host!;
    final port = validation.port!;
    final normalized = validation.normalizedUrl!;
    final uri = Uri.parse(normalized);

    // 2. TCP Socket connect test
    logs.add('[2/5] Testing TCP socket reachability to $host:$port...');
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(seconds: cfg.connectionTimeoutSeconds),
      );
      socket.destroy();
      logs.add('PASSED: TCP handshake succeeded on port $port');
    } on SocketException catch (e) {
      final msg = e.message.toLowerCase();
      String techDetails = 'Socket error: ${e.message}';
      String userMsg = 'Could not reach $host on port $port.';
      if (msg.contains('connection refused')) {
        userMsg =
            'Connection refused. Pi is online, but camera server is stopped.';
        techDetails =
            'Port $port refused connection. Ensure "python3 ~/aerialeye_view.py" is running.';
      } else {
        userMsg = 'Host unreachable. Check phone hotspot and Pi connection.';
        techDetails =
            'No network route to $host. Ensure Pi is connected to the same mobile hotspot.';
      }
      logs.add('FAILED: $userMsg');
      final res = CameraDiagnosticsResult(
        isSuccess: false,
        stage: 'TCP Socket Connect',
        message: userMsg,
        technicalDetails: techDetails,
        stepLogs: logs,
        timestamp: DateTime.now(),
      );
      _diagnosticsController.add(res);
      return res;
    } catch (e) {
      logs.add('FAILED: Unexpected socket error: $e');
      final res = CameraDiagnosticsResult(
        isSuccess: false,
        stage: 'TCP Socket Connect',
        message: 'Socket test failed: $e',
        technicalDetails: e.toString(),
        stepLogs: logs,
        timestamp: DateTime.now(),
      );
      _diagnosticsController.add(res);
      return res;
    }

    // 3. HTTP GET probe
    logs.add('[3/5] Sending HTTP GET probe to $uri...');
    final diagClient = HttpClient()
      ..connectionTimeout = Duration(seconds: cfg.connectionTimeoutSeconds);
    try {
      final req = await diagClient
          .getUrl(uri)
          .timeout(Duration(seconds: cfg.connectionTimeoutSeconds));
      req.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace, image/jpeg, text/html, */*',
      );
      final resp = await req.close().timeout(
        Duration(seconds: cfg.connectionTimeoutSeconds),
      );

      logs.add(
        'PASSED: HTTP Response received: ${resp.statusCode} ${resp.reasonPhrase}',
      );
      if (resp.statusCode != HttpStatus.ok) {
        logs.add('FAILED: Server returned HTTP ${resp.statusCode}');
        final res = CameraDiagnosticsResult(
          isSuccess: false,
          stage: 'HTTP Handshake',
          message:
              'Server returned HTTP ${resp.statusCode} (${resp.reasonPhrase})',
          technicalDetails:
              'Expected HTTP 200 OK from camera viewing endpoint.',
          stepLogs: logs,
          timestamp: DateTime.now(),
        );
        _diagnosticsController.add(res);
        return res;
      }

      // 4. Content-Type and payload inspection
      final contentType = resp.headers.contentType?.mimeType ?? 'unknown';
      logs.add('[4/5] Content-Type detected: $contentType');

      String resolvedEndpoint = uri.toString();
      if (contentType == 'text/html') {
        final html = await resp.transform(utf8.decoder).join();
        final foundStream = extractStreamUrlFromHtml(html, uri);
        if (foundStream != null) {
          resolvedEndpoint = foundStream;
          logs.add(
            'PASSED: Extracted stream endpoint from HTML: $resolvedEndpoint',
          );
        } else {
          logs.add(
            'FAILED: HTML received, but no embedded stream <img> tag found.',
          );
          final res = CameraDiagnosticsResult(
            isSuccess: false,
            stage: 'MIME Negotiation',
            message: 'Endpoint returned HTML with no video stream.',
            technicalDetails:
                'HTML contents did not have an <img src="..."> stream link.',
            stepLogs: logs,
            timestamp: DateTime.now(),
          );
          _diagnosticsController.add(res);
          return res;
        }
      }

      // 5. Test frame decoding from the stream
      logs.add('[5/5] Testing frame reception and JPEG marker validation...');
      final frameCompleter = Completer<bool>();
      final testBuffer = BytesBuilder(copy: false);
      StreamSubscription<List<int>>? testSub;

      testSub = resp.listen(
        (chunk) {
          testBuffer.add(chunk);
          final frames = extractJpegFrames(testBuffer.toBytes());
          if (frames.isNotEmpty && !frameCompleter.isCompleted) {
            frameCompleter.complete(true);
          }
        },
        onError: (err) {
          if (!frameCompleter.isCompleted) {
            frameCompleter.completeError(err);
          }
        },
        onDone: () {
          if (!frameCompleter.isCompleted) {
            frameCompleter.complete(false);
          }
        },
      );

      final receivedValidFrame = await frameCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );

      await testSub.cancel();
      stopwatch.stop();

      if (receivedValidFrame) {
        logs.add('PASSED: Valid JPEG frame decoded (SOI: 0xFFD8, EOI: 0xFFD9)');
        final res = CameraDiagnosticsResult(
          isSuccess: true,
          stage: 'Completed',
          message: 'Raspberry Pi Camera Feed is online and streaming!',
          technicalDetails:
              'Connected to $host:$port ($contentType). Frames successfully decoded in ${stopwatch.elapsedMilliseconds}ms.',
          roundTripMs: stopwatch.elapsedMilliseconds,
          resolvedEndpoint: resolvedEndpoint,
          detectedContentType: contentType,
          stepLogs: logs,
          timestamp: DateTime.now(),
        );
        _diagnosticsController.add(res);
        return res;
      } else {
        logs.add(
          'FAILED: Connected to HTTP server, but no valid JPEG frames were received.',
        );
        final res = CameraDiagnosticsResult(
          isSuccess: false,
          stage: 'Frame Decoding',
          message: 'Connected to server, but no camera frames received.',
          technicalDetails:
              'Ensure camera module OV5647 is enabled and aerialeye_live.py is capturing.',
          stepLogs: logs,
          timestamp: DateTime.now(),
        );
        _diagnosticsController.add(res);
        return res;
      }
    } catch (e) {
      logs.add('FAILED: Diagnostic error: $e');
      final res = CameraDiagnosticsResult(
        isSuccess: false,
        stage: 'HTTP Probe',
        message:
            'HTTP probe failed: ${e.toString().replaceAll("Exception: ", "")}',
        technicalDetails: e.toString(),
        stepLogs: logs,
        timestamp: DateTime.now(),
      );
      _diagnosticsController.add(res);
      return res;
    } finally {
      diagClient.close(force: true);
    }
  }

  /// Parses an HTML string to find an embedded video stream `<img src="...">`
  static String? extractStreamUrlFromHtml(String html, Uri baseUri) {
    final imgRegex = RegExp(
      r'<img[^>]+src=["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    );
    final match = imgRegex.firstMatch(html);
    if (match != null) {
      final src = match.group(1);
      if (src != null && src.isNotEmpty) {
        return baseUri.resolve(src).toString();
      }
    }
    return null;
  }

  /// Extracts complete JPEG frames from a byte buffer by locating 0xFF,0xD8 (SOI) and 0xFF,0xD9 (EOI)
  static List<ParsedJpegFrame> extractJpegFrames(Uint8List data) {
    final frames = <ParsedJpegFrame>[];
    int i = 0;

    while (i < data.length - 1) {
      // Find SOI marker: 0xFF, 0xD8
      if (data[i] == 0xFF && data[i + 1] == 0xD8) {
        final startIndex = i;
        int endIndex = -1;

        // Search for EOI marker: 0xFF, 0xD9
        for (int j = startIndex + 2; j < data.length - 1; j++) {
          if (data[j] == 0xFF && data[j + 1] == 0xD9) {
            endIndex = j + 2;
            break;
          }
        }

        if (endIndex != -1) {
          final frameBytes = data.sublist(startIndex, endIndex);

          // Check if frame was preceded by multipart X-Detections header
          List<Map<String, dynamic>>? frameDetections;
          if (startIndex > 0) {
            final headerLookback = max(0, startIndex - 1024);
            try {
              final headerStr = ascii.decode(
                data.sublist(headerLookback, startIndex),
                allowInvalid: true,
              );
              final match = RegExp(
                r'X-Detections:\s*([^\r\n]+)',
                caseSensitive: false,
              ).firstMatch(headerStr);
              if (match != null) {
                final jsonStr = match.group(1)!.trim();
                final decoded = jsonDecode(jsonStr);
                if (decoded is List) {
                  frameDetections = decoded.cast<Map<String, dynamic>>();
                } else if (decoded is Map && decoded['detections'] is List) {
                  frameDetections = (decoded['detections'] as List)
                      .cast<Map<String, dynamic>>();
                }
              }
            } catch (_) {}
          }

          frames.add(
            ParsedJpegFrame(
              bytes: frameBytes,
              startIndex: startIndex,
              endIndex: endIndex,
              detections: frameDetections,
            ),
          );
          i = endIndex;
        } else {
          // Incomplete frame, wait for more data
          break;
        }
      } else {
        i++;
      }
    }

    return frames;
  }

  /// Extracts width and height from JPEG SOF0/SOF2 marker
  static JpegDimensions? getJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    int i = 2;
    while (i < bytes.length - 8) {
      if (bytes[i] == 0xFF) {
        final marker = bytes[i + 1];
        // SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2)
        if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
          final height = (bytes[i + 5] << 8) | bytes[i + 6];
          final width = (bytes[i + 7] << 8) | bytes[i + 8];
          return JpegDimensions(width: width, height: height);
        }
        final length = (bytes[i + 2] << 8) | bytes[i + 3];
        i += 2 + length;
      } else {
        i++;
      }
    }
    return null;
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _closeActiveStream();
    _stateController.close();
    _frameController.close();
    _diagnosticsController.close();
    _detectionsController.close();
  }
}

class ParsedJpegFrame {
  final Uint8List bytes;
  final int startIndex;
  final int endIndex;
  final List<Map<String, dynamic>>? detections;

  const ParsedJpegFrame({
    required this.bytes,
    required this.startIndex,
    required this.endIndex,
    this.detections,
  });
}

class JpegDimensions {
  final int width;
  final int height;

  const JpegDimensions({required this.width, required this.height});
}
