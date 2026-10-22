import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/pi_shutdown_config.dart';
import 'package:aerial_eye/models/pi_shutdown_state.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/pi_shutdown_service.dart';

// Test mock for DroneService to test flight safety interlocks
class MockDroneService implements DroneService {
  DroneTelemetry _telemetry = DroneTelemetry.initial();

  void setTelemetry(DroneTelemetry t) {
    _telemetry = t;
  }

  @override
  DroneTelemetry get currentTelemetry => _telemetry;

  @override
  DroneConnectionState get connectionState => DroneConnectionState.connected;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiShutdownConfig Unit Tests', () {
    test('Default configuration values match system specifications', () {
      final config = PiShutdownConfig.defaultConfig();
      expect(config.host, equals('10.174.17.87'));
      expect(config.port, equals(5005));
      expect(config.secretToken, isNotEmpty);
      expect(config.timeoutSeconds, equals(4));
    });

    test('JSON serialization round-trip retains all fields', () {
      const config = PiShutdownConfig(
        host: '192.168.1.100',
        port: 5050,
        secretToken: 'secret_token_abc_123',
        timeoutSeconds: 8,
      );

      final json = config.toJson();
      final restored = PiShutdownConfig.fromJson(json);

      expect(restored.host, equals('192.168.1.100'));
      expect(restored.port, equals(5050));
      expect(restored.secretToken, equals('secret_token_abc_123'));
      expect(restored.timeoutSeconds, equals(8));
    });

    test('copyWith updates specified fields only', () {
      final original = PiShutdownConfig.defaultConfig();
      final updated = original.copyWith(host: '10.0.0.99', port: 6000);

      expect(updated.host, equals('10.0.0.99'));
      expect(updated.port, equals(6000));
      expect(updated.secretToken, equals(original.secretToken));
      expect(updated.timeoutSeconds, equals(original.timeoutSeconds));
    });
  });

  group('PiShutdownState Display and Status Tests', () {
    test('Initial state properties', () {
      final state = PiShutdownState.initial();
      expect(state.status, equals(PiPowerStatus.unknown));
      expect(state.isOnline, isFalse);
      expect(state.isChecking, isFalse);
      expect(state.statusDisplay, equals('Status Unknown'));
    });

    test('Status display strings for all enum states', () {
      expect(
        PiShutdownState.initial().copyWith(status: PiPowerStatus.online).statusDisplay,
        equals('Online (Ready)'),
      );
      expect(
        PiShutdownState.initial().copyWith(status: PiPowerStatus.shuttingDown).statusDisplay,
        equals('Shutting Down...'),
      );
      expect(
        PiShutdownState.initial().copyWith(status: PiPowerStatus.shutdownComplete).statusDisplay,
        equals('Powered Off (Offline)'),
      );
      expect(
        PiShutdownState.initial().copyWith(status: PiPowerStatus.offline).statusDisplay,
        equals('Offline (Unreachable)'),
      );
      expect(
        PiShutdownState.initial().copyWith(status: PiPowerStatus.error).statusDisplay,
        equals('Connection Error'),
      );
    });
  });

  group('Flight Safety Interlock Tests', () {
    late MockDroneService mockDrone;
    late PiShutdownService service;

    setUp(() {
      mockDrone = MockDroneService();
      service = PiShutdownService(droneService: mockDrone);
    });

    tearDown(() {
      service.dispose();
    });

    test('Blocks shutdown when drone is ARMED', () async {
      mockDrone.setTelemetry(
        DroneTelemetry.initial().copyWith(
          armed: true,
          relativeAltitude: 0.0,
          flightMode: 'STABILIZE',
        ),
      );

      final safetyError = service.validateFlightSafety();
      expect(safetyError, isNotNull);
      expect(safetyError, contains('ARMED'));

      final result = await service.requestShutdown();
      expect(result.isBlockedByFlight, isTrue);
      expect(result.success, isFalse);
    });

    test('Blocks shutdown when drone is IN ACTIVE FLIGHT (altitude > 1m)', () async {
      mockDrone.setTelemetry(
        DroneTelemetry.initial().copyWith(
          armed: false,
          relativeAltitude: 2.5,
          speed: 0.2,
          flightMode: 'STABILIZE',
        ),
      );

      final safetyError = service.validateFlightSafety();
      expect(safetyError, isNotNull);
      expect(safetyError, contains('ACTIVE FLIGHT'));

      final result = await service.requestShutdown();
      expect(result.isBlockedByFlight, isTrue);
      expect(result.success, isFalse);
    });

    test('Blocks shutdown when drone is in AUTO / GUIDED mission mode', () async {
      mockDrone.setTelemetry(
        DroneTelemetry.initial().copyWith(
          armed: false,
          relativeAltitude: 0.0,
          flightMode: 'AUTO',
        ),
      );

      final safetyError = service.validateFlightSafety();
      expect(safetyError, isNotNull);
      expect(safetyError, contains('AUTO'));

      final result = await service.requestShutdown();
      expect(result.isBlockedByFlight, isTrue);
    });

    test('Permits shutdown when drone is on the ground, disarmed, in STABILIZE mode', () {
      mockDrone.setTelemetry(
        DroneTelemetry.initial().copyWith(
          armed: false,
          relativeAltitude: 0.0,
          speed: 0.0,
          flightMode: 'STABILIZE',
        ),
      );

      final safetyError = service.validateFlightSafety();
      expect(safetyError, isNull);
    });
  });

  group('HTTP Communication with Mock Server', () {
    late HttpServer server;
    late int serverPort;
    const testSecret = 'TEST_SHUTDOWN_KEY_4321';
    late PiShutdownService service;
    bool serverShutdownCalled = false;

    setUp(() async {
      HttpOverrides.global = null;
      serverShutdownCalled = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = server.port;

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        final authHeader = request.headers.value('x-aerialeye-token') ??
            request.headers.value('authorization');
        await request.drain<void>();

        if (path == '/status') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'status': 'online',
              'hostname': 'aerialeye',
              'shutdown_in_progress': serverShutdownCalled,
              'uptime_seconds': 123.4,
            }));
          await request.response.close();
        } else if (path == '/shutdown') {
          final isAuthorized = authHeader == testSecret ||
              authHeader == 'Bearer $testSecret';

          if (!isAuthorized) {
            request.response
              ..statusCode = HttpStatus.unauthorized
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Unauthorized'}));
            await request.response.close();
            return;
          }

          if (serverShutdownCalled) {
            request.response
              ..statusCode = HttpStatus.conflict
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'message': 'Shutdown already in progress'}));
            await request.response.close();
            return;
          }

          serverShutdownCalled = true;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'status': 'shutting_down',
              'message': 'Raspberry Pi safe shutdown initiated.',
              'delay_seconds': 1.5,
            }));
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found');
          await request.response.close();
        }
      });

      service = PiShutdownService(
        initialConfig: PiShutdownConfig(
          host: '127.0.0.1',
          port: serverPort,
          secretToken: testSecret,
          timeoutSeconds: 2,
        ),
      );
    });

    tearDown(() async {
      service.dispose();
      await server.close(force: true);
    });

    test('checkStatus parses 200 JSON and transitions to online state', () async {
      final state = await service.checkStatus();

      expect(state.status, equals(PiPowerStatus.online));
      expect(state.hostname, equals('aerialeye'));
      expect(state.uptimeSeconds, equals(123.4));
      expect(state.isOnline, isTrue);
    });

    test('requestShutdown with valid token returns HTTP 200 success', () async {
      final result = await service.requestShutdown(force: true);

      expect(result.success, isTrue);
      expect(result.statusCode, equals(200));
      expect(result.message, contains('safe shutdown initiated'));
      expect(serverShutdownCalled, isTrue);
      expect(service.currentState.status, equals(PiPowerStatus.shuttingDown));
    });

    test('requestShutdown with invalid token returns HTTP 401 unauthorized', () async {
      service.updateConfig(
        service.config.copyWith(secretToken: 'WRONG_SECRET_TOKEN'),
      );

      final result = await service.requestShutdown(force: true);

      expect(result.success, isFalse);
      expect(result.statusCode, equals(401));
      expect(service.currentState.status, equals(PiPowerStatus.error));
      expect(service.currentState.errorMessage, contains('Invalid shutdown secret token'));
    });

    test('requestShutdown handles HTTP 409 conflict when already in progress', () async {
      serverShutdownCalled = true; // Simulate already shutting down on server

      final result = await service.requestShutdown(force: true);

      expect(result.success, isTrue);
      expect(result.statusCode, equals(409));
      expect(result.message, contains('already in progress'));
      expect(service.currentState.status, equals(PiPowerStatus.shuttingDown));
    });

    test('Unreachable server marks state as offline with error message', () async {
      service.updateConfig(
        service.config.copyWith(port: 59999), // Closed port
      );

      final state = await service.checkStatus();

      expect(state.status, equals(PiPowerStatus.offline));
      expect(state.errorMessage, isNotNull);
      expect(state.isOnline, isFalse);
    });
  });
}
