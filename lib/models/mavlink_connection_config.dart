enum MavlinkTransport { udp, http }

enum MavlinkConnectionMode {
  listener, // Binds on 0.0.0.0:<localPort> and receives from MAVProxy/SITL/Radio
  direct, // Sends directly to <remoteHost>:<remotePort>
}

class MavlinkConnectionConfig {
  final MavlinkTransport transport;
  final MavlinkConnectionMode connectionMode;
  final String bindAddress;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final int sourceSystemId;
  final int sourceComponentId;
  final int targetSystemId;
  final int targetComponentId;
  final bool autoTargetSystem;
  final bool autoTargetComponent;
  final int heartbeatTimeoutSeconds;
  final int telemetryTimeoutSeconds;
  final int reconnectIntervalSeconds;
  final int telemetryRateHz;
  final bool debugLogging;

  // Raspberry Pi Flask HTTP Telemetry fields
  final String httpBaseUrl;
  final int httpPollingIntervalMs;
  final int httpTimeoutSeconds;

  const MavlinkConnectionConfig({
    this.transport = MavlinkTransport.udp,
    this.connectionMode = MavlinkConnectionMode.listener,
    this.bindAddress = '0.0.0.0',
    this.localPort = 14550,
    this.remoteHost = '',
    this.remotePort = 14550,
    this.sourceSystemId = 255,
    this.sourceComponentId = 190,
    this.targetSystemId = 1,
    this.targetComponentId = 1,
    this.autoTargetSystem = true,
    this.autoTargetComponent = true,
    this.heartbeatTimeoutSeconds = 3,
    this.telemetryTimeoutSeconds = 5,
    this.reconnectIntervalSeconds = 3,
    this.telemetryRateHz = 10,
    this.debugLogging = true,
    this.httpBaseUrl = 'http://10.174.17.87:8081',
    this.httpPollingIntervalMs = 1000,
    this.httpTimeoutSeconds = 3,
  });

  factory MavlinkConnectionConfig.defaultConfig() {
    return const MavlinkConnectionConfig();
  }

  MavlinkConnectionConfig copyWith({
    MavlinkTransport? transport,
    MavlinkConnectionMode? connectionMode,
    String? bindAddress,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    int? sourceSystemId,
    int? sourceComponentId,
    int? targetSystemId,
    int? targetComponentId,
    bool? autoTargetSystem,
    bool? autoTargetComponent,
    int? heartbeatTimeoutSeconds,
    int? telemetryTimeoutSeconds,
    int? reconnectIntervalSeconds,
    int? telemetryRateHz,
    bool? debugLogging,
    String? httpBaseUrl,
    int? httpPollingIntervalMs,
    int? httpTimeoutSeconds,
  }) {
    return MavlinkConnectionConfig(
      transport: transport ?? this.transport,
      connectionMode: connectionMode ?? this.connectionMode,
      bindAddress: bindAddress ?? this.bindAddress,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      sourceSystemId: sourceSystemId ?? this.sourceSystemId,
      sourceComponentId: sourceComponentId ?? this.sourceComponentId,
      targetSystemId: targetSystemId ?? this.targetSystemId,
      targetComponentId: targetComponentId ?? this.targetComponentId,
      autoTargetSystem: autoTargetSystem ?? this.autoTargetSystem,
      autoTargetComponent: autoTargetComponent ?? this.autoTargetComponent,
      heartbeatTimeoutSeconds:
          heartbeatTimeoutSeconds ?? this.heartbeatTimeoutSeconds,
      telemetryTimeoutSeconds:
          telemetryTimeoutSeconds ?? this.telemetryTimeoutSeconds,
      reconnectIntervalSeconds:
          reconnectIntervalSeconds ?? this.reconnectIntervalSeconds,
      telemetryRateHz: telemetryRateHz ?? this.telemetryRateHz,
      debugLogging: debugLogging ?? this.debugLogging,
      httpBaseUrl: httpBaseUrl ?? this.httpBaseUrl,
      httpPollingIntervalMs:
          httpPollingIntervalMs ?? this.httpPollingIntervalMs,
      httpTimeoutSeconds: httpTimeoutSeconds ?? this.httpTimeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transport': transport.name,
      'connectionMode': connectionMode.name,
      'bindAddress': bindAddress,
      'localPort': localPort,
      'remoteHost': remoteHost,
      'remotePort': remotePort,
      'sourceSystemId': sourceSystemId,
      'sourceComponentId': sourceComponentId,
      'targetSystemId': targetSystemId,
      'targetComponentId': targetComponentId,
      'autoTargetSystem': autoTargetSystem,
      'autoTargetComponent': autoTargetComponent,
      'heartbeatTimeoutSeconds': heartbeatTimeoutSeconds,
      'telemetryTimeoutSeconds': telemetryTimeoutSeconds,
      'reconnectIntervalSeconds': reconnectIntervalSeconds,
      'telemetryRateHz': telemetryRateHz,
      'debugLogging': debugLogging,
      'httpBaseUrl': httpBaseUrl,
      'httpPollingIntervalMs': httpPollingIntervalMs,
      'httpTimeoutSeconds': httpTimeoutSeconds,
    };
  }

  factory MavlinkConnectionConfig.fromJson(Map<String, dynamic> json) {
    return MavlinkConnectionConfig(
      transport: MavlinkTransport.values.firstWhere(
        (e) => e.name == json['transport'],
        orElse: () => MavlinkTransport.udp,
      ),
      connectionMode: MavlinkConnectionMode.values.firstWhere(
        (e) => e.name == json['connectionMode'],
        orElse: () => MavlinkConnectionMode.listener,
      ),
      bindAddress: json['bindAddress'] as String? ?? '0.0.0.0',
      localPort: json['localPort'] as int? ?? 14550,
      remoteHost: json['remoteHost'] as String? ?? '',
      remotePort: json['remotePort'] as int? ?? 14550,
      sourceSystemId: json['sourceSystemId'] as int? ?? 255,
      sourceComponentId: json['sourceComponentId'] as int? ?? 190,
      targetSystemId: json['targetSystemId'] as int? ?? 1,
      targetComponentId: json['targetComponentId'] as int? ?? 1,
      autoTargetSystem: json['autoTargetSystem'] as bool? ?? true,
      autoTargetComponent: json['autoTargetComponent'] as bool? ?? true,
      heartbeatTimeoutSeconds: json['heartbeatTimeoutSeconds'] as int? ?? 3,
      telemetryTimeoutSeconds: json['telemetryTimeoutSeconds'] as int? ?? 5,
      reconnectIntervalSeconds: json['reconnectIntervalSeconds'] as int? ?? 3,
      telemetryRateHz: json['telemetryRateHz'] as int? ?? 10,
      debugLogging: json['debugLogging'] as bool? ?? true,
      httpBaseUrl:
          json['httpBaseUrl'] as String? ?? 'http://10.174.17.87:8081',
      httpPollingIntervalMs: json['httpPollingIntervalMs'] as int? ?? 1000,
      httpTimeoutSeconds: json['httpTimeoutSeconds'] as int? ?? 3,
    );
  }

  /// Validates configuration parameters and returns list of validation error messages (empty if valid).
  List<String> validate() {
    final errors = <String>[];

    if (transport == MavlinkTransport.http) {
      final trimmedUrl = httpBaseUrl.trim();
      if (trimmedUrl.isEmpty) {
        errors.add('Raspberry Pi HTTP Base URL is required');
      } else {
        final uri = Uri.tryParse(trimmedUrl);
        if (uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          errors.add('Invalid HTTP Base URL (must start with http:// or https://)');
        }
      }
      if (httpPollingIntervalMs < 200 || httpPollingIntervalMs > 10000) {
        errors.add('HTTP polling interval must be between 200ms and 10000ms');
      }
      if (httpTimeoutSeconds <= 0 || httpTimeoutSeconds > 30) {
        errors.add('HTTP request timeout must be between 1 and 30 seconds');
      }
      return errors;
    }

    // UDP Validation
    if (localPort < 1 || localPort > 65535) {
      errors.add('Local UDP Port must be between 1 and 65535');
    }

    if (connectionMode == MavlinkConnectionMode.direct) {
      if (remoteHost.trim().isEmpty) {
        errors.add('Remote Host IP is required in Direct UDP mode');
      }
      if (remotePort < 1 || remotePort > 65535) {
        errors.add('Remote UDP Port must be between 1 and 65535');
      }
    } else {
      if (remotePort < 1 || remotePort > 65535) {
        errors.add('Remote UDP Port must be between 1 and 65535');
      }
    }

    if (sourceSystemId < 1 || sourceSystemId > 255) {
      errors.add('Source System ID must be between 1 and 255');
    }

    if (sourceComponentId < 1 || sourceComponentId > 255) {
      errors.add('Source Component ID must be between 1 and 255');
    }

    if (!autoTargetSystem && (targetSystemId < 1 || targetSystemId > 255)) {
      errors.add('Target System ID must be between 1 and 255 when manual');
    }

    if (!autoTargetComponent &&
        (targetComponentId < 1 || targetComponentId > 255)) {
      errors.add('Target Component ID must be between 1 and 255 when manual');
    }

    if (heartbeatTimeoutSeconds <= 0) {
      errors.add('Heartbeat timeout must be greater than 0 seconds');
    }

    if (telemetryTimeoutSeconds <= 0) {
      errors.add('Telemetry timeout must be greater than 0 seconds');
    }

    if (reconnectIntervalSeconds <= 0) {
      errors.add('Reconnect interval must be greater than 0 seconds');
    }

    if (telemetryRateHz <= 0 || telemetryRateHz > 100) {
      errors.add('Telemetry rate must be between 1 and 100 Hz');
    }

    return errors;
  }
}
