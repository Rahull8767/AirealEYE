import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

// A mock implementation of RawDatagramSocket to spy on sent packets and inject events
class MockRawDatagramSocket extends Stream<RawSocketEvent> implements RawDatagramSocket {
  final List<Uint8List> sentPackets = [];
  StreamController<RawSocketEvent> _controller = StreamController<RawSocketEvent>.broadcast();
  Datagram? _nextDatagram;

  void injectDatagram(Uint8List data, InternetAddress address, int port) {
    if (_controller.isClosed) {
      _controller = StreamController<RawSocketEvent>.broadcast();
    }
    _nextDatagram = Datagram(data, address, port);
    _controller.add(RawSocketEvent.read);
  }

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    sentPackets.add(Uint8List.fromList(buffer));
    return buffer.length;
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Datagram? receive() {
    final dg = _nextDatagram;
    _nextDatagram = null;
    return dg;
  }

  @override
  void close() {
    _controller.close();
  }

  @override
  bool broadcastEnabled = false;

  @override
  int multicastHops = 1;

  @override
  bool multicastLoopback = true;

  @override
  NetworkInterface? multicastInterface;

  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {}

  @override
  void leaveMulticast(InternetAddress group, [NetworkInterface? interface]) {}

  @override
  void setRawOption(RawSocketOption option) {}

  @override
  int get port => 14550;
  @override
  InternetAddress get address => InternetAddress.anyIPv4;
  bool setOption(RawSocketOption option) => true;
  @override
  Uint8List getRawOption(RawSocketOption option) => Uint8List(0);
  void write(List<int> buffer) {}
  int available() => 0;
  @override
  bool get readEventsEnabled => true;
  @override
  set readEventsEnabled(bool value) {}
  @override
  bool get writeEventsEnabled => false;
  @override
  set writeEventsEnabled(bool value) {}
}

void main() {
  group('Flight Mode Control Tests', () {
    late MavlinkDroneService service;

    setUp(() {
      service = MavlinkDroneService();
    });

    test('Supported mode validation', () {
      final supported = ['STABILIZE', 'GUIDED', 'LOITER', 'AUTO', 'RTL', 'LAND'];
      for (final mode in supported) {
        // Validation passes (throws StateError since socket is null, not ArgumentError)
        expect(() => service.setFlightMode(mode), throwsA(isA<StateError>()));
      }
    });

    test('Unsupported mode rejection', () async {
      expect(
        () => service.setFlightMode('UNKNOWN'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Disconnected vehicle rejection', () async {
      expect(
        () => service.setFlightMode('GUIDED'),
        throwsA(isA<StateError>()),
      );
    });

    test('Correct MAVLink mode command generation', () async {
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      // Start setFlightMode in a future
      final future = service.setFlightMode('GUIDED');

      // Verify that a packet was sent to the socket
      expect(mockSocket.sentPackets, isNotEmpty);
      final sentBytes = mockSocket.sentPackets.first;

      // Parse the sent bytes using the dialect
      final parser = MavlinkParser(MavlinkDialectArdupilotmega());
      MavlinkFrame? parsedFrame;
      parser.stream.listen((frame) {
        parsedFrame = frame;
      });
      parser.parse(sentBytes);

      // Wait a microtask for stream listener to run
      await Future.delayed(Duration.zero);

      expect(parsedFrame, isNotNull);
      expect(parsedFrame!.message, isA<CommandLong>());
      final cmd = parsedFrame!.message as CommandLong;
      expect(cmd.command, 176); // MAV_CMD_DO_SET_MODE
      expect(cmd.param1, 1.0);  // Custom mode enabled
      expect(cmd.param2, 4.0);  // GUIDED is 4

      // Clean up to prevent background timer from firing after test completion
      service.disconnect();
      await expectLater(future, throwsA(isA<StateError>()));
    });

    test('COMMAND_ACK ACCEPTED and HEARTBEAT mode confirmation', () async {
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      final future = service.setFlightMode('GUIDED');

      // Inject COMMAND_ACK ACCEPTED (result = 0)
      final ackMessage = CommandAck(
        command: 176,
        result: 0, // ACCEPTED
        progress: 0,
        resultParam2: 0,
        targetSystem: 1,
        targetComponent: 1,
      );
      final ackFrame = MavlinkFrame.v2(0, 1, 1, ackMessage);
      final ackBytes = ackFrame.serialize();

      mockSocket.injectDatagram(ackBytes, InternetAddress.loopbackIPv4, 14550);

      // Wait a microtask
      await Future.delayed(const Duration(milliseconds: 50));

      // Now, let's inject HEARTBEAT with GUIDED mode (custom mode = 4, base mode = 128 to be armed)
      final hbMessage = Heartbeat(
        customMode: 4,
        type: 2,
        autopilot: 3,
        baseMode: 128,
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      final hbFrame = MavlinkFrame.v2(0, 1, 1, hbMessage);
      final hbBytes = hbFrame.serialize();

      mockSocket.injectDatagram(hbBytes, InternetAddress.loopbackIPv4, 14550);

      // The future should now complete with true!
      final result = await future;
      expect(result, isTrue);
      expect(service.currentTelemetry.flightMode, 'GUIDED');
    });

    test('COMMAND_ACK DENIED rejection', () async {
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      final future = service.setFlightMode('GUIDED');

      // Inject COMMAND_ACK DENIED (result = 2)
      final ackMessage = CommandAck(
        command: 176,
        result: 2, // DENIED
        progress: 0,
        resultParam2: 0,
        targetSystem: 1,
        targetComponent: 1,
      );
      final ackFrame = MavlinkFrame.v2(0, 1, 1, ackMessage);
      final ackBytes = ackFrame.serialize();

      mockSocket.injectDatagram(ackBytes, InternetAddress.loopbackIPv4, 14550);

      // The future should throw an Exception
      expect(future, throwsA(isA<Exception>()));
    });

    test('Confirmation timeout', () async {
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      final future = service.setFlightMode('GUIDED');

      // We don't inject any ACKs or Heartbeats.
      // The future should throw a TimeoutException after 3 seconds.
      expect(future, throwsA(isA<TimeoutException>()));
    });
  });

  group('MAVLink Connection & Simulation Mode Tests', () {
    late MavlinkDroneService service;

    setUp(() {
      service = MavlinkDroneService();
    });

    tearDown(() {
      service.disconnect();
    });

    test('Heartbeat received -> connected state', () async {
      service.connectionMode = DroneConnectionMode.real;
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      // Start connection
      service.connect();
      expect(service.connectionState, isIn([DroneConnectionState.connecting, DroneConnectionState.socketBoundWaiting, DroneConnectionState.listening]));

      // Inject Heartbeat
      final hbMessage = Heartbeat(
        customMode: 4,
        type: 2,
        autopilot: 3,
        baseMode: 128,
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      final hbFrame = MavlinkFrame.v2(0, 1, 1, hbMessage);
      final hbBytes = hbFrame.serialize();
      mockSocket.injectDatagram(hbBytes, InternetAddress.loopbackIPv4, 14550);

      // Wait a bit for heartbeat to be processed and liveness timer to tick
      await Future.delayed(const Duration(milliseconds: 600));

      expect(service.connectionState, equals(DroneConnectionState.connected));
      expect(service.currentTelemetry.isConnected, isTrue);
      expect(service.currentTelemetry.isStale, isFalse);
    });

    test('Heartbeat timeout -> connectionLost state', () async {
      service.connectionMode = DroneConnectionMode.real;
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      service.connect();
      
      // Inject Heartbeat first to establish connection
      final hbMessage = Heartbeat(
        customMode: 4,
        type: 2,
        autopilot: 3,
        baseMode: 128,
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      mockSocket.injectDatagram(MavlinkFrame.v2(0, 1, 1, hbMessage).serialize(), InternetAddress.loopbackIPv4, 14550);

      await Future.delayed(const Duration(milliseconds: 600));
      expect(service.connectionState, equals(DroneConnectionState.connected));

      // Now wait 3.5 seconds without any heartbeats
      await Future.delayed(const Duration(milliseconds: 3500));

      expect(service.connectionState, equals(DroneConnectionState.telemetryStale));
      expect(service.currentTelemetry.isConnected, isFalse);
      expect(service.currentTelemetry.isStale, isTrue);
    });

    test('Heartbeat timeout followed by reconnect -> connected state', () async {
      service.connectionMode = DroneConnectionMode.real;
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);

      service.connect();
      
      // Inject Heartbeat first
      final hbMessage = Heartbeat(
        customMode: 4,
        type: 2,
        autopilot: 3,
        baseMode: 128,
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      mockSocket.injectDatagram(MavlinkFrame.v2(0, 1, 1, hbMessage).serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 600));
      expect(service.connectionState, equals(DroneConnectionState.connected));

      // Wait 3.5 seconds for timeout
      await Future.delayed(const Duration(milliseconds: 3500));
      expect(service.connectionState, equals(DroneConnectionState.telemetryStale));

      // Inject heartbeat again
      mockSocket.injectDatagram(MavlinkFrame.v2(0, 1, 1, hbMessage).serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(service.connectionState, equals(DroneConnectionState.connected));
      expect(service.currentTelemetry.isConnected, isTrue);
      expect(service.currentTelemetry.isStale, isFalse);
    });

    test('Simulation mode -> simulated telemetry updates', () async {
      service.connectionMode = DroneConnectionMode.simulation;
      service.connect();

      expect(service.connectionState, equals(DroneConnectionState.connected));
      
      final initialLat = service.currentTelemetry.latitude;
      
      // Wait for simulation fallback to run (jitter telemetry)
      await Future.delayed(const Duration(milliseconds: 1100));

      expect(service.currentTelemetry.latitude, isNot(equals(initialLat)));
      expect(service.currentTelemetry.batteryPercent, lessThanOrEqualTo(1.0));
    });

    test('Real mode -> no simulated telemetry updates', () async {
      service.connectionMode = DroneConnectionMode.real;
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);
      service.connect();

      expect(service.connectionState, isIn([DroneConnectionState.connecting, DroneConnectionState.socketBoundWaiting, DroneConnectionState.listening]));
      
      final initialLat = service.currentTelemetry.latitude;
      
      // Wait for telemetry timer ticks (simulation should not run)
      await Future.delayed(const Duration(milliseconds: 1000));

      expect(service.currentTelemetry.latitude, equals(initialLat));
      expect(service.connectionState, isIn([DroneConnectionState.socketBoundWaiting, DroneConnectionState.listening]));
    });

    test('Disconnected / waiting -> flight controls throw StateError', () async {
      // 1. Disconnected state
      expect(service.connectionState, equals(DroneConnectionState.disconnected));
      expect(() => service.arm(), throwsA(isA<StateError>()));
      expect(() => service.disarm(), throwsA(isA<StateError>()));
      expect(() => service.takeoff(5.0), throwsA(isA<StateError>()));
      expect(() => service.setFlightMode('GUIDED'), throwsA(isA<StateError>()));

      // 2. Waiting state (no heartbeat yet)
      service.connectionMode = DroneConnectionMode.real;
      final mockSocket = MockRawDatagramSocket();
      service.setMockSocket(mockSocket);
      service.connect();

      expect(service.connectionState, isIn([DroneConnectionState.connecting, DroneConnectionState.socketBoundWaiting, DroneConnectionState.listening]));

      expect(() => service.arm(), throwsA(isA<StateError>()));
      expect(() => service.disarm(), throwsA(isA<StateError>()));
      expect(() => service.takeoff(5.0), throwsA(isA<StateError>()));
      expect(() => service.setFlightMode('GUIDED'), throwsA(isA<StateError>()));
    });
  });
}
