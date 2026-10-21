import 'package:aerial_eye/services/drone_service.dart';

enum LinkHealth { live, stale, notAvailable, error }

class ConnectionDiagnostics {
  final DroneConnectionState connectionState;
  final String socketStatus; // 'BOUND', 'CLOSED', 'ERROR', 'CONNECTING'
  final String localAddress;
  final int localPort;
  final String? configuredRemoteHost;
  final int? configuredRemotePort;
  final String? remoteAddress; // actual discovered sender IP:port
  final int? discoveredSystemId;
  final int? discoveredComponentId;
  final int sourceSystemId;
  final int sourceComponentId;
  final int commandTargetSystemId;
  final int commandTargetComponentId;
  final String
  mavlinkProtocolVersion; // 'MAVLink v2 (0xFD)', 'MAVLink v1 (0xFE)', 'None'
  final int? lastReceivedSourceSystemId;
  final int? lastReceivedSourceComponentId;
  final String? lastReceivedMessageType;
  final String vehicleType; // e.g. 'ArduCopter', 'Plane', 'Unknown'
  final String autopilotType; // e.g. 'ArduPilot', 'PX4', 'Unknown'
  final String flightMode;
  final bool armed;
  final LinkHealth heartbeatHealth;
  final int? lastRawDatagramSize;
  final String? lastRawDatagramPreview;
  final String? lastRawSender;
  final DateTime? lastHeartbeatTime;
  final int heartbeatCount;
  final LinkHealth telemetryHealth;
  final DateTime? lastTelemetryTime;
  final int rawDatagramsReceived;
  final int mavlinkFramesReceived;
  final int malformedFramesCount;
  final int packetsReceived; // Alias for total frames
  final double packetsPerSecond;
  final int packetsDropped;
  final DateTime? lastDatagramTime;
  final DateTime? lastPacketTime;
  final int? satellites;
  final double? batteryVoltage;
  final String? lastStatusText;
  final DateTime? lastGlobalPositionTime;
  final DateTime? lastGpsRawTime;
  final DateTime? lastAttitudeTime;
  final DateTime? lastVfrHudTime;
  final DateTime? lastBatteryTime;
  final List<String> recentLogs;

  const ConnectionDiagnostics({
    this.connectionState = DroneConnectionState.disconnected,
    this.socketStatus = 'CLOSED',
    this.localAddress = '0.0.0.0',
    this.localPort = 14550,
    this.configuredRemoteHost,
    this.configuredRemotePort,
    this.remoteAddress,
    this.discoveredSystemId,
    this.discoveredComponentId,
    this.sourceSystemId = 255,
    this.sourceComponentId = 190,
    this.commandTargetSystemId = 1,
    this.commandTargetComponentId = 1,
    this.mavlinkProtocolVersion = 'None',
    this.lastReceivedSourceSystemId,
    this.lastReceivedSourceComponentId,
    this.lastReceivedMessageType,
    this.vehicleType = 'Unknown',
    this.autopilotType = 'Unknown',
    this.flightMode = 'DISCONNECTED',
    this.armed = false,
    this.lastRawDatagramSize,
    this.lastRawDatagramPreview,
    this.lastRawSender,
    this.heartbeatHealth = LinkHealth.notAvailable,
    this.lastHeartbeatTime,
    this.heartbeatCount = 0,
    this.telemetryHealth = LinkHealth.notAvailable,
    this.lastTelemetryTime,
    this.rawDatagramsReceived = 0,
    this.mavlinkFramesReceived = 0,
    this.malformedFramesCount = 0,
    this.packetsReceived = 0,
    this.packetsPerSecond = 0.0,
    this.packetsDropped = 0,
    this.lastDatagramTime,
    this.lastPacketTime,
    this.satellites,
    this.batteryVoltage,
    this.lastStatusText,
    this.lastGlobalPositionTime,
    this.lastGpsRawTime,
    this.lastAttitudeTime,
    this.lastVfrHudTime,
    this.lastBatteryTime,
    this.recentLogs = const [],
  });

  factory ConnectionDiagnostics.initial() {
    return const ConnectionDiagnostics();
  }

  String get connectionStateLabel {
    switch (connectionState) {
      case DroneConnectionState.socketNotBound:
      case DroneConnectionState.disconnected:
        return 'Socket Not Bound / Disconnected';
      case DroneConnectionState.socketBoundWaiting:
      case DroneConnectionState.listening:
        return 'Socket Bound / Waiting for Packets';
      case DroneConnectionState.udpPacketsNoMavlink:
        return 'UDP Packets Received (No MAVLink)';
      case DroneConnectionState.mavlinkNoHeartbeat:
        return 'MAVLink Packets Received (No Heartbeat)';
      case DroneConnectionState.connected:
        return 'Heartbeat Received / Connected';
      case DroneConnectionState.telemetryStale:
      case DroneConnectionState.connectionLost:
      case DroneConnectionState.stale:
        return 'Telemetry Stale / Link Lost';
      case DroneConnectionState.connecting:
        return 'Connecting / Binding';
      case DroneConnectionState.degraded:
        return 'Degraded Link';
      case DroneConnectionState.reconnecting:
        return 'Reconnecting';
      case DroneConnectionState.error:
        return 'Socket / Network Error';
    }
  }

  String get rootCauseDiagnosis {
    if (socketStatus != 'BOUND') {
      return 'A: UDP Socket is not bound. Check port permissions or port conflicts.';
    }
    if (rawDatagramsReceived == 0) {
      return 'B/C: No UDP datagrams received. Check MAVProxy forwarding (udp:<PHONE_IP>:$localPort) and Wi-Fi connection.';
    }
    if (mavlinkFramesReceived == 0) {
      return 'D: UDP datagrams arriving ($rawDatagramsReceived pkts), but no valid MAVLink frames found. Check MAVLink baudrate/protocol version in MAVProxy.';
    }
    if (heartbeatCount == 0) {
      return 'E: MAVLink packets received ($mavlinkFramesReceived frames), but no valid Heartbeat detected. Check autopilot stream rate.';
    }
    if (heartbeatHealth == LinkHealth.stale) {
      return 'E: Heartbeat stopped arriving. Check if SITL / drone is still transmitting.';
    }
    return 'ALL CHECKS PASSED: Live bidirectional MAVLink link established.';
  }

  String toClipboardReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== AerialEye MAVLink Network Diagnostics ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Overall State: $connectionStateLabel');
    buffer.writeln('Diagnosis: $rootCauseDiagnosis');
    buffer.writeln('');
    buffer.writeln('--- Socket & Endpoints ---');
    buffer.writeln('Socket Status: $socketStatus');
    buffer.writeln('Local Endpoint: $localAddress:$localPort');
    if (configuredRemoteHost != null && configuredRemoteHost!.isNotEmpty) {
      buffer.writeln(
        'Configured Remote: $configuredRemoteHost:$configuredRemotePort',
      );
    }
    buffer.writeln('Discovered Remote Sender: ${remoteAddress ?? "None"}');
    buffer.writeln('');
    buffer.writeln('--- Packet & Framing Metrics ---');
    buffer.writeln('Raw UDP Datagrams: $rawDatagramsReceived');
    buffer.writeln('Valid MAVLink Frames: $mavlinkFramesReceived');
    buffer.writeln('Malformed / Non-MAVLink: $malformedFramesCount');
    buffer.writeln('Packets / Sec: ${packetsPerSecond.toStringAsFixed(1)} PPS');
    buffer.writeln(
      'Last Datagram: ${lastDatagramTime?.toIso8601String() ?? "Never"}',
    );
    if (lastRawSender != null) {
      buffer.writeln(
        'Last Datagram Sender: $lastRawSender (${lastRawDatagramSize ?? 0} bytes)',
      );
    }
    if (lastRawDatagramPreview != null && lastRawDatagramPreview!.isNotEmpty) {
      buffer.writeln('Last Raw Payload (ASCII): "$lastRawDatagramPreview"');
    }
    buffer.writeln(
      'Last Valid Frame: ${lastMavlinkFrameTime?.toIso8601String() ?? "Never"}',
    );
    buffer.writeln('Detected Protocol: $mavlinkProtocolVersion');
    buffer.writeln('');
    buffer.writeln('--- MAVLink Addressing & Identity ---');
    buffer.writeln(
      'GCS Source ID: Sys=$sourceSystemId, Comp=$sourceComponentId',
    );
    buffer.writeln(
      'Discovered Vehicle ID: Sys=${discoveredSystemId ?? "None"}, Comp=${discoveredComponentId ?? "None"}',
    );
    buffer.writeln(
      'Command Target ID: Sys=$commandTargetSystemId, Comp=$commandTargetComponentId',
    );
    buffer.writeln(
      'Last Received Msg: ${lastReceivedMessageType ?? "None"} (from Sys=${lastReceivedSourceSystemId ?? "?"}, Comp=${lastReceivedSourceComponentId ?? "?"})',
    );
    buffer.writeln('Vehicle Type: $vehicleType');
    buffer.writeln('Autopilot Type: $autopilotType');
    buffer.writeln('');
    buffer.writeln('--- Link Health ---');
    buffer.writeln(
      'Heartbeat Status: ${heartbeatHealth.name.toUpperCase()} (Total: $heartbeatCount, Last: ${lastHeartbeatTime?.toIso8601String() ?? "Never"})',
    );
    buffer.writeln(
      'Telemetry Status: ${telemetryHealth.name.toUpperCase()} (Last: ${lastTelemetryTime?.toIso8601String() ?? "Never"})',
    );
    buffer.writeln('Flight Mode: $flightMode | Armed: $armed');
    buffer.writeln(
      'Satellites: ${satellites ?? "N/A"} | Battery: ${batteryVoltage != null ? "${batteryVoltage}V" : "N/A"}',
    );
    if (lastStatusText != null && lastStatusText!.isNotEmpty) {
      buffer.writeln('Last Autopilot STATUSTEXT: $lastStatusText');
    }
    buffer.writeln('');
    buffer.writeln('--- Recent Diagnostic Events ---');
    if (recentLogs.isEmpty) {
      buffer.writeln('  (No diagnostic events recorded yet)');
    } else {
      for (final log in recentLogs) {
        buffer.writeln('  $log');
      }
    }
    buffer.writeln('=============================================');
    return buffer.toString();
  }

  DateTime? get lastMavlinkFrameTime => lastPacketTime;

  ConnectionDiagnostics copyWith({
    DroneConnectionState? connectionState,
    String? socketStatus,
    String? localAddress,
    int? localPort,
    String? configuredRemoteHost,
    int? configuredRemotePort,
    String? remoteAddress,
    int? discoveredSystemId,
    int? discoveredComponentId,
    int? sourceSystemId,
    int? sourceComponentId,
    int? commandTargetSystemId,
    int? commandTargetComponentId,
    String? mavlinkProtocolVersion,
    int? lastReceivedSourceSystemId,
    int? lastReceivedSourceComponentId,
    String? lastReceivedMessageType,
    String? vehicleType,
    String? autopilotType,
    String? flightMode,
    bool? armed,
    int? lastRawDatagramSize,
    String? lastRawDatagramPreview,
    String? lastRawSender,
    LinkHealth? heartbeatHealth,
    DateTime? lastHeartbeatTime,
    int? heartbeatCount,
    LinkHealth? telemetryHealth,
    DateTime? lastTelemetryTime,
    int? rawDatagramsReceived,
    int? mavlinkFramesReceived,
    int? malformedFramesCount,
    int? packetsReceived,
    double? packetsPerSecond,
    int? packetsDropped,
    DateTime? lastDatagramTime,
    DateTime? lastPacketTime,
    int? satellites,
    double? batteryVoltage,
    String? lastStatusText,
    DateTime? lastGlobalPositionTime,
    DateTime? lastGpsRawTime,
    DateTime? lastAttitudeTime,
    DateTime? lastVfrHudTime,
    DateTime? lastBatteryTime,
    List<String>? recentLogs,
  }) {
    return ConnectionDiagnostics(
      connectionState: connectionState ?? this.connectionState,
      socketStatus: socketStatus ?? this.socketStatus,
      localAddress: localAddress ?? this.localAddress,
      localPort: localPort ?? this.localPort,
      configuredRemoteHost: configuredRemoteHost ?? this.configuredRemoteHost,
      configuredRemotePort: configuredRemotePort ?? this.configuredRemotePort,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      discoveredSystemId: discoveredSystemId ?? this.discoveredSystemId,
      discoveredComponentId:
          discoveredComponentId ?? this.discoveredComponentId,
      sourceSystemId: sourceSystemId ?? this.sourceSystemId,
      sourceComponentId: sourceComponentId ?? this.sourceComponentId,
      commandTargetSystemId:
          commandTargetSystemId ?? this.commandTargetSystemId,
      commandTargetComponentId:
          commandTargetComponentId ?? this.commandTargetComponentId,
      mavlinkProtocolVersion:
          mavlinkProtocolVersion ?? this.mavlinkProtocolVersion,
      lastReceivedSourceSystemId:
          lastReceivedSourceSystemId ?? this.lastReceivedSourceSystemId,
      lastReceivedSourceComponentId:
          lastReceivedSourceComponentId ?? this.lastReceivedSourceComponentId,
      lastReceivedMessageType:
          lastReceivedMessageType ?? this.lastReceivedMessageType,
      vehicleType: vehicleType ?? this.vehicleType,
      autopilotType: autopilotType ?? this.autopilotType,
      flightMode: flightMode ?? this.flightMode,
      armed: armed ?? this.armed,
      lastRawDatagramSize: lastRawDatagramSize ?? this.lastRawDatagramSize,
      lastRawDatagramPreview:
          lastRawDatagramPreview ?? this.lastRawDatagramPreview,
      lastRawSender: lastRawSender ?? this.lastRawSender,
      heartbeatHealth: heartbeatHealth ?? this.heartbeatHealth,
      lastHeartbeatTime: lastHeartbeatTime ?? this.lastHeartbeatTime,
      heartbeatCount: heartbeatCount ?? this.heartbeatCount,
      telemetryHealth: telemetryHealth ?? this.telemetryHealth,
      lastTelemetryTime: lastTelemetryTime ?? this.lastTelemetryTime,
      rawDatagramsReceived: rawDatagramsReceived ?? this.rawDatagramsReceived,
      mavlinkFramesReceived:
          mavlinkFramesReceived ?? this.mavlinkFramesReceived,
      malformedFramesCount: malformedFramesCount ?? this.malformedFramesCount,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      packetsPerSecond: packetsPerSecond ?? this.packetsPerSecond,
      packetsDropped: packetsDropped ?? this.packetsDropped,
      lastDatagramTime: lastDatagramTime ?? this.lastDatagramTime,
      lastPacketTime: lastPacketTime ?? this.lastPacketTime,
      satellites: satellites ?? this.satellites,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      lastStatusText: lastStatusText ?? this.lastStatusText,
      lastGlobalPositionTime:
          lastGlobalPositionTime ?? this.lastGlobalPositionTime,
      lastGpsRawTime: lastGpsRawTime ?? this.lastGpsRawTime,
      lastAttitudeTime: lastAttitudeTime ?? this.lastAttitudeTime,
      lastVfrHudTime: lastVfrHudTime ?? this.lastVfrHudTime,
      lastBatteryTime: lastBatteryTime ?? this.lastBatteryTime,
      recentLogs: recentLogs ?? this.recentLogs,
    );
  }
}
