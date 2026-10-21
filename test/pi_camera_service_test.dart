import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/camera_connection_config.dart';
import 'package:aerial_eye/models/camera_diagnostics.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/services/pi_camera_service.dart';

void main() {
  group('CameraConnectionConfig URL Validation Tests', () {
    test('Default Raspberry Pi URL validates successfully', () {
      final res = CameraConnectionConfig.validateUrl(
        'http://10.174.17.87:8080',
      );
      expect(res.isValid, isTrue);
      expect(res.host, '10.174.17.87');
      expect(res.port, 8080);
      expect(res.normalizedUrl, 'http://10.174.17.87:8080');
    });

    test('Bare IP and port automatically normalizes to http scheme', () {
      final res = CameraConnectionConfig.validateUrl('10.174.17.87:8080');
      expect(res.isValid, isTrue);
      expect(res.host, '10.174.17.87');
      expect(res.port, 8080);
      expect(res.normalizedUrl, 'http://10.174.17.87:8080');
    });

    test('Valid hostname and custom port validates', () {
      final res = CameraConnectionConfig.validateUrl(
        'http://raspberrypi.local:8080/video_feed',
      );
      expect(res.isValid, isTrue);
      expect(res.host, 'raspberrypi.local');
      expect(res.port, 8080);
    });

    test('Rejects empty or whitespace-only URL', () {
      final res = CameraConnectionConfig.validateUrl('   ');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('cannot be empty'));
    });

    test('Rejects unsupported schemes like rtsp:// or ftp://', () {
      final res = CameraConnectionConfig.validateUrl(
        'rtsp://10.174.17.87:8554/live',
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Unsupported scheme'));
    });

    test('Rejects invalid IPv4 octets greater than 255', () {
      final res = CameraConnectionConfig.validateUrl(
        'http://299.174.17.87:8080',
      );
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('Invalid IPv4 octet'));
    });

    test('Rejects invalid port numbers out of 1-65535 range', () {
      final res0 = CameraConnectionConfig.validateUrl('http://10.174.17.87:0');
      expect(res0.isValid, isFalse);

      final resLarge = CameraConnectionConfig.validateUrl(
        'http://10.174.17.87:70000',
      );
      expect(resLarge.isValid, isFalse);
    });
  });

  group('CameraConnectionConfig Serialization Tests', () {
    test('Default config has correct initial values', () {
      final config = CameraConnectionConfig.defaultConfig();
      expect(config.baseUrl, 'http://10.174.17.87:8080');
      expect(config.host, '10.174.17.87');
      expect(config.port, 8080);
      expect(config.autoReconnect, isTrue);
    });

    test('JSON serialization round-trip preserves values', () {
      const original = CameraConnectionConfig(
        baseUrl: 'http://192.168.43.100:5000/stream',
        connectionTimeoutSeconds: 8,
        reconnectIntervalSeconds: 4,
        autoReconnect: false,
        maxRetries: 3,
        autoConnect: true,
      );

      final json = original.toJson();
      final restored = CameraConnectionConfig.fromJson(json);

      expect(restored.baseUrl, original.baseUrl);
      expect(
        restored.connectionTimeoutSeconds,
        original.connectionTimeoutSeconds,
      );
      expect(
        restored.reconnectIntervalSeconds,
        original.reconnectIntervalSeconds,
      );
      expect(restored.autoReconnect, original.autoReconnect);
      expect(restored.maxRetries, original.maxRetries);
      expect(restored.autoConnect, original.autoConnect);
      expect(restored.host, '192.168.43.100');
      expect(restored.port, 5000);
    });

    test('copyWith properly overrides individual properties', () {
      final original = CameraConnectionConfig.defaultConfig();
      final updated = original.copyWith(
        baseUrl: 'http://10.174.17.90:8080',
        autoConnect: true,
      );

      expect(updated.baseUrl, 'http://10.174.17.90:8080');
      expect(updated.autoConnect, isTrue);
      expect(
        updated.connectionTimeoutSeconds,
        original.connectionTimeoutSeconds,
      );
      expect(updated.autoReconnect, original.autoReconnect);
    });
  });

  group('MJPEG Stream & Frame Parser Tests', () {
    test(
      'Extracts valid JPEG frame delimited by SOI (0xFFD8) and EOI (0xFFD9)',
      () {
        // Create synthetic multipart MJPEG chunk with header and JPEG payload
        final header = '--frame\r\nContent-Type: image/jpeg\r\n\r\n'.codeUnits;
        final jpegPayload = [0xFF, 0xD8, 0x01, 0x02, 0x03, 0x04, 0xFF, 0xD9];
        final rawData = Uint8List.fromList([...header, ...jpegPayload]);

        final frames = PiCameraService.extractJpegFrames(rawData);
        expect(frames.length, 1);
        expect(
          frames.first.bytes,
          equals([0xFF, 0xD8, 0x01, 0x02, 0x03, 0x04, 0xFF, 0xD9]),
        );
        expect(frames.first.startIndex, header.length);
        expect(frames.first.endIndex, rawData.length);
      },
    );

    test('Extracts multiple concatenated frames in single buffer', () {
      final frame1 = [0xFF, 0xD8, 0x10, 0x20, 0xFF, 0xD9];
      final frame2 = [0xFF, 0xD8, 0x30, 0x40, 0x50, 0xFF, 0xD9];
      final boundary = '--boundary\r\n'.codeUnits;
      final rawData = Uint8List.fromList([
        ...boundary,
        ...frame1,
        ...boundary,
        ...frame2,
      ]);

      final frames = PiCameraService.extractJpegFrames(rawData);
      expect(frames.length, 2);
      expect(frames[0].bytes, equals(frame1));
      expect(frames[1].bytes, equals(frame2));
    });

    test('Returns empty list when frame is incomplete (missing EOI)', () {
      final incomplete = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02, 0x03]);
      final frames = PiCameraService.extractJpegFrames(incomplete);
      expect(frames, isEmpty);
    });

    test('Extracts image dimensions from JPEG SOF0 header', () {
      // Synthetic SOF0 marker: 0xFF, 0xC0, len_hi, len_lo, precision, h_hi, h_lo, w_hi, w_lo
      // Height: 480 (0x01E0), Width: 640 (0x0280)
      final jpegData = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, 0x00, 0x11, 0x08, 0x01, 0xE0, 0x02, 0x80, // SOF0: 640x480
        0xFF, 0xD9, // EOI
      ]);

      final dims = PiCameraService.getJpegDimensions(jpegData);
      expect(dims, isNotNull);
      expect(dims?.width, 640);
      expect(dims?.height, 480);
    });
  });

  group('HTML Stream URL Resolution Tests', () {
    test('Resolves relative <img> src from Flask viewing webpage', () {
      const html = '''
        <!DOCTYPE html>
        <html>
          <head><title>AerialEYE Camera</title></head>
          <body>
            <h1>Live OV5647 Stream</h1>
            <img src="/video_feed" width="640" height="480" />
          </body>
        </html>
      ''';

      final baseUri = Uri.parse('http://10.174.17.87:8080');
      final streamUrl = PiCameraService.extractStreamUrlFromHtml(html, baseUri);
      expect(streamUrl, 'http://10.174.17.87:8080/video_feed');
    });

    test('Resolves absolute <img> src from webpage', () {
      const html = '''
        <html>
          <img src="http://10.174.17.87:8080/stream.mjpg">
        </html>
      ''';

      final baseUri = Uri.parse('http://10.174.17.87:8080');
      final streamUrl = PiCameraService.extractStreamUrlFromHtml(html, baseUri);
      expect(streamUrl, 'http://10.174.17.87:8080/stream.mjpg');
    });

    test('Returns null when HTML contains no <img> tag', () {
      const html = '<html><body><h1>No Camera Found</h1></body></html>';
      final baseUri = Uri.parse('http://10.174.17.87:8080');
      final streamUrl = PiCameraService.extractStreamUrlFromHtml(html, baseUri);
      expect(streamUrl, isNull);
    });
  });

  group('CameraStreamState & Diagnostics Tests', () {
    test('Initial camera state is disconnected', () {
      final state = CameraStreamState.initial();
      expect(state.status, CameraStatus.disconnected);
      expect(state.isConnected, isFalse);
      expect(state.statusDisplay, 'DISCONNECTED');
      expect(state.fps, 0.0);
    });

    test('Status display reflects active states', () {
      const connectedState = CameraStreamState(
        status: CameraStatus.connected,
        fps: 28.5,
        latencyMs: 38,
      );
      expect(connectedState.isConnected, isTrue);
      expect(connectedState.statusDisplay, 'LIVE STREAM');

      const reconnectingState = CameraStreamState(
        status: CameraStatus.reconnecting,
        retryAttempt: 2,
        maxRetries: 5,
      );
      expect(reconnectingState.isReconnecting, isTrue);
      expect(reconnectingState.statusDisplay, contains('RECONNECTING (2/5)'));

      const errorState = CameraStreamState(
        status: CameraStatus.error,
        errorCategory: CameraErrorCategory.connectionRefused,
      );
      expect(errorState.hasError, isTrue);
      expect(errorState.statusDisplay, 'STREAM ERROR');
    });

    test('Diagnostics model stores technical step logs and stage', () {
      final diag = CameraDiagnosticsResult(
        isSuccess: true,
        stage: 'Completed',
        message: 'Camera is online',
        technicalDetails: 'Response received in 42ms',
        roundTripMs: 42,
        resolvedEndpoint: 'http://10.174.17.87:8080/video_feed',
        detectedContentType: 'multipart/x-mixed-replace',
        stepLogs: ['[1/5] URL validated', '[2/5] Socket connected'],
        timestamp: DateTime.now(),
      );

      expect(diag.isSuccess, isTrue);
      expect(diag.stage, 'Completed');
      expect(diag.roundTripMs, 42);
      expect(diag.stepLogs.length, 2);
    });
  });
}
