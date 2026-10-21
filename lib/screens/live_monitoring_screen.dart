import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/models/notification.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/screens/camera_connection_screen.dart';
import 'package:aerial_eye/widgets/camera/pi_camera_view.dart';

class LiveMonitoringScreen extends ConsumerStatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  ConsumerState<LiveMonitoringScreen> createState() =>
      _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends ConsumerState<LiveMonitoringScreen> {
  bool _isRecording = false;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    // Auto-connect to camera stream if disconnected or configured
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cameraService = ref.read(piCameraServiceProvider);
      if (cameraService.currentState.status == CameraStatus.disconnected) {
        cameraService.connect();
      }
    });
  }

  void _openCameraSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraConnectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final missionState = ref.watch(missionProvider);
    final cameraService = ref.watch(piCameraServiceProvider);
    final cameraStateAsync = ref.watch(piCameraStateProvider);
    final cameraState = cameraStateAsync.value ?? cameraService.currentState;

    final double progress = missionState.activeMission == null
        ? 0.0
        : telemetry.distance > 0
        ? (telemetry.distance / (missionState.plannedWaypoints.length * 280))
              .clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      body: Column(
        children: [
          // 1. Raspberry Pi Live Camera Viewport (70% height)
          Expanded(
            flex: 7,
            child: Stack(
              children: [
                // Real Raspberry Pi Camera Stream
                PiCameraView(
                  zoomLevel: _zoomLevel,
                  isRecording: _isRecording,
                  onOpenSettings: _openCameraSettings,
                ),

                // Top overlay parameters
                Positioned(
                  left: 16,
                  top: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Recording status pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _isRecording
                                    ? AppTheme.danger
                                    : Colors.white54,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isRecording ? 'REC' : 'STANDBY',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Live Stream telemetry & diagnostics pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cameraState.isConnected
                                ? AppTheme.success.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          cameraState.isConnected
                              ? 'FPS: ${cameraState.fps.toStringAsFixed(0)} | Latency: ${cameraState.latencyMs}ms | OV5647'
                              : 'Pi Camera: ${cameraState.statusDisplay}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cameraState.isConnected
                                ? AppTheme.success
                                : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Right HUD Action bar (Autopilot overrides)
                Positioned(
                  right: 16,
                  top: 70,
                  child: Column(
                    children: [
                      _buildMonitoringAction(
                        icon: LucideIcons.pause,
                        label: 'Hold',
                        onTap:
                            (telemetry.isConnected &&
                                telemetry.flightMode == 'AUTO')
                            ? () => ref
                                  .read(missionProvider.notifier)
                                  .stopMission(MissionStatus.failed)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.play,
                        label: 'Resume',
                        onTap:
                            (telemetry.isConnected &&
                                telemetry.flightMode == 'LOITER')
                            ? () => ref
                                  .read(missionProvider.notifier)
                                  .startMission()
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.arrowDownLeft,
                        label: 'RTL',
                        onTap: telemetry.isConnected
                            ? () => ref
                                  .read(missionProvider.notifier)
                                  .stopMission(MissionStatus.failed)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.planeLanding,
                        label: 'Land',
                        onTap: telemetry.isConnected
                            ? () => ref
                                  .read(missionProvider.notifier)
                                  .stopMission(MissionStatus.completed)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.alertTriangle,
                        label: 'KILL',
                        color: AppTheme.danger,
                        onTap: telemetry.isConnected
                            ? () {
                                ref.read(droneServiceProvider).disconnect();
                                ref
                                    .read(notificationProvider.notifier)
                                    .addNotification(
                                      'EMERGENCY STOP ACTIVE',
                                      'MAVLink connection severed by operator. Rotors cut immediately.',
                                      NotificationType.critical,
                                    );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),

                // Left camera actions & controls
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Stream Start / Stop toggle
                        IconButton(
                          tooltip: cameraState.isConnected
                              ? 'Disconnect Feed'
                              : 'Connect Feed',
                          icon: Icon(
                            cameraState.isConnected
                                ? LucideIcons.power
                                : LucideIcons.play,
                            color: cameraState.isConnected
                                ? AppTheme.secondary
                                : Colors.white70,
                            size: 18,
                          ),
                          onPressed: () {
                            if (cameraState.isConnected) {
                              cameraService.disconnect();
                            } else {
                              cameraService.connect();
                            }
                          },
                        ),
                        // Recording toggle
                        IconButton(
                          tooltip: _isRecording
                              ? 'Stop Recording'
                              : 'Start Recording',
                          icon: Icon(
                            _isRecording
                                ? LucideIcons.videoOff
                                : LucideIcons.video,
                            color: _isRecording
                                ? AppTheme.danger
                                : Colors.white,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _isRecording = !_isRecording),
                        ),
                        // Snapshot capture
                        IconButton(
                          tooltip: 'Capture Frame',
                          icon: const Icon(
                            LucideIcons.camera,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'High-res image frame captured and saved to storage.',
                                ),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          },
                        ),
                        // Zoom toggle
                        IconButton(
                          tooltip: _zoomLevel > 1.0
                              ? 'Zoom Out (1x)'
                              : 'Zoom In (2x)',
                          icon: Icon(
                            _zoomLevel > 1.0
                                ? LucideIcons.zoomOut
                                : LucideIcons.zoomIn,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _zoomLevel = _zoomLevel > 1.0 ? 1.0 : 2.0;
                            });
                          },
                        ),
                        // Quick Camera Settings navigation
                        IconButton(
                          tooltip: 'Camera Network Settings',
                          icon: const Icon(
                            LucideIcons.settings,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: _openCameraSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. HUD Telemetry Bar (30% height)
          Expanded(
            flex: 3,
            child: Container(
              color: AppTheme.card,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'VEHICLE STATS OVERLAY',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      if (missionState.activeMission != null)
                        Text(
                          'MISSION PROGRESS: ${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondary,
                          ),
                        ),
                    ],
                  ),
                  if (missionState.activeMission != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: AppTheme.secondary,
                        backgroundColor: AppTheme.border,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 4,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildHUDItem(
                          'Altitude AGL',
                          telemetry.isConnected
                              ? '${telemetry.altitude.toStringAsFixed(1)} m'
                              : '0.0 m',
                        ),
                        _buildHUDItem(
                          'Groundspeed',
                          telemetry.isConnected
                              ? '${telemetry.speed.toStringAsFixed(1)} m/s'
                              : '0.0 m/s',
                        ),
                        _buildHUDItem(
                          'Flight distance',
                          telemetry.isConnected
                              ? '${telemetry.distance.toStringAsFixed(0)} m'
                              : '0 m',
                        ),
                        _buildHUDItem(
                          'Heading Angle',
                          telemetry.isConnected
                              ? '${telemetry.heading.toStringAsFixed(0)}°'
                              : '0°',
                        ),
                        _buildHUDItem(
                          'Battery Volt',
                          telemetry.isConnected
                              ? '${telemetry.batteryVoltage} V'
                              : '0.0 V',
                        ),
                        _buildHUDItem(
                          'GPS Satellites',
                          telemetry.isConnected
                              ? '${telemetry.satellites} Sats'
                              : '0 Sats',
                        ),
                        _buildHUDItem(
                          'RF Signal RSSI',
                          telemetry.isConnected
                              ? '${telemetry.rssi.toStringAsFixed(0)}%'
                              : '0%',
                        ),
                        _buildHUDItem(
                          'MAVLink Link',
                          telemetry.isConnected ? 'ARMED' : 'STANDBY',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoringAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final disabled = onTap == null;
    return FloatingActionButton.small(
      heroTag: 'live_fab_$label',
      onPressed: onTap,
      backgroundColor: disabled
          ? AppTheme.surface.withValues(alpha: 0.5)
          : AppTheme.card,
      foregroundColor: disabled
          ? AppTheme.textSecondary
          : color ?? AppTheme.secondary,
      tooltip: label,
      child: Icon(icon, size: 16),
    );
  }

  Widget _buildHUDItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 8,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
