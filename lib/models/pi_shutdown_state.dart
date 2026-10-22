enum PiPowerStatus {
  unknown,
  checking,
  online,
  shuttingDown,
  shutdownComplete,
  offline,
  error,
}

class PiShutdownState {
  final PiPowerStatus status;
  final String hostname;
  final double? uptimeSeconds;
  final String? message;
  final String? errorMessage;
  final DateTime? lastChecked;

  const PiShutdownState({
    this.status = PiPowerStatus.unknown,
    this.hostname = 'aerialeye',
    this.uptimeSeconds,
    this.message,
    this.errorMessage,
    this.lastChecked,
  });

  factory PiShutdownState.initial() => const PiShutdownState();

  bool get isOnline => status == PiPowerStatus.online;
  bool get isChecking => status == PiPowerStatus.checking;
  bool get isShuttingDown => status == PiPowerStatus.shuttingDown;
  bool get isShutdownComplete => status == PiPowerStatus.shutdownComplete;
  bool get isOffline =>
      status == PiPowerStatus.offline ||
      status == PiPowerStatus.shutdownComplete;

  String get statusDisplay {
    switch (status) {
      case PiPowerStatus.unknown:
        return 'Status Unknown';
      case PiPowerStatus.checking:
        return 'Checking Status...';
      case PiPowerStatus.online:
        return 'Online (Ready)';
      case PiPowerStatus.shuttingDown:
        return 'Shutting Down...';
      case PiPowerStatus.shutdownComplete:
        return 'Powered Off (Offline)';
      case PiPowerStatus.offline:
        return 'Offline (Unreachable)';
      case PiPowerStatus.error:
        return 'Connection Error';
    }
  }

  PiShutdownState copyWith({
    PiPowerStatus? status,
    String? hostname,
    double? uptimeSeconds,
    String? message,
    String? errorMessage,
    DateTime? lastChecked,
    bool clearError = false,
  }) {
    return PiShutdownState(
      status: status ?? this.status,
      hostname: hostname ?? this.hostname,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
      message: message ?? this.message,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

class PiShutdownResult {
  final bool success;
  final bool isBlockedByFlight;
  final String message;
  final int? statusCode;

  const PiShutdownResult({
    required this.success,
    this.isBlockedByFlight = false,
    required this.message,
    this.statusCode,
  });

  factory PiShutdownResult.success(String message, [int code = 200]) {
    return PiShutdownResult(success: true, message: message, statusCode: code);
  }

  factory PiShutdownResult.blocked(String reason) {
    return PiShutdownResult(
      success: false,
      isBlockedByFlight: true,
      message: reason,
    );
  }

  factory PiShutdownResult.failure(String error, [int? code]) {
    return PiShutdownResult(
      success: false,
      isBlockedByFlight: false,
      message: error,
      statusCode: code,
    );
  }
}
