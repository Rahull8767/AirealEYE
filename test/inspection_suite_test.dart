import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/services/mavlink_drone_service.dart';
import 'package:aerial_eye/services/mock_detection_service.dart';
import 'package:aerial_eye/services/detection_service.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

// Spy socket to monitor MAVLink packets and feed fake Autopilot responses
class SpyRawDatagramSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  final List<Uint8List> sentPackets = [];
  final StreamController<RawSocketEvent> _controller =
      StreamController<RawSocketEvent>.broadcast();
  Datagram? _nextDatagram;

  void injectDatagram(Uint8List data) {
    _nextDatagram = Datagram(data, InternetAddress.loopbackIPv4, 14550);
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
  group('MAVLink Mission Upload Suite', () {
    late MavlinkDroneService service;
    late SpyRawDatagramSocket spySocket;
    final parser = MavlinkParser(MavlinkDialectArdupilotmega());

    setUp(() {
      service = MavlinkDroneService();
      spySocket = SpyRawDatagramSocket();
      service.setMockSocket(spySocket);
    });

    tearDown(() {
      service.disconnect();
    });

    test(
      'uploadMission initiates protocol sequence with MISSION_COUNT',
      () async {
        final waypoints = [
          Waypoint(
            id: 1,
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 30.0,
            speed: 5.0,
            hoverTime: 2,
          ),
        ];

        // Run upload as async
        final future = service.uploadMission(waypoints);

        // Verify MISSION_COUNT was sent
        expect(spySocket.sentPackets.isNotEmpty, isTrue);

        MavlinkFrame? countFrame;
        parser.stream.listen((frame) {
          countFrame = frame;
        });
        parser.parse(spySocket.sentPackets.first);

        await Future.delayed(Duration.zero);

        expect(countFrame, isNotNull);
        expect(countFrame!.message, isA<MissionCount>());

        final countMsg = countFrame!.message as MissionCount;
        expect(
          countMsg.count,
          equals(2),
        ); // Home position (seq 0) + Waypoint 1 (seq 1)
        expect(countMsg.missionType, equals(0));

        service.disconnect();
        await expectLater(future, throwsA(isA<StateError>()));
      },
    );

    test(
      'uploadMission responds to MISSION_REQUEST with waypoint data and succeeds on MISSION_ACK',
      () async {
        final waypoints = [
          Waypoint(
            id: 1,
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 30.0,
            speed: 5.0,
            hoverTime: 2,
          ),
        ];

        final future = service.uploadMission(waypoints);

        // Autopilot requests seq 0 (home position)
        final request0 = MissionRequest(
          targetSystem: 255,
          targetComponent: 1,
          seq: 0,
          missionType: 0,
        );
        spySocket.injectDatagram(
          MavlinkFrame.v2(0, 1, 1, request0).serialize(),
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Autopilot requests seq 1 (waypoint 1)
        final request1 = MissionRequest(
          targetSystem: 255,
          targetComponent: 1,
          seq: 1,
          missionType: 0,
        );
        spySocket.injectDatagram(
          MavlinkFrame.v2(1, 1, 1, request1).serialize(),
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Autopilot sends MISSION_ACK success
        final ack = MissionAck(
          targetSystem: 255,
          targetComponent: 1,
          type: 0,
          missionType: 0,
          opaqueId: 0,
        );
        spySocket.injectDatagram(MavlinkFrame.v2(2, 1, 1, ack).serialize());

        final result = await future;
        expect(result, isTrue);
        expect(service.activeWaypoints.length, equals(1));
      },
    );

    test(
      'uploadMission throws TimeoutException if Autopilot fails to respond',
      () async {
        final waypoints = [
          Waypoint(
            id: 1,
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 30.0,
            speed: 5.0,
            hoverTime: 2,
          ),
        ];

        expect(
          service.uploadMission(waypoints),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });

  group('AI Detection & Geolocation Suite', () {
    test(
      'MockDetectionService produces detections with required properties',
      () {
        final service = MockDetectionService();
        final list = service.generateInitialDetections();

        expect(list.isNotEmpty, isTrue);
        for (var d in list) {
          expect(d.id.isNotEmpty, isTrue);
          expect(d.altitude, greaterThan(0.0));
          expect(d.boundingBox, isNotNull);
          expect(d.boundingBox!.length, equals(4));
          expect(d.severity.isNotEmpty, isTrue);
        }
      },
    );

    test('GeolocationServiceImpl returns current coordinates', () {
      final geoService = GeolocationServiceImpl();
      final geotag = geoService.calculateGeotag(
        37.7749,
        -122.4194,
        90.0,
        -45.0,
        30.0,
      );

      expect(geotag.latitude, equals(37.7749));
      expect(geotag.longitude, equals(-122.4194));
    });
  });
}
