import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/models/notification.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/services/mock_camera_service.dart';

class LiveMonitoringScreen extends ConsumerStatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  ConsumerState<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends ConsumerState<LiveMonitoringScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _cameraController;
  bool _isRecording = false;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    // Continuous loop for simulated camera movements
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final missionState = ref.watch(missionProvider);
    final detectionState = ref.watch(detectionProvider);

    // Map active detections to bounding boxes to draw on video overlay
    final List<SimulatedDetectionBox> activeBoxes = [];
    if (telemetry.isConnected && telemetry.flightMode == 'AUTO') {
      // Map the 3 most recent detections to simulated boxes
      final recentDetections = detectionState.detections.take(3).toList();
      for (int i = 0; i < recentDetections.length; i++) {
        final d = recentDetections[i];
        activeBoxes.add(
          SimulatedDetectionBox(
            label: d.typeLabel,
            confidence: d.confidence,
            xPercent: 0.35 + (i * 0.15),
            yPercent: 0.25 + (i * 0.12),
            width: 70,
            height: 55,
            color: d.color,
          ),
        );
      }
    }

    final double progress = missionState.activeMission == null
        ? 0.0
        : telemetry.distance > 0
            ? (telemetry.distance / (missionState.plannedWaypoints.length * 280)).clamp(0.0, 1.0)
            : 0.0;

    return Scaffold(
      body: Column(
        children: [
          // 1. Video Player Container (70% height)
          Expanded(
            flex: 7,
            child: Stack(
              children: [
                // Live camera custom canvas
                AnimatedBuilder(
                  animation: _cameraController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: DroneCameraPainter(
                        animationValue: _cameraController.value,
                        isRecording: _isRecording,
                        zoomLevel: _zoomLevel,
                        activeDetections: activeBoxes,
                      ),
                      child: Container(),
                    );
                  },
                ),

                // Top overlay parameters
                Positioned(
                  left: 16,
                  top: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Recording pill
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _isRecording ? AppTheme.danger : Colors.white54,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isRecording ? 'REC 04:12' : 'STANDBY',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // FPS / latency diagnostics
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'FPS: 30 | Latency: 42ms | Bitrate: 4.8 Mbps',
                          style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
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
                        onTap: (telemetry.isConnected && telemetry.flightMode == 'AUTO')
                            ? () => ref.read(missionProvider.notifier).stopMission(MissionStatus.failed)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.play,
                        label: 'Resume',
                        onTap: (telemetry.isConnected && telemetry.flightMode == 'LOITER')
                            ? () => ref.read(missionProvider.notifier).startMission()
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.arrowDownLeft,
                        label: 'RTL',
                        onTap: telemetry.isConnected
                            ? () => ref.read(missionProvider.notifier).stopMission(MissionStatus.failed)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _buildMonitoringAction(
                        icon: LucideIcons.planeLanding,
                        label: 'Land',
                        onTap: telemetry.isConnected
                            ? () => ref.read(missionProvider.notifier).stopMission(MissionStatus.completed)
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
                                ref.read(notificationProvider.notifier).addNotification(
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

                // Left camera actions
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isRecording ? LucideIcons.videoOff : LucideIcons.video,
                            color: _isRecording ? AppTheme.danger : Colors.white,
                          ),
                          onPressed: () => setState(() => _isRecording = !_isRecording),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.camera, color: Colors.white),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('High-res image frame captured and saved to SD Card.'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _zoomLevel > 1.0 ? LucideIcons.zoomOut : LucideIcons.zoomIn,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _zoomLevel = _zoomLevel > 1.0 ? 1.0 : 2.0;
                            });
                          },
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
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.secondary),
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
                        _buildHUDItem('Altitude AGL', telemetry.isConnected ? '${telemetry.altitude.toStringAsFixed(1)} m' : '0.0 m'),
                        _buildHUDItem('Groundspeed', telemetry.isConnected ? '${telemetry.speed.toStringAsFixed(1)} m/s' : '0.0 m/s'),
                        _buildHUDItem('Flight distance', telemetry.isConnected ? '${telemetry.distance.toStringAsFixed(0)} m' : '0 m'),
                        _buildHUDItem('Heading Angle', telemetry.isConnected ? '${telemetry.heading.toStringAsFixed(0)}°' : '0°'),
                        _buildHUDItem('Battery Volt', telemetry.isConnected ? '${telemetry.batteryVoltage} V' : '0.0 V'),
                        _buildHUDItem('GPS Satellites', telemetry.isConnected ? '${telemetry.satellites} Sats' : '0 Sats'),
                        _buildHUDItem('RF Signal RSSI', telemetry.isConnected ? '${telemetry.rssi.toStringAsFixed(0)}%' : '0%'),
                        _buildHUDItem('MAVLink Link', telemetry.isConnected ? 'ARMED' : 'STANDBY'),
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
      backgroundColor: disabled ? AppTheme.surface.withOpacity(0.5) : AppTheme.card,
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
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
