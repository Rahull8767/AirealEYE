import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/models/motor_test_state.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mavlink_config_storage.dart';
import 'package:aerial_eye/services/pi_http_telemetry_service.dart';
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

class MavlinkDroneService implements DroneService {
  MavlinkConnectionConfig _config = MavlinkConnectionConfig.defaultConfig();
  late final PiHttpTelemetryService _httpService;

  final _telemetryController = StreamController<DroneTelemetry>.broadcast();
  DroneTelemetry _currentTelemetry = DroneTelemetry.initial();

  final _connectionStateController =
      StreamController<DroneConnectionState>.broadcast();
  DroneConnectionState _connectionState = DroneConnectionState.disconnected;

  final _diagnosticsController =
      StreamController<ConnectionDiagnostics>.broadcast();
  ConnectionDiagnostics _currentDiagnostics = ConnectionDiagnostics.initial();

  final MavlinkParser _mavlinkParser = MavlinkParser(
    MavlinkDialectArdupilotmega(),
  );

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

  Completer<MotorTestResult>? _motorTestCompleter;
  Timer? _motorTestTimeoutTimer;
  Timer? _motorTestDurationTimer;
  int? _activeMotorTestInstance;
  bool _activeMotorTestIsAll = false;
  double _lastMotorTestThrottle = 10.0;
  int _lastMotorTestDuration = 3;

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

  MavlinkDroneService({MavlinkConnectionConfig? initialConfig}) {
    if (initialConfig != null) {
      _config = initialConfig;
    }
    _httpService = PiHttpTelemetryService(config: _config);
    _initHttpListeners();
    _initStoredConfig(skipIfConfigured: initialConfig != null);
    _initParserListener();
    _startPpsSampler();
  }

  void _initHttpListeners() {
    _httpService.telemetryStream.listen((telem) {
      if (_config.transport == MavlinkTransport.http) {
        _currentTelemetry = telem;
        _telemetryController.add(telem);
      }
    });

    _httpService.connectionStateStream.listen((state) {
      if (_config.transport == MavlinkTransport.http) {
        _connectionState = state;
        _connectionStateController.add(state);
      }
    });

    _httpService.diagnosticsStream.listen((diag) {
      if (_config.transport == MavlinkTransport.http) {
        _currentDiagnostics = diag;
        _diagnosticsController.add(diag);
      }
    });
  }

  void _initParserListener() {
    _mavlinkParser.stream.listen(
      (frame) {
        _mavlinkFramesReceived++;
        _lastMavlinkFrameTime = DateTime.now();
        _lastReceivedSourceSystemId = frame.systemId;
        _lastReceivedSourceComponentId = frame.componentId;
        _lastReceivedMessageType = frame.message.runtimeType.toString();

        _handleTypedMavlinkMessage(
          frame.message,
          frame.systemId,
          frame.componentId,
        );
      },
      onError: (err) {
        _malformedFramesCount++;
        _packetsDropped++;
        _logDiagnostic("[MAVLINK ERROR] Framing / CRC parse error: $err");
      },
    );
  }

  Future<void> _initStoredConfig({bool skipIfConfigured = false}) async {
    if (skipIfConfigured) return;
    try {
      final stored = await MavlinkConfigStorage.loadConfig();
      _config = stored;
      _httpService.updateConfig(stored);
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
    final transportChanged = _config.transport != newConfig.transport;
    _config = newConfig;
    _httpService.updateConfig(newConfig);
    MavlinkConfigStorage.saveConfig(newConfig);
    _logDiagnostic(
      "Config updated: transport=${newConfig.transport.name}, localPort=${newConfig.localPort}, httpUrl=${newConfig.httpBaseUrl}",
    );
    if (transportChanged &&
        _connectionState == DroneConnectionState.connected) {
      disconnect();
      connect();
    }
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
  Stream<DroneConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  DroneConnectionState get connectionState => _connectionState;

  @override
  Stream<ConnectionDiagnostics> get diagnosticsStream =>
      _diagnosticsController.stream;

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

    if (_config.transport == MavlinkTransport.http) {
      if (_socket != null) {
        _socket?.close();
        _socket = null;
        _socketStatus = 'CLOSED';
      }
      _isUsingHardware = false;
      _httpService.start();
      return;
    }

    _httpService.stop();

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
      _logDiagnostic(
        "Simulation mode active: simulated vehicle telemetry running",
      );
    }

    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
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

    _httpService.stop();

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
      _modeChangeCompleter!.completeError(
        StateError("MAVLink link was disconnected."),
      );
    }
    _cleanupModeChange();

    if (_armCompleter != null && !_armCompleter!.isCompleted) {
      _armCompleter!.completeError(
        StateError("MAVLink link was disconnected."),
      );
    }
    _cleanupArmChange();

    if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
      _takeoffCompleter!.completeError(
        StateError("MAVLink link was disconnected."),
      );
    }
    _cleanupTakeoff();

    if (_missionUploadCompleter != null &&
        !_missionUploadCompleter!.isCompleted) {
      _missionUploadCompleter!.completeError(
        StateError("MAVLink link was disconnected."),
      );
    }
    _cleanupMissionUpload();

    if (_motorTestCompleter != null && !_motorTestCompleter!.isCompleted) {
      _motorTestCompleter!.completeError(
        StateError("MAVLink link was disconnected."),
      );
    }
    _cleanupMotorTest();
  }

  void _setConnectionState(DroneConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionStateController.add(_connectionState);
      _logDiagnostic(
        "Connection state changed: ${_currentDiagnostics.connectionStateLabel}",
      );
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
      _logDiagnostic(
        "[SOCKET REBIND] Closing existing UDP socket before rebinding...",
      );
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

      _logDiagnostic(
        "[SOCKET BINDING] Binding local UDP socket on ${bindAddr.address}:${_config.localPort} (reuseAddress: true)...",
      );
      _socket = await RawDatagramSocket.bind(
        bindAddr,
        _config.localPort,
        reuseAddress: true,
      );
      _socketStatus = 'BOUND';
      _logDiagnostic(
        "[SOCKET BOUND] Local UDP socket successfully bound on ${_socket!.address.address}:${_socket!.port}",
      );

      if (_connectionState == DroneConnectionState.connecting) {
        _setConnectionState(DroneConnectionState.socketBoundWaiting);
      }

      _socket?.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            while (true) {
              final datagram = _socket?.receive();
              if (datagram == null) break;
              _onDatagramReceived(datagram);
            }
          }
        },
        onError: (error) {
          _socketStatus = 'ERROR';
          _logDiagnostic("[SOCKET ERROR] Local UDP Socket error: $error");
          _setConnectionState(DroneConnectionState.error);
        },
        onDone: () {
          _socketStatus = 'CLOSED';
          _logDiagnostic("[SOCKET CLOSED] Local UDP Socket closed by system");
        },
      );
    } catch (e) {
      _socketStatus = 'ERROR';
      _logDiagnostic(
        "[SOCKET ERROR] Local UDP socket bind failed on port ${_config.localPort}: $e",
      );
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
      final previewChars = data
          .take(64)
          .map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.')
          .join();
      asciiPreview = previewChars;
    }

    _lastRawDatagramSize = byteLength;
    _lastRawDatagramPreview = asciiPreview;
    _lastRawSender = '$srcIp:$srcPort';

    _logDiagnostic(
      "[UDP RX #$_rawDatagramsReceived] $srcIp:$srcPort -> $byteLength bytes ($protoLabel) | Content: \"$asciiPreview\"",
    );

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
        if (_connectionState == DroneConnectionState.socketBoundWaiting ||
            _connectionState == DroneConnectionState.connecting) {
          _setConnectionState(DroneConnectionState.mavlinkNoHeartbeat);
        }
      } else if (_rawDatagramsReceived > 0) {
        if (_connectionState == DroneConnectionState.socketBoundWaiting ||
            _connectionState == DroneConnectionState.connecting) {
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
          _logDiagnostic(
            "Heartbeat timed out (${diff.inSeconds}s since last heartbeat). Link marked stale.",
          );

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
      if (_mavlinkFramesReceived > 0 &&
          _connectionState != DroneConnectionState.mavlinkNoHeartbeat) {
        _setConnectionState(DroneConnectionState.mavlinkNoHeartbeat);
      } else if (_rawDatagramsReceived > 0 &&
          _connectionState != DroneConnectionState.udpPacketsNoMavlink) {
        _setConnectionState(DroneConnectionState.udpPacketsNoMavlink);
      } else if (_socket != null &&
          _connectionState != DroneConnectionState.socketBoundWaiting &&
          _connectionState != DroneConnectionState.connecting) {
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
      satellites: _currentTelemetry.hasReceivedGps
          ? _currentTelemetry.satellites
          : null,
      batteryVoltage: _currentTelemetry.hasReceivedBattery
          ? _currentTelemetry.batteryVoltage
          : null,
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
      heading:
          (_currentTelemetry.heading + (random.nextDouble() - 0.5) * 2) % 360,
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
        _logDiagnostic(
          "Valid MAVLink heartbeat received: SysID=$sysId, CompID=$compId, Vehicle=$_detectedVehicleType, Mode=$mode, Armed=$isArmed",
        );
      }

      if (_mockSocketInstance == null &&
          (_heartbeatCount == 1 || _heartbeatCount % 20 == 0)) {
        requestDataStreams();
      }

      _currentTelemetry = _currentTelemetry.copyWith(
        isConnected: true,
        isStale: false,
        flightMode: mode,
        armed: isArmed,
        lastHeartbeat: now,
        lastUpdate: now,
      );
      _telemetryController.add(_currentTelemetry);

      if (_targetMode != null &&
          _modeChangeCompleter != null &&
          !_modeChangeCompleter!.isCompleted) {
        if (mode == _targetMode) {
          _logDiagnostic("[MODE CONFIRMED] mode=$_targetMode");
          _modeChangeCompleter!.complete(true);
          _cleanupModeChange();
        }
      }

      if (_targetArmState != null &&
          _armCompleter != null &&
          !_armCompleter!.isCompleted) {
        if (isArmed == _targetArmState) {
          _logDiagnostic("[ARM CONFIRMED] state=$_targetArmState");
          _armCompleter!.complete(true);
          _cleanupArmChange();
        }
      }
    } else if (msg is SysStatus) {
      double volts = double.parse(
        (msg.voltageBattery / 1000.0).toStringAsFixed(2),
      );
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
      _logTelemetryThrottled(
        "SYS_STATUS: voltage=${volts}V, percent=${(pct * 100).toStringAsFixed(0)}%",
      );
    } else if (msg is BatteryStatus) {
      int firstVoltMv = msg.voltages.isNotEmpty ? msg.voltages.first : 0;
      double volts = firstVoltMv > 0
          ? double.parse((firstVoltMv / 1000.0).toStringAsFixed(2))
          : _currentTelemetry.batteryVoltage;
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
      _logTelemetryThrottled(
        "GPS_RAW_INT: satellites=${msg.satellitesVisible}, fix=${msg.fixType}",
      );
    } else if (msg is GlobalPositionInt) {
      double lat = msg.lat / 1E7;
      double lon = msg.lon / 1E7;
      double alt = msg.relativeAlt / 1000.0;
      double hdg = msg.hdg / 100.0;

      final double? currentHomeLat =
          _currentTelemetry.homeLatitude ?? (lat != 0.0 ? lat : null);
      final double? currentHomeLon =
          _currentTelemetry.homeLongitude ?? (lon != 0.0 ? lon : null);

      _currentTelemetry = _currentTelemetry.copyWith(
        latitude: lat,
        longitude: lon,
        altitude: alt,
        relativeAltitude: alt,
        heading: hdg,
        homeLatitude: currentHomeLat,
        homeLongitude: currentHomeLon,
        hasReceivedPosition: true,
        lastGlobalPosition: now,
      );
      _telemetryController.add(_currentTelemetry);
      _logTelemetryThrottled(
        "[TAKEOFF TELEMETRY] altitude=${alt.toStringAsFixed(1)}m",
      );
      _logTelemetryThrottled(
        "GLOBAL_POSITION_INT: lat=$lat, lon=$lon, alt=${alt}m, hdg=$hdg°",
      );
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
      _logDiagnostic(
        "COMMAND_ACK received: command=${msg.command}, result=${msg.result}",
      );

      if (msg.command == 176) {
        // MAV_CMD_DO_SET_MODE
        if (msg.result == 0) {
          // Accepted, wait for heartbeat confirmation
        } else {
          if (_modeChangeCompleter != null &&
              !_modeChangeCompleter!.isCompleted) {
            _modeChangeCompleter!.completeError(
              Exception("Mode change rejected: result code ${msg.result}"),
            );
          }
          _cleanupModeChange();
        }
      } else if (msg.command == 400) {
        // MAV_CMD_COMPONENT_ARM_DISARM
        if (msg.result == 0) {
          // Accepted, wait for heartbeat confirmation
        } else {
          if (_armCompleter != null && !_armCompleter!.isCompleted) {
            _armCompleter!.completeError(
              Exception(
                "Arm/Disarm rejected: result code ${msg.result} (Pre-arm check or state fault)",
              ),
            );
          }
          _cleanupArmChange();
        }
      } else if (msg.command == 22) {
        // MAV_CMD_NAV_TAKEOFF
        _logDiagnostic("[TAKEOFF ACK] result=${msg.result}");
        if (msg.result == 0) {
          if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
            _takeoffCompleter!.complete(true);
          }
        } else {
          if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
            _takeoffCompleter!.completeError(
              Exception("Takeoff rejected: result code ${msg.result}"),
            );
          }
        }
        _cleanupTakeoff();
      } else if (msg.command == 209) {
        // MAV_CMD_DO_MOTOR_TEST
        _logDiagnostic("[MOTOR_TEST ACK] command=209 result=${msg.result}");
        _handleMotorTestAck(msg.result);
      }
    } else if (msg is Statustext) {
      final textStr = String.fromCharCodes(
        msg.text.where((c) => c != 0),
      ).trim();
      _logDiagnostic("STATUSTEXT (severity ${msg.severity}): $textStr");
      _currentDiagnostics = _currentDiagnostics.copyWith(
        lastStatusText: textStr,
      );
    } else if (msg is MissionRequest || msg is MissionRequestInt) {
      final int requestedSeq = msg is MissionRequest
          ? msg.seq
          : (msg as MissionRequestInt).seq;
      _logDiagnostic("[MISSION REQUEST] index=$requestedSeq");
      if (_missionUploadCompleter != null &&
          !_missionUploadCompleter!.isCompleted) {
        if (requestedSeq >= 0 && requestedSeq < _uploadingWaypoints.length) {
          final item = _uploadingWaypoints[requestedSeq];
          final frame = _createOutFrame(item);
          final packet = frame.serialize();
          _logDiagnostic("[MISSION TX] item=$requestedSeq");
          _sendMavlinkPacket(packet);

          _missionUploadTimeoutTimer?.cancel();
          _missionUploadTimeoutTimer = Timer(const Duration(seconds: 5), () {
            if (_missionUploadCompleter != null &&
                !_missionUploadCompleter!.isCompleted) {
              _missionUploadCompleter!.completeError(
                TimeoutException(
                  "Mission upload timed out waiting for next request",
                ),
              );
            }
            _cleanupMissionUpload();
          });
        }
      }
    } else if (msg is MissionAck) {
      _logDiagnostic("[MISSION ACK] result=${msg.type}");
      if (_missionUploadCompleter != null &&
          !_missionUploadCompleter!.isCompleted) {
        if (msg.type == 0) {
          _missionUploadCompleter!.complete(true);
        } else {
          _missionUploadCompleter!.completeError(
            Exception("Mission upload rejected with error code: ${msg.type}"),
          );
        }
        _cleanupMissionUpload();
      }
    } else if (msg is MissionCurrent) {
      _logDiagnostic("[MISSION_CURRENT] active seq=${msg.seq}");
      _currentWaypointIndex = msg.seq;
      _currentTelemetry = _currentTelemetry.copyWith(
        currentWaypoint: msg.seq,
        totalWaypoints: _activeWaypoints.length,
      );
      _telemetryController.add(_currentTelemetry);
    }

    _updateDiagnostics();
  }

  void _logTelemetryThrottled(String msg) {
    final now = DateTime.now();
    if (_lastTelemetryLogTime == null ||
        now.difference(_lastTelemetryLogTime!) >= const Duration(seconds: 3)) {
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
      case 0:
        return 'STABILIZE';
      case 1:
        return 'ACRO';
      case 2:
        return 'ALT_HOLD';
      case 3:
        return 'AUTO';
      case 4:
        return 'GUIDED';
      case 5:
        return 'LOITER';
      case 6:
        return 'RTL';
      case 7:
        return 'CIRCLE';
      case 9:
        return 'LAND';
      case 11:
        return 'DRIFT';
      case 13:
        return 'SPORT';
      case 14:
        return 'FLIP';
      case 15:
        return 'AUTOTUNE';
      case 16:
        return 'POSHOLD';
      case 17:
        return 'BRAKE';
      case 18:
        return 'THROW';
      case 19:
        return 'AVOID_ADSB';
      case 20:
        return 'GUIDED_NOGPS';
      case 21:
        return 'SMART_RTL';
      default:
        return 'MODE:$customMode';
    }
  }

  String _resolveVehicleType(int type) {
    switch (type) {
      case 1:
        return 'Fixed Wing';
      case 2:
        return 'ArduCopter (Quad)';
      case 3:
        return 'Coaxial Helicopter';
      case 4:
        return 'Helicopter';
      case 10:
        return 'Ground Rover';
      case 11:
        return 'Surface Boat';
      case 12:
        return 'Submarine';
      case 13:
        return 'Hexarotor';
      case 14:
        return 'Octorotor';
      case 15:
        return 'Tricopter';
      default:
        return 'Type $type';
    }
  }

  String _resolveAutopilotType(int autopilot) {
    switch (autopilot) {
      case 3:
        return 'ArduPilot';
      case 12:
        return 'PX4';
      case 0:
        return 'Generic';
      default:
        return 'Autopilot $autopilot';
    }
  }

  // --- Step-by-Step Test Connection Feature ---

  @override
  Future<MavlinkTestResult> testConnection(
    MavlinkConnectionConfig testConfig,
  ) async {
    final validationErrors = testConfig.validate();
    if (validationErrors.isNotEmpty) {
      return MavlinkTestResult(
        success: false,
        message: 'Invalid configuration: ${validationErrors.join(", ")}',
      );
    }

    if (testConfig.transport == MavlinkTransport.http) {
      return _httpService.testEndpoint(
        testConfig.httpBaseUrl,
        timeoutSeconds: testConfig.httpTimeoutSeconds,
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

      testSocket = await RawDatagramSocket.bind(
        bindAddr,
        testConfig.localPort,
        reuseAddress: true,
      );

      timeoutTimer = Timer(Duration(seconds: testConfig.heartbeatTimeoutSeconds), () {
        if (!completer.isCompleted) {
          if (testDatagrams == 0) {
            completer.complete(
              MavlinkTestResult(
                success: false,
                message:
                    'Diagnostic failure [B/C]: Socket bound on ${bindAddr.address}:${testConfig.localPort}, but 0 UDP packets arrived within ${testConfig.heartbeatTimeoutSeconds}s. Verify MAVProxy is forwarding to udp:<PHONE_IP>:${testConfig.localPort} or test with Windows PowerShell UDP sender.',
                rawDatagramsReceived: 0,
                mavlinkFramesReceived: 0,
                protocolVersion: testProtocol,
              ),
            );
          } else if (testFrames == 0) {
            final String senderInfo = testSenderAddr != null
                ? 'from ${testSenderAddr!.address}:$testSenderPort'
                : '';
            completer.complete(
              MavlinkTestResult(
                success: true,
                message:
                    'UDP Transport SUCCESS [A-B Verified]: Received $testDatagrams raw UDP packets $senderInfo. UDP network path is open and functioning properly (Non-MAVLink payload detected).',
                rawDatagramsReceived: testDatagrams,
                mavlinkFramesReceived: 0,
                protocolVersion: testProtocol,
                remoteAddress: testSenderAddr != null
                    ? '${testSenderAddr!.address}:$testSenderPort'
                    : null,
              ),
            );
          } else {
            completer.complete(
              MavlinkTestResult(
                success: false,
                message:
                    'Diagnostic failure [E]: Received $testFrames MAVLink frames, but no HEARTBEAT was detected within ${testConfig.heartbeatTimeoutSeconds}s.',
                rawDatagramsReceived: testDatagrams,
                mavlinkFramesReceived: testFrames,
                protocolVersion: testProtocol,
                remoteAddress: testSenderAddr != null
                    ? '${testSenderAddr!.address}:$testSenderPort'
                    : null,
              ),
            );
          }
        }
      });

      testParser.stream.listen((frame) {
        testFrames++;
        if (frame.message is Heartbeat) {
          final hb = frame.message as Heartbeat;
          if (!completer.isCompleted) {
            completer.complete(
              MavlinkTestResult(
                success: true,
                message:
                    'Diagnostic SUCCESS [A-E]: Live MAVLink heartbeat verified from Sys=${frame.systemId}, Comp=${frame.componentId} via ${testSenderAddr?.address ?? "remote"}:${testSenderPort ?? testConfig.localPort}.',
                systemId: frame.systemId,
                componentId: frame.componentId,
                vehicleType: _resolveVehicleType(hb.type),
                autopilotType: _resolveAutopilotType(hb.autopilot),
                remoteAddress: testSenderAddr != null
                    ? '${testSenderAddr!.address}:$testSenderPort'
                    : 'Remote Host',
                rawDatagramsReceived: testDatagrams,
                mavlinkFramesReceived: testFrames,
                protocolVersion: testProtocol,
              ),
            );
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

  void _assertCommandSupported(String commandName) {
    if (_config.transport == MavlinkTransport.http) {
      final msg =
          'Flight command "$commandName" is not supported in Raspberry Pi HTTP Telemetry mode. Switch to MAVLink UDP mode for full flight control.';
      _logDiagnostic("[HTTP RESTRICTION] $msg");
      throw UnsupportedError(msg);
    }
  }

  @override
  Future<bool> arm() async {
    _assertCommandSupported('arm');
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

    _logDiagnostic(
      "[ARM REQUEST] targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId",
    );

    final command = CommandLong(
      command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
      param1: 1.0, // Arm
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

    final frame = _createOutFrame(command);
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
    _assertCommandSupported('disarm');
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

    _logDiagnostic(
      "[DISARM REQUEST] targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId",
    );

    final command = CommandLong(
      command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
      param1: 0.0, // Disarm
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

    final frame = _createOutFrame(command);
    final packet = frame.serialize();

    _targetArmState = false;
    _armCompleter = Completer<bool>();

    _logDiagnostic("[DISARM TX] false");
    _sendMavlinkPacket(packet);

    _armTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_armCompleter != null && !_armCompleter!.isCompleted) {
        _logDiagnostic("[DISARM TIMEOUT] false");
        _armCompleter!.completeError(
          TimeoutException("Disarm command timed out"),
        );
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
    _assertCommandSupported('setFlightMode');
    final modeUpper = mode.toUpperCase();
    final supportedModes = [
      'STABILIZE',
      'GUIDED',
      'LOITER',
      'AUTO',
      'RTL',
      'LAND',
    ];
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

    _logDiagnostic(
      "[MODE REQUEST] $modeUpper targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId",
    );

    int? customModeVal;
    switch (modeUpper) {
      case 'STABILIZE':
        customModeVal = 0;
        break;
      case 'AUTO':
        customModeVal = 3;
        break;
      case 'GUIDED':
        customModeVal = 4;
        break;
      case 'LOITER':
        customModeVal = 5;
        break;
      case 'RTL':
        customModeVal = 6;
        break;
      case 'LAND':
        customModeVal = 9;
        break;
    }

    if (customModeVal == null) {
      return false;
    }

    final command = CommandLong(
      command: 176, // MAV_CMD_DO_SET_MODE
      param1: 1.0, // Enable custom mode
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

    final frame = _createOutFrame(command);
    final packet = frame.serialize();

    _targetMode = modeUpper;
    _modeChangeCompleter = Completer<bool>();

    _logDiagnostic("[MODE TX] $modeUpper");
    _sendMavlinkPacket(packet);

    _modeTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_modeChangeCompleter != null && !_modeChangeCompleter!.isCompleted) {
        _logDiagnostic("[MODE TIMEOUT] $modeUpper");
        _modeChangeCompleter!.completeError(
          TimeoutException("Mode change timed out"),
        );
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
    _assertCommandSupported('takeoff');
    _logDiagnostic("[TAKEOFF REQUEST]");

    final bool isConnected =
        _connectionState == DroneConnectionState.connected &&
        _currentTelemetry.isConnected;
    _logDiagnostic("[TAKEOFF CHECK] connected=$isConnected");

    if (!isConnected) {
      throw StateError("MAVLink link is not connected.");
    }

    final bool isArmed = _currentTelemetry.armed;
    _logDiagnostic("[TAKEOFF CHECK] armed=$isArmed");

    if (!isArmed) {
      throw StateError("Vehicle must be armed before takeoff.");
    }

    _logDiagnostic("[TAKEOFF CHECK] mode=${_currentTelemetry.flightMode}");

    if (_takeoffCompleter != null) {
      throw StateError("A takeoff command is already in progress.");
    }

    if (!_isUsingHardware) {
      if (_currentTelemetry.flightMode != 'GUIDED') {
        _logDiagnostic("[TAKEOFF MODE] requesting GUIDED");
        await setFlightMode('GUIDED');
        _logDiagnostic("[TAKEOFF MODE] GUIDED confirmed");
      }
      _logDiagnostic("[TAKEOFF TX] altitude=$altitudeMeters");
      _logDiagnostic("[TAKEOFF ACK] result=0");
      _currentTelemetry = _currentTelemetry.copyWith(
        altitude: altitudeMeters,
        relativeAltitude: altitudeMeters,
      );
      _telemetryController.add(_currentTelemetry);
      _logDiagnostic(
        "[TAKEOFF TELEMETRY] altitude=${_currentTelemetry.altitude}",
      );
      return true;
    }

    // If vehicle is armed but not in GUIDED, transition to GUIDED and await Heartbeat confirmation
    if (_currentTelemetry.flightMode != 'GUIDED') {
      _logDiagnostic("[TAKEOFF MODE] requesting GUIDED");
      final modeSuccess = await setFlightMode('GUIDED');
      if (!modeSuccess || _currentTelemetry.flightMode != 'GUIDED') {
        throw StateError(
          "Failed to transition to GUIDED mode prior to takeoff.",
        );
      }
      _logDiagnostic("[TAKEOFF MODE] GUIDED confirmed");
    }

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

    final frame = _createOutFrame(command);
    final packet = frame.serialize();

    _takeoffCompleter = Completer<bool>();

    _logDiagnostic("[TAKEOFF TX] altitude=$altitudeMeters");
    _sendMavlinkPacket(packet);

    _takeoffTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_takeoffCompleter != null && !_takeoffCompleter!.isCompleted) {
        _logDiagnostic("[TAKEOFF TIMEOUT] $altitudeMeters");
        _takeoffCompleter!.completeError(
          TimeoutException("Takeoff command timed out waiting for COMMAND_ACK"),
        );
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

  void _handleMotorTestAck(int result) {
    if (_motorTestCompleter != null && !_motorTestCompleter!.isCompleted) {
      final success = result == 0;
      final desc = MotorTestResult.describeMavResult(result);
      _motorTestCompleter!.complete(
        MotorTestResult(
          success: success,
          ackResult: result,
          message: success
              ? "Motor test command accepted by flight controller"
              : "Motor test rejected: $desc",
          commandId: 209,
          motorIndex: _activeMotorTestInstance ?? 1,
          testAll: _activeMotorTestIsAll,
          throttlePercent: _lastMotorTestThrottle,
          durationSeconds: _lastMotorTestDuration,
          isSimulated: !_isUsingHardware,
          timestamp: DateTime.now(),
        ),
      );
    }
    _cleanupMotorTestAck();
  }

  void _cleanupMotorTestAck() {
    _motorTestTimeoutTimer?.cancel();
    _motorTestTimeoutTimer = null;
    _motorTestCompleter = null;
  }

  void _cleanupMotorTest() {
    _cleanupMotorTestAck();
    _motorTestDurationTimer?.cancel();
    _motorTestDurationTimer = null;
    _activeMotorTestInstance = null;
    _activeMotorTestIsAll = false;
  }

  @override
  List<Waypoint> get activeWaypoints => _activeWaypoints;

  @override
  Future<bool> uploadMission(List<Waypoint> waypoints) async {
    _assertCommandSupported('uploadMission');
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
      list.add(
        MissionItemInt(
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
        ),
      );
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

    final frame = _createOutFrame(countMsg);
    final packet = frame.serialize();

    _logDiagnostic("[MISSION TX] count=${_uploadingWaypoints.length}");
    _sendMavlinkPacket(packet);

    _missionUploadTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_missionUploadCompleter != null &&
          !_missionUploadCompleter!.isCompleted) {
        _logDiagnostic("[MISSION TIMEOUT] upload");
        _missionUploadCompleter!.completeError(
          TimeoutException("Mission upload timed out"),
        );
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
    _assertCommandSupported('clearMission');
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
    final frame = _createOutFrame(clearMsg);
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
    _assertCommandSupported('startMission');
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
    _assertCommandSupported('pauseMission');
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      _isMissionActive = false;
      _currentTelemetry = _currentTelemetry.copyWith(
        flightMode: 'LOITER',
        speed: 0.0,
      );
      _telemetryController.add(_currentTelemetry);
      return true;
    }
    return setFlightMode('LOITER');
  }

  @override
  Future<bool> resumeMission() async {
    _assertCommandSupported('resumeMission');
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      if (_activeWaypoints.isNotEmpty) {
        _isMissionActive = true;
        _currentTelemetry = _currentTelemetry.copyWith(
          flightMode: 'AUTO',
          speed: 5.0,
        );
        _telemetryController.add(_currentTelemetry);
        return true;
      }
      return false;
    }
    return setFlightMode('AUTO');
  }

  @override
  Future<bool> returnToLaunch() async {
    _assertCommandSupported('returnToLaunch');
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      _isMissionActive = false;
      _missionTimer?.cancel();
      _currentTelemetry = _currentTelemetry.copyWith(
        flightMode: 'RTL',
        speed: 8.0,
      );
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
    _assertCommandSupported('land');
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }
    if (!_isUsingHardware) {
      _isMissionActive = false;
      _missionTimer?.cancel();
      _currentTelemetry = _currentTelemetry.copyWith(
        flightMode: 'LAND',
        speed: 1.2,
      );
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
          _logDiagnostic(
            "Error sending UDP packet to direct host ${_config.remoteHost}: $e",
          );
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
          _logDiagnostic(
            "Error sending UDP packet to fallback host ${_config.remoteHost}: $e",
          );
        }
      } else {
        // Fallback before any remote packet has arrived (e.g. testing / local loopback)
        try {
          _socket!.send(
            packet,
            InternetAddress.loopbackIPv4,
            _config.localPort,
          );
        } catch (e) {
          _logDiagnostic("Error sending UDP packet: $e");
        }
      }
    }
  }

  MavlinkFrame _createOutFrame(MavlinkMessage message) {
    if (_detectedProtocolVersion.contains('v1')) {
      return MavlinkFrame.v1(
        _sequenceNumber++,
        _config.sourceSystemId,
        _config.sourceComponentId,
        message,
      );
    }
    return MavlinkFrame.v2(
      _sequenceNumber++,
      _config.sourceSystemId,
      _config.sourceComponentId,
      message,
    );
  }

  @override
  void requestDataStreams({int? rateHz}) {
    if (_config.transport == MavlinkTransport.http) return;
    final rate = rateHz ?? _config.telemetryRateHz;
    _logDiagnostic(
      "[DATA STREAMS] Requesting telemetry streams at ${rate}Hz (targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId)",
    );

    // 0: MAV_DATA_STREAM_ALL
    final reqAll = RequestDataStream(
      reqMessageRate: rate,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      reqStreamId: 0,
      startStop: 1,
    );
    _sendMavlinkPacket(_createOutFrame(reqAll).serialize());

    // 6: MAV_DATA_STREAM_POSITION (GLOBAL_POSITION_INT)
    final reqPos = RequestDataStream(
      reqMessageRate: rate,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      reqStreamId: 6,
      startStop: 1,
    );
    _sendMavlinkPacket(_createOutFrame(reqPos).serialize());

    // 2: MAV_DATA_STREAM_EXTENDED_STATUS (SYS_STATUS, GPS_RAW_INT)
    final reqExt = RequestDataStream(
      reqMessageRate: rate > 2 ? 2 : rate,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      reqStreamId: 2,
      startStop: 1,
    );
    _sendMavlinkPacket(_createOutFrame(reqExt).serialize());

    // 10: MAV_DATA_STREAM_EXTRA1 (Attitude)
    final reqAtt = RequestDataStream(
      reqMessageRate: rate,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      reqStreamId: 10,
      startStop: 1,
    );
    _sendMavlinkPacket(_createOutFrame(reqAtt).serialize());

    // 11: MAV_DATA_STREAM_EXTRA2 (VFR_HUD)
    final reqHud = RequestDataStream(
      reqMessageRate: rate,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      reqStreamId: 11,
      startStop: 1,
    );
    _sendMavlinkPacket(_createOutFrame(reqHud).serialize());
  }

  @override
  Future<MotorTestResult> testMotor({
    required int motorInstance,
    required double throttlePercent,
    required int durationSeconds,
    bool testAll = false,
  }) async {
    if (testAll) {
      return testAllMotors(
        throttlePercent: throttlePercent,
        durationSeconds: durationSeconds,
      );
    }

    _assertCommandSupported('testMotor');
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (_currentTelemetry.armed) {
      throw StateError(
        "Safety Block: Drone is armed. Motor test is strictly permitted only when disarmed on the ground.",
      );
    }

    if (throttlePercent < 0.0 || throttlePercent > 100.0) {
      throw ArgumentError.value(
        throttlePercent,
        'throttlePercent',
        'Throttle must be between 0% and 100%.',
      );
    }

    if (durationSeconds < 1 || durationSeconds > 600) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'Duration must be between 1 and 600 seconds (up to 10 minutes).',
      );
    }

    if (motorInstance < 1 || motorInstance > 4) {
      throw ArgumentError.value(
        motorInstance,
        'motorInstance',
        'Motor instance must be between 1 and 4.',
      );
    }

    if (_motorTestCompleter != null) {
      throw StateError("A motor test is already in progress.");
    }

    if (!_isUsingHardware) {
      _activeMotorTestInstance = motorInstance;
      _activeMotorTestIsAll = false;
      _lastMotorTestThrottle = throttlePercent;
      _lastMotorTestDuration = durationSeconds;
      _logDiagnostic(
        "[SIMULATED MOTOR TEST] motor=$motorInstance, throttle=$throttlePercent%, duration=${durationSeconds}s",
      );
      _motorTestDurationTimer?.cancel();
      _motorTestDurationTimer = Timer(Duration(seconds: durationSeconds), () {
        _cleanupMotorTest();
      });
      return MotorTestResult(
        success: true,
        ackResult: 0,
        message:
            "Simulated Motor $motorInstance test accepted for ${durationSeconds}s",
        commandId: 209,
        motorIndex: motorInstance,
        testAll: false,
        throttlePercent: throttlePercent,
        durationSeconds: durationSeconds,
        isSimulated: true,
        timestamp: DateTime.now(),
      );
    }

    _logDiagnostic(
      "[MOTOR_TEST REQUEST] targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId, "
      "motor=$motorInstance, throttle=$throttlePercent%, duration=${durationSeconds}s",
    );

    try {
      final result = await _sendSingleMotorTestPacket(
        motorInstance: motorInstance,
        throttlePercent: throttlePercent,
        durationSeconds: durationSeconds,
        testAll: false,
      );
      if (result.success) {
        _motorTestDurationTimer?.cancel();
        _motorTestDurationTimer = Timer(Duration(seconds: durationSeconds), () {
          _cleanupMotorTest();
        });
      } else {
        _cleanupMotorTest();
      }
      return result;
    } catch (e) {
      _cleanupMotorTest();
      rethrow;
    }
  }

  @override
  Future<MotorTestResult> testAllMotors({
    required double throttlePercent,
    required int durationSeconds,
  }) async {
    _assertCommandSupported('testAllMotors');
    if (_connectionState != DroneConnectionState.connected) {
      throw StateError("MAVLink link is not connected.");
    }

    if (_currentTelemetry.armed) {
      throw StateError(
        "Safety Block: Drone is armed. Motor test is strictly permitted only when disarmed on the ground.",
      );
    }

    if (throttlePercent < 0.0 || throttlePercent > 100.0) {
      throw ArgumentError.value(
        throttlePercent,
        'throttlePercent',
        'Throttle must be between 0% and 100%.',
      );
    }

    if (durationSeconds < 1 || durationSeconds > 600) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'Duration must be between 1 and 600 seconds (up to 10 minutes).',
      );
    }

    if (_motorTestCompleter != null) {
      throw StateError("A motor test is already in progress.");
    }

    _activeMotorTestInstance = 1;
    _activeMotorTestIsAll = true;
    _lastMotorTestThrottle = throttlePercent;
    _lastMotorTestDuration = durationSeconds;

    if (!_isUsingHardware) {
      _logDiagnostic(
        "[SIMULATED MOTOR TEST] ALL MOTORS SIMULTANEOUS, throttle=$throttlePercent%, duration=${durationSeconds}s",
      );
      _motorTestDurationTimer?.cancel();
      _motorTestDurationTimer = Timer(Duration(seconds: durationSeconds), () {
        _cleanupMotorTest();
      });
      return MotorTestResult(
        success: true,
        ackResult: 0,
        message:
            "Simulated simultaneous test of all 4 motors accepted and running for ${durationSeconds}s",
        commandId: 209,
        motorIndex: 1,
        testAll: true,
        throttlePercent: throttlePercent,
        durationSeconds: durationSeconds,
        isSimulated: true,
        timestamp: DateTime.now(),
      );
    }

    _logDiagnostic(
      "[MOTOR_TEST REQUEST] targetSys=$effectiveTargetSystemId, targetComp=$effectiveTargetComponentId, "
      "SIMULTANEOUS ALL MOTORS (1..4), throttle=$throttlePercent%, duration=${durationSeconds}s",
    );

    try {
      // Dispatch MAV_CMD_DO_MOTOR_TEST for each motor (1..4) in rapid succession without inter-motor delays,
      // matching Mission Planner's but_TestAll. In ArduCopter 3.2.1, output_test() sets each channel's PWM
      // without clearing previous channels, resulting in all 4 motors running simultaneously.
      for (int motor = 1; motor <= 4; motor++) {
        final result = await _sendSingleMotorTestPacket(
          motorInstance: motor,
          throttlePercent: throttlePercent,
          durationSeconds: durationSeconds,
          testAll: true,
        );

        if (!result.success) {
          // If any motor command is rejected, stop all motors immediately and report failure
          await stopMotorTest();
          return MotorTestResult(
            success: false,
            ackResult: result.ackResult,
            message:
                "Simultaneous motor test aborted at Motor $motor: ${result.message}",
            commandId: 209,
            motorIndex: motor,
            testAll: true,
            throttlePercent: throttlePercent,
            durationSeconds: durationSeconds,
            isSimulated: false,
            timestamp: DateTime.now(),
          );
        }
      }

      // All 4 motors accepted and active simultaneously
      _motorTestDurationTimer?.cancel();
      _motorTestDurationTimer = Timer(Duration(seconds: durationSeconds), () {
        _cleanupMotorTest();
      });

      return MotorTestResult(
        success: true,
        ackResult: 0,
        message:
            "Simultaneous test of all 4 motors accepted by flight controller",
        commandId: 209,
        motorIndex: 1,
        testAll: true,
        throttlePercent: throttlePercent,
        durationSeconds: durationSeconds,
        isSimulated: false,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      await stopMotorTest();
      rethrow;
    }
  }

  Future<MotorTestResult> _sendSingleMotorTestPacket({
    required int motorInstance,
    required double throttlePercent,
    required int durationSeconds,
    required bool testAll,
  }) {
    _activeMotorTestInstance = motorInstance;
    _activeMotorTestIsAll = testAll;
    _lastMotorTestThrottle = throttlePercent;
    _lastMotorTestDuration = durationSeconds;

    // MAV_CMD_DO_MOTOR_TEST (Command 209)
    // Param 1: Motor instance sequence (1..4)
    // Param 2: Throttle type: 0 = THROTTLE_PERCENT (0..100)
    // Param 3: Throttle value: 0..100
    // Param 4: Timeout in seconds: 1..5
    // Param 5: Motor count: 0 for single motor instance (Param 5 in MAVLink is sequential motor count)
    // Param 6: Test order: 0
    // Param 7: 0.0
    final command = CommandLong(
      command: 209,
      param1: motorInstance.toDouble(),
      param2: 0.0,
      param3: throttlePercent,
      param4: durationSeconds.toDouble(),
      param5: testAll ? 0.0 : 1.0,
      param6: 0.0,
      param7: 0.0,
      targetSystem: effectiveTargetSystemId,
      targetComponent: effectiveTargetComponentId,
      confirmation: 0,
    );

    final frame = _createOutFrame(command);
    final packet = frame.serialize();

    _motorTestCompleter = Completer<MotorTestResult>();

    _logDiagnostic(
      "[MOTOR_TEST TX] command=209, p1=${command.param1}, p2=0, p3=$throttlePercent, p4=$durationSeconds, p5=${command.param5}",
    );
    _sendMavlinkPacket(packet);

    _motorTestTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (_motorTestCompleter != null && !_motorTestCompleter!.isCompleted) {
        _logDiagnostic(
          "[MOTOR_TEST TIMEOUT] Autopilot did not return COMMAND_ACK for command 209 (motor $motorInstance) within 3s",
        );
        _motorTestCompleter!.complete(
          MotorTestResult(
            success: false,
            ackResult: null,
            message:
                "Autopilot did not acknowledge MAV_CMD_DO_MOTOR_TEST (timeout after 3s). Check telemetry link and APM firmware.",
            commandId: 209,
            motorIndex: motorInstance,
            testAll: testAll,
            throttlePercent: throttlePercent,
            durationSeconds: durationSeconds,
            isSimulated: false,
            timestamp: DateTime.now(),
          ),
        );
      }
      _cleanupMotorTestAck();
    });

    return _motorTestCompleter!.future;
  }

  @override
  Future<MotorTestResult> stopMotorTest() async {
    _assertCommandSupported('stopMotorTest');
    _logDiagnostic(
      "[MOTOR_TEST STOP] Sending immediate stop (throttle=0, duration=0)",
    );

    _cleanupMotorTest();

    if (!_isUsingHardware) {
      return MotorTestResult(
        success: true,
        ackResult: 0,
        message: "Motor test stopped (throttle cut to 0%)",
        commandId: 209,
        motorIndex: 1,
        throttlePercent: 0.0,
        durationSeconds: 0,
        isSimulated: true,
        timestamp: DateTime.now(),
      );
    }

    if (_connectionState != DroneConnectionState.connected) {
      return MotorTestResult(
        success: false,
        ackResult: null,
        message: "Cannot stop motor test: MAVLink link is disconnected",
        commandId: 209,
        motorIndex: 1,
        throttlePercent: 0.0,
        durationSeconds: 0,
        isSimulated: false,
        timestamp: DateTime.now(),
      );
    }

    // In ArduPilot, sending MAV_CMD_DO_MOTOR_TEST with throttle = 0 (and duration = 0)
    // calls motor_test_stop(), which halts output immediately.
    final command = CommandLong(
      command: 209,
      param1: 1.0,
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

    final frame = _createOutFrame(command);
    final packet = frame.serialize();

    _sendMavlinkPacket(packet);

    return MotorTestResult(
      success: true,
      ackResult: 0,
      message: "Emergency stop packet sent to autopilot (throttle cut to 0%)",
      commandId: 209,
      motorIndex: 1,
      throttlePercent: 0.0,
      durationSeconds: 0,
      isSimulated: false,
      timestamp: DateTime.now(),
    );
  }
}
