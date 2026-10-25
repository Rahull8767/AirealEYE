import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';
import 'package:aerial_eye/models/connection_diagnostics.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/screens/mavlink_connection_screen.dart';
import 'package:aerial_eye/screens/camera_connection_screen.dart';
import 'package:aerial_eye/screens/motor_test_screen.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _isConnecting = false;
  String? _pendingMode;
  bool _isModeChanging = false;
  bool _isArming = false;
  bool _isTakingOff = false;
  double _configuredTakeoffAltitude = 5.0;

  Timer? _uiTickTimer;

  @override
  void initState() {
    super.initState();
    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiTickTimer?.cancel();
    super.dispose();
  }

  void _openMavlinkSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MavlinkConnectionScreen()),
    );
  }

  void _setFlightMode(String mode) async {
    if (mode == 'RTL' || mode == 'LAND') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Safety Command'),
          content: Text(
            'Are you sure you want to command the drone to ${mode == "RTL" ? "Return to Launch (RTL)" : "LAND"}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: Text('Confirm $mode'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _isModeChanging = true;
      _pendingMode = mode;
    });

    try {
      final success = await ref.read(droneServiceProvider).setFlightMode(mode);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Flight mode successfully changed to $mode'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to change mode to $mode'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mode change failed: ${e.toString().replaceAll("Exception: ", "")}',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isModeChanging = false;
          _pendingMode = null;
        });
      }
    }
  }

  void _armDrone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Motor Arming'),
        content: const Text(
          'Warning: Arming will engage motors and spin propellers. Ensure the drone is clear of all personnel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('ARM MOTORS'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isArming = true);
    try {
      final success = await ref.read(droneServiceProvider).arm();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle Armed Successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Arming failed: ${e.toString().replaceAll("Exception: ", "")}',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isArming = false);
    }
  }

  void _disarmDrone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Disarm'),
        content: const Text(
          'Are you sure you want to disarm motors? If the vehicle is airborne it will fall.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('DISARM NOW'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isArming = true);
    try {
      final success = await ref.read(droneServiceProvider).disarm();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle Disarmed.'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Disarm failed: ${e.toString().replaceAll("Exception: ", "")}',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isArming = false);
    }
  }

  void _takeoffDrone() async {
    final droneService = ref.read(droneServiceProvider);
    final telemetry = droneService.currentTelemetry;

    if (!telemetry.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vehicle is disconnected. Establish MAVLink connection first.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (!telemetry.armed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle must be armed before takeoff.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final double? altitude = await showDialog<double>(
      context: context,
      builder: (context) {
        double targetAlt = _configuredTakeoffAltitude;
        return StatefulBuilder(
          builder: (context, setAltState) => AlertDialog(
            backgroundColor: AppTheme.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Command Takeoff'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set target takeoff altitude (meters AGL):',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${targetAlt.toStringAsFixed(1)} m AGL',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.secondary,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.minusCircle),
                          onPressed: () {
                            if (targetAlt > 1.0)
                              setAltState(() => targetAlt -= 0.5);
                          },
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.plusCircle),
                          onPressed: () {
                            if (targetAlt < 50.0)
                              setAltState(() => targetAlt += 0.5);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                Slider(
                  value: targetAlt,
                  min: 1.0,
                  max: 30.0,
                  divisions: 58,
                  label: '${targetAlt.toStringAsFixed(1)}m',
                  activeColor: AppTheme.secondary,
                  onChanged: (val) {
                    setAltState(() => targetAlt = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, targetAlt),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                ),
                child: const Text('EXECUTE TAKEOFF'),
              ),
            ],
          ),
        );
      },
    );

    if (altitude == null) return;
    _configuredTakeoffAltitude = altitude;

    setState(() => _isTakingOff = true);
    try {
      final success = await droneService.takeoff(altitude);
      if (success && mounted) {
        final currentAlt = droneService.currentTelemetry.altitudeDisplay;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'TAKEOFF ACCEPTED (Target: ${altitude.toStringAsFixed(1)}m) — Altitude: $currentAlt',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Takeoff failed: ${e.toString().replaceAll("Exception: ", "").replaceAll("StateError: ", "")}',
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTakingOff = false);
    }
  }

  void _connectDrone() async {
    setState(() => _isConnecting = true);
    ref.read(droneServiceProvider).connect();
    setState(() => _isConnecting = false);
  }

  void _disconnectDrone() {
    ref.read(droneServiceProvider).disconnect();
  }

  void _copyDiagnosticsToClipboard(ConnectionDiagnostics diagnostics) {
    final report = diagnostics.toClipboardReport();
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('MAVLink network diagnostics copied to clipboard!'),
        backgroundColor: AppTheme.secondary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();

    final droneService = ref.watch(droneServiceProvider);
    final connectionStateAsync = ref.watch(droneConnectionStateProvider);
    final connectionState =
        connectionStateAsync.value ?? droneService.connectionState;
    final diagnosticsAsync = ref.watch(droneDiagnosticsProvider);
    final diagnostics =
        diagnosticsAsync.value ?? droneService.currentDiagnostics;
    final connectionMode = droneService.connectionMode;
    final config = droneService.config;

    final piCamService = ref.watch(piCameraServiceProvider);
    final piCamState =
        ref.watch(piCameraStateProvider).value ?? piCamService.currentState;

    String statusText = 'DISCONNECTED';
    Color statusColor = AppTheme.danger;

    if (connectionMode == DroneConnectionMode.simulation &&
        connectionState == DroneConnectionState.connected) {
      statusText = 'SIMULATION';
      statusColor = AppTheme.secondary;
    } else {
      switch (connectionState) {
        case DroneConnectionState.connected:
          statusText = 'MAVLINK CONNECTED';
          statusColor = AppTheme.success;
          break;
        case DroneConnectionState.socketBoundWaiting:
        case DroneConnectionState.listening:
          statusText = 'LISTENING (0.0.0.0:${config.localPort})';
          statusColor = AppTheme.secondary;
          break;
        case DroneConnectionState.udpPacketsNoMavlink:
          statusText =
              'RECEIVING (RAW UDP: ${diagnostics.rawDatagramsReceived} PKTS)';
          statusColor = AppTheme.warning;
          break;
        case DroneConnectionState.mavlinkNoHeartbeat:
          statusText =
              'RECEIVING (MAVLINK FRAMES: ${diagnostics.mavlinkFramesReceived})';
          statusColor = AppTheme.secondary;
          break;
        case DroneConnectionState.telemetryStale:
        case DroneConnectionState.connectionLost:
        case DroneConnectionState.stale:
          statusText = 'TELEMETRY STALE';
          statusColor = AppTheme.warning;
          break;
        case DroneConnectionState.connecting:
          statusText = 'BINDING SOCKET';
          statusColor = AppTheme.secondary;
          break;
        case DroneConnectionState.error:
          statusText = 'ERROR';
          statusColor = AppTheme.danger;
          break;
        case DroneConnectionState.socketNotBound:
        case DroneConnectionState.disconnected:
        default:
          statusText = 'DISCONNECTED';
          statusColor = AppTheme.danger;
          break;
      }
    }

    final isLiveOrStale =
        connectionState == DroneConnectionState.connected ||
        connectionState == DroneConnectionState.telemetryStale ||
        connectionState == DroneConnectionState.connectionLost ||
        connectionState == DroneConnectionState.stale ||
        connectionState == DroneConnectionState.mavlinkNoHeartbeat;

    final isListeningOrActive =
        connectionState == DroneConnectionState.socketBoundWaiting ||
        connectionState == DroneConnectionState.listening ||
        connectionState == DroneConnectionState.connecting ||
        connectionState == DroneConnectionState.udpPacketsNoMavlink ||
        connectionState == DroneConnectionState.mavlinkNoHeartbeat ||
        isLiveOrStale;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Console'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 20),
            tooltip: 'Copy Diagnostics',
            onPressed: () => _copyDiagnosticsToClipboard(diagnostics),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            tooltip: 'MAVLink Connection Settings',
            onPressed: _openMavlinkSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          children: [
            // 0. Mode Selector & Settings Shortcut
            GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Operation Mode:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  DropdownButton<DroneConnectionMode>(
                    value: connectionMode,
                    dropdownColor: AppTheme.surface,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: DroneConnectionMode.real,
                        child: Text(
                          'Real MAVLink (UDP)',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: DroneConnectionMode.simulation,
                        child: Text(
                          'Simulation / Mock',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                    onChanged:
                        connectionState == DroneConnectionState.disconnected
                        ? (mode) {
                            if (mode != null) {
                              ref.read(droneServiceProvider).connectionMode =
                                  mode;
                              setState(() {});
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. Connection Animation / status indicator
            _buildPulseRing(
              connectionState == DroneConnectionState.connected,
              statusColor,
            ),
            const SizedBox(height: 24),

            // 2. Drone Connection Card
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MAVLink Link Status',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (connectionState == DroneConnectionState.listening) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.secondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Listening on ${config.bindAddress}:${config.localPort}... Waiting for MAVLink heartbeat from MAVProxy / SITL.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (isLiveOrStale) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'MAVLink Heartbeat:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          diagnostics.heartbeatHealth == LinkHealth.live
                              ? 'LIVE (${diagnostics.lastHeartbeatTime != null ? '${(DateTime.now().difference(diagnostics.lastHeartbeatTime!).inMilliseconds / 1000.0).toStringAsFixed(1)}s ago' : 'active'})'
                              : (diagnostics.heartbeatHealth == LinkHealth.stale
                                    ? 'STALE'
                                    : 'NOT AVAILABLE'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                diagnostics.heartbeatHealth == LinkHealth.live
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Telemetry Stream:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          diagnostics.telemetryHealth == LinkHealth.live
                              ? 'LIVE'
                              : (diagnostics.telemetryHealth == LinkHealth.stale
                                    ? 'STALE'
                                    : 'WAITING...'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                diagnostics.telemetryHealth == LinkHealth.live
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Remote Vehicle:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          diagnostics.vehicleType != 'Unknown'
                              ? '${diagnostics.vehicleType} (${diagnostics.autopilotType})'
                              : 'Auto-discovering...',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      'MAVLink UDP endpoint configured to listen for heartbeat telemetry packets.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],

                  const Divider(color: AppTheme.border, height: 24),

                  // Configured parameters summary
                  _buildSettingRow('Bind Address', config.bindAddress),
                  _buildSettingRow('Local UDP Port', '${config.localPort}'),
                  _buildSettingRow(
                    'Connection Mode',
                    config.connectionMode == MavlinkConnectionMode.listener
                        ? 'UDP Listener'
                        : 'UDP Direct (${config.remoteHost}:${config.remotePort})',
                  ),
                  _buildSettingRow(
                    'Target Addressing',
                    config.autoTargetSystem
                        ? 'Auto-Discover (Discovered: Sys ${diagnostics.discoveredSystemId ?? "--"}, Comp ${diagnostics.discoveredComponentId ?? "--"})'
                        : 'Manual (Sys ${config.targetSystemId}, Comp ${config.targetComponentId})',
                  ),

                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _openMavlinkSettings,
                        icon: const Icon(
                          LucideIcons.sliders,
                          size: 14,
                          color: AppTheme.secondary,
                        ),
                        label: const Text(
                          'MAVLink Settings',
                          style: TextStyle(
                            color: AppTheme.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MotorTestScreen(),
                            ),
                          );
                        },
                        icon: const Icon(
                          LucideIcons.fan,
                          size: 14,
                          color: AppTheme.primary,
                        ),
                        label: const Text(
                          'Motor Test Panel',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
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

            // 2.5 Raspberry Pi Camera Feed Card
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            LucideIcons.camera,
                            color: piCamState.isConnected
                                ? AppTheme.success
                                : AppTheme.secondary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Raspberry Pi Camera Feed',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (piCamState.isConnected
                                      ? AppTheme.success
                                      : (piCamState.hasError
                                            ? AppTheme.danger
                                            : AppTheme.surface))
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          piCamState.statusDisplay,
                          style: TextStyle(
                            color: piCamState.isConnected
                                ? AppTheme.success
                                : (piCamState.hasError
                                      ? AppTheme.danger
                                      : AppTheme.textSecondary),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSettingRow(
                    'Camera Endpoint',
                    piCamService.config.baseUrl,
                  ),
                  if (piCamState.isConnected) ...[
                    _buildSettingRow(
                      'Stream Rate',
                      '${piCamState.fps.toStringAsFixed(0)} FPS (${piCamState.latencyMs} ms latency)',
                    ),
                    _buildSettingRow(
                      'Frames Received',
                      '${piCamState.totalFramesReceived} frames',
                    ),
                  ],
                  if (piCamState.hasError &&
                      piCamState.errorMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      piCamState.errorMessage!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CameraConnectionScreen(),
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.settings, size: 14),
                          label: const Text('Configure IP'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppTheme.border),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (piCamState.isConnected) {
                              piCamService.disconnect();
                            } else {
                              piCamService.connect();
                            }
                          },
                          icon: Icon(
                            piCamState.isConnected
                                ? LucideIcons.power
                                : LucideIcons.play,
                            size: 14,
                          ),
                          label: Text(
                            piCamState.isConnected
                                ? 'Disconnect'
                                : 'Connect Feed',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: piCamState.isConnected
                                ? AppTheme.danger
                                : AppTheme.secondary,
                            foregroundColor: piCamState.isConnected
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Telemetry parameters
            if (isLiveOrStale) ...[
              GlassPanel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Link Diagnostics',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _copyDiagnosticsToClipboard(diagnostics),
                          icon: const Icon(
                            LucideIcons.copy,
                            size: 14,
                            color: AppTheme.secondary,
                          ),
                          label: const Text(
                            'Copy Report',
                            style: TextStyle(
                              color: AppTheme.secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDiagTile(
                            'Battery Pack',
                            telemetry.batteryVoltageDisplay,
                            LucideIcons.battery,
                          ),
                        ),
                        Expanded(
                          child: _buildDiagTile(
                            'Flight Mode',
                            telemetry.flightMode,
                            LucideIcons.plane,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDiagTile(
                            'GPS Satellites',
                            telemetry.satellitesDisplay,
                            LucideIcons.satellite,
                          ),
                        ),
                        Expanded(
                          child: _buildDiagTile(
                            'Telemetry RSSI',
                            '${telemetry.rssi.toStringAsFixed(0)} %',
                            LucideIcons.wifi,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDiagTile(
                            'Altitude AGL',
                            telemetry.altitudeDisplay,
                            LucideIcons.arrowUpRight,
                          ),
                        ),
                        Expanded(
                          child: _buildDiagTile(
                            'Heading Comp.',
                            telemetry.headingDisplay,
                            LucideIcons.compass,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDiagTile(
                            'Raw UDP Packets',
                            '${diagnostics.rawDatagramsReceived} pkts',
                            LucideIcons.activity,
                          ),
                        ),
                        Expanded(
                          child: _buildDiagTile(
                            'Valid MAVLink',
                            '${diagnostics.mavlinkFramesReceived} frames (${diagnostics.packetsPerSecond.toStringAsFixed(0)} pps)',
                            LucideIcons.checkCircle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDiagTile(
                            'Protocol',
                            diagnostics.mavlinkProtocolVersion,
                            LucideIcons.shieldCheck,
                          ),
                        ),
                        Expanded(
                          child: _buildDiagTile(
                            'Addressing',
                            'GCS ${diagnostics.sourceSystemId} -> Drone ${diagnostics.commandTargetSystemId}',
                            LucideIcons.radio,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDiagTile(
                            'Remote Endpoint',
                            diagnostics.remoteAddress ?? '--',
                            LucideIcons.network,
                          ),
                        ),
                        Expanded(
                          child: _buildDiagTile(
                            'Malformed Pkts',
                            '${diagnostics.malformedFramesCount}',
                            LucideIcons.alertTriangle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildFlightModePanel(context, telemetry, connectionState),
              const SizedBox(height: 20),
              _buildArmControlPanel(context, telemetry, connectionState),
              const SizedBox(height: 24),
            ],

            // 4. Control buttons
            Column(
              children: [
                if (_isConnecting)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.secondary,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: AnimatedButton(
                        onTap: _openMavlinkSettings,
                        child: OutlinedButton.icon(
                          onPressed: _openMavlinkSettings,
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: const Text('Settings'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedButton(
                        onTap: _isConnecting
                            ? null
                            : isListeningOrActive
                            ? _disconnectDrone
                            : _connectDrone,
                        child: ElevatedButton(
                          onPressed: _isConnecting
                              ? null
                              : isListeningOrActive
                              ? _disconnectDrone
                              : _connectDrone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isListeningOrActive
                                ? AppTheme.danger
                                : AppTheme.primary,
                          ),
                          child: Text(
                            isListeningOrActive ? 'Disconnect' : 'Connect Link',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseRing(bool isConnected, Color ringColor) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: ringColor.withOpacity(0.08),
        shape: BoxShape.circle,
        border: Border.all(color: ringColor.withOpacity(0.3), width: 2.0),
      ),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: 1.2),
          duration: const Duration(seconds: 1),
          builder: (context, val, child) {
            return Transform.scale(
              scale: isConnected ? val : 1.0,
              child: Icon(LucideIcons.plane, size: 36, color: ringColor),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.secondary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlightModePanel(
    BuildContext context,
    DroneTelemetry telemetry,
    DroneConnectionState connectionState,
  ) {
    final modes = ['STABILIZE', 'GUIDED', 'LOITER', 'AUTO', 'RTL', 'LAND'];
    final isConnectionLost =
        connectionState == DroneConnectionState.connectionLost ||
        connectionState == DroneConnectionState.stale;

    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FLIGHT MODE CONTROL',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Transition the drone to a new flight mode. RTL and LAND require safety confirmation.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const Divider(color: AppTheme.border, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Current confirmed mode:',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  telemetry.flightMode,
                  style: const TextStyle(
                    color: AppTheme.secondary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modes.map((mode) {
              final isCurrent = telemetry.flightMode == mode;
              final isPending = _isModeChanging && _pendingMode == mode;

              Color buttonBgColor = AppTheme.surface;
              Color buttonTextColor = AppTheme.textPrimary;
              BorderSide borderSide = const BorderSide(
                color: AppTheme.border,
                width: 0.8,
              );

              if (isCurrent) {
                buttonBgColor = AppTheme.secondary.withOpacity(0.2);
                buttonTextColor = AppTheme.secondary;
                borderSide = const BorderSide(
                  color: AppTheme.secondary,
                  width: 1.2,
                );
              }

              if (isConnectionLost) {
                buttonTextColor = buttonTextColor.withOpacity(0.4);
                buttonBgColor = buttonBgColor.withOpacity(0.5);
              }

              return InkWell(
                onTap: (_isModeChanging || isConnectionLost)
                    ? null
                    : () => _setFlightMode(mode),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: (MediaQuery.of(context).size.width - 80) / 2,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: buttonBgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.fromBorderSide(borderSide),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isPending) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        mode,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: buttonTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildArmControlPanel(
    BuildContext context,
    DroneTelemetry telemetry,
    DroneConnectionState connectionState,
  ) {
    final isConnectionLost =
        connectionState == DroneConnectionState.connectionLost ||
        connectionState == DroneConnectionState.stale;
    if (!telemetry.isConnected && !isConnectionLost)
      return const SizedBox.shrink();

    String armLabel = telemetry.armed ? 'ARMED' : 'DISARMED';
    Color armColor = telemetry.armed
        ? AppTheme.success
        : AppTheme.textSecondary;
    if (_isArming) {
      armLabel = telemetry.armed ? 'DISARMING...' : 'ARMING...';
      armColor = AppTheme.warning;
    }

    final isButtonsDisabled = _isArming || _isTakingOff || isConnectionLost;

    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VEHICLE OPERATION CONTROL',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Arm the motors or execute takeoff. Safe and explicit confirmation is required.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const Divider(color: AppTheme.border, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Motors State:',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    armLabel,
                    style: TextStyle(
                      color: armColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: isButtonsDisabled
                        ? null
                        : (telemetry.armed ? _disarmDrone : _armDrone),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: telemetry.armed
                          ? AppTheme.danger
                          : AppTheme.success,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_isArming) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(telemetry.armed ? 'DISARM' : 'ARM VEHICLE'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: isButtonsDisabled ? null : _takeoffDrone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_isTakingOff) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Text('TAKEOFF'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
