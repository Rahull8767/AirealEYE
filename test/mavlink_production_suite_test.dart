import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';
import 'package:aerial_eye/services/mock_drone_service.dart';
import 'package:aerial_eye/services/mavlink_config_storage.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

// Mock implementation of RawDatagramSocket for testing
class TestSpyDatagramSocket extends Stream<RawSocketEvent> implements RawDatagramSocket {
  final List<Uint8List> sentPackets = [];
  StreamController<RawSocketEvent> _controller = StreamController<RawSocketEvent>.broadcast();
  final List<Datagram> _incomingQueue = [];

  void injectDatagram(Uint8List data, {InternetAddress? address, int port = 14550}) {
    if (_controller.isClosed) {
      _controller = StreamController<RawSocketEvent>.broadcast();
    }
    _incomingQueue.add(Datagram(data, address ?? InternetAddress.loopbackIPv4, port));
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

  group('1. MAVLink Configuration & Persistence Tests', () {
    test('1.1 Default configuration values', () {
      final config = MavlinkConnectionConfig.defaultConfig();
      expect(config.transport, equals(MavlinkTransport.udp));
      expect(config.connectionMode, equals(MavlinkConnectionMode.listener));
      expect(config.bindAddress, equals('0.0.0.0'));
      expect(config.localPort, equals(14550));
      expect(config.sourceSystemId, equals(255));
      expect(config.sourceComponentId, equals(190));
      expect(config.targetSystemId, equals(1));
      expect(config.targetComponentId, equals(1));
      expect(config.autoTargetSystem, isTrue);
      expect(config.autoTargetComponent, isTrue);
      expect(config.heartbeatTimeoutSeconds, equals(3));
      expect(config.telemetryTimeoutSeconds, equals(5));
      expect(config.telemetryRateHz, equals(10));
      expect(config.debugLogging, isTrue);
    });

    test('1.2 Configuration validation passes for valid parameters', () {
      final validConfig = MavlinkConnectionConfig.defaultConfig();
      expect(validConfig.validate(), isEmpty);
    });

    test('1.3 Configuration validation detects invalid port, IDs, and timeouts', () {
      const invalidConfig = MavlinkConnectionConfig(
        localPort: 99999, // out of range
        sourceSystemId: 0, // invalid
        sourceComponentId: 300, // out of range
        autoTargetSystem: false,
        targetSystemId: 0, // invalid when manual
        heartbeatTimeoutSeconds: 0, // too short
      );
      final errors = invalidConfig.validate();
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Port')), isTrue);
      expect(errors.any((e) => e.contains('Source System ID')), isTrue);
      expect(errors.any((e) => e.contains('Source Component ID')), isTrue);
      expect(errors.any((e) => e.contains('Target System ID')), isTrue);
      expect(errors.any((e) => e.contains('Heartbeat timeout')), isTrue);
    });

    test('1.4 Configuration persistence with SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      const customConfig = MavlinkConnectionConfig(
        bindAddress: '192.168.1.50',
        localPort: 14555,
        remoteHost: '192.168.1.5',
        remotePort: 14550,
        sourceSystemId: 250,
        sourceComponentId: 180,
        targetSystemId: 2,
        targetComponentId: 2,
        autoTargetSystem: false,
        autoTargetComponent: false,
        heartbeatTimeoutSeconds: 4,
        telemetryTimeoutSeconds: 6,
        telemetryRateHz: 20,
        debugLogging: false,
      );

      await MavlinkConfigStorage.saveConfig(customConfig);
      final loaded = await MavlinkConfigStorage.loadConfig();

      expect(loaded.bindAddress, equals('192.168.1.50'));
      expect(loaded.localPort, equals(14555));
      expect(loaded.remoteHost, equals('192.168.1.5'));
      expect(loaded.remotePort, equals(14550));
      expect(loaded.sourceSystemId, equals(250));
      expect(loaded.sourceComponentId, equals(180));
      expect(loaded.targetSystemId, equals(2));
      expect(loaded.targetComponentId, equals(2));
      expect(loaded.autoTargetSystem, isFalse);
      expect(loaded.autoTargetComponent, isFalse);
      expect(loaded.heartbeatTimeoutSeconds, equals(4));
      expect(loaded.telemetryTimeoutSeconds, equals(6));
      expect(loaded.telemetryRateHz, equals(20));
      expect(loaded.debugLogging, isFalse);
    });
  });

  group('2. MAVLink Telemetry Parsing & Discovery Suite', () {
    late MavlinkDroneService service;
    late TestSpyDatagramSocket spySocket;

    setUp(() {
      service = MavlinkDroneService();
      spySocket = TestSpyDatagramSocket();
      service.setMockSocket(spySocket);
    });

    tearDown(() {
      service.disconnect();
    });

    test('2.1 Heartbeat parsing, System ID discovery, and vehicle identification', () async {
      final hb = Heartbeat(
        customMode: 4, // GUIDED
        type: 2,       // ArduCopter (Quad)
        autopilot: 3,  // ArduPilot
        baseMode: 128, // Armed
        systemStatus: 4,
        mavlinkVersion: 3,
      );
      final frame = MavlinkFrame.v2(0, 1, 1, hb);
      final bytes = frame.serialize();

      spySocket.injectDatagram(bytes, address: InternetAddress('192.168.1.5'), port: 14550);
      await Future.delayed(const Duration(milliseconds: 50));

      final tel = service.currentTelemetry;
      final diag = service.currentDiagnostics;

      expect(tel.isConnected, isTrue);
      expect(tel.flightMode, equals('GUIDED'));
      expect(tel.armed, isTrue);

      expect(diag.discoveredSystemId, equals(1));
      expect(diag.discoveredComponentId, equals(1));
      expect(diag.vehicleType, equals('ArduCopter (Quad)'));
      expect(diag.autopilotType, equals('ArduPilot'));
      expect(diag.heartbeatHealth, equals(LinkHealth.live));
      expect(diag.remoteAddress, equals('192.168.1.5:14550'));
    });

    test('2.2 SYS_STATUS battery parsing', () async {
      final sys = SysStatus(
        onboardControlSensorsPresent: 0,
        onboardControlSensorsEnabled: 0,
        onboardControlSensorsHealth: 0,
        load: 500,
        voltageBattery: 16800, // 16.80 V
        currentBattery: 1200,  // 12.00 A
        batteryRemaining: 85,  // 85%
        dropRateComm: 0,
        errorsComm: 0,
        errorsCount1: 0,
        errorsCount2: 0,
        errorsCount3: 0,
        errorsCount4: 0,
        onboardControlSensorsPresentExtended: 0,
        onboardControlSensorsEnabledExtended: 0,
        onboardControlSensorsHealthExtended: 0,
      );
      final frame = MavlinkFrame.v2(1, 1, 1, sys);
      spySocket.injectDatagram(frame.serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      final tel = service.currentTelemetry;
      expect(tel.hasReceivedBattery, isTrue);
      expect(tel.batteryVoltage, equals(16.8));
      expect(tel.batteryPercent, equals(0.85));
      expect(tel.batteryPercentage, equals(85.0));
      expect(tel.batteryVoltageDisplay, equals('16.8 V'));
    });

    test('2.3 GPS_RAW_INT parsing', () async {
      final gps = GpsRawInt(
        timeUsec: 1000000,
        fixType: 3, // 3D Fix
        lat: 377749290,
        lon: -1224194160,
        alt: 15500,
        eph: 100,
        epv: 100,
        vel: 250,
        cog: 18000,
        satellitesVisible: 14,
        altEllipsoid: 15500,
        hAcc: 50,
        vAcc: 50,
        velAcc: 10,
        hdgAcc: 10,
        yaw: 18000,
      );
      final frame = MavlinkFrame.v2(2, 1, 1, gps);
      spySocket.injectDatagram(frame.serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      final tel = service.currentTelemetry;
      expect(tel.hasReceivedGps, isTrue);
      expect(tel.satellites, equals(14));
      expect(tel.satellitesDisplay, equals('14 Sats'));
      expect(tel.gpsFix, equals(3));
    });

    test('2.4 GLOBAL_POSITION_INT parsing', () async {
      final pos = GlobalPositionInt(
        timeBootMs: 2000,
        lat: 377749290,
        lon: -1224194160,
        alt: 25000,
        relativeAlt: 15500, // 15.5 m AGL
        vx: 100,
        vy: 0,
        vz: 0,
        hdg: 18000, // 180.0 deg
      );
      final frame = MavlinkFrame.v2(3, 1, 1, pos);
      spySocket.injectDatagram(frame.serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      final tel = service.currentTelemetry;
      expect(tel.hasReceivedPosition, isTrue);
      expect(tel.latitude, closeTo(37.774929, 0.0001));
      expect(tel.longitude, closeTo(-122.419416, 0.0001));
      expect(tel.altitude, closeTo(15.5, 0.1));
      expect(tel.altitudeDisplay, equals('15.5 m'));
      expect(tel.heading, equals(180.0));
    });

    test('2.5 ATTITUDE and VFR_HUD parsing', () async {
      final att = Attitude(
        timeBootMs: 3000,
        roll: 0.1,  // ~5.73 deg
        pitch: -0.05, // ~ -2.86 deg
        yaw: 3.14159, // ~ 180 deg
        rollspeed: 0.0,
        pitchspeed: 0.0,
        yawspeed: 0.0,
      );
      spySocket.injectDatagram(MavlinkFrame.v2(4, 1, 1, att).serialize());

      final vfr = VfrHud(
        airspeed: 12.5,
        groundspeed: 12.0,
        heading: 180,
        throttle: 65,
        alt: 15.5,
        climb: 0.5,
      );
      spySocket.injectDatagram(MavlinkFrame.v2(5, 1, 1, vfr).serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      final tel = service.currentTelemetry;
      expect(tel.hasReceivedAttitude, isTrue);
      expect(tel.hasReceivedVfrHud, isTrue);
      expect(tel.roll, closeTo(5.73, 0.1));
      expect(tel.speed, equals(12.0));
      expect(tel.climbRate, equals(0.5));
    });
  });

  group('3. Command Handling & State Machine Suite', () {
    late MavlinkDroneService service;
    late TestSpyDatagramSocket spySocket;

    setUp(() {
      service = MavlinkDroneService();
      spySocket = TestSpyDatagramSocket();
      service.setMockSocket(spySocket);
    });

    tearDown(() {
      service.disconnect();
    });

    test('3.1 Dynamic target addressing uses auto-discovered IDs for commands', () async {
      // First inject a heartbeat from SysID 2, CompID 1
      final hb = Heartbeat(customMode: 0, type: 2, autopilot: 3, baseMode: 0, systemStatus: 4, mavlinkVersion: 3);
      spySocket.injectDatagram(MavlinkFrame.v2(0, 2, 1, hb).serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(service.effectiveTargetSystemId, equals(2));

      // Trigger arm command
      final future = service.arm();

      expect(spySocket.sentPackets, isNotEmpty);
      final parser = MavlinkParser(MavlinkDialectArdupilotmega());
      MavlinkFrame? parsedFrame;
      parser.stream.listen((frame) { parsedFrame = frame; });
      parser.parse(spySocket.sentPackets.last);
      await Future.delayed(Duration.zero);

      expect(parsedFrame, isNotNull);
      final cmd = parsedFrame!.message as CommandLong;
      expect(cmd.targetSystem, equals(2)); // auto-discovered target ID!

      // Confirm with ACK & Heartbeat
      spySocket.injectDatagram(MavlinkFrame.v2(1, 2, 1, CommandAck(command: 400, result: 0, progress: 0, resultParam2: 0, targetSystem: 255, targetComponent: 190)).serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      final armedHb = Heartbeat(customMode: 0, type: 2, autopilot: 3, baseMode: 128, systemStatus: 4, mavlinkVersion: 3);
      spySocket.injectDatagram(MavlinkFrame.v2(2, 2, 1, armedHb).serialize());

      final res = await future;
      expect(res, isTrue);
      expect(service.currentTelemetry.armed, isTrue);
    });

    test('3.2 COMMAND_ACK rejection throws Exception and cleans up completer', () async {
      final future = service.setFlightMode('LOITER');

      // Inject COMMAND_ACK DENIED (result = 2)
      final ack = CommandAck(command: 176, result: 2, progress: 0, resultParam2: 0, targetSystem: 255, targetComponent: 190);
      spySocket.injectDatagram(MavlinkFrame.v2(1, 1, 1, ack).serialize());

      expect(future, throwsA(isA<Exception>()));
    });

    test('3.3 Connect and disconnect idempotency', () {
      service.connect();
      service.connect(); // safe duplicate call
      expect(service.connectionState, isNot(equals(DroneConnectionState.error)));

      service.disconnect();
      service.disconnect(); // safe duplicate call
      expect(service.connectionState, equals(DroneConnectionState.disconnected));
    });

    test('3.4 MockDroneService functions without real socket', () async {
      final mock = MockDroneService();
      expect(mock.connectionMode, equals(DroneConnectionMode.simulation));
      expect(mock.connectionState, equals(DroneConnectionState.disconnected));

      mock.connect();
      await Future.delayed(const Duration(milliseconds: 600));

      expect(mock.connectionState, equals(DroneConnectionState.connected));
      expect(mock.currentTelemetry.isConnected, isTrue);

      final armed = await mock.arm();
      expect(armed, isTrue);
      expect(mock.currentTelemetry.armed, isTrue);

      final modeChanged = await mock.setFlightMode('AUTO');
      expect(modeChanged, isTrue);
      expect(mock.currentTelemetry.flightMode, equals('AUTO'));

      mock.disconnect();
      expect(mock.connectionState, equals(DroneConnectionState.disconnected));
    });
  });

  group('4. Detailed MAVLink Diagnostics & State Machine Tests', () {
    late MavlinkDroneService service;
    late TestSpyDatagramSocket spySocket;

    setUp(() {
      service = MavlinkDroneService();
      spySocket = TestSpyDatagramSocket();
      service.setMockSocket(spySocket);
    });

    tearDown(() {
      service.disconnect();
    });

    test('4.1 Datagram counts and protocol detection for MAVLink v2', () async {
      final hb = Heartbeat(customMode: 0, type: 2, autopilot: 3, baseMode: 0, systemStatus: 4, mavlinkVersion: 3);
      final frame = MavlinkFrame.v2(0, 1, 1, hb);
      spySocket.injectDatagram(frame.serialize());
      await Future.delayed(const Duration(milliseconds: 50));

      final diag = service.currentDiagnostics;
      expect(diag.rawDatagramsReceived, equals(1));
      expect(diag.mavlinkFramesReceived, equals(1));
      expect(diag.mavlinkProtocolVersion, contains('MAVLink v2'));
      expect(diag.malformedFramesCount, equals(0));
      expect(diag.lastReceivedSourceSystemId, equals(1));
      expect(diag.lastReceivedMessageType, equals('Heartbeat'));
    });

    test('4.2 Malformed non-MAVLink datagram tracking', () async {
      // Send arbitrary non-MAVLink bytes (e.g. 0xAA 0xBB 0xCC)
      final badData = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]);
      spySocket.injectDatagram(badData);
      await Future.delayed(const Duration(milliseconds: 50));

      final diag = service.currentDiagnostics;
      expect(diag.rawDatagramsReceived, equals(1));
      expect(diag.mavlinkFramesReceived, equals(0));
      expect(diag.malformedFramesCount, greaterThan(0));
    });

    test('4.3 Diagnostics report formatting for clipboard export', () async {
      final hb = Heartbeat(customMode: 4, type: 2, autopilot: 3, baseMode: 128, systemStatus: 4, mavlinkVersion: 3);
      spySocket.injectDatagram(MavlinkFrame.v2(0, 1, 1, hb).serialize(), address: InternetAddress('192.168.1.5'), port: 14550);
      await Future.delayed(const Duration(milliseconds: 50));

      final diag = service.currentDiagnostics;
      final report = diag.toClipboardReport();

      expect(report, contains('=== AerialEye MAVLink Network Diagnostics ==='));
      expect(report, contains('Socket Status: BOUND'));
      expect(report, contains('Local Endpoint: ${service.config.bindAddress}:${service.config.localPort}'));
      expect(report, contains('Discovered Remote Sender: 192.168.1.5:14550'));
      expect(report, contains('Raw UDP Datagrams: 1'));
      expect(report, contains('Valid MAVLink Frames: 1'));
      expect(report, contains('MAVLink v2'));
      expect(report, contains('ArduCopter (Quad)'));
      expect(report, contains('Recent Diagnostic Events'));
    });

    test('4.4 Arbitrary UDP packet reception (e.g. TEST-WINDOWS-UDP) correctly counts and previews payload', () async {
      // Simulate Windows PowerShell sending "TEST-WINDOWS-UDP"
      final testData = Uint8List.fromList('TEST-WINDOWS-UDP'.codeUnits);
      spySocket.injectDatagram(testData, address: InternetAddress('192.168.1.5'), port: 54321);
      await Future.delayed(const Duration(milliseconds: 50));

      final diag = service.currentDiagnostics;
      expect(diag.rawDatagramsReceived, equals(1));
      expect(diag.mavlinkFramesReceived, equals(0));
      expect(diag.malformedFramesCount, equals(1));
      expect(diag.lastRawSender, equals('192.168.1.5:54321'));
      expect(diag.lastRawDatagramSize, equals(16));
      expect(diag.lastRawDatagramPreview, equals('TEST-WINDOWS-UDP'));
      expect(diag.recentLogs.any((l) => l.contains('TEST-WINDOWS-UDP')), isTrue);
    });
  });
}
