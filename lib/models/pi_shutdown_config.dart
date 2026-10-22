class PiShutdownConfig {
  final String host;
  final int port;
  final String secretToken;
  final int timeoutSeconds;

  const PiShutdownConfig({
    this.host = '10.174.17.87',
    this.port = 5005,
    this.secretToken = 'aerialeye-safe-shutdown-secret-2026',
    this.timeoutSeconds = 4,
  });

  factory PiShutdownConfig.defaultConfig() {
    return const PiShutdownConfig();
  }

  String get baseUrl => 'http://$host:$port';

  PiShutdownConfig copyWith({
    String? host,
    int? port,
    String? secretToken,
    int? timeoutSeconds,
  }) {
    return PiShutdownConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      secretToken: secretToken ?? this.secretToken,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'secretToken': secretToken,
      'timeoutSeconds': timeoutSeconds,
    };
  }

  factory PiShutdownConfig.fromJson(Map<String, dynamic> json) {
    return PiShutdownConfig(
      host: json['host'] as String? ?? '10.174.17.87',
      port: json['port'] as int? ?? 5005,
      secretToken:
          json['secretToken'] as String? ??
          'aerialeye-safe-shutdown-secret-2026',
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 4,
    );
  }
}
