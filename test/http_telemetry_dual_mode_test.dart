import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';
import 'package:aerial_eye/services/pi_http_telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MavlinkConnectionConfig Dual Mode Unit Tests', () {
    test('Default config has UDP transport and valid HTTP defaults', () {
      final config = MavlinkConnectionConfig.defaultConfig();
      expect(config.transport, equals(MavlinkTransport.udp));
      expect(config.httpBaseUrl, equals('http://10.174.17.87:8081'));
      expect(config.httpPollingIntervalMs, equals(1000));
      expect(config.httpTimeoutSeconds, equals(3));
      expect(config.validate(), isEmpty);
    });

    test(
      'HTTP config serialization and deserialization retains all fields',
      () {
        const config = MavlinkConnectionConfig(
          transport: MavlinkTransport.http,
          httpBaseUrl: 'http://192.168.43.87:8081',
          httpPollingIntervalMs: 500,
          httpTimeoutSeconds: 5,
        );

        final json = config.toJson();
        expect(json['transport'], equals('http'));
        expect(json['httpBaseUrl'], equals('http://192.168.43.87:8081'));
        expect(json['httpPollingIntervalMs'], equals(500));
        expect(json['httpTimeoutSeconds'], equals(5));

        final restored = MavlinkConnectionConfig.fromJson(json);
        expect(restored.transport, equals(MavlinkTransport.http));
        expect(restored.httpBaseUrl, equals('http://192.168.43.87:8081'));
        expect(restored.httpPollingIntervalMs, equals(500));
        expect(restored.httpTimeoutSeconds, equals(5));
        expect(restored.validate(), isEmpty);
      },
    );

    test('Backward compatibility: JSON without transport defaults to UDP', () {
      final legacyJson = {
        'connectionMode': 'listener',
        'bindAddress': '0.0.0.0',
        'localPort': 14550,
      };

      final restored = MavlinkConnectionConfig.fromJson(legacyJson);
      expect(restored.transport, equals(MavlinkTransport.udp));
      expect(restored.localPort, equals(14550));
      expect(restored.httpBaseUrl, equals('http://10.174.17.87:8081'));
    });

    test('Validation catches invalid HTTP settings in HTTP mode', () {
      // Empty URL
      var cfg = const MavlinkConnectionConfig(
        transport: MavlinkTransport.http,
        httpBaseUrl: '',
      );
      expect(
        cfg.validate(),
        contains('Raspberry Pi HTTP Base URL is required'),
      );

      // Non-HTTP scheme
      cfg = const MavlinkConnectionConfig(
        transport: MavlinkTransport.http,
        httpBaseUrl: 'ftp://10.174.17.87:8081',
      );
      expect(
        cfg.validate().any(
          (e) => e.contains('must start with http:// or https://'),
        ),
        isTrue,
      );

      // Polling interval too low
      cfg = const MavlinkConnectionConfig(
        transport: MavlinkTransport.http,
        httpBaseUrl: 'http://10.174.17.87:8081',
        httpPollingIntervalMs: 100,
      );
      expect(
        cfg.validate().any((e) => e.contains('interval must be between 200ms')),
        isTrue,
      );

      // Polling interval too high
      cfg = const MavlinkConnectionConfig(
        transport: MavlinkTransport.http,
        httpBaseUrl: 'http://10.174.17.87:8081',
        httpPollingIntervalMs: 20000,
      );
      expect(
        cfg.validate().any(
          (e) => e.contains('interval must be between 200ms and 10000ms'),
        ),
        isTrue,
      );

      // Valid HTTP config
      cfg = const MavlinkConnectionConfig(
        transport: MavlinkTransport.http,
        httpBaseUrl: 'http://10.174.17.87:8081',
        httpPollingIntervalMs: 1000,
        httpTimeoutSeconds: 3,
      );
      expect(cfg.validate(), isEmpty);
    });
  });

  group('DroneTelemetry Battery & Null Handling Tests', () {
    test('batteryPercentDisplay formats negative values as dashes', () {
      final unavailable = DroneTelemetry.initial().copyWith(
        batteryPercentage: -1.0,
        hasReceivedBattery: true,
      );
      expect(unavailable.batteryPercentage, equals(-1.0));
      expect(unavailable.isBatteryPercentAvailable, isFalse);
      expect(unavailable.batteryPercentDisplay, equals('--'));

      final available = DroneTelemetry.initial().copyWith(
        batteryPercentage: 84.5,
        hasReceivedBattery: true,
      );
      expect(available.batteryPercentage, equals(84.5));
      expect(available.isBatteryPercentAvailable, isTrue);
      expect(available.batteryPercentDisplay, equals('85%'));
    });
  });

  group('PiHttpTelemetryService Payload Parsing Tests', () {
    test('Parses full valid telemetry JSON payload correctly', () {
      final sampleJson = {
        'mode': 'LOITER',
        'armed': true,
        'relative_altitude_m': 14.8,
        'altitude_m': 42.1,
        'heading_deg': 245.5,
        'roll_deg': 1.5,
        'pitch_deg': -2.3,
        'battery_voltage_v': 12.35,
        'battery_remaining_pct': 82,
        'gps_fix': 3,
        'gps_satellites': 12,
        'gps_valid': true,
        'latitude': 18.52043,
        'longitude': 73.85674,
        'last_update': 1700000000.5,
      };

      final telem = PiHttpTelemetryService.parseJson(sampleJson);

      expect(telem.flightMode, equals('LOITER'));
      expect(telem.armed, isTrue);
      expect(telem.relativeAltitude, equals(14.8));
      expect(telem.altitude, equals(42.1));
      expect(telem.heading, equals(245.5));
      expect(telem.yaw, equals(245.5));
      expect(telem.roll, equals(1.5));
      expect(telem.pitch, equals(-2.3));
      expect(telem.batteryVoltage, equals(12.35));
      expect(telem.batteryPercentage, equals(82.0));
      expect(telem.batteryPercentDisplay, equals('82%'));
      expect(telem.satellites, equals(12));
      expect(telem.gpsFix, equals(3));
      expect(telem.latitude, equals(18.52043));
      expect(telem.longitude, equals(73.85674));
      expect(telem.hasReceivedPosition, isTrue);
      expect(telem.hasReceivedAttitude, isTrue);
      expect(telem.isStale, isFalse);
    });

    test(
      'Null battery remaining percentage preserves voltage and formats as dashes',
      () {
        final sampleJson = {
          'mode': 'ALT_HOLD',
          'armed': false,
          'battery_voltage_v': 11.9,
          'battery_remaining_pct': null, // APM 2.8 voltage-only sensor
        };

        final telem = PiHttpTelemetryService.parseJson(sampleJson);

        expect(telem.batteryVoltage, equals(11.9));
        expect(telem.batteryPercentage, equals(-1.0));
        expect(telem.isBatteryPercentAvailable, isFalse);
        expect(telem.batteryPercentDisplay, equals('--'));
        expect(telem.batteryVoltageDisplay, equals('11.9 V'));
      },
    );

    test(
      'Invalid GPS fix or gps_valid false prevents applying invalid coordinates',
      () {
        final invalidGpsJson = {
          'gps_fix': 1, // No fix
          'gps_valid': false,
          'latitude': 0.0,
          'longitude': 0.0,
        };

        final telem = PiHttpTelemetryService.parseJson(invalidGpsJson);

        expect(telem.hasReceivedPosition, isFalse);
        expect(telem.gpsFix, equals(1));
        // Coordinates remain 0.0 without triggering valid position flag
        expect(telem.latitude, equals(0.0));
        expect(telem.longitude, equals(0.0));
      },
    );

    test(
      'Valid GPS 2D fix (fix == 2) with gps_valid true enables position flag',
      () {
        final gps2DJson = {
          'gps_fix': 2,
          'gps_valid': true,
          'latitude': 18.53,
          'longitude': 73.86,
        };

        final telem = PiHttpTelemetryService.parseJson(gps2DJson);

        expect(telem.hasReceivedPosition, isTrue);
        expect(telem.gpsFix, equals(2));
        expect(telem.latitude, equals(18.53));
        expect(telem.longitude, equals(73.86));
      },
    );
  });

  group('Mock HTTP Server & PiHttpTelemetryService Integration', () {
    late HttpServer mockServer;
    late int serverPort;
    bool shouldReturnSuccess = true;

    setUp(() async {
      HttpOverrides.global = null;
      shouldReturnSuccess = true;
      mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = mockServer.port;

      mockServer.listen((HttpRequest request) {
        if (!shouldReturnSuccess) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('Internal Server Error');
          request.response.close();
          return;
        }

        if (request.uri.path == '/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'status': 'ok',
              'service': 'aerialeye-telemetry',
              'fc_connected': true,
              'fc_heartbeat': true,
              'mode': 'LOITER',
              'armed': false,
            }),
          );
          request.response.close();
        } else if (request.uri.path == '/telemetry') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'mode': 'GUIDED',
              'armed': true,
              'relative_altitude_m': 10.2,
              'altitude_m': 35.0,
              'heading_deg': 90.0,
              'battery_voltage_v': 12.1,
              'battery_remaining_pct': 75,
              'connected': true,
              'heartbeat': true,
              'last_update': DateTime.now().millisecondsSinceEpoch / 1000.0,
            }),
          );
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });
    });

    tearDown(() async {
      await mockServer.close(force: true);
    });

    test('testEndpoint returns success on live server', () async {
      final service = PiHttpTelemetryService(
        config: MavlinkConnectionConfig(
          transport: MavlinkTransport.http,
          httpBaseUrl: 'http://127.0.0.1:$serverPort',
        ),
      );

      final result = await service.testEndpoint('http://127.0.0.1:$serverPort');
      expect(result.success, isTrue);
      expect(result.message, contains('OK'));
      expect(result.vehicleType, contains('APM 2.8'));

      service.dispose();
    });

    test('testEndpoint reports failure on server error', () async {
      shouldReturnSuccess = false;

      final service = PiHttpTelemetryService(
        config: MavlinkConnectionConfig(
          transport: MavlinkTransport.http,
          httpBaseUrl: 'http://127.0.0.1:$serverPort',
        ),
      );

      final result = await service.testEndpoint('http://127.0.0.1:$serverPort');
      expect(result.success, isFalse);

      service.dispose();
    });

    test(
      'Live polling emits telemetry on stream and transitions to connected',
      () async {
        final service = PiHttpTelemetryService(
          config: MavlinkConnectionConfig(
            transport: MavlinkTransport.http,
            httpBaseUrl: 'http://127.0.0.1:$serverPort',
            httpPollingIntervalMs: 200,
          ),
        );

        final telemetryFuture = service.telemetryStream.firstWhere(
          (t) => t.flightMode == 'GUIDED' && t.armed == true,
        );

        service.start();

        final received = await telemetryFuture.timeout(
          const Duration(seconds: 4),
        );
        expect(received.flightMode, equals('GUIDED'));
        expect(received.armed, isTrue);
        expect(received.relativeAltitude, equals(10.2));

        expect(service.connectionState, equals(DroneConnectionState.connected));

        service.stop();
        expect(
          service.connectionState,
          equals(DroneConnectionState.disconnected),
        );

        service.dispose();
      },
    );
  });

  group('MavlinkDroneService Dual Mode Command Safety Interlock', () {
    test(
      'Throws UnsupportedError on flight commands when in HTTP mode',
      () async {
        final droneService = MavlinkDroneService(
          initialConfig: const MavlinkConnectionConfig(
            transport: MavlinkTransport.http,
            httpBaseUrl: 'http://10.174.17.87:8081',
          ),
        );

        expect(() => droneService.arm(), throwsA(isA<UnsupportedError>()));
        expect(() => droneService.disarm(), throwsA(isA<UnsupportedError>()));
        expect(
          () => droneService.takeoff(5.0),
          throwsA(isA<UnsupportedError>()),
        );
        expect(() => droneService.land(), throwsA(isA<UnsupportedError>()));
        expect(
          () => droneService.returnToLaunch(),
          throwsA(isA<UnsupportedError>()),
        );
        expect(
          () => droneService.setFlightMode('LOITER'),
          throwsA(isA<UnsupportedError>()),
        );
        expect(
          () => droneService.uploadMission([]),
          throwsA(isA<UnsupportedError>()),
        );
        expect(
          () => droneService.clearMission(),
          throwsA(isA<UnsupportedError>()),
        );
        expect(
          () => droneService.startMission(),
          throwsA(isA<UnsupportedError>()),
        );
        expect(
          () => droneService.pauseMission(),
          throwsA(isA<UnsupportedError>()),
        );
        expect(
          () => droneService.resumeMission(),
          throwsA(isA<UnsupportedError>()),
        );

        // Request data streams should complete gracefully without error in HTTP mode
        expect(() => droneService.requestDataStreams(), returnsNormally);

        droneService.disconnect();
      },
    );
  });
}
