import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/motor_test_state.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';
import 'package:aerial_eye/services/mock_drone_service.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

// TestSpyDatagramSocket for testing MAVLink packets
class TestSpyDatagramSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final List<Uint8List> sentPackets = [];
  StreamController<RawSocketEvent> _controller =
      StreamController<RawSocketEvent>.broadcast();
  final List<Datagram> _incomingQueue = [];

  void injectDatagram(
    Uint8List data, {
    InternetAddress? address,
    int port = 14550,
  }) {
    if (_controller.isClosed) {
      _controller = StreamController<RawSocketEvent>.broadcast();
    }
    _incomingQueue.add(
      Datagram(data, address ?? InternetAddress.loopbackIPv4, port),
    );
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
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Datagram? receive() {
    if (_incomingQueue.isEmpty) return null;
    return _incomingQueue.removeAt(0);
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
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List buildHeartbeatPacket({
    int systemId = 1,
    int componentId = 1,
    int customMode = 0, // STABILIZE
    int baseMode = 89, // Disarmed
    bool v1 = true,
  }) {
    final hb = Heartbeat(
      customMode: customMode,
      type: 2, // MAV_TYPE_QUADROTOR
      autopilot: 3, // MAV_AUTOPILOT_ARDUPILOTMEGA
      baseMode: baseMode,
      systemStatus: 4,
      mavlinkVersion: 3,
    );
    final frame = v1
        ? MavlinkFrame.v1(0, systemId, componentId, hb)
        : MavlinkFrame.v2(0, systemId, componentId, hb);
    return Uint8List.fromList(frame.serialize());
  }

  Uint8List buildCommandAckPacket({
    int command = 209,
    int result = 0,
    int systemId = 1,
    int componentId = 1,
    bool v1 = true,
  }) {
    final ack = CommandAck(
      command: command,
      result: result,
      progress: 0,
      resultParam2: 0,
      targetSystem: 1,
      targetComponent: 1,
    );
    final frame = v1
        ? MavlinkFrame.v1(1, systemId, componentId, ack)
        : MavlinkFrame.v2(1, systemId, componentId, ack);
    return Uint8List.fromList(frame.serialize());
  }

  Future<CommandLong?> extractCommandLong(Uint8List bytes) async {
    final parser = MavlinkParser(MavlinkDialectArdupilotmega());
    MavlinkFrame? frame;
    parser.stream.listen((f) {
      frame = f;
    });
    parser.parse(bytes);
    await Future.delayed(Duration.zero);
    return frame?.message is CommandLong ? frame!.message as CommandLong : null;
  }

  group('Motor Test State & Models Tests', () {
    test(
      'MotorSelection mapping correctly identifies letters, pins, directions',
      () {
        expect(MotorSelection.motor1.motorIndex, 1);
        expect(MotorSelection.motor1.letterCode, 'A');
        expect(MotorSelection.motor1.displayLabel, contains('Front-Right'));
        expect(MotorSelection.motor1.isAllMotors, false);

        expect(MotorSelection.motor2.motorIndex, 2);
        expect(MotorSelection.motor2.letterCode, 'B');
        expect(MotorSelection.motor2.displayLabel, contains('Rear-Right'));

        expect(MotorSelection.motor3.motorIndex, 3);
        expect(MotorSelection.motor3.letterCode, 'C');
        expect(MotorSelection.motor3.displayLabel, contains('Rear-Left'));

        expect(MotorSelection.motor4.motorIndex, 4);
        expect(MotorSelection.motor4.letterCode, 'D');
        expect(MotorSelection.motor4.displayLabel, contains('Front-Left'));

        expect(MotorSelection.allMotors.motorIndex, 1);
        expect(MotorSelection.allMotors.letterCode, 'ALL');
        expect(MotorSelection.allMotors.isAllMotors, true);
      },
    );

    test('MotorTestResult.describeMavResult provides clear diagnostics', () {
      expect(
        MotorTestResult.describeMavResult(0),
        contains('MAV_RESULT_ACCEPTED'),
      );
      expect(
        MotorTestResult.describeMavResult(1),
        contains('MAV_RESULT_TEMPORARILY_REJECTED'),
      );
      expect(
        MotorTestResult.describeMavResult(2),
        contains('MAV_RESULT_DENIED'),
      );
      expect(
        MotorTestResult.describeMavResult(3),
        contains('MAV_RESULT_UNSUPPORTED'),
      );
      expect(
        MotorTestResult.describeMavResult(4),
        contains('MAV_RESULT_FAILED'),
      );
      expect(MotorTestResult.describeMavResult(null), contains('timeout'));
    });
  });

  group('MockDroneService Motor Test Tests', () {
    test(
      'Mock service enforces disarmed state and returns simulated result',
      () async {
        final mockService = MockDroneService();
        mockService.connect();

        await Future.delayed(const Duration(milliseconds: 600));
        expect(mockService.connectionState, DroneConnectionState.connected);

        // Single motor test
        final result1 = await mockService.testMotor(
          motorInstance: 2,
          throttlePercent: 15.0,
          durationSeconds: 2,
        );
        expect(result1.success, true);
        expect(result1.isSimulated, true);
        expect(result1.ackResult, 0);
        expect(result1.motorIndex, 2);

        // Stop test
        final stopResult = await mockService.stopMotorTest();
        expect(stopResult.success, true);
        expect(stopResult.throttlePercent, 0.0);

        // Test all motors simultaneously
        final resultAll = await mockService.testAllMotors(
          throttlePercent: 10.0,
          durationSeconds: 3,
        );
        expect(resultAll.success, true);
        expect(resultAll.testAll, true);
        expect(
          resultAll.message,
          contains('simultaneous test of all 4 motors'),
        );
      },
    );
  });

  group('MavlinkDroneService Hardware & Safety Motor Test Tests', () {
    late MavlinkDroneService service;
    late TestSpyDatagramSocket spySocket;

    setUp(() {
      spySocket = TestSpyDatagramSocket();
      service = MavlinkDroneService(
        initialConfig: const MavlinkConnectionConfig(
          remoteHost: '127.0.0.1',
          localPort: 14550,
          remotePort: 14550,
        ),
      );
      service.setMockSocket(spySocket);
      service.connectionMode = DroneConnectionMode.real;
      service.connect();
    });

    tearDown(() {
      service.disconnect();
    });

    test('Safety Block: throws StateError if drone is not connected', () async {
      expect(
        () => service.testMotor(
          motorInstance: 1,
          throttlePercent: 10.0,
          durationSeconds: 3,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Safety Block: throws StateError if drone is ARMED', () async {
      // Connect with armed=true (baseMode: 217 -> armed bit set)
      spySocket.injectDatagram(
        buildHeartbeatPacket(systemId: 1, baseMode: 217, v1: true),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(service.connectionState, DroneConnectionState.connected);
      expect(service.currentTelemetry.armed, true);

      expect(
        () => service.testMotor(
          motorInstance: 1,
          throttlePercent: 10.0,
          durationSeconds: 3,
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message.contains('Safety Block: Drone is armed'),
          ),
        ),
      );
      expect(spySocket.sentPackets.isEmpty, true);
    });

    test(
      'Parameter validation: rejects throttle < 0 or > 100 and duration < 1 or > 600',
      () async {
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.currentTelemetry.armed, false);

        expect(
          () => service.testMotor(
            motorInstance: 1,
            throttlePercent: -5.0,
            durationSeconds: 3,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => service.testMotor(
            motorInstance: 1,
            throttlePercent: 105.0,
            durationSeconds: 3,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => service.testMotor(
            motorInstance: 1,
            throttlePercent: 10.0,
            durationSeconds: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => service.testMotor(
            motorInstance: 1,
            throttlePercent: 10.0,
            durationSeconds: 601,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => service.testMotor(
            motorInstance: 5,
            throttlePercent: 10.0,
            durationSeconds: 3,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'Accurately encodes MAV_CMD_DO_MOTOR_TEST (209) parameters for Motor 2',
      () async {
        // Connect disarmed
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        final testFuture = service.testMotor(
          motorInstance: 2,
          throttlePercent: 15.0,
          durationSeconds: 2,
          testAll: false,
        );

        await Future.delayed(const Duration(milliseconds: 50));
        expect(spySocket.sentPackets.isNotEmpty, true);

        final msg = await extractCommandLong(spySocket.sentPackets.last);
        expect(msg, isNotNull);
        expect(msg!.command, 209); // MAV_CMD_DO_MOTOR_TEST
        expect(msg.param1, 2.0); // Motor 2
        expect(msg.param2, 0.0); // Throttle percentage (0)
        expect(msg.param3, 15.0); // 15% throttle
        expect(msg.param4, 2.0); // 2 seconds duration
        expect(msg.param5, 1.0); // Motor count = 1 (single motor)
        expect(msg.targetSystem, 1);
        expect(msg.targetComponent, 1);

        // Inject COMMAND_ACK accepted (result 0)
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 0, v1: true),
        );

        final result = await testFuture;
        expect(result.success, true);
        expect(result.ackResult, 0);
        expect(result.motorIndex, 2);
        expect(result.throttlePercent, 15.0);
        expect(result.durationSeconds, 2);
        expect(result.isSimulated, false);
      },
    );

    test(
      'Encodes simultaneous Test All Motors with command 209 for all 4 motors and param5=0 (not sequential)',
      () async {
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        final testFuture = service.testAllMotors(
          throttlePercent: 12.0,
          durationSeconds: 3,
        );

        // Process Motor 1
        await Future.delayed(const Duration(milliseconds: 30));
        expect(spySocket.sentPackets.length, 1);
        final msg1 = await extractCommandLong(spySocket.sentPackets[0]);
        expect(msg1, isNotNull);
        expect(msg1!.command, 209);
        expect(msg1.param1, 1.0); // Motor 1
        expect(msg1.param2, 0.0); // Percentage
        expect(msg1.param3, 12.0); // 12% throttle
        expect(msg1.param4, 3.0); // 3 seconds
        expect(
          msg1.param5,
          0.0,
        ); // Motor count = 0 (single motor output, not sequence)
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 0, v1: true),
        );

        // Process Motor 2
        await Future.delayed(const Duration(milliseconds: 30));
        expect(spySocket.sentPackets.length, 2);
        final msg2 = await extractCommandLong(spySocket.sentPackets[1]);
        expect(msg2, isNotNull);
        expect(msg2!.command, 209);
        expect(msg2.param1, 2.0); // Motor 2
        expect(msg2.param3, 12.0);
        expect(msg2.param4, 3.0);
        expect(msg2.param5, 0.0);
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 0, v1: true),
        );

        // Process Motor 3
        await Future.delayed(const Duration(milliseconds: 30));
        expect(spySocket.sentPackets.length, 3);
        final msg3 = await extractCommandLong(spySocket.sentPackets[2]);
        expect(msg3, isNotNull);
        expect(msg3!.command, 209);
        expect(msg3.param1, 3.0); // Motor 3
        expect(msg3.param3, 12.0);
        expect(msg3.param4, 3.0);
        expect(msg3.param5, 0.0);
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 0, v1: true),
        );

        // Process Motor 4
        await Future.delayed(const Duration(milliseconds: 30));
        expect(spySocket.sentPackets.length, 4);
        final msg4 = await extractCommandLong(spySocket.sentPackets[3]);
        expect(msg4, isNotNull);
        expect(msg4!.command, 209);
        expect(msg4.param1, 4.0); // Motor 4
        expect(msg4.param3, 12.0);
        expect(msg4.param4, 3.0);
        expect(msg4.param5, 0.0);
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 0, v1: true),
        );

        final result = await testFuture;
        expect(result.success, true);
        expect(result.testAll, true);
        expect(result.ackResult, 0);
        expect(
          result.message,
          contains('Simultaneous test of all 4 motors accepted'),
        );
      },
    );

    test(
      'Simultaneous test aborts and triggers stop if any motor command is rejected',
      () async {
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        final testFuture = service.testAllMotors(
          throttlePercent: 10.0,
          durationSeconds: 2,
        );

        // Motor 1 accepted
        await Future.delayed(const Duration(milliseconds: 30));
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 0, v1: true),
        );

        // Motor 2 rejected (TEMPORARILY_REJECTED code 1)
        await Future.delayed(const Duration(milliseconds: 30));
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 1, v1: true),
        );

        final result = await testFuture;
        expect(result.success, false);
        expect(result.ackResult, 1);
        expect(result.message, contains('aborted at Motor 2'));

        // Verify that emergency stop command (param3=0, param4=0) was dispatched immediately
        final stopMsg = await extractCommandLong(spySocket.sentPackets.last);
        expect(stopMsg, isNotNull);
        expect(stopMsg!.command, 209);
        expect(stopMsg.param3, 0.0);
        expect(stopMsg.param4, 0.0);
      },
    );

    test(
      'Reports failure when autopilot returns MAV_RESULT_UNSUPPORTED (code 3)',
      () async {
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        final testFuture = service.testMotor(
          motorInstance: 1,
          throttlePercent: 10.0,
          durationSeconds: 2,
        );

        await Future.delayed(const Duration(milliseconds: 50));
        // Inject COMMAND_ACK with result 3 (UNSUPPORTED)
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 3, v1: true),
        );

        final result = await testFuture;
        expect(result.success, false);
        expect(result.ackResult, 3);
        expect(result.message, contains('MAV_RESULT_UNSUPPORTED'));
      },
    );

    test(
      'Reports failure when autopilot returns MAV_RESULT_TEMPORARILY_REJECTED (code 1)',
      () async {
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        final testFuture = service.testMotor(
          motorInstance: 3,
          throttlePercent: 10.0,
          durationSeconds: 2,
        );

        await Future.delayed(const Duration(milliseconds: 50));
        // Inject COMMAND_ACK with result 1 (TEMPORARILY_REJECTED)
        spySocket.injectDatagram(
          buildCommandAckPacket(command: 209, result: 1, v1: true),
        );

        final result = await testFuture;
        expect(result.success, false);
        expect(result.ackResult, 1);
        expect(result.message, contains('MAV_RESULT_TEMPORARILY_REJECTED'));
      },
    );

    test(
      'stopMotorTest sends MAV_CMD_DO_MOTOR_TEST with throttle 0% and duration 0s',
      () async {
        spySocket.injectDatagram(
          buildHeartbeatPacket(systemId: 1, baseMode: 89, v1: true),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        spySocket.sentPackets.clear();
        final stopResult = await service.stopMotorTest();
        expect(stopResult.success, true);
        expect(stopResult.throttlePercent, 0.0);

        expect(spySocket.sentPackets.isNotEmpty, true);
        final msg = await extractCommandLong(spySocket.sentPackets.last);

        expect(msg, isNotNull);
        expect(msg!.command, 209);
        expect(msg.param3, 0.0); // 0% throttle
        expect(msg.param4, 0.0); // 0s duration
      },
    );
  });
}
