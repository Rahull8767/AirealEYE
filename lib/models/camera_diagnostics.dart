class CameraDiagnosticsResult {
  final bool isSuccess;
  final String stage;
  final String message;
  final String technicalDetails;
  final int roundTripMs;
  final String? resolvedEndpoint;
  final String? detectedContentType;
  final List<String> stepLogs;
  final DateTime timestamp;

  const CameraDiagnosticsResult({
    required this.isSuccess,
    required this.stage,
    required this.message,
    required this.technicalDetails,
    this.roundTripMs = 0,
    this.resolvedEndpoint,
    this.detectedContentType,
    required this.stepLogs,
    required this.timestamp,
  });

  factory CameraDiagnosticsResult.initial() {
    return CameraDiagnosticsResult(
      isSuccess: false,
      stage: 'Idle',
      message: 'No diagnostics run yet. Click "Test Connection" to diagnose.',
      technicalDetails: '',
      stepLogs: const [],
      timestamp: DateTime.now(),
    );
  }
}
