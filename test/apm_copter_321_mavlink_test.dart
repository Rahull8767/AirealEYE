import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

/// Mock socket that tracks sent packets and allows injecting incoming MAVLink datagrams.
class MockDatagramSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final List<Uint8List> sentPackets = [];
  StreamController<RawSocketEvent> _controller =
      StreamController<RawSocketEvent>.broadcast();
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
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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
  group('APM 2.8 & ArduCopter 3.2.1 MAVLink Compatibility Tests', () {
    late MavlinkDroneService service;
    late MockDatagramSocket socket;

    setUp(() {
      service = MavlinkDroneService();
      socket = MockDatagramSocket();
      service.setMockSocket(socket);
    });

    tearDown(() {
      service.disconnect();
    });

    test('Outbound frames use MAVLink 1.0 (0xFE) magic header for APM 2.8', () async {
      final future = service.setFlightMode('ALT_HOLD');

      expect(socket.sentPackets, isNotEmpty);
      final rawBytes = socket.sentPackets.first;

      // APM 2.8 ATmega2560 only parses MAVLink 1.0 packets (magic byte 0xFE)
      expect(rawBytes[0], 0xFE,
          reason: 'Packet must start with MAVLink 1.0 magic byte 0xFE, not 0xFD');

      service.disconnect();
      await expectLater(future, throwsA(isA<StateError>()));
    });

    test('ArduCopter 3.2.1 AltHold custom mode 2 mapping and normalization', () async {
      // Test ALT_HOLD
      final altHoldFuture = service.setFlightMode('ALT_HOLD');
      expect(socket.sentPackets, isNotEmpty);

      final parser = MavlinkParser(MavlinkDialectArdupilotmega());
      MavlinkFrame? parsedFrame;
      parser.stream.listen((f) => parsedFrame = f);
      parser.parse(socket.sentPackets.first);
      await Future.delayed(Duration.zero);

      expect(parsedFrame?.message, isA<CommandLong>());
      final cmd = parsedFrame!.message as CommandLong;
      expect(cmd.command, 176); // MAV_CMD_DO_SET_MODE
      expect(cmd.param1, 1.0); // MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
      expect(cmd.param2, 2.0); // ArduCopter AltHold is custom mode 2

      service.disconnect();
      await expectLater(altHoldFuture, throwsA(isA<StateError>()));

      // Test ALTHOLD without underscore
      final socket2 = MockDatagramSocket();
      service.setMockSocket(socket2);
      final altHoldNormalizedFuture = service.setFlightMode('ALTHOLD');
      expect(socket2.sentPackets, isNotEmpty);

      parsedFrame = null;
      parser.parse(socket2.sentPackets.first);
      await Future.delayed(Duration.zero);

      final cmd2 = parsedFrame!.message as CommandLong;
      expect(cmd2.param2, 2.0); // Also mapped to 2.0

      service.disconnect();
      await expectLater(altHoldNormalizedFuture, throwsA(isA<StateError>()));
    });

    test('VFR_HUD extracts barometric altitude and climb rate when GPS is absent', () async {
      // Inject Heartbeat first to establish connection
      final hb = Heartbeat(
        customMode: 2, // ALT_HOLD
        type: 2, // MAV_TYPE_QUADROTOR
        autopilot: 3, // MAV_AUTOPILOT_ARDUPILOTMEGA
        baseMode: 128, // Armed
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      final hbFrame = MavlinkFrame.v1(0, 1, 1, hb);
      socket.injectDatagram(hbFrame.serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 30));

      // Inject VFR_HUD with 2.15m altitude and 0.25m/s climb
      final vfr = VfrHud(
        airspeed: 0.0,
        groundspeed: 0.0,
        heading: 90,
        throttle: 50,
        alt: 2.15,
        climb: 0.25,
      );
      final vfrFrame = MavlinkFrame.v1(1, 1, 1, vfr);
      socket.injectDatagram(vfrFrame.serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 30));

      final telem = service.currentTelemetry;
      expect(telem.barometricAltitude, closeTo(2.15, 0.01));
      expect(telem.relativeAltitude, closeTo(2.15, 0.01));
      expect(telem.altitude, closeTo(2.15, 0.01));
      expect(telem.climbRate, closeTo(0.25, 0.01));
      expect(telem.altitudeDisplay, '2.1 m');
      expect(telem.satellitesDisplay, 'Waiting...');
      expect(telem.hasReceivedGps, isFalse);
      expect(telem.isAltHold, isTrue);
    });

    test('STATUSTEXT captures APM 2.8 pre-arm check rejection reason', () async {
      // Inject STATUSTEXT warning from APM 2.8 (e.g., Compass or Accel failure)
      final statusTextMsg = Statustext(
        severity: 2, // MAV_SEVERITY_CRITICAL
        text: 'PreArm: Bad Compass Health'.codeUnits,
        id: 0,
        chunkSeq: 0,
      );
      final statusFrame = MavlinkFrame.v1(0, 1, 1, statusTextMsg);
      socket.injectDatagram(statusFrame.serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(service.currentTelemetry.lastStatusText, 'PreArm: Bad Compass Health');

      // Now initiate arming
      final armFuture = service.arm();

      // Autopilot sends COMMAND_ACK DENIED (result = 2)
      final ack = CommandAck(
        command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
        result: 2, // DENIED
        progress: 0,
        resultParam2: 0,
        targetSystem: 1,
        targetComponent: 1,
      );
      final ackFrame = MavlinkFrame.v1(1, 1, 1, ack);
      socket.injectDatagram(ackFrame.serialize(), InternetAddress.loopbackIPv4, 14550);

      // Must fail with the specific STATUSTEXT error included
      expect(
        armFuture,
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('PreArm: Bad Compass Health') &&
            e.toString().toLowerCase().contains('denied'))),
      );
    });

    test('Arming requires both COMMAND_ACK ACCEPTED and subsequent Heartbeat armed confirmation', () async {
      final armFuture = service.arm();

      // First: Autopilot returns COMMAND_ACK result=0 (ACCEPTED)
      final ack = CommandAck(
        command: 400,
        result: 0, // ACCEPTED
        progress: 0,
        resultParam2: 0,
        targetSystem: 1,
        targetComponent: 1,
      );
      socket.injectDatagram(MavlinkFrame.v1(0, 1, 1, ack).serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 50));

      // Telemetry must NOT claim armed yet until Heartbeat confirms
      expect(service.currentTelemetry.isArmed, isFalse);

      // Second: Autopilot sends Heartbeat with baseMode armed bit (128)
      final hbArmed = Heartbeat(
        customMode: 2, // ALT_HOLD
        type: 2,
        autopilot: 3,
        baseMode: 128, // MAV_MODE_FLAG_SAFETY_ARMED
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      socket.injectDatagram(MavlinkFrame.v1(1, 1, 1, hbArmed).serialize(), InternetAddress.loopbackIPv4, 14550);

      final result = await armFuture;
      expect(result, isTrue);
      expect(service.currentTelemetry.isArmed, isTrue);
    });

    test('Disarming requires COMMAND_ACK and Heartbeat confirmation', () async {
      // Put vehicle into armed state first via Heartbeat
      final hbArmed = Heartbeat(
        customMode: 2,
        type: 2,
        autopilot: 3,
        baseMode: 128,
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      socket.injectDatagram(MavlinkFrame.v1(0, 1, 1, hbArmed).serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 30));
      expect(service.currentTelemetry.isArmed, isTrue);

      final disarmFuture = service.disarm();

      // Autopilot sends COMMAND_ACK ACCEPTED (result = 0)
      final ack = CommandAck(
        command: 400,
        result: 0,
        progress: 0,
        resultParam2: 0,
        targetSystem: 1,
        targetComponent: 1,
      );
      socket.injectDatagram(MavlinkFrame.v1(1, 1, 1, ack).serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 30));

      // Autopilot sends Heartbeat disarmed (baseMode = 0)
      final hbDisarmed = Heartbeat(
        customMode: 2,
        type: 2,
        autopilot: 3,
        baseMode: 0,
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      socket.injectDatagram(MavlinkFrame.v1(2, 1, 1, hbDisarmed).serialize(), InternetAddress.loopbackIPv4, 14550);

      final result = await disarmFuture;
      expect(result, isTrue);
      expect(service.currentTelemetry.isArmed, isFalse);
    });

    test('ARMING_CHECK parameter request and value parsing', () async {
      service.requestArmingCheck();

      expect(socket.sentPackets, isNotEmpty);
      final raw = socket.sentPackets.last;
      final parser = MavlinkParser(MavlinkDialectArdupilotmega());
      MavlinkFrame? parsedFrame;
      parser.stream.listen((f) => parsedFrame = f);
      parser.parse(raw);
      await Future.delayed(Duration.zero);

      expect(parsedFrame?.message, isA<ParamRequestRead>());
      final req = parsedFrame!.message as ParamRequestRead;
      final paramIdStr = String.fromCharCodes(req.paramId.where((c) => c != 0)).trim();
      expect(paramIdStr, 'ARMING_CHECK');

      // Inject PARAM_VALUE for ARMING_CHECK = 1 (All enabled)
      final paramVal = ParamValue(
        paramId: 'ARMING_CHECK'.codeUnits,
        paramValue: 1.0,
        paramType: 6, // MAV_PARAM_TYPE_INT32
        paramCount: 100,
        paramIndex: 12,
      );
      socket.injectDatagram(MavlinkFrame.v1(0, 1, 1, paramVal).serialize(), InternetAddress.loopbackIPv4, 14550);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(service.currentTelemetry.armingCheckValue, 1);
      expect(service.currentTelemetry.armingCheckSummary, 'All Arming Checks Enabled (1)');
    });

    test('Telemetry helper methods accurately evaluate GPS dependency', () {
      expect(DroneTelemetry.isModeGpsDependent('ALT_HOLD'), isFalse);
      expect(DroneTelemetry.isModeGpsDependent('STABILIZE'), isFalse);
      expect(DroneTelemetry.isModeGpsDependent('LAND'), isFalse);
      expect(DroneTelemetry.isModeGpsDependent('GUIDED'), isTrue);
      expect(DroneTelemetry.isModeGpsDependent('LOITER'), isTrue);
      expect(DroneTelemetry.isModeGpsDependent('AUTO'), isTrue);
      expect(DroneTelemetry.isModeGpsDependent('RTL'), isTrue);
    });
  });
}
