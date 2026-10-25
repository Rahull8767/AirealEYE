import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/screens/motor_test_screen.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class MavlinkConnectionScreen extends ConsumerStatefulWidget {
  const MavlinkConnectionScreen({super.key});

  @override
  ConsumerState<MavlinkConnectionScreen> createState() =>
      _MavlinkConnectionScreenState();
}

class _MavlinkConnectionScreenState
    extends ConsumerState<MavlinkConnectionScreen> {
  late MavlinkTransport _transport;
  late MavlinkConnectionMode _connectionMode;
  late TextEditingController _bindAddressCtrl;
  late TextEditingController _localPortCtrl;
  late TextEditingController _remoteHostCtrl;
  late TextEditingController _remotePortCtrl;
  late TextEditingController _sourceSysIdCtrl;
  late TextEditingController _sourceCompIdCtrl;
  late TextEditingController _targetSysIdCtrl;
  late TextEditingController _targetCompIdCtrl;
  late TextEditingController _hbTimeoutCtrl;
  late TextEditingController _telTimeoutCtrl;
  late TextEditingController _telRateCtrl;
  late bool _autoTargetSys;
  late bool _autoTargetComp;
  late bool _debugLogging;

  // Raspberry Pi HTTP Telemetry controllers
  late TextEditingController _httpBaseUrlCtrl;
  late TextEditingController _httpIntervalCtrl;
  late TextEditingController _httpTimeoutCtrl;

  bool _isTesting = false;
  bool _showLogBuffer = false;
  MavlinkTestResult? _testResult;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final config = ref.read(droneServiceProvider).config;
    _initFromConfig(config);
  }

  void _initFromConfig(MavlinkConnectionConfig config) {
    _transport = config.transport;
    _connectionMode = config.connectionMode;
    _bindAddressCtrl = TextEditingController(text: config.bindAddress);
    _localPortCtrl = TextEditingController(text: config.localPort.toString());
    _remoteHostCtrl = TextEditingController(text: config.remoteHost);
    _remotePortCtrl = TextEditingController(text: config.remotePort.toString());
    _sourceSysIdCtrl = TextEditingController(
      text: config.sourceSystemId.toString(),
    );
    _sourceCompIdCtrl = TextEditingController(
      text: config.sourceComponentId.toString(),
    );
    _targetSysIdCtrl = TextEditingController(
      text: config.targetSystemId.toString(),
    );
    _targetCompIdCtrl = TextEditingController(
      text: config.targetComponentId.toString(),
    );
    _hbTimeoutCtrl = TextEditingController(
      text: config.heartbeatTimeoutSeconds.toString(),
    );
    _telTimeoutCtrl = TextEditingController(
      text: config.telemetryTimeoutSeconds.toString(),
    );
    _telRateCtrl = TextEditingController(
      text: config.telemetryRateHz.toString(),
    );
    _autoTargetSys = config.autoTargetSystem;
    _autoTargetComp = config.autoTargetComponent;
    _debugLogging = config.debugLogging;

    _httpBaseUrlCtrl = TextEditingController(text: config.httpBaseUrl);
    _httpIntervalCtrl = TextEditingController(
      text: config.httpPollingIntervalMs.toString(),
    );
    _httpTimeoutCtrl = TextEditingController(
      text: config.httpTimeoutSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _bindAddressCtrl.dispose();
    _localPortCtrl.dispose();
    _remoteHostCtrl.dispose();
    _remotePortCtrl.dispose();
    _sourceSysIdCtrl.dispose();
    _sourceCompIdCtrl.dispose();
    _targetSysIdCtrl.dispose();
    _targetCompIdCtrl.dispose();
    _hbTimeoutCtrl.dispose();
    _telTimeoutCtrl.dispose();
    _telRateCtrl.dispose();
    _httpBaseUrlCtrl.dispose();
    _httpIntervalCtrl.dispose();
    _httpTimeoutCtrl.dispose();
    super.dispose();
  }

  MavlinkConnectionConfig _buildCurrentConfig() {
    return MavlinkConnectionConfig(
      transport: _transport,
      connectionMode: _connectionMode,
      bindAddress: _bindAddressCtrl.text.trim().isEmpty
          ? '0.0.0.0'
          : _bindAddressCtrl.text.trim(),
      localPort: int.tryParse(_localPortCtrl.text) ?? 14550,
      remoteHost: _remoteHostCtrl.text.trim(),
      remotePort: int.tryParse(_remotePortCtrl.text) ?? 14550,
      sourceSystemId: int.tryParse(_sourceSysIdCtrl.text) ?? 255,
      sourceComponentId: int.tryParse(_sourceCompIdCtrl.text) ?? 190,
      targetSystemId: int.tryParse(_targetSysIdCtrl.text) ?? 1,
      targetComponentId: int.tryParse(_targetCompIdCtrl.text) ?? 1,
      autoTargetSystem: _autoTargetSys,
      autoTargetComponent: _autoTargetComp,
      heartbeatTimeoutSeconds: int.tryParse(_hbTimeoutCtrl.text) ?? 3,
      telemetryTimeoutSeconds: int.tryParse(_telTimeoutCtrl.text) ?? 5,
      reconnectIntervalSeconds: 3,
      telemetryRateHz: int.tryParse(_telRateCtrl.text) ?? 10,
      debugLogging: _debugLogging,
      httpBaseUrl: _httpBaseUrlCtrl.text.trim(),
      httpPollingIntervalMs: int.tryParse(_httpIntervalCtrl.text) ?? 1000,
      httpTimeoutSeconds: int.tryParse(_httpTimeoutCtrl.text) ?? 3,
    );
  }

  void _saveConfig() {
    final cfg = _buildCurrentConfig();
    final errors = cfg.validate();
    if (errors.isNotEmpty) {
      setState(() {
        _validationError = errors.first;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_validationError!),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() {
      _validationError = null;
    });

    ref.read(droneServiceProvider).updateConfig(cfg);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('MAVLink connection settings saved successfully!'),
        backgroundColor: AppTheme.success,
      ),
    );
    Navigator.pop(context);
  }

  void _resetDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all MAVLink connection settings to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final def = MavlinkConnectionConfig.defaultConfig();
              setState(() {
                _transport = def.transport;
                _connectionMode = def.connectionMode;
                _bindAddressCtrl.text = def.bindAddress;
                _localPortCtrl.text = def.localPort.toString();
                _remoteHostCtrl.text = def.remoteHost;
                _remotePortCtrl.text = def.remotePort.toString();
                _sourceSysIdCtrl.text = def.sourceSystemId.toString();
                _sourceCompIdCtrl.text = def.sourceComponentId.toString();
                _targetSysIdCtrl.text = def.targetSystemId.toString();
                _targetCompIdCtrl.text = def.targetComponentId.toString();
                _hbTimeoutCtrl.text = def.heartbeatTimeoutSeconds.toString();
                _telTimeoutCtrl.text = def.telemetryTimeoutSeconds.toString();
                _telRateCtrl.text = def.telemetryRateHz.toString();
                _autoTargetSys = def.autoTargetSystem;
                _autoTargetComp = def.autoTargetComponent;
                _debugLogging = def.debugLogging;
                _httpBaseUrlCtrl.text = def.httpBaseUrl;
                _httpIntervalCtrl.text = def.httpPollingIntervalMs.toString();
                _httpTimeoutCtrl.text = def.httpTimeoutSeconds.toString();
                _validationError = null;
                _testResult = null;
              });
              ref.read(droneServiceProvider).updateConfig(def);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Settings restored to defaults.'),
                  backgroundColor: AppTheme.secondary,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _copyDiagnostics(ConnectionDiagnostics diagnostics) {
    final report = diagnostics.toClipboardReport();
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'MAVLink network diagnostics report copied to clipboard!',
        ),
        backgroundColor: AppTheme.secondary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _runTestConnection() async {
    final cfg = _buildCurrentConfig();
    final errors = cfg.validate();
    if (errors.isNotEmpty) {
      setState(() => _validationError = errors.first);
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _validationError = null;
    });

    try {
      final res = await ref.read(droneServiceProvider).testConnection(cfg);
      if (mounted) {
        setState(() {
          _testResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResult = MavlinkTestResult(
            success: false,
            message: 'Test failed: $e',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnosticsAsync = ref.watch(droneDiagnosticsProvider);
    final diagnostics =
        diagnosticsAsync.value ??
        ref.read(droneServiceProvider).currentDiagnostics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MAVLink Connection'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 20),
            tooltip: 'Copy Diagnostics',
            onPressed: () => _copyDiagnostics(diagnostics),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error banner if any
            if (_validationError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.danger),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      color: AppTheme.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationError!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Live Diagnostics Card
            _buildSectionHeader('Live Network Diagnostics'),
            GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (_transport == MavlinkTransport.http
                                      ? (diagnostics.socketStatus ==
                                          'HTTP POLLING')
                                      : (diagnostics.socketStatus == 'BOUND'))
                                  ? AppTheme.success
                                  : AppTheme.danger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _transport == MavlinkTransport.http
                                ? 'Status: ${diagnostics.socketStatus}'
                                : 'Socket: ${diagnostics.socketStatus}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () => _copyDiagnostics(diagnostics),
                        icon: const Icon(
                          LucideIcons.copy,
                          size: 13,
                          color: AppTheme.secondary,
                        ),
                        label: const Text(
                          'Copy Diagnostics',
                          style: TextStyle(
                            color: AppTheme.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'State: ${diagnostics.connectionStateLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Divider(color: AppTheme.border, height: 16),
                  if (_transport == MavlinkTransport.http) ...[
                    _buildDiagItem(
                      'Transport Mode:',
                      'Raspberry Pi Flask HTTP',
                    ),
                    _buildDiagItem(
                      'Endpoint URL:',
                      _httpBaseUrlCtrl.text.trim(),
                    ),
                    _buildDiagItem(
                      'HTTP Polling Requests:',
                      '${diagnostics.rawDatagramsReceived} reqs (${diagnostics.packetsPerSecond.toStringAsFixed(1)} rps)',
                    ),
                    _buildDiagItem(
                      'Valid Telemetry Payloads:',
                      '${diagnostics.mavlinkFramesReceived} frames',
                    ),
                    _buildDiagItem(
                      'HTTP Errors / Timeouts:',
                      '${diagnostics.malformedFramesCount} errs',
                    ),
                    _buildDiagItem(
                      'Detected Protocol:',
                      diagnostics.mavlinkProtocolVersion,
                    ),
                    _buildDiagItem(
                      'Target Vehicle:',
                      diagnostics.vehicleType,
                    ),
                    _buildDiagItem(
                      'Watchdog Status:',
                      diagnostics.heartbeatHealth.name.toUpperCase(),
                    ),
                  ] else ...[
                    _buildDiagItem(
                      'Local Endpoint:',
                      '${diagnostics.localAddress}:${diagnostics.localPort}',
                    ),
                    _buildDiagItem(
                      'Remote Sender:',
                      diagnostics.remoteAddress ?? 'Waiting for datagrams...',
                    ),
                    _buildDiagItem(
                      'Raw UDP Datagrams:',
                      '${diagnostics.rawDatagramsReceived} pkts',
                    ),
                    if (diagnostics.lastRawSender != null)
                      _buildDiagItem(
                        'Last UDP Packet:',
                        '${diagnostics.lastRawSender} (${diagnostics.lastRawDatagramSize ?? 0} B)',
                      ),
                    if (diagnostics.lastRawDatagramPreview != null &&
                        diagnostics.lastRawDatagramPreview!.isNotEmpty)
                      _buildDiagItem(
                        'Last Raw Payload:',
                        '"${diagnostics.lastRawDatagramPreview}"',
                      ),
                    _buildDiagItem(
                      'Valid MAVLink Frames:',
                      '${diagnostics.mavlinkFramesReceived} frames (${diagnostics.packetsPerSecond.toStringAsFixed(1)} pps)',
                    ),
                    _buildDiagItem(
                      'Malformed / Non-MAVLink:',
                      '${diagnostics.malformedFramesCount} pkts',
                    ),
                    _buildDiagItem(
                      'Detected Protocol:',
                      diagnostics.mavlinkProtocolVersion,
                    ),
                    _buildDiagItem(
                      'Target Vehicle:',
                      diagnostics.vehicleType != 'Unknown'
                          ? '${diagnostics.vehicleType} (Sys ${diagnostics.discoveredSystemId ?? "--"}, Comp ${diagnostics.discoveredComponentId ?? "--"})'
                          : 'Auto-discovering...',
                    ),
                    _buildDiagItem(
                      'Heartbeat Status:',
                      diagnostics.heartbeatHealth.name.toUpperCase(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final droneService = ref.read(droneServiceProvider);
                            final isRunning = _transport == MavlinkTransport.http
                                ? (droneService.connectionState ==
                                        DroneConnectionState.connected ||
                                    droneService.connectionState ==
                                        DroneConnectionState.connecting ||
                                    diagnostics.socketStatus ==
                                        'HTTP POLLING')
                                : (diagnostics.socketStatus == 'BOUND');

                            if (isRunning) {
                              droneService.disconnect();
                            } else {
                              final cfg = _buildCurrentConfig();
                              final errors = cfg.validate();
                              if (errors.isNotEmpty) {
                                setState(() => _validationError = errors.first);
                                return;
                              }
                              droneService.updateConfig(cfg);
                              droneService.connect();
                            }
                          },
                          icon: Icon(
                            (_transport == MavlinkTransport.http
                                    ? (diagnostics.socketStatus ==
                                        'HTTP POLLING')
                                    : (diagnostics.socketStatus == 'BOUND'))
                                ? LucideIcons.square
                                : (_transport == MavlinkTransport.http
                                    ? LucideIcons.globe
                                    : LucideIcons.play),
                            size: 15,
                          ),
                          label: Text(
                            _transport == MavlinkTransport.http
                                ? (diagnostics.socketStatus == 'HTTP POLLING'
                                    ? 'Stop HTTP Telemetry'
                                    : 'Start HTTP Telemetry')
                                : (diagnostics.socketStatus == 'BOUND'
                                    ? 'Stop UDP Listener'
                                    : 'Start UDP Listener'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_transport ==
                                        MavlinkTransport.http
                                    ? (diagnostics.socketStatus ==
                                        'HTTP POLLING')
                                    : (diagnostics.socketStatus == 'BOUND'))
                                ? AppTheme.danger.withOpacity(0.8)
                                : AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () =>
                        setState(() => _showLogBuffer = !_showLogBuffer),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _showLogBuffer
                              ? 'Hide Diagnostic Log Buffer'
                              : 'Show Diagnostic Log Buffer (${diagnostics.recentLogs.length} events)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          _showLogBuffer
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 14,
                          color: AppTheme.secondary,
                        ),
                      ],
                    ),
                  ),
                  if (_showLogBuffer) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 140,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: diagnostics.recentLogs.isEmpty
                          ? const Center(
                              child: Text(
                                'No diagnostic events recorded yet.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            )
                          : ListView.builder(
                              reverse: true,
                              itemCount: diagnostics.recentLogs.length,
                              itemBuilder: (context, index) {
                                final log =
                                    diagnostics.recentLogs[diagnostics
                                            .recentLogs
                                            .length -
                                        1 -
                                        index];
                                return Text(
                                  log,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: AppTheme.textSecondary,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Transport Selection Section
            _buildSectionHeader('Transport Protocol'),
            Row(
              children: [
                Expanded(
                  child: _buildTransportCard(
                    transport: MavlinkTransport.http,
                    title: 'Raspberry Pi HTTP',
                    badge: 'Flask API :8081',
                    subtitle:
                        'Polls live telemetry over Wi-Fi. Safe read-only monitoring.',
                    icon: LucideIcons.globe,
                    isSelected: _transport == MavlinkTransport.http,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTransportCard(
                    transport: MavlinkTransport.udp,
                    title: 'MAVLink UDP',
                    badge: 'UDP Port 14550',
                    subtitle:
                        'Standard socket for SITL, MAVProxy & flight controls.',
                    icon: LucideIcons.radio,
                    isSelected: _transport == MavlinkTransport.udp,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Transport-Specific Settings
            if (_transport == MavlinkTransport.http) ...[
              // Section: Raspberry Pi HTTP Settings
              _buildSectionHeader('Raspberry Pi HTTP Telemetry Settings'),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      label: 'Raspberry Pi Base URL',
                      helper:
                          'Flask API base URL (provides /health and /telemetry)',
                      controller: _httpBaseUrlCtrl,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildPresetChip(
                          '10.174.17.87:8081 (Default Pi)',
                          'http://10.174.17.87:8081',
                        ),
                        _buildPresetChip(
                          '192.168.43.87:8081 (Hotspot)',
                          'http://192.168.43.87:8081',
                        ),
                        _buildPresetChip(
                          '127.0.0.1:8081 (Localhost)',
                          'http://127.0.0.1:8081',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildTextField(
                            label: 'Polling Interval (ms)',
                            helper: 'Default 1000ms (1 Hz)',
                            controller: _httpIntervalCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            label: 'Timeout (sec)',
                            helper: 'Default 3s',
                            controller: _httpTimeoutCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            LucideIcons.info,
                            color: AppTheme.secondary,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Notice: Raspberry Pi HTTP mode provides safe read-only telemetry monitoring. Flight control commands (Arm, Takeoff, Flight Mode change, Mission execution) require MAVLink UDP mode.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // PowerShell UDP Test Helper
              _buildSectionHeader('Windows PowerShell UDP Test Tool'),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'To test UDP connectivity from your Windows laptop to this phone:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        '\$u = New-Object System.Net.Sockets.UdpClient; \$u.Send([Text.Encoding]::ASCII.GetBytes("TEST-WINDOWS-UDP"), 16, "<PHONE_IP>", ${_localPortCtrl.text.trim()}); \$u.Close()',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          color: AppTheme.secondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Replace <PHONE_IP> with phone\'s Wi-Fi IP (e.g. 192.168.1.9).',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final port = _localPortCtrl.text.trim();
                            Clipboard.setData(
                              ClipboardData(
                                text:
                                    '\$u = New-Object System.Net.Sockets.UdpClient; \$u.Send([Text.Encoding]::ASCII.GetBytes("TEST-WINDOWS-UDP"), 16, "192.168.1.9", $port); \$u.Close()',
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'PowerShell UDP test command copied to clipboard!',
                                ),
                                backgroundColor: AppTheme.secondary,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(
                            LucideIcons.copy,
                            size: 13,
                            color: AppTheme.secondary,
                          ),
                          label: const Text(
                            'Copy Command',
                            style: TextStyle(
                              color: AppTheme.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Section 1: UDP Connection Mode
              _buildSectionHeader('UDP Connection Mode'),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RadioListTile<MavlinkConnectionMode>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'UDP Listener Mode (Recommended for SITL & Drone)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Binds socket on 0.0.0.0:<port> and receives forwarded UDP packets from MAVProxy / Drone.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      value: MavlinkConnectionMode.listener,
                      groupValue: _connectionMode,
                      activeColor: AppTheme.secondary,
                      onChanged: (val) {
                        if (val != null) setState(() => _connectionMode = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<MavlinkConnectionMode>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'UDP Direct Mode',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Sends UDP packets directly to a target remote IP/port.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      value: MavlinkConnectionMode.direct,
                      groupValue: _connectionMode,
                      activeColor: AppTheme.secondary,
                      onChanged: (val) {
                        if (val != null) setState(() => _connectionMode = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Section 2: Endpoints
              _buildSectionHeader('IP Addresses & Ports'),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildTextField(
                            label: 'Local Bind Address',
                            helper: 'Default 0.0.0.0 (all interfaces)',
                            controller: _bindAddressCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            label: 'Local UDP Port',
                            helper: 'Default 14550',
                            controller: _localPortCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildTextField(
                            label: 'Remote IP (Optional for listener)',
                            helper: 'e.g. 192.168.1.5 for MAVProxy',
                            controller: _remoteHostCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildTextField(
                            label: 'Remote Port',
                            helper: 'Default 14550',
                            controller: _remotePortCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Section 3: System & Component IDs
              _buildSectionHeader('MAVLink System & Component IDs'),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'GCS System ID',
                            helper: 'Default 255 (Ground Station)',
                            controller: _sourceSysIdCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            label: 'GCS Component ID',
                            helper: 'Default 190 (Mission Planner)',
                            controller: _sourceCompIdCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: AppTheme.border, height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoTargetSys,
                      title: const Text(
                        'Auto-Discover Target Vehicle System ID',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Automatically targets first discovered drone heartbeat',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      activeThumbColor: AppTheme.secondary,
                      onChanged: (val) => setState(() => _autoTargetSys = val),
                    ),
                    if (!_autoTargetSys) ...[
                      const SizedBox(height: 8),
                      _buildTextField(
                        label: 'Manual Target System ID',
                        helper: 'Usually 1 for first drone',
                        controller: _targetSysIdCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoTargetComp,
                      title: const Text(
                        'Auto-Discover Target Component ID',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Automatically targets autopilot component ID (usually 1)',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      activeThumbColor: AppTheme.secondary,
                      onChanged: (val) => setState(() => _autoTargetComp = val),
                    ),
                    if (!_autoTargetComp) ...[
                      const SizedBox(height: 8),
                      _buildTextField(
                        label: 'Manual Target Component ID',
                        helper:
                            'Usually 1 for autopilot (MAV_COMP_ID_AUTOPILOT1)',
                        controller: _targetCompIdCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Section 4: Timeouts & Rates
              _buildSectionHeader('Timeouts & Rates'),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Heartbeat Timeout (sec)',
                            helper: 'Default 3s',
                            controller: _hbTimeoutCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            label: 'Telemetry Timeout (sec)',
                            helper: 'Default 5s',
                            controller: _telTimeoutCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      label: 'Telemetry Rate (Hz)',
                      helper: 'Requested rate: 10 Hz',
                      controller: _telRateCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const Divider(color: AppTheme.border, height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _debugLogging,
                      title: const Text(
                        'MAVLink Debug Logging',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Prints structured [MAVLINK] logs in developer console',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      activeThumbColor: AppTheme.secondary,
                      onChanged: (val) => setState(() => _debugLogging = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Test Result Card
            if (_testResult != null) ...[
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _testResult!.success
                              ? LucideIcons.checkCircle
                              : LucideIcons.alertCircle,
                          color: _testResult!.success
                              ? AppTheme.success
                              : AppTheme.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testResult!.success
                                ? 'Connection Test Succeeded'
                                : 'Connection Test Diagnostic Assessment',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _testResult!.success
                                  ? AppTheme.success
                                  : AppTheme.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _testResult!.message,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    const Divider(color: AppTheme.border, height: 16),
                    if (_transport == MavlinkTransport.http) ...[
                      if (_testResult!.remoteAddress != null)
                        _buildDiagItem(
                          'Target Endpoint:',
                          _testResult!.remoteAddress!,
                        ),
                      _buildDiagItem(
                        'Protocol Detected:',
                        _testResult!.protocolVersion,
                      ),
                      if (_testResult!.vehicleType != null)
                        _buildDiagItem(
                          'Vehicle Status:',
                          _testResult!.vehicleType!,
                        ),
                    ] else ...[
                      _buildDiagItem(
                        'Raw Datagrams Received:',
                        '${_testResult!.rawDatagramsReceived} pkts',
                      ),
                      _buildDiagItem(
                        'Valid MAVLink Frames:',
                        '${_testResult!.mavlinkFramesReceived} frames',
                      ),
                      _buildDiagItem(
                        'Protocol Detected:',
                        _testResult!.protocolVersion,
                      ),
                      if (_testResult!.remoteAddress != null)
                        _buildDiagItem(
                          'Remote Endpoint:',
                          _testResult!.remoteAddress!,
                        ),
                      if (_testResult!.systemId != null)
                        _buildDiagItem(
                          'Vehicle System ID:',
                          '${_testResult!.systemId}',
                        ),
                      if (_testResult!.componentId != null)
                        _buildDiagItem(
                          'Component ID:',
                          '${_testResult!.componentId}',
                        ),
                      if (_testResult!.vehicleType != null)
                        _buildDiagItem(
                          'Vehicle Type:',
                          _testResult!.vehicleType!,
                        ),
                      if (_testResult!.autopilotType != null)
                        _buildDiagItem(
                          'Autopilot:',
                          _testResult!.autopilotType!,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isTesting ? null : _runTestConnection,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.secondary),
                    ),
                    child: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.secondary,
                              ),
                            ),
                          )
                        : const Text(
                            'Test Connection',
                            style: TextStyle(
                              color: AppTheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Save Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MotorTestScreen(),
                    ),
                  );
                },
                icon: const Icon(LucideIcons.fan, size: 16, color: AppTheme.secondary),
                label: const Text(
                  'Open Motor Test Panel (Bench Diagnostics)',
                  style: TextStyle(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _resetDefaults,
                icon: const Icon(
                  LucideIcons.rotateCcw,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                label: const Text(
                  'Reset to Defaults',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String helper,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.secondary),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDiagItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String url) {
    final isCurrent = _httpBaseUrlCtrl.text.trim() == url;
    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        color: isCurrent ? Colors.white : AppTheme.secondary,
        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: isCurrent
          ? AppTheme.secondary.withOpacity(0.3)
          : AppTheme.surface,
      side: BorderSide(
        color: isCurrent ? AppTheme.secondary : AppTheme.border,
      ),
      onPressed: () {
        setState(() {
          _httpBaseUrlCtrl.text = url;
        });
      },
    );
  }

  Widget _buildTransportCard({
    required MavlinkTransport transport,
    required String title,
    required String badge,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => setState(() => _transport = transport),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.secondary.withOpacity(0.12)
              : AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.secondary : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color:
                      isSelected ? AppTheme.secondary : AppTheme.textSecondary,
                  size: 20,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.secondary.withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppTheme.secondary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppTheme.textSecondary,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
