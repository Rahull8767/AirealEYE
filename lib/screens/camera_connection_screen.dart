import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/camera_connection_config.dart';
import 'package:aerial_eye/models/camera_diagnostics.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class CameraConnectionScreen extends ConsumerStatefulWidget {
  const CameraConnectionScreen({super.key});

  @override
  ConsumerState<CameraConnectionScreen> createState() =>
      _CameraConnectionScreenState();
}

class _CameraConnectionScreenState
    extends ConsumerState<CameraConnectionScreen> {
  late TextEditingController _urlController;
  late TextEditingController _ipController;
  late TextEditingController _portController;

  bool _isTesting = false;
  CameraDiagnosticsResult? _latestDiagnostics;
  bool _autoReconnect = true;
  bool _autoConnect = false;
  int _timeoutSeconds = 5;

  @override
  void initState() {
    super.initState();
    final config = ref.read(piCameraServiceProvider).config;
    _urlController = TextEditingController(text: config.baseUrl);
    _ipController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: '${config.port}');
    _autoReconnect = config.autoReconnect;
    _autoConnect = config.autoConnect;
    _timeoutSeconds = config.connectionTimeoutSeconds;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _syncFromIpAndPort() {
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    if (ip.isNotEmpty) {
      final portPart = port.isNotEmpty ? ':$port' : '';
      setState(() {
        _urlController.text = 'http://$ip$portPart';
      });
    }
  }

  void _syncFromUrl(String val) {
    try {
      final validation = CameraConnectionConfig.validateUrl(val);
      if (validation.isValid) {
        setState(() {
          _ipController.text = validation.host ?? '';
          _portController.text = '${validation.port ?? 8080}';
        });
      }
    } catch (_) {}
  }

  void _saveConfiguration() {
    final validation = CameraConnectionConfig.validateUrl(_urlController.text);
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation.errorMessage ?? 'Invalid URL format.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final newConfig = CameraConnectionConfig(
      baseUrl: validation.normalizedUrl!,
      connectionTimeoutSeconds: _timeoutSeconds,
      autoReconnect: _autoReconnect,
      autoConnect: _autoConnect,
    );

    ref.read(piCameraServiceProvider).updateConfig(newConfig);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Camera configuration saved successfully.'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  Future<void> _runConnectionTest() async {
    final validation = CameraConnectionConfig.validateUrl(_urlController.text);
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            validation.errorMessage ?? 'Please provide a valid camera URL.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _latestDiagnostics = null;
    });

    final testConfig = CameraConnectionConfig(
      baseUrl: validation.normalizedUrl!,
      connectionTimeoutSeconds: _timeoutSeconds,
    );

    final result = await ref
        .read(piCameraServiceProvider)
        .testConnection(testConfig);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _latestDiagnostics = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameraService = ref.watch(piCameraServiceProvider);
    final stateAsync = ref.watch(piCameraStateProvider);
    final streamState = stateAsync.value ?? cameraService.currentState;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raspberry Pi Camera Link'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.rotateCcw),
            tooltip: 'Reset to Default (10.174.17.87:8080)',
            onPressed: () {
              setState(() {
                _urlController.text = 'http://10.174.17.87:8080';
                _ipController.text = '10.174.17.87';
                _portController.text = '8080';
                _timeoutSeconds = 5;
                _autoReconnect = true;
              });
              _saveConfiguration();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Current Live Status Card
          _buildStatusHeaderCard(streamState),
          const SizedBox(height: 20),

          // 2. Primary Connection Form
          _buildSectionHeader('Connection Endpoint'),
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Camera Base URL',
                    hintText: 'http://10.174.17.87:8080',
                    prefixIcon: Icon(LucideIcons.link, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: _syncFromUrl,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'Raspberry Pi IP',
                          hintText: '10.174.17.87',
                          prefixIcon: Icon(LucideIcons.cpu, size: 18),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _syncFromIpAndPort(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '8080',
                          prefixIcon: Icon(LucideIcons.hash, size: 18),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _syncFromIpAndPort(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Quick Hotspot Presets:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetChip(
                      'Hotspot: 10.174.17.87:8080',
                      'http://10.174.17.87:8080',
                      '10.174.17.87',
                      '8080',
                    ),
                    _buildPresetChip(
                      'Hotspot: 192.168.43.87:8080',
                      'http://192.168.43.87:8080',
                      '192.168.43.87',
                      '8080',
                    ),
                    _buildPresetChip(
                      'Home Wi-Fi: 192.168.1.87:8080',
                      'http://192.168.1.87:8080',
                      '192.168.1.87',
                      '8080',
                    ),
                    _buildPresetChip(
                      'Emulator: 10.0.2.2:8080',
                      'http://10.0.2.2:8080',
                      '10.0.2.2',
                      '8080',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Reliability & Timing Settings
          _buildSectionHeader('Stream Parameters'),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoReconnect,
                  title: const Text('Auto-reconnect on frame drop'),
                  subtitle: const Text(
                    'Automatically recovers stream if hotspot fluctuates',
                  ),
                  activeThumbColor: AppTheme.secondary,
                  onChanged: (val) => setState(() => _autoReconnect = val),
                ),
                const Divider(color: AppTheme.border, height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoConnect,
                  title: const Text('Connect automatically on app launch'),
                  subtitle: const Text(
                    'Starts streaming immediately when monitoring screen opens',
                  ),
                  activeThumbColor: AppTheme.secondary,
                  onChanged: (val) => setState(() => _autoConnect = val),
                ),
                const Divider(color: AppTheme.border, height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Connection Timeout'),
                  trailing: DropdownButton<int>(
                    value: _timeoutSeconds,
                    dropdownColor: AppTheme.card,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('3 seconds')),
                      DropdownMenuItem(
                        value: 5,
                        child: Text('5 seconds (Default)'),
                      ),
                      DropdownMenuItem(value: 10, child: Text('10 seconds')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _timeoutSeconds = val);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isTesting ? null : _runConnectionTest,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.stethoscope, size: 16),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.card,
                    foregroundColor: AppTheme.secondary,
                    side: const BorderSide(color: AppTheme.secondary, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _saveConfiguration();
                    if (streamState.isConnected) {
                      cameraService.disconnect();
                    } else {
                      cameraService.connect();
                    }
                  },
                  icon: Icon(
                    streamState.isConnected
                        ? LucideIcons.power
                        : LucideIcons.play,
                    size: 16,
                  ),
                  label: Text(
                    streamState.isConnected ? 'Disconnect' : 'Connect Stream',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: streamState.isConnected
                        ? AppTheme.danger
                        : AppTheme.secondary,
                    foregroundColor: streamState.isConnected
                        ? Colors.white
                        : Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 5. Diagnostics Report Card
          if (_latestDiagnostics != null) ...[
            _buildSectionHeader('Diagnostic Probe Results'),
            _buildDiagnosticsCard(_latestDiagnostics!),
            const SizedBox(height: 20),
          ],

          // 6. Setup & Troubleshooting Guide
          _buildSectionHeader('One-Phone Hotspot Guide'),
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuideStep('1', 'Turn ON Mobile Hotspot on this phone.'),
                _buildGuideStep(
                  '2',
                  'Connect Raspberry Pi 3A+ to this phone\'s hotspot.',
                ),
                _buildGuideStep(
                  '3',
                  'Open phone\'s Hotspot settings to verify the Pi\'s IP (e.g. 10.174.17.87).',
                ),
                _buildGuideStep(
                  '4',
                  'On Pi, start detector & viewing server:\n   python3 ~/aerialeye_live.py &\n   python3 ~/aerialeye_view.py',
                ),
                _buildGuideStep(
                  '5',
                  'Verify feed opens in phone\'s Chrome at http://<Pi-IP>:8080.',
                ),
                _buildGuideStep(
                  '6',
                  'Tap "Test Connection" above to verify direct in-app streaming!',
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
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

  Widget _buildPresetChip(String label, String url, String ip, String port) {
    return InkWell(
      onTap: () {
        setState(() {
          _urlController.text = url;
          _ipController.text = ip;
          _portController.text = port;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border, width: 0.8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  Widget _buildStatusHeaderCard(CameraStreamState state) {
    Color statusColor;
    IconData statusIcon;

    switch (state.status) {
      case CameraStatus.connected:
        statusColor = AppTheme.success;
        statusIcon = LucideIcons.radio;
        break;
      case CameraStatus.connecting:
      case CameraStatus.reconnecting:
        statusColor = Colors.orange;
        statusIcon = LucideIcons.loader;
        break;
      case CameraStatus.error:
        statusColor = AppTheme.danger;
        statusIcon = LucideIcons.alertTriangle;
        break;
      case CameraStatus.disconnected:
        statusColor = AppTheme.textSecondary;
        statusIcon = LucideIcons.videoOff;
        break;
    }

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.statusDisplay,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        state.connectedUrl.isNotEmpty
                            ? state.connectedUrl
                            : 'Not Connected',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (state.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.fps.toStringAsFixed(0)} FPS',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.success,
                    ),
                  ),
                ),
            ],
          ),
          if (state.isConnected) ...[
            const Divider(color: AppTheme.border, height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('Latency', '${state.latencyMs} ms'),
                _buildStatColumn('Frames', '${state.totalFramesReceived}'),
                _buildStatColumn(
                  'Data RX',
                  '${(state.totalBytesReceived / 1024).toStringAsFixed(0)} KB',
                ),
                _buildStatColumn(
                  'Resolution',
                  state.imageWidth > 0
                      ? '${state.imageWidth}x${state.imageHeight}'
                      : 'Auto',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticsCard(CameraDiagnosticsResult diag) {
    final isSuccess = diag.isSuccess;
    final color = isSuccess ? AppTheme.success : AppTheme.danger;

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSuccess ? LucideIcons.checkCircle2 : LucideIcons.xCircle,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diag.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              if (diag.roundTripMs > 0)
                Text(
                  '${diag.roundTripMs} ms',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          if (diag.technicalDetails.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              diag.technicalDetails,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: diag.stepLogs.map((log) {
                final isFailed = log.startsWith('FAILED');
                final isPassed = log.startsWith('PASSED');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: isFailed
                          ? AppTheme.danger
                          : (isPassed
                                ? AppTheme.success
                                : AppTheme.textSecondary),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideStep(String stepNumber, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
