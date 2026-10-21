import 'dart:typed_data';

enum CameraStatus { disconnected, connecting, connected, reconnecting, error }

enum CameraErrorCategory {
  none,
  invalidUrl,
  networkUnreachable,
  connectionRefused,
  timeout,
  httpError,
  cleartextTrafficBlocked,
  invalidMimeType,
  frameDecodeError,
  streamSevered,
  unknown,
}

class CameraStreamState {
  final CameraStatus status;
  final CameraErrorCategory errorCategory;
  final String? errorMessage;
  final String? diagnosticDetails;
  final String connectedUrl;
  final double fps;
  final int latencyMs;
  final int totalFramesReceived;
  final int totalBytesReceived;
  final DateTime? lastFrameTime;
  final int retryAttempt;
  final int maxRetries;
  final int imageWidth;
  final int imageHeight;

  const CameraStreamState({
    required this.status,
    this.errorCategory = CameraErrorCategory.none,
    this.errorMessage,
    this.diagnosticDetails,
    this.connectedUrl = '',
    this.fps = 0.0,
    this.latencyMs = 0,
    this.totalFramesReceived = 0,
    this.totalBytesReceived = 0,
    this.lastFrameTime,
    this.retryAttempt = 0,
    this.maxRetries = 5,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  factory CameraStreamState.initial() {
    return const CameraStreamState(status: CameraStatus.disconnected);
  }

  bool get isConnected => status == CameraStatus.connected;
  bool get isConnecting => status == CameraStatus.connecting;
  bool get isReconnecting => status == CameraStatus.reconnecting;
  bool get hasError => status == CameraStatus.error;

  String get statusDisplay {
    switch (status) {
      case CameraStatus.disconnected:
        return 'DISCONNECTED';
      case CameraStatus.connecting:
        return 'CONNECTING...';
      case CameraStatus.connected:
        return 'LIVE STREAM';
      case CameraStatus.reconnecting:
        return 'RECONNECTING ($retryAttempt/$maxRetries)';
      case CameraStatus.error:
        return 'STREAM ERROR';
    }
  }

  CameraStreamState copyWith({
    CameraStatus? status,
    CameraErrorCategory? errorCategory,
    String? errorMessage,
    String? diagnosticDetails,
    String? connectedUrl,
    double? fps,
    int? latencyMs,
    int? totalFramesReceived,
    int? totalBytesReceived,
    DateTime? lastFrameTime,
    int? retryAttempt,
    int? maxRetries,
    int? imageWidth,
    int? imageHeight,
  }) {
    return CameraStreamState(
      status: status ?? this.status,
      errorCategory: errorCategory ?? this.errorCategory,
      errorMessage: errorMessage ?? this.errorMessage,
      diagnosticDetails: diagnosticDetails ?? this.diagnosticDetails,
      connectedUrl: connectedUrl ?? this.connectedUrl,
      fps: fps ?? this.fps,
      latencyMs: latencyMs ?? this.latencyMs,
      totalFramesReceived: totalFramesReceived ?? this.totalFramesReceived,
      totalBytesReceived: totalBytesReceived ?? this.totalBytesReceived,
      lastFrameTime: lastFrameTime ?? this.lastFrameTime,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      maxRetries: maxRetries ?? this.maxRetries,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
    );
  }
}
