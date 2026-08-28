import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_config_storage.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

class MavlinkDroneService implements DroneService {
  MavlinkConnectionConfig _config = MavlinkConnectionConfig.defaultConfig();

  final _telemetryController = StreamController<DroneTelemetry>.broadcast();
  DroneTelemetry _currentTelemetry = DroneTelemetry.initial();

  final _connectionStateController = StreamController<DroneConnectionState>.broadcast();
  DroneConnectionState _connectionState = DroneConnectionState.disconnected;

  final _diagnosticsController = StreamController<ConnectionDiagnostics>.broadcast();
  ConnectionDiagnostics _currentDiagnostics = ConnectionDiagnostics.initial();

  final MavlinkParser _mavlinkParser = MavlinkParser(MavlinkDialectArdupilotmega());

  Completer<bool>? _modeChangeCompleter;
  String? _targetMode;
  Timer? _modeTimeoutTimer;
  int _sequenceNumber = 0;

  Completer<bool>? _armCompleter;
  bool? _targetArmState;
  Timer? _armTimeoutTimer;

  Completer<bool>? _takeoffCompleter;
  Timer? _takeoffTimeoutTimer;

  Completer<bool>? _missionUploadCompleter;
  List<MissionItemInt> _uploadingWaypoints = [];
  Timer? _missionUploadTimeoutTimer;

  RawDatagramSocket? _socket;
  RawDatagramSocket? _mockSocketInstance;
  String _socketStatus = 'CLOSED';
  Timer? _telemetryTimer;
  Timer? _missionTimer;
  Timer? _rateTimer;

  // Discovered remote vehicle parameters
  InternetAddress? _lastSenderAddress;
  int? _lastSenderPort;
  int? _discoveredSystemId;
  int? _discoveredComponentId;
  int? _lastReceivedSourceSystemId;
  int? _lastReceivedSourceComponentId;
  String? _lastReceivedMessageType;
  String _detectedVehicleType = 'Unknown';
  String _detectedAutopilotType = 'Unknown';
  String _detectedProtocolVersion = 'None';

  // Metrics tracking
  int _rawDatagramsReceived = 0;
  int _mavlinkFramesReceived = 0;
  int _malformedFramesCount = 0;
  int _heartbeatCount = 0;
  int _packetsInLastSecond = 0;
  double _currentPps = 0.0;
  int _packetsDropped = 0;
  DateTime? _lastDatagramTime;
  DateTime? _lastMavlinkFrameTime;
  int? _lastRawDatagramSize;
  String? _lastRawDatagramPreview;
  String? _lastRawSender;

  // Heartbeat tracking
  DateTime? _lastHeartbeatTime;
  bool _isUsingHardware = false;
  DroneConnectionMode _connectionMode = DroneConnectionMode.real;

  // Recent diagnostic events ring buffer
  final List<String> _recentLogs = [];
  static const int _maxRecentLogs = 50;

  // Rate-limiting debug logs
  DateTime? _lastTelemetryLogTime;

  MavlinkDroneService() {
    _initStoredConfig();
    _initParserListener();
    _startPpsSampler();
  }

  void _initParserListener() {
    _mavlinkParser.stream.listen((frame) {
      _mavlinkFramesReceived++;
      _lastMavlinkFrameTime = DateTime.now();
      _lastReceivedSourceSystemId = frame.systemId;
      _lastReceivedSourceComponentId = frame.componentId;
      _lastReceivedMessageType = frame.message.runtimeType.toString();

      _handleTypedMavlinkMessage(frame.message, frame.systemId, frame.componentId);
    }, onError: (err) {
      _malformedFramesCount++;
      _packetsDropped++;
      _logDiagnostic("[MAVLINK ERROR] Framing / CRC parse error: $err");
    });
  }

  Future<void> _initStoredConfig() async {
    try {
      final stored = await MavlinkConfigStorage.loadConfig();
      _config = stored;
    } catch (_) {}
  }

  void _startPpsSampler() {
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentPps = _packetsInLastSecond.toDouble();
      _packetsInLastSecond = 0;
      _updateDiagnostics();
    });
  }

  @override
  MavlinkConnectionConfig get config => _config;

  @override
  void updateConfig(MavlinkConnectionConfig newConfig) {
    _config = newConfig;
    MavlinkConfigStorage.saveConfig(newConfig);
    _logDiagnostic("Config updated: localPort=${newConfig.localPort}, mode=${newConfig.connectionMode.name}, bind=${newConfig.bindAddress}, remote=${newConfig.remoteHost}:${newConfig.remotePort}");
    _updateDiagnostics();
  }

  @override
  DroneConnectionMode get connectionMode => _connectionMode;

  @override
  set connectionMode(DroneConnectionMode mode) {
    _connectionMode = mode;
  }

  // Simulation fallbacks
  int _currentWaypointIndex = 0;
  List<Waypoint> _activeWaypoints = [];
  bool _isMissionActive = false;

  @override
  Stream<DroneTelemetry> get telemetryStream => _telemetryController.stream;

  @override
  DroneTelemetry get currentTelemetry => _currentTelemetry;

  @override
  Stream<DroneConnectionState> get connectionStateStream => _connectionStateController.stream;

  @override
  DroneConnectionState get connectionState => _connectionState;

  @override
  Stream<ConnectionDiagnostics> get diagnosticsStream => _diagnosticsController.stream;

  @override
  ConnectionDiagnostics get currentDiagnostics => _currentDiagnostics;

  int get effectiveTargetSystemId {
    if (_config.autoTargetSystem && _discoveredSystemId != null) {
      return _discoveredSystemId!;
    }
    return _config.targetSystemId;
  }

  int get effectiveTargetComponentId {
    if (_config.autoTargetComponent && _discoveredComponentId != null) {
      return _discoveredComponentId!;
    }
    return _config.targetComponentId;
  }

  void _logDiagnostic(String message) {
    final timeStr = DateTime.now().toIso8601String().substring(11, 19);
    final formatted = '[$timeStr] $message';

    if (_recentLogs.length >= _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }
    _recentLogs.add(formatted);

    if (_config.debugLogging) {
      debugPrint("[MAVLINK] $message");
    }
  }

  @override
  void connect() {
    _telemetryTimer?.cancel();
    _lastHeartbeatTime = null;
    _heartbeatCount = 0;
    _rawDatagramsReceived = 0;
    _mavlinkFramesReceived = 0;
    _malformedFramesCount = 0;
    _detectedProtocolVersion = 'None';

    if (_connectionMode == DroneConnectionMode.real) {
      _isUsingHardware = true;
      _setConnectionState(DroneConnectionState.connecting);
      _initSocket();
    } else {
      _isUsingHardware = false;
      _socketStatus = 'SIMULATION';
      _setConnectionState(DroneConnectionState.connected);

      _currentTelemetry = _currentTelemetry.copyWith(
        isConnected: true,
        isStale: false,
        flightMode: 'GUIDED',
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 0.0,
        speed: 0.0,
        batteryPercent: 1.0,
        batteryPercentage: 100.0,
        batteryVoltage: 16.8,
        satellites: 18,
        hasReceivedGps: true,
        hasReceivedBattery: true,
        hasReceivedPosition: true,
        hasReceivedAttitude: true,
        hasReceivedVfrHud: true,
      );
      _telemetryController.add(_currentTelemetry);
      _logDiagnostic("Simulation mode active: simulated vehicle telemetry running");
    }

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_connectionMode == DroneConnectionMode.real) {
        _checkMavlinkLiveness();
      } else {
        _runFallbackSimulation();
      }
      _updateDiagnostics();
    });
  }

  @override
  void disconnect() {
    _cleanupCompletersOnDisconnect();

    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _missionTimer?.cancel();
    _missionTimer = null;
    _isMissionActive = false;

    if (_mockSocketInstance == null) {
      _socket?.close();
      _socket = null;
    }
    _socketStatus = 'CLOSED';

    _isUsingHardware = false;
    _lastHeartbeatTime = null;
    _lastSenderAddress = null;
    _lastSenderPort = null;
    _discoveredSystemId = null;
    _discoveredComponentId = null;
    _detectedVehicleType = 'Unknown';
    _detectedAutopilotType = 'Unknown';
    _detectedProtocolVersion = 'None';

    _setConnectionState(DroneConnectionState.disconnected);

    _currentTelemetry = DroneTelemetry.initial();
    _telemetryController.add(_currentTelemetry);

    _logDiagnostic("Disconnected. UDP socket closed and state reset.");
    _updateDiagnostics();
  }

  void _cleanupCompletersOnDisconnect() {
    if (_modeChangeCompleter != null && !_modeChangeCompleter!.isCompleted) {
      _modeChangeCompleter!.completeError(StateError("MAVLink link was disconnected."));
    }
    _cleanupModeChange();

    if (_armCompleter != null && !_armCompleter!.isCompleted) {
      _armCompleter!.completeError(StateError("MAVLink link was disconnected."));
    }
    _cleanupArmChange();

    if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
      _takeoffCompleter!.completeError(StateError("MAVLink link was disconnected."));
    }
    _cleanupTakeoff();

    if (_missionUploadCompleter != null && !_missionUploadCompleter!.isCompleted) {
      _missionUploadCompleter!.completeError(StateError("MAVLink link was disconnected."));
    }
    _cleanupMissionUpload();
  }

  void _setConnectionState(DroneConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionStateController.add(_connectionState);
      _logDiagnostic("Connection state changed: ${_currentDiagnostics.connectionStateLabel}");
      _updateDiagnostics();
    }
  }

  void _initSocket() async {
    if (_mockSocketInstance != null) {
      _socket = _mockSocketInstance;
      _socketStatus = 'BOUND';
      _logDiagnostic("[MOCK SOCKET] Mock UDP socket bound for testing.");
      if (_connectionState == DroneConnectionState.connecting) {
        _setConnectionState(DroneConnectionState.socketBoundWaiting);
      }
      return;
    }

    if (_socket != null) {
      _logDiagnostic("[SOCKET REBIND] Closing existing UDP socket before rebinding...");
      _socket?.close();
      _socket = null;
    }

    try {
      // Android UDP local binding: Bind to InternetAddress.anyIPv4 (0.0.0.0) locally
      InternetAddress bindAddr = InternetAddress.anyIPv4;
      if (_config.bindAddress.isNotEmpty &&
          _config.bindAddress != '0.0.0.0' &&
          _config.bindAddress.toLowerCase() != 'any') {
        final parsed = InternetAddress.tryParse(_config.bindAddress);
        if (parsed != null) {
          bindAddr = parsed;
        }
      }

      _logDiagnostic("[SOCKET BINDING] Binding local UDP socket on ${bindAddr.address}:${_config.localPort} (reuseAddress: true)...");
      _socket = await RawDatagramSocket.bind(bindAddr, _config.localPort, reuseAddress: true);
      _socketStatus = 'BOUND';
      _logDiagnostic("[SOCKET BOUND] Local UDP socket successfully bound on ${_socket!.address.address}:${_socket!.port}");

      if (_connectionState == DroneConnectionState.connecting) {
        _setConnectionState(DroneConnectionState.socketBoundWaiting);
      }

      _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final datagram = _socket?.receive();
            if (datagram == null) break;
            _onDatagramReceived(datagram);
          }
        }
      }, onError: (error) {
        _socketStatus = 'ERROR';
        _logDiagnostic("[SOCKET ERROR] Local UDP Socket error: $error");
        _setConnectionState(DroneConnectionState.error);
      }, onDone: () {
        _socketStatus = 'CLOSED';
        _logDiagnostic("[SOCKET CLOSED] Local UDP Socket closed by system");
      });
    } catch (e) {
      _socketStatus = 'ERROR';
      _logDiagnostic("[SOCKET ERROR] Local UDP socket bind failed on port ${_config.localPort}: $e");
      _setConnectionState(DroneConnectionState.error);
    }
  }

  void _onDatagramReceived(Datagram datagram) {
    final now = DateTime.now();
    _lastSenderAddress = datagram.address;
    _lastSenderPort = datagram.port;
    _rawDatagramsReceived++;
    _packetsInLastSecond++;
    _lastDatagramTime = now;

    final data = datagram.data;
    final int byteLength = data.length;
    final String srcIp = datagram.address.address;
    final int srcPort = datagram.port;

    bool isMavlink = false;
    String protoLabel = 'Non-MAVLink';

    // Inspect protocol version from magic byte
    if (data.isNotEmpty) {
      final magic = data[0];
      if (magic == 0xFD) {
        isMavlink = true;
        protoLabel = 'MAVLink v2 (0xFD)';
        _detectedProtocolVersion = protoLabel;
      } else if (magic == 0xFE) {
        isMavlink = true;
        protoLabel = 'MAVLink v1 (0xFE)';
        _detectedProtocolVersion = protoLabel;
      } else {
        _malformedFramesCount++;
      }
    }

    // Build ASCII preview for logging & diagnostics UI
    String asciiPreview = '';
    if (data.isNotEmpty) {
      final previewChars = data.take(64).map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
      asciiPreview = previewChars;
    }

    _lastRawDatagramSize = byteLength;
    _lastRawDatagramPreview = asciiPreview;
    _lastRawSender = '$srcIp:$srcPort';

    _logDiagnostic("[UDP RX #$_rawDatagramsReceived] $srcIp:$srcPort -> $byteLength bytes ($protoLabel) | Content: \"$asciiPreview\"");

    // Keep MAVLink parsing separate from UDP transport
    if (isMavlink) {
      try {
        _mavlinkParser.parse(data);
      } catch (e) {
        _malformedFramesCount++;
        _logDiagnostic("[PARSER EXCEPTION] $e");
      }
    }

    // Update intermediate granular states
    if (_heartbeatCount == 0) {
      if (_mavlinkFramesReceived > 0) {
        if (_connectionState == DroneConnectionState.socketBoundWaiting || _connectionState == DroneConnectionState.connecting) {
          _setConnectionState(DroneConnectionState.mavlinkNoHeartbeat);
        }
      } else if (_rawDatagramsReceived > 0) {
        if (_connectionState == DroneConnectionState.socketBoundWaiting || _connectionState == DroneConnectionState.connecting) {
          _setConnectionState(DroneConnectionState.udpPacketsNoMavlink);
        }
      }
    }
    _updateDiagnostics();
  }

  void _checkMavlinkLiveness() {
    final now = DateTime.now();

    if (_lastHeartbeatTime != null) {
      final diff = now.difference(_lastHeartbeatTime!);
      if (diff < Duration(seconds: _config.heartbeatTimeoutSeconds)) {
        if (_connectionState != DroneConnectionState.connected) {
          _setConnectionState(DroneConnectionState.connected);
        }

        _currentTelemetry = _currentTelemetry.copyWith(
          isConnected: true,
          isStale: false,
          lastUpdate: _lastHeartbeatTime,
        );
        _telemetryController.add(_currentTelemetry);
      } else {
        // Heartbeat was received previously but is now timed out
        if (_connectionState == DroneConnectionState.connected) {
          _setConnectionState(DroneConnectionState.telemetryStale);
          _logDiagnostic("Heartbeat timed out (${diff.inSeconds}s since last heartbeat). Link marked stale.");

          _currentTelemetry = _currentTelemetry.copyWith(
            isConnected: false,
            isStale: true,
          );
          _telemetryController.add(_currentTelemetry);
        }
      }
    } else {
      // No heartbeat has arrived yet.
      // Do NOT claim connectionLost if socket is still bound and waiting!
      if (_mavlinkFramesReceived > 0 && _connectionState != DroneConnectionState.mavlinkNoHeartbeat) {
        _setConnectionState(DroneConnectionState.mavlinkNoHeartbeat);
      } else if (_rawDatagramsReceived > 0 && _connectionState != DroneConnectionState.udpPacketsNoMavlink) {
        _setConnectionState(DroneConnectionState.udpPacketsNoMavlink);
      } else if (_socket != null && _connectionState != DroneConnectionState.socketBoundWaiting && _connectionState != DroneConnectionState.connecting) {
        _setConnectionState(DroneConnectionState.socketBoundWaiting);
      }
    }
  }

  void _updateDiagnostics() {
    final now = DateTime.now();

    LinkHealth hbHealth = LinkHealth.notAvailable;
    if (_lastHeartbeatTime != null) {
      final diff = now.difference(_lastHeartbeatTime!);
      if (diff < Duration(seconds: _config.heartbeatTimeoutSeconds)) {
        hbHealth = LinkHealth.live;
      } else {
        hbHealth = LinkHealth.stale;
      }
    }

    LinkHealth telHealth = LinkHealth.notAvailable;
    if (_lastMavlinkFrameTime != null) {
      final diff = now.difference(_lastMavlinkFrameTime!);
      if (diff < Duration(seconds: _config.telemetryTimeoutSeconds)) {
        telHealth = LinkHealth.live;
      } else {
        telHealth = LinkHealth.stale;
      }
    }

    String? remote;
    if (_lastSenderAddress != null && _lastSenderPort != null) {
      remote = '${_lastSenderAddress!.address}:$_lastSenderPort';
    } else if (_config.remoteHost.isNotEmpty) {
      remote = '${_config.remoteHost}:${_config.remotePort} (Configured)';
    }

    _currentDiagnostics = ConnectionDiagnostics(
      connectionState: _connectionState,
      socketStatus: _socketStatus,
      localAddress: _config.bindAddress,
      localPort: _config.localPort,
      configuredRemoteHost: _config.remoteHost,
      configuredRemotePort: _config.remotePort,
      remoteAddress: remote,
      discoveredSystemId: _discoveredSystemId,
      discoveredComponentId: _discoveredComponentId,
      sourceSystemId: _config.sourceSystemId,
      sourceComponentId: _config.sourceComponentId,
      commandTargetSystemId: effectiveTargetSystemId,
      commandTargetComponentId: effectiveTargetComponentId,
      mavlinkProtocolVersion: _detectedProtocolVersion,
      lastReceivedSourceSystemId: _lastReceivedSourceSystemId,
      lastReceivedSourceComponentId: _lastReceivedSourceComponentId,
      lastReceivedMessageType: _lastReceivedMessageType,
      vehicleType: _detectedVehicleType,
      autopilotType: _detectedAutopilotType,
      flightMode: _currentTelemetry.flightMode,
      armed: _currentTelemetry.armed,
      lastRawDatagramSize: _lastRawDatagramSize,
      lastRawDatagramPreview: _lastRawDatagramPreview,
      lastRawSender: _lastRawSender,
      heartbeatHealth: hbHealth,
      lastHeartbeatTime: _lastHeartbeatTime,
      heartbeatCount: _heartbeatCount,
      telemetryHealth: telHealth,
      lastTelemetryTime: _lastMavlinkFrameTime,
      rawDatagramsReceived: _rawDatagramsReceived,
      mavlinkFramesReceived: _mavlinkFramesReceived,
      malformedFramesCount: _malformedFramesCount,
      packetsReceived: _mavlinkFramesReceived,
      packetsPerSecond: _currentPps,
      packetsDropped: _packetsDropped,
      lastDatagramTime: _lastDatagramTime,
      lastPacketTime: _lastMavlinkFrameTime,
      satellites: _currentTelemetry.hasReceivedGps ? _currentTelemetry.satellites : null,
      batteryVoltage: _currentTelemetry.hasReceivedBattery ? _currentTelemetry.batteryVoltage : null,
      lastStatusText: _currentDiagnostics.lastStatusText,
      lastGlobalPositionTime: _currentTelemetry.lastGlobalPosition,
      lastGpsRawTime: _currentTelemetry.lastGpsUpdate,
      lastAttitudeTime: _currentTelemetry.lastAttitudeUpdate,
      lastVfrHudTime: _currentTelemetry.lastVfrHudUpdate,
      lastBatteryTime: _currentTelemetry.lastBatteryUpdate,
      recentLogs: List.unmodifiable(_recentLogs),
    );

    _diagnosticsController.add(_currentDiagnostics);
  }

  void _runFallbackSimulation() {
    final random = Random();
    double newPercent = _currentTelemetry.batteryPercent;
    double newVoltage = _currentTelemetry.batteryVoltage;

    if (_isMissionActive) {
      newPercent -= 0.0008;
      newVoltage -= 0.003;
    } else {
      newPercent -= 0.0001;
      newVoltage -= 0.0005;
    }

    if (newPercent < 0.0) newPercent = 0.0;
    if (newVoltage < 10.0) newVoltage = 10.0;

    final double jitterLat = (random.nextDouble() - 0.5) * 0.00002;
    final double jitterLng = (random.nextDouble() - 0.5) * 0.00002;

    _currentTelemetry = _currentTelemetry.copyWith(
      isConnected: true,
      batteryPercent: newPercent,
      batteryPercentage: newPercent * 100.0,
      batteryVoltage: double.parse(newVoltage.toStringAsFixed(2)),
      latitude: _currentTelemetry.latitude + jitterLat,
      longitude: _currentTelemetry.longitude + jitterLng,
      satellites: 15 + random.nextInt(5),
      rssi: (90.0 + random.nextDouble() * 10).clamp(0, 100),
      heading: (_currentTelemetry.heading + (random.nextDouble() - 0.5) * 2) % 360,
      hasReceivedGps: true,
      hasReceivedBattery: true,
      hasReceivedPosition: true,
    );

    if (!_isMissionActive && _currentTelemetry.flightMode == 'DISCONNECTED') {
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'GUIDED');
    }

    if (_connectionState == DroneConnectionState.connecting) {
      _setConnectionState(DroneConnectionState.connected);
    }

    _telemetryController.add(_currentTelemetry);
  }

  // --- Strongly-Typed MAVLink Handler ---

  void _handleTypedMavlinkMessage(MavlinkMessage msg, int sysId, int compId) {
    final now = DateTime.now();

    if (_discoveredSystemId == null || _discoveredSystemId != sysId) {
      _discoveredSystemId = sysId;
      _logDiagnostic("Auto-discovered vehicle System ID: $sysId");
    }
    if (_discoveredComponentId == null || _discoveredComponentId != compId) {
      _discoveredComponentId = compId;
      _logDiagnostic("Auto-discovered vehicle Component ID: $compId");
    }

    if (msg is Heartbeat) {
      _heartbeatCount++;
      _lastHeartbeatTime = now;
      _detectedVehicleType = _resolveVehicleType(msg.type);
      _detectedAutopilotType = _resolveAutopilotType(msg.autopilot);

      String mode = _resolveFlightMode(msg.customMode);
      bool isArmed = (msg.baseMode & 128) != 0;

      if (_connectionState != DroneConnectionState.connected) {
        _setConnectionState(DroneConnectionState.connected);
        _logDiagnostic("Valid MAVLink heartbeat received: SysID=$sysId, CompID=$compId, Vehicle=$_detectedVehicleType, Mode=$mode, Armed=$isArmed");
      }

      _currentTelemetry = _currentTelemetry.copyWith(
        isConnected: true,
        isStale: false,
        flightMode: isArmed ? mode : 'STANDBY',
        armed: isArmed,
        lastHeartbeat: now,
        lastUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);

      if (_targetMode != null && _modeChangeCompleter != null && !_modeChangeCompleter!.isCompleted) {
        if (mode == _targetMode) {
          _logDiagnostic("[MODE CONFIRMED] mode=$_targetMode");
          _modeChangeCompleter!.complete(true);
          _cleanupModeChange();
        }
      }

      if (_targetArmState != null && _armCompleter != null && !_armCompleter!.isCompleted) {
        if (isArmed == _targetArmState) {
          _logDiagnostic("[ARM CONFIRMED] state=$_targetArmState");
          _armCompleter!.complete(true);
          _cleanupArmChange();
        }
      }
    } else if (msg is SysStatus) {
      double volts = double.parse((msg.voltageBattery / 1000.0).toStringAsFixed(2));
      double pct = msg.batteryRemaining >= 0 && msg.batteryRemaining <= 100
          ? msg.batteryRemaining / 100.0
          : _currentTelemetry.batteryPercent;

      _currentTelemetry = _currentTelemetry.copyWith(
        batteryVoltage: volts,
        batteryPercent: pct,
        batteryPercentage: pct * 100.0,
        hasReceivedBattery: true,
        lastBatteryUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);
      _logTelemetryThrottled("SYS_STATUS: voltage=${volts}V, percent=${(pct * 100).toStringAsFixed(0)}%");
    } else if (msg is BatteryStatus) {
      int firstVoltMv = msg.voltages.isNotEmpty ? msg.voltages.first : 0;
      double volts = firstVoltMv > 0 ? double.parse((firstVoltMv / 1000.0).toStringAsFixed(2)) : _currentTelemetry.batteryVoltage;
      double pct = msg.batteryRemaining >= 0 && msg.batteryRemaining <= 100
          ? msg.batteryRemaining / 100.0
          : _currentTelemetry.batteryPercent;

      _currentTelemetry = _currentTelemetry.copyWith(
        batteryVoltage: volts,
        batteryPercent: pct,
        batteryPercentage: pct * 100.0,
        hasReceivedBattery: true,
        lastBatteryUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);
    } else if (msg is GpsRawInt) {
      _currentTelemetry = _currentTelemetry.copyWith(
        satellites: msg.satellitesVisible,
        gpsFix: msg.fixType,
        hasReceivedGps: true,
        lastGpsUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);
      _logTelemetryThrottled("GPS_RAW_INT: satellites=${msg.satellitesVisible}, fix=${msg.fixType}");
    } else if (msg is GlobalPositionInt) {
      double lat = msg.lat / 1E7;
      double lon = msg.lon / 1E7;
      double alt = msg.relativeAlt / 1000.0;
      double hdg = msg.hdg / 100.0;

      _currentTelemetry = _currentTelemetry.copyWith(
        latitude: lat,
        longitude: lon,
        altitude: alt,
        relativeAltitude: alt,
        heading: hdg,
        hasReceivedPosition: true,
        lastGlobalPosition: now,
      );
      _telemetryController.add(_currentTelemetry);
      _logTelemetryThrottled("GLOBAL_POSITION_INT: lat=$lat, lon=$lon, alt=${alt}m, hdg=$hdg°");
    } else if (msg is Attitude) {
      _currentTelemetry = _currentTelemetry.copyWith(
        roll: msg.roll * 180.0 / pi,
        pitch: msg.pitch * 180.0 / pi,
        yaw: msg.yaw * 180.0 / pi,
        hasReceivedAttitude: true,
        lastAttitudeUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);
    } else if (msg is VfrHud) {
      _currentTelemetry = _currentTelemetry.copyWith(
        airSpeed: msg.airspeed,
        groundSpeed: msg.groundspeed,
        speed: msg.groundspeed,
        climbRate: msg.climb,
        hasReceivedVfrHud: true,
        lastVfrHudUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);
    } else if (msg is CommandAck) {
      _logDiagnostic("COMMAND_ACK received: command=${msg.command}, result=${msg.result}");

      if (msg.command == 176) { // MAV_CMD_DO_SET_MODE
        if (msg.result == 0) {
          // Accepted, wait for heartbeat confirmation
        } else {
          if (_modeChangeCompleter != null && !_modeChangeCompleter!.isCompleted) {
            _modeChangeCompleter!.completeError(Exception("Mode change rejected: result code ${msg.result}"));
          }
          _cleanupModeChange();
        }
      } else if (msg.command == 400) { // MAV_CMD_COMPONENT_ARM_DISARM
        if (msg.result == 0) {
          // Accepted, wait for heartbeat confirmation
        } else {
          if (_armCompleter != null && !_armCompleter!.isCompleted) {
            _armCompleter!.completeError(Exception("Arm/Disarm rejected: result code ${msg.result}"));
          }
          _cleanupArmChange();
        }
      } else if (msg.command == 22) { // MAV_CMD_NAV_TAKEOFF
        if (msg.result == 0) {
          if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
            _takeoffCompleter!.complete(true);
          }
        } else {
          if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
            _takeoffCompleter!.completeError(Exception("Takeoff rejected: result code ${msg.result}"));
          }
        }
        _cleanupTakeoff();
      }
    } else if (msg is Statustext) {
      final textStr = String.fromCharCodes(msg.text.where((c) => c != 0)).trim();
      _logDiagnostic("STATUSTEXT (severity ${msg.severity}): $textStr");
      _currentDiagnostics = _currentDiagnostics.copyWith(lastStatusText: textStr);
    } else if (msg is MissionRequest) {
      _logDiagnostic("[MISSION REQUEST] index=${msg.seq}");
      if (_missionUploadCompleter != null && !_missionUploadCompleter!.isCompleted) {
        if (msg.seq >= 0 && msg.seq < _uploadingWaypoints.length) {
          final item = _uploadingWaypoints[msg.seq];
          final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, item);
          final packet = frame.serialize();
          _logDiagnostic("[MISSION TX] item=${msg.seq}");
          _sendMavlinkPacket(packet);

          _missionUploadTimeoutTimer?.cancel();
          _missionUploadTimeoutTimer = Timer(const Duration(seconds: 5), () {
            if (_missionUploadCompleter != null && !_missionUploadCompleter!.isCompleted) {
              _missionUploadCompleter!.completeError(TimeoutException("Mission upload timed out waiting for next request"));
            }
            _cleanupMissionUpload();
          });
        }
      }
    } else if (msg is MissionAck) {
      _logDiagnostic("[MISSION ACK] result=${msg.type}");
      if (_missionUploadCompleter != null && !_missionUploadCompleter!.isCompleted) {
        if (msg.type == 0) {
          _missionUploadCompleter!.complete(true);
        } else {
          _missionUploadCompleter!.completeError(Exception("Mission upload rejected with error code: ${msg.type}"));
        }
        _cleanupMissionUpload();
      }
    } else if (msg is MissionCurrent) {
      _logDiagnostic("[MISSION_CURRENT] active seq=${msg.seq}");
      if (msg.seq > 0 && msg.seq <= _activeWaypoints.length) {
        _currentWaypointIndex = msg.seq - 1;
        final target = _activeWaypoints[_currentWaypointIndex];
        _currentTelemetry = _currentTelemetry.copyWith(
          altitude: target.altitude,
          speed: target.speed,
        );
        _telemetryController.add(_currentTelemetry);
      }
    }

    _updateDiagnostics();
  }

  void _logTelemetryThrottled(String msg) {
    final now = DateTime.now();
    if (_lastTelemetryLogTime == null || now.difference(_lastTelemetryLogTime!) >= const Duration(seconds: 3)) {
      _lastTelemetryLogTime = now;
      _logDiagnostic(msg);
    }
  }

  // Inject a mock socket and force hardware mode active for testing
  void setMockSocket(RawDatagramSocket socket) {
    _mockSocketInstance = socket;
    _socket = socket;
    _socketStatus = 'BOUND';
    _isUsingHardware = true;
    _setConnectionState(DroneConnectionState.connected);
    _socket?.listen((event) {
      if (event == RawSocketEvent.read) {
        while (true) {
          final datagram = _socket?.receive();
          if (datagram == null) break;
          _onDatagramReceived(datagram);
        }
      }
    });
  }

  String _resolveFlightMode(int customMode) {
    switch (customMode) {
      case 0: return 'STABILIZE';
      case 1: return 'ACRO';
      case 2: return 'ALT_HOLD';
      case 3: return 'AUTO';
      case 4: return 'GUIDED';
      case 5: return 'LOITER';
      case 6: return 'RTL';
      case 7: return 'CIRCLE';
      case 9: return 'LAND';
      case 11: return 'DRIFT';
      case 13: return 'SPORT';
      case 14: return 'FLIP';
      case 15: return 'AUTOTUNE';
      case 16: return 'POSHOLD';
      case 17: return 'BRAKE';
      case 18: return 'THROW';
      case 19: return 'AVOID_ADSB';
      case 20: return 'GUIDED_NOGPS';
      case 21: return 'SMART_RTL';
      default: return 'MODE:$customMode';
    }
  }

  String _resolveVehicleType(int type) {
    switch (type) {
      case 1: return 'Fixed Wing';
      case 2: return 'ArduCopter (Quad)';
      case 3: return 'Coaxial Helicopter';
      case 4: return 'Helicopter';
      case 10: return 'Ground Rover';
      case 11: return 'Surface Boat';
      case 12: return 'Submarine';
      case 13: return 'Hexarotor';
      case 14: return 'Octorotor';
      case 15: return 'Tricopter';
      default: return 'Type $type';
    }
  }

  String _resolveAutopilotType(int autopilot) {
    switch (autopilot) {
      case 3: return 'ArduPilot';
      case 12: return 'PX4';
      case 0: return 'Generic';
      default: return 'Autopilot $autopilot';
    }
  }

  // --- Step-by-Step Test Connection Feature ---

  @override
  Future<MavlinkTestResult> testConnection(MavlinkConnectionConfig testConfig) async {
    final validationErrors = testConfig.validate();
    if (validationErrors.isNotEmpty) {
      return MavlinkTestResult(
        success: false,
        message: 'Invalid configuration: ${validationErrors.join(", ")}',
      );
    }

    RawDatagramSocket? testSocket;
    final completer = Completer<MavlinkTestResult>();
    Timer? timeoutTimer;
    final testParser = MavlinkParser(MavlinkDialectArdupilotmega());
    int testDatagrams = 0;
    int testFrames = 0;
    String testProtocol = 'None';
    InternetAddress? testSenderAddr;
    int? testSenderPort;

    try {
      InternetAddress bindAddr = InternetAddress.anyIPv4;
      if (testConfig.bindAddress != '0.0.0.0' && 
          testConfig.bindAddress.isNotEmpty && 
          testConfig.bindAddress.toLowerCase() != 'any') {
        final parsed = InternetAddress.tryParse(testConfig.bindAddress);
        if (parsed != null) bindAddr = parsed;
      }

      testSocket = await RawDatagramSocket.bind(bindAddr, testConfig.localPort, reuseAddress: true);

      timeoutTimer = Timer(Duration(seconds: testConfig.heartbeatTimeoutSeconds), () {
        if (!completer.isCompleted) {
          if (testDatagrams == 0) {
            completer.complete(MavlinkTestResult(
              success: false,
              message: 'Diagnostic failure [B/C]: Socket bound on ${bindAddr.address}:${testConfig.localPort}, but 0 UDP packets arrived within ${testConfig.heartbeatTimeoutSeconds}s. Verify MAVProxy is forwarding to udp:<PHONE_IP>:${testConfig.localPort} or test with Windows PowerShell UDP sender.',
              rawDatagramsReceived: 0,
              mavlinkFramesReceived: 0,
              protocolVersion: testProtocol,
            ));
          } else if (testFrames == 0) {
            final String senderInfo = testSenderAddr != null ? 'from ${testSenderAddr!.address}:$testSenderPort' : '';
            completer.complete(MavlinkTestResult(
              success: true,
              message: 'UDP Transport SUCCESS [A-B Verified]: Received $testDatagrams raw UDP packets $senderInfo. UDP network path is open and functioning properly (Non-MAVLink payload detected).',
              rawDatagramsReceived: testDatagrams,
              mavlinkFramesReceived: 0,
              protocolVersion: testProtocol,
              remoteAddress: testSenderAddr != null ? '${testSenderAddr!.address}:$testSenderPort' : null,
            ));
          } else {
            completer.complete(MavlinkTestResult(
              success: false,
              message: 'Diagnostic failure [E]: Received $testFrames MAVLink frames, but no HEARTBEAT was detected within ${testConfig.heartbeatTimeoutSeconds}s.',
              rawDatagramsReceived: testDatagrams,
              mavlinkFramesReceived: testFrames,
              protocolVersion: testProtocol,
              remoteAddress: testSenderAddr != null ? '${testSenderAddr!.address}:$testSenderPort' : null,
            ));
          }
        }
      });

      testParser.stream.listen((frame) {
        testFrames++;
        if (frame.message is Heartbeat) {
          final hb = frame.message as Heartbeat;
          if (!completer.isCompleted) {
            completer.complete(MavlinkTestResult(
              success: true,
              message: 'Diagnostic SUCCESS [A-E]: Live MAVLink heartbeat verified from Sys=${frame.systemId}, Comp=${frame.componentId} via ${testSenderAddr?.address ?? "remote"}:${testSenderPort ?? testConfig.localPort}.',
              systemId: frame.systemId,
              componentId: frame.componentId,
              vehicleType: _resolveVehicleType(hb.type),
              autopilotType: _resolveAutopilotType(hb.autopilot),
              remoteAddress: testSenderAddr != null ? '${testSenderAddr!.address}:$testSenderPort' : 'Remote Host',
              rawDatagramsReceived: testDatagrams,
              mavlinkFramesReceived: testFrames,
              protocolVersion: testProtocol,
            ));
          }
        }
      });

      testSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final datagram = testSocket?.receive();
            if (datagram == null) break;
            testDatagrams++;
            testSenderAddr = datagram.address;
            testSenderPort = datagram.port;
            if (datagram.data.isNotEmpty) {
              if (datagram.data[0] == 0xFD) {
                testProtocol = 'MAVLink v2 (0xFD)';
                testParser.parse(datagram.data);
              } else if (datagram.data[0] == 0xFE) {
                testProtocol = 'MAVLink v1 (0xFE)';
                testParser.parse(datagram.data);
              } else {
                testProtocol = 'Raw UDP / Non-MAVLink';
              }
            }
          }
        }
      });

      final result = await completer.future;
      timeoutTimer.cancel();
      testSocket.close();
      return result;
    } catch (e) {
      timeoutTimer?.cancel();
      testSocket?.close();
      return MavlinkTestResult(
        success: false,
        message: 'Diagnostic failure [A]: UDP Socket bind error: $e',
      );
    }
  }

  // --- Flight Commands ---

  @override
  Future<bool> arm() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      _currentTelemetry = _currentTelemetry.copyWith(armed: true);
      _telemetryController.add(_currentTelemetry);
      return true;
    }

    if (_armCompleter != null) {
      throw StateError("An arm/disarm command is already in progress.");
    }

    _logDiagnostic("[ARM REQUEST] targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId");

    final command = CommandLong(
      command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
      param1: 1.0,  // Arm
      param2: 0.0,
      param3: 0.0,
      param4: 0.0,
      param5: 0.0,
      param6: 0.0,
      param7: 0.0,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      confirmation: 0,
    );

    final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, command);
    final packet = frame.serialize();

    _targetArmState = true;
    _armCompleter = Completer<bool>();

    _logDiagnostic("[ARM TX] true");
    _sendMavlinkPacket(packet);

    _armTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_armCompleter != null && !_armCompleter!.isCompleted) {
        _logDiagnostic("[ARM TIMEOUT] true");
        _armCompleter!.completeError(TimeoutException("Arm command timed out"));
      }
      _cleanupArmChange();
    });

    try {
      final success = await _armCompleter!.future;
      return success;
    } catch (e) {
      _cleanupArmChange();
      rethrow;
    }
  }

  @override
  Future<bool> disarm() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      _currentTelemetry = _currentTelemetry.copyWith(armed: false);
      _telemetryController.add(_currentTelemetry);
      return true;
    }

    if (_armCompleter != null) {
      throw StateError("An arm/disarm command is already in progress.");
    }

    _logDiagnostic("[DISARM REQUEST] targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId");

    final command = CommandLong(
      command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
      param1: 0.0,  // Disarm
      param2: 0.0,
      param3: 0.0,
      param4: 0.0,
      param5: 0.0,
      param6: 0.0,
      param7: 0.0,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      confirmation: 0,
    );

    final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, command);
    final packet = frame.serialize();

    _targetArmState = false;
    _armCompleter = Completer<bool>();

    _logDiagnostic("[DISARM TX] false");
    _sendMavlinkPacket(packet);

    _armTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_armCompleter != null && !_armCompleter!.isCompleted) {
        _logDiagnostic("[DISARM TIMEOUT] false");
        _armCompleter!.completeError(TimeoutException("Disarm command timed out"));
      }
      _cleanupArmChange();
    });

    try {
      final success = await _armCompleter!.future;
      return success;
    } catch (e) {
      _cleanupArmChange();
      rethrow;
    }
  }

  @override
  Future<bool> setFlightMode(String mode) async {
    final modeUpper = mode.toUpperCase();
    final supportedModes = ['STABILIZE', 'GUIDED', 'LOITER', 'AUTO', 'RTL', 'LAND'];
    if (!supportedModes.contains(modeUpper)) {
      throw ArgumentError("Unsupported flight mode: $mode");
    }

    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: modeUpper);
      _telemetryController.add(_currentTelemetry);
      return true;
    }

    if (_modeChangeCompleter != null) {
      throw StateError("A mode change is already in progress.");
    }

    _logDiagnostic("[MODE REQUEST] $modeUpper targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId");

    int? customModeVal;
    switch (modeUpper) {
      case 'STABILIZE': customModeVal = 0; break;
      case 'AUTO': customModeVal = 3; break;
      case 'GUIDED': customModeVal = 4; break;
      case 'LOITER': customModeVal = 5; break;
      case 'RTL': customModeVal = 6; break;
      case 'LAND': customModeVal = 9; break;
    }

    if (customModeVal == null) {
      return false;
    }

    final command = CommandLong(
      command: 176, // MAV_CMD_DO_SET_MODE
      param1: 1.0,  // Enable custom mode
      param2: customModeVal.toDouble(),
      param3: 0.0,
      param4: 0.0,
      param5: 0.0,
      param6: 0.0,
      param7: 0.0,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      confirmation: 0,
    );

    final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, command);
    final packet = frame.serialize();

    _targetMode = modeUpper;
    _modeChangeCompleter = Completer<bool>();

    _logDiagnostic("[MODE TX] $modeUpper");
    _sendMavlinkPacket(packet);

    _modeTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_modeChangeCompleter != null && !_modeChangeCompleter!.isCompleted) {
        _logDiagnostic("[MODE TIMEOUT] $modeUpper");
        _modeChangeCompleter!.completeError(TimeoutException("Mode change timed out"));
      }
      _cleanupModeChange();
    });

    try {
      final success = await _modeChangeCompleter!.future;
      return success;
    } catch (e) {
      _cleanupModeChange();
      rethrow;
    }
  }

  void _cleanupModeChange() {
    _modeTimeoutTimer?.cancel();
    _modeTimeoutTimer = null;
    _modeChangeCompleter = null;
    _targetMode = null;
  }

  @override
  Future<bool> takeoff(double altitudeMeters) async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      _currentTelemetry = _currentTelemetry.copyWith(
        altitude: altitudeMeters,
        relativeAltitude: altitudeMeters,
      );
      _telemetryController.add(_currentTelemetry);
      return true;
    }

    if (!_currentTelemetry.armed) {
      throw StateError("Vehicle must be armed before takeoff.");
    }

    if (_takeoffCompleter != null) {
      throw StateError("A takeoff command is already in progress.");
    }

    _logDiagnostic("[TAKEOFF REQUEST] ${altitudeMeters}m targetSys=$effectiveTargetSystemId");

    final command = CommandLong(
      command: 22, // MAV_CMD_NAV_TAKEOFF
      param1: 0.0,
      param2: 0.0,
      param3: 0.0,
      param4: 0.0,
      param5: 0.0,
      param6: 0.0,
      param7: altitudeMeters,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      confirmation: 0,
    );

    final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, command);
    final packet = frame.serialize();

    _takeoffCompleter = Completer<bool>();

    _logDiagnostic("[TAKEOFF TX] $altitudeMeters");
    _sendMavlinkPacket(packet);

    _takeoffTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
        _logDiagnostic("[TAKEOFF TIMEOUT] $altitudeMeters");
        _takeoffCompleter!.completeError(TimeoutException("Takeoff command timed out"));
      }
      _cleanupTakeoff();
    });

    try {
      final success = await _takeoffCompleter!.future;
      return success;
    } catch (e) {
      _cleanupTakeoff();
      rethrow;
    }
  }

  void _cleanupTakeoff() {
    _takeoffTimeoutTimer?.cancel();
    _takeoffTimeoutTimer = null;
    _takeoffCompleter = null;
  }

  void _cleanupArmChange() {
    _armTimeoutTimer?.cancel();
    _armTimeoutTimer = null;
    _armCompleter = null;
    _targetArmState = null;
  }

  @override
  List<Waypoint> get activeWaypoints => _activeWaypoints;

  @override
  Future<bool> uploadMission(List<Waypoint> waypoints) async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      _activeWaypoints = waypoints;
      _currentWaypointIndex = 0;
      return true;
    }

    if (_missionUploadCompleter != null) {
      throw StateError("A mission upload is already in progress.");
    }

    _logDiagnostic("[MISSION REQUEST] count=${waypoints.length}");

    double homeLat = _currentTelemetry.latitude;
    double homeLng = _currentTelemetry.longitude;
    if (homeLat == 0.0 || homeLat == 37.7749) {
      homeLat = waypoints.first.latitude;
      homeLng = waypoints.first.longitude;
    }

    final homeItem = MissionItemInt(
      seq: 0,
      frame: 3, // MAV_FRAME_GLOBAL_RELATIVE_ALT
      command: 16, // MAV_CMD_NAV_WAYPOINT
      current: 0,
      autocontinue: 1,
      param1: 0.0,
      param2: 0.0,
      param3: 0.0,
      param4: 0.0,
      x: (homeLat * 1E7).toInt(),
      y: (homeLng * 1E7).toInt(),
      z: 0.0,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      missionType: 0,
    );

    final list = <MissionItemInt>[homeItem];
    for (int i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      list.add(MissionItemInt(
        seq: i + 1,
        frame: 3, // MAV_FRAME_GLOBAL_RELATIVE_ALT
        command: 16, // MAV_CMD_NAV_WAYPOINT
        current: 0,
        autocontinue: 1,
        param1: wp.hoverTime.toDouble(),
        param2: 2.0, // 2m acceptance radius
        param3: 0.0,
        param4: 0.0,
        x: (wp.latitude * 1E7).toInt(),
        y: (wp.longitude * 1E7).toInt(),
        z: wp.altitude,
        targetSystem: effectiveTargetSystemId,
        targetComponent: effectiveTargetComponentId,
        missionType: 0,
      ));
    }

    _uploadingWaypoints = list;
    _missionUploadCompleter = Completer<bool>();

    final countMsg = MissionCount(
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      count: _uploadingWaypoints.length,
      missionType: 0,
      opaqueId: 0,
    );

    final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, countMsg);
    final packet = frame.serialize();

    _logDiagnostic("[MISSION TX] count=${_uploadingWaypoints.length}");
    _sendMavlinkPacket(packet);

    _missionUploadTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_missionUploadCompleter != null && !_missionUploadCompleter!.isCompleted) {
        _logDiagnostic("[MISSION TIMEOUT] upload");
        _missionUploadCompleter!.completeError(TimeoutException("Mission upload timed out"));
      }
      _cleanupMissionUpload();
    });

    try {
      final success = await _missionUploadCompleter!.future;
      if (success) {
        _activeWaypoints = waypoints;
        _currentWaypointIndex = 0;
      }
      return success;
    } catch (e) {
      _cleanupMissionUpload();
      rethrow;
    }
  }

  void _cleanupMissionUpload() {
    _missionUploadTimeoutTimer?.cancel();
    _missionUploadTimeoutTimer = null;
    _missionUploadCompleter = null;
    _uploadingWaypoints = [];
  }

  @override
  Future<bool> clearMission() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      _isMissionActive = false;
      _missionTimer?.cancel();
      _activeWaypoints = [];
      _currentWaypointIndex = 0;
      return true;
    }

    final clearMsg = MissionClearAll(
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      missionType: 0,
    );
    final frame = MavlinkFrame.v2(_sequenceNumber++, _config.sourceSystemId, _config.sourceComponentId, clearMsg);
    final packet = frame.serialize();
    _sendMavlinkPacket(packet);

    _isMissionActive = false;
    _missionTimer?.cancel();
    _activeWaypoints = [];
    _currentWaypointIndex = 0;
    return true;
  }

  @override
  Future<bool> startMission() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (!_isUsingHardware) {
      if (_activeWaypoints.isEmpty) return false;
      _currentWaypointIndex = 0;
      _isMissionActive = true;

      _currentTelemetry = _currentTelemetry.copyWith(
        flightMode: 'AUTO',
        speed: _activeWaypoints.first.speed,
        altitude: _activeWaypoints.first.altitude,
        latitude: _activeWaypoints.first.latitude,
        longitude: _activeWaypoints.first.longitude,
      );
      _telemetryController.add(_currentTelemetry);

      _missionTimer?.cancel();
      _missionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_isMissionActive) return;

        if (_currentWaypointIndex >= _activeWaypoints.length) {
          _isMissionActive = false;
          _missionTimer?.cancel();
          _currentTelemetry = _currentTelemetry.copyWith(
            flightMode: 'LOITER',
            speed: 0.0,
          );
          _telemetryController.add(_currentTelemetry);
          return;
        }

        final target = _activeWaypoints[_currentWaypointIndex];
        final double currentLat = _currentTelemetry.latitude;
        final double currentLng = _currentTelemetry.longitude;

        final double distLat = target.latitude - currentLat;
        final double distLng = target.longitude - currentLng;
        final double dist = sqrt(distLat * distLat + distLng * distLng);

        if (dist < 0.00015) {
          _currentWaypointIndex++;
          if (_currentWaypointIndex < _activeWaypoints.length) {
            _currentTelemetry = _currentTelemetry.copyWith(
              altitude: _activeWaypoints[_currentWaypointIndex].altitude,
              speed: _activeWaypoints[_currentWaypointIndex].speed,
            );
          }
        } else {
          final double stepLat = (distLat / dist) * 0.00015;
          final double stepLng = (distLng / dist) * 0.00015;

          double angle = atan2(distLng, distLat) * 180 / pi;
          if (angle < 0) angle += 360;

          _currentTelemetry = _currentTelemetry.copyWith(
            latitude: currentLat + stepLat,
            longitude: currentLng + stepLng,
            heading: angle,
            distance: _currentTelemetry.distance + 8.5,
          );
        }

        _telemetryController.add(_currentTelemetry);
      });
      return true;
    }

    return setFlightMode('AUTO');
  }

  @override
  Future<bool> pauseMission() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      _isMissionActive = false;
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'LOITER', speed: 0.0);
      _telemetryController.add(_currentTelemetry);
      return true;
    }
    return setFlightMode('LOITER');
  }

  @override
  Future<bool> resumeMission() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      if (_activeWaypoints.isNotEmpty) {
        _isMissionActive = true;
        _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'AUTO', speed: 5.0);
        _telemetryController.add(_currentTelemetry);
        return true;
      }
      return false;
    }
    return setFlightMode('AUTO');
  }

  @override
  Future<bool> returnToLaunch() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      _isMissionActive = false;
      _missionTimer?.cancel();
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'RTL', speed: 8.0);
      _telemetryController.add(_currentTelemetry);

      Timer(const Duration(seconds: 6), () {
        _currentTelemetry = _currentTelemetry.copyWith(
          latitude: 37.7749,
          longitude: -122.4194,
          altitude: 0.0,
          speed: 0.0,
          flightMode: 'LANDED',
        );
        _telemetryController.add(_currentTelemetry);
      });
      return true;
    }
    return setFlightMode('RTL');
  }

  @override
  Future<bool> land() async {
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      _isMissionActive = false;
      _missionTimer?.cancel();
      _currentTelemetry = _currentTelemetry.copyWith(flightMode: 'LAND', speed: 1.2);
      _telemetryController.add(_currentTelemetry);

      Timer(const Duration(seconds: 5), () {
        _currentTelemetry = _currentTelemetry.copyWith(
          altitude: 0.0,
          speed: 0.0,
          flightMode: 'LANDED',
        );
        _telemetryController.add(_currentTelemetry);
      });
      return true;
    }
    return setFlightMode('LAND');
  }

  // --- UDP Packet Transmitter ---

  void _sendMavlinkPacket(Uint8List packet) {
    if (_socket == null) return;

    if (_config.connectionMode == MavlinkConnectionMode.direct) {
      if (_config.remoteHost.isNotEmpty) {
        try {
          final destination = InternetAddress(_config.remoteHost);
          _socket!.send(packet, destination, _config.remotePort);
        } catch (e) {
          _logDiagnostic("Error sending UDP packet to direct host ${_config.remoteHost}: $e");
        }
      }
    } else {
      // Listener mode: reply to discovered sender if available, or fallback to remote host if configured
      if (_lastSenderAddress != null && _lastSenderPort != null) {
        _socket!.send(packet, _lastSenderAddress!, _lastSenderPort!);
      } else if (_config.remoteHost.isNotEmpty) {
        try {
          final destination = InternetAddress(_config.remoteHost);
          _socket!.send(packet, destination, _config.remotePort);
        } catch (e) {
          _logDiagnostic("Error sending UDP packet to fallback host ${_config.remoteHost}: $e");
        }
      } else {
        // Fallback before any remote packet has arrived (e.g. testing / local loopback)
        try {
          _socket!.send(packet, InternetAddress.loopbackIPv4, _config.localPort);
        } catch (e) {
          _logDiagnostic("Error sending UDP packet: $e");
        }
      }
    }
  }
}
