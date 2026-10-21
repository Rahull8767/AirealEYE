import 'dart:core';

class UrlValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? normalizedUrl;
  final String? host;
  final int? port;

  const UrlValidationResult({
    required this.isValid,
    this.errorMessage,
    this.normalizedUrl,
    this.host,
    this.port,
  });

  factory UrlValidationResult.valid({
    required String normalizedUrl,
    required String host,
    required int port,
  }) {
    return UrlValidationResult(
      isValid: true,
      normalizedUrl: normalizedUrl,
      host: host,
      port: port,
    );
  }

  factory UrlValidationResult.invalid(String message) {
    return UrlValidationResult(isValid: false, errorMessage: message);
  }
}

class CameraConnectionConfig {
  final String baseUrl;
  final int connectionTimeoutSeconds;
  final int reconnectIntervalSeconds;
  final bool autoReconnect;
  final int maxRetries;
  final bool autoConnect;

  const CameraConnectionConfig({
    this.baseUrl = 'http://10.174.17.87:8080',
    this.connectionTimeoutSeconds = 5,
    this.reconnectIntervalSeconds = 3,
    this.autoReconnect = true,
    this.maxRetries = 5,
    this.autoConnect = false,
  });

  factory CameraConnectionConfig.defaultConfig() {
    return const CameraConnectionConfig();
  }

  String get host {
    try {
      final uri = Uri.parse(baseUrl);
      return uri.host;
    } catch (_) {
      return '10.174.17.87';
    }
  }

  int get port {
    try {
      final uri = Uri.parse(baseUrl);
      return uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    } catch (_) {
      return 8080;
    }
  }

  String get path {
    try {
      final uri = Uri.parse(baseUrl);
      return uri.path;
    } catch (_) {
      return '';
    }
  }

  CameraConnectionConfig copyWith({
    String? baseUrl,
    int? connectionTimeoutSeconds,
    int? reconnectIntervalSeconds,
    bool? autoReconnect,
    int? maxRetries,
    bool? autoConnect,
  }) {
    return CameraConnectionConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      reconnectIntervalSeconds:
          reconnectIntervalSeconds ?? this.reconnectIntervalSeconds,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      maxRetries: maxRetries ?? this.maxRetries,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'reconnectIntervalSeconds': reconnectIntervalSeconds,
      'autoReconnect': autoReconnect,
      'maxRetries': maxRetries,
      'autoConnect': autoConnect,
    };
  }

  factory CameraConnectionConfig.fromJson(Map<String, dynamic> json) {
    return CameraConnectionConfig(
      baseUrl: json['baseUrl'] as String? ?? 'http://10.174.17.87:8080',
      connectionTimeoutSeconds: json['connectionTimeoutSeconds'] as int? ?? 5,
      reconnectIntervalSeconds: json['reconnectIntervalSeconds'] as int? ?? 3,
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      maxRetries: json['maxRetries'] as int? ?? 5,
      autoConnect: json['autoConnect'] as bool? ?? false,
    );
  }

  static UrlValidationResult validateUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return UrlValidationResult.invalid('URL cannot be empty.');
    }

    String toParse = trimmed;
    if (!toParse.contains('://')) {
      // Allow bare IP:port by prepending http://
      toParse = 'http://$toParse';
    }

    Uri uri;
    try {
      uri = Uri.parse(toParse);
    } catch (e) {
      return UrlValidationResult.invalid('Malformed URL: ${e.toString()}');
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return UrlValidationResult.invalid(
        'Unsupported scheme "${uri.scheme}". Only http:// and https:// are supported.',
      );
    }

    if (uri.host.isEmpty) {
      return UrlValidationResult.invalid('Host IP or domain is missing.');
    }

    // Validate IPv4 or hostname format
    final ipV4Regex = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final match = ipV4Regex.firstMatch(uri.host);
    if (match != null) {
      for (int i = 1; i <= 4; i++) {
        final octet = int.tryParse(match.group(i)!);
        if (octet == null || octet < 0 || octet > 255) {
          return UrlValidationResult.invalid(
            'Invalid IPv4 octet in host: ${match.group(i)}',
          );
        }
      }
    } else {
      // Validate hostname characters
      final hostnameRegex = RegExp(r'^[a-zA-Z0-9.-]+$');
      if (!hostnameRegex.hasMatch(uri.host)) {
        return UrlValidationResult.invalid(
          'Host contains invalid characters: ${uri.host}',
        );
      }
    }

    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    if (port <= 0 || port > 65535) {
      return UrlValidationResult.invalid(
        'Port must be between 1 and 65535 (got $port).',
      );
    }

    return UrlValidationResult.valid(
      normalizedUrl: uri.toString(),
      host: uri.host,
      port: port,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraConnectionConfig &&
          runtimeType == other.runtimeType &&
          baseUrl == other.baseUrl &&
          connectionTimeoutSeconds == other.connectionTimeoutSeconds &&
          reconnectIntervalSeconds == other.reconnectIntervalSeconds &&
          autoReconnect == other.autoReconnect &&
          maxRetries == other.maxRetries &&
          autoConnect == other.autoConnect;

  @override
  int get hashCode =>
      baseUrl.hashCode ^
      connectionTimeoutSeconds.hashCode ^
      reconnectIntervalSeconds.hashCode ^
      autoReconnect.hashCode ^
      maxRetries.hashCode ^
      autoConnect.hashCode;
}
