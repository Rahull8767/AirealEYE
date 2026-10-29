import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/pi_shutdown_state.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/providers/pi_shutdown_provider.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class PiShutdownCard extends ConsumerStatefulWidget {
  final bool showHeader;
  const PiShutdownCard({super.key, this.showHeader = true});

  @override
  ConsumerState<PiShutdownCard> createState() => _PiShutdownCardState();
}

class _PiShutdownCardState extends ConsumerState<PiShutdownCard> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;

  bool _obscureToken = true;
  bool _showAdvancedSettings = false;
  bool _isCheckingStatus = false;
  bool _isShuttingDown = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(piShutdownServiceProvider).config;
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: '${config.port}');
    _tokenController = TextEditingController(text: config.secretToken);

    // Initial status probe
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStatus();
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _saveConfig() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 5005;
    final token = _tokenController.text.trim();

    final service = ref.read(piShutdownServiceProvider);
    service.updateConfig(
      service.config.copyWith(
        host: host.isNotEmpty ? host : '10.174.17.87',
        port: port,
        secretToken: token,
      ),
    );
  }

  Future<void> _checkStatus() async {
    if (_isCheckingStatus) return;
    setState(() => _isCheckingStatus = true);
    _saveConfig();
    try {
      final service = ref.read(piShutdownServiceProvider);
      await service.checkStatus();
    } catch (_) {}
    if (mounted) {
      setState(() => _isCheckingStatus = false);
    }
  }

  Future<void> _handleShutdownPressed() async {
    _saveConfig();
    final service = ref.read(piShutdownServiceProvider);
    final drone = ref.read(droneServiceProvider);
    final telemetry = drone.currentTelemetry;
    final isConnected = drone.connectionState == DroneConnectionState.connected;

    // 1. Check if drone is armed or flying -> Hard block
    final flightBlocker = service.validateFlightSafety();
    if (flightBlocker != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(
            LucideIcons.shieldAlert,
            color: AppTheme.danger,
            size: 36,
          ),
          title: const Text('Shutdown Blocked for Flight Safety'),
          content: Text(
            flightBlocker,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondary,
                foregroundColor: Colors.black,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. Open confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(LucideIcons.alertTriangle, color: AppTheme.danger, size: 22),
            SizedBox(width: 8),
            Text('Shut Down Raspberry Pi?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will initiate a clean system poweroff (systemctl poweroff) on the companion computer.',
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SERVICES THAT WILL STOP:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• OV5647 Camera Stream & YOLO NCNN Detector\n'
                    '• MAVLink Serial-to-UDP Router\n'
                    '• Wi-Fi Web Server on Port 8080',
                    style: TextStyle(fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Flight Safety Status indicator
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isConnected
                    ? AppTheme.success.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isConnected
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isConnected
                        ? LucideIcons.checkCircle2
                        : LucideIcons.alertCircle,
                    color: isConnected ? AppTheme.success : Colors.amber,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConnected
                          ? 'Drone Disarmed & Landed (Mode: ${telemetry.flightMode})'
                          : 'Telemetry Disconnected: Confirm drone is landed and disarmed before proceeding.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isConnected ? AppTheme.success : Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Note: Physical power to the Raspberry Pi must be power-cycled to turn it back on.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(LucideIcons.power, size: 14),
            label: const Text('Confirm Shutdown'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 3. Execute shutdown request
    setState(() => _isShuttingDown = true);

    final result = await service.requestShutdown(force: !isConnected);

    if (mounted) {
      setState(() => _isShuttingDown = false);
      if (result.success) {
        // Disconnect camera stream to prevent reconnection retries
        try {
          ref.read(piCameraServiceProvider).disconnect();
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Color _getStatusColor(PiPowerStatus status) {
    switch (status) {
      case PiPowerStatus.online:
        return AppTheme.success;
      case PiPowerStatus.shuttingDown:
        return Colors.orange;
      case PiPowerStatus.shutdownComplete:
      case PiPowerStatus.offline:
        return AppTheme.textSecondary;
      case PiPowerStatus.error:
        return AppTheme.danger;
      case PiPowerStatus.checking:
      case PiPowerStatus.unknown:
        return AppTheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shutdownService = ref.watch(piShutdownServiceProvider);
    final state =
        ref.watch(piShutdownStateProvider).value ??
        shutdownService.currentState;
    final drone = ref.watch(droneServiceProvider);
    final telemetry = drone.currentTelemetry;
    final isFlightActive = telemetry.armed || telemetry.relativeAltitude > 1.0;

    final statusColor = _getStatusColor(state.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Raspberry Pi Power Control',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Status Badge & Probe Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state.statusDisplay,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _isCheckingStatus ? null : _checkStatus,
                    icon: _isCheckingStatus
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.refreshCw, size: 13),
                    label: const Text(
                      'Refresh',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.secondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Device metadata summary
              Text(
                'Target: http://${shutdownService.config.host}:${shutdownService.config.port} • Hostname: ${state.hostname}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),

              if (state.errorMessage != null &&
                  state.status == PiPowerStatus.error) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 14,
                        color: AppTheme.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          state.errorMessage!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Divider(color: AppTheme.border, height: 20),

              // Action Buttons Row: Shut Down Pi & Advanced Toggle
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          (_isShuttingDown ||
                              state.status == PiPowerStatus.shuttingDown ||
                              isFlightActive)
                          ? null
                          : _handleShutdownPressed,
                      icon: _isShuttingDown
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.power, size: 16),
                      label: Text(
                        _isShuttingDown
                            ? 'Shutting Down...'
                            : (state.status == PiPowerStatus.shutdownComplete
                                  ? 'Pi Powered Down'
                                  : 'Shut Down Raspberry Pi'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTheme.danger.withValues(
                          alpha: 0.3,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showAdvancedSettings = !_showAdvancedSettings;
                      });
                    },
                    icon: Icon(
                      _showAdvancedSettings
                          ? LucideIcons.chevronUp
                          : LucideIcons.settings2,
                      color: AppTheme.secondary,
                      size: 20,
                    ),
                    tooltip: 'Shutdown Settings',
                  ),
                ],
              ),

              if (isFlightActive) ...[
                const SizedBox(height: 8),
                const Text(
                  '⚠️ Shutdown is disabled while drone is armed or in flight.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              // Collapsible Advanced Settings (Host, Port, Secret Token)
              if (_showAdvancedSettings) ...[
                const Divider(color: AppTheme.border, height: 24),
                const Text(
                  'DAEMON CONNECTION & AUTHENTICATION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Pi IP Address',
                          hintText: '10.174.17.87',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _saveConfig(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '5005',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _saveConfig(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'Authentication Secret Token',
                    hintText:
                        'Secret configured in /etc/aerialeye/shutdown.conf',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 16,
                      ),
                      onPressed: () {
                        setState(() => _obscureToken = !_obscureToken);
                      },
                    ),
                  ),
                  onChanged: (_) => _saveConfig(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tokens are validated by aerialeye-shutdown.service. Matches AERIALEYE_SHUTDOWN_TOKEN on the Pi.',
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
