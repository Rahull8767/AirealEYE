import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/models/notification.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/evidence_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/providers/video_recording_provider.dart';
import 'package:aerial_eye/screens/camera_connection_screen.dart';
import 'package:aerial_eye/screens/gallery_screen.dart';
import 'package:aerial_eye/screens/video_recordings_screen.dart';
import 'package:aerial_eye/services/detection_storage_service.dart';
import 'package:aerial_eye/services/evidence_storage_service.dart';
import 'package:aerial_eye/services/video_recording_service.dart';
import 'package:aerial_eye/widgets/camera/pi_camera_view.dart';

class LiveMonitoringScreen extends ConsumerStatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  ConsumerState<LiveMonitoringScreen> createState() =>
      _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends ConsumerState<LiveMonitoringScreen> {
  double _zoomLevel = 1.0;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _handleCapturePhoto() async {
    if (_isCapturing) return; // Prevent duplicate rapid requests
    setState(() => _isCapturing = true);

    final cameraService = ref.read(piCameraServiceProvider);
    final telemetry =
        ref.read(droneTelemetryProvider).value ?? DroneTelemetry.initial();
    final missionState = ref.read(missionProvider);
    final liveDetections = ref
        .read(realDetectionServiceProvider)
        .currentLiveDetections;

    try {
      final frame = cameraService.latestFrame;
      if (frame == null || frame.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to capture: Camera stream is offline or not receiving frames.',
              ),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }

      // Identify active YOLO detection in frame if present
      DetectionType? detType;
      double? confidence;
      List<double>? boundingBox;
      String severity = 'Low';

      if (liveDetections.isNotEmpty) {
        final primary = liveDetections.first;
        detType = primary.type;
        confidence = primary.confidence;
        boundingBox = primary.boundingBox;
        if (detType == DetectionType.pothole) {
          severity = primary.confidence >= 0.85 ? 'Critical' : 'High';
        } else if (detType == DetectionType.animal) {
          severity = 'High';
        } else if (detType == DetectionType.roadCrack) {
          severity = 'Medium';
        }
      }

      final hasValidGps =
          telemetry.isConnected &&
          telemetry.isGpsValid &&
          telemetry.latitude != 0.0;
      final missionId = missionState.activeMission?.id ?? 'MANUAL_INSPECTION';

      // 1. Save to EvidenceStorageService
      final evidence = await EvidenceStorageService.savePhoto(
        bytes: frame,
        missionId: missionId,
        detectionType: detType,
        confidence: confidence,
        hasValidGps: hasValidGps,
        latitude: hasValidGps ? telemetry.latitude : null,
        longitude: hasValidGps ? telemetry.longitude : null,
        altitude: telemetry.isConnected ? telemetry.altitude : null,
        flightMode: telemetry.isConnected ? telemetry.flightMode : null,
        isSimulated: false,
      );

      // 2. Also register in DetectionStorageService & detectionProvider
      final detectionRecord = AiDetection(
        id: evidence.id,
        missionId: missionId,
        type: detType ?? DetectionType.obstacle,
        confidence: confidence ?? 1.0,
        timestamp: evidence.timestamp,
        latitude: hasValidGps ? telemetry.latitude : 0.0,
        longitude: hasValidGps ? telemetry.longitude : 0.0,
        altitude: telemetry.isConnected ? telemetry.altitude : 0.0,
        boundingBox: boundingBox,
        severity: severity,
        imagePath: evidence.filePath,
        isSimulated: false,
        sequenceNumber: 0,
      );

      await DetectionStorageService.saveDetection(
        detection: detectionRecord,
        imageBytes: frame,
      );

      ref.read(evidenceProvider.notifier).addEvidence(evidence);
      ref
          .read(detectionProvider.notifier)
          .addDetectionDirectly(detectionRecord);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Photo saved to device: ${evidence.id}.jpg'),
                ),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GalleryScreen()),
                    );
                  },
                  child: const Text(
                    'VIEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save photo: ${e.toString()}'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _handleRecordingToggle() async {
    final recordingService = ref.read(videoRecordingServiceProvider);
    final cameraService = ref.read(piCameraServiceProvider);
    final telemetry =
        ref.read(droneTelemetryProvider).value ?? DroneTelemetry.initial();
    final missionState = ref.read(missionProvider);

    if (recordingService.isRecording) {
      // Stop recording
      final hasValidGps =
          telemetry.isConnected &&
          telemetry.isGpsValid &&
          telemetry.latitude != 0.0;
      final saved = await recordingService.stopRecording(
        baseUrl: cameraService.config.baseUrl,
        missionId: missionState.activeMission?.id ?? 'MANUAL_INSPECTION',
        hasValidGps: hasValidGps,
        latitude: hasValidGps ? telemetry.latitude : null,
        longitude: hasValidGps ? telemetry.longitude : null,
        altitude: telemetry.isConnected ? telemetry.altitude : null,
        flightMode: telemetry.isConnected ? telemetry.flightMode : null,
        fallbackLatestFrame: cameraService.latestFrame,
      );

      if (saved != null) {
        ref.read(evidenceProvider.notifier).addEvidence(saved);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    LucideIcons.checkCircle,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recording saved successfully (${saved.formattedDuration}, ${saved.formattedSize})',
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VideoRecordingsScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'LIBRARY',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.success,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } else {
      // Start recording
      final hasValidGps =
          telemetry.isConnected &&
          telemetry.isGpsValid &&
          telemetry.latitude != 0.0;
      await recordingService.startRecording(
        baseUrl: cameraService.config.baseUrl,
        missionId: missionState.activeMission?.id ?? 'MANUAL_INSPECTION',
        hasValidGps: hasValidGps,
        latitude: hasValidGps ? telemetry.latitude : null,
        longitude: hasValidGps ? telemetry.longitude : null,
        altitude: telemetry.isConnected ? telemetry.altitude : null,
        flightMode: telemetry.isConnected ? telemetry.flightMode : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final missionState = ref.watch(missionProvider);
    final cameraService = ref.watch(piCameraServiceProvider);
    final cameraStateAsync = ref.watch(piCameraStateProvider);
    final cameraState = cameraStateAsync.value ?? cameraService.currentState;
    final recordingSnapshotAsync = ref.watch(videoRecordingSnapshotProvider);
    final recordingSnapshot =
        recordingSnapshotAsync.value ??
        ref.watch(videoRecordingServiceProvider).currentSnapshot;

    final double progress = missionState.activeMission == null
        ? 0.0
        : telemetry.distance > 0
        ? (telemetry.distance / (missionState.plannedWaypoints.length * 280))
              .clamp(0.0, 1.0)
        : 0.0;

    final isRecording = recordingSnapshot.state.isActive;
    final isTransitioning = recordingSnapshot.state.isTransitioning;

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
                  isRecording: isRecording,
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
                      // Recording status pill with live duration
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isRecording
                                ? AppTheme.danger
                                : Colors.white12,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isRecording
                                    ? AppTheme.danger
                                    : isTransitioning
                                    ? AppTheme.warning
                                    : Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isRecording
                                  ? 'REC ${recordingSnapshot.formattedDuration}'
                                  : isTransitioning
                                  ? 'PROCESSING...'
                                  : 'STANDBY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isRecording
                                    ? AppTheme.danger
                                    : Colors.white,
                                fontFamily: isRecording ? 'monospace' : null,
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
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
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

                        // Video Recording Toggle Button (Requirement 4)
                        IconButton(
                          tooltip: isRecording
                              ? 'Stop Recording'
                              : 'Start Recording',
                          icon: isTransitioning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.warning,
                                  ),
                                )
                              : Icon(
                                  isRecording
                                      ? LucideIcons.stopCircle
                                      : LucideIcons.video,
                                  color: isRecording
                                      ? AppTheme.danger
                                      : Colors.white,
                                  size: 19,
                                ),
                          onPressed: isTransitioning
                              ? null
                              : _handleRecordingToggle,
                        ),

                        // Snapshot Capture Button (Requirement 3)
                        IconButton(
                          tooltip: 'Capture Photo',
                          icon: _isCapturing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.secondary,
                                  ),
                                )
                              : const Icon(
                                  LucideIcons.camera,
                                  color: Colors.white,
                                  size: 18,
                                ),
                          onPressed: _isCapturing ? null : _handleCapturePhoto,
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

                        // Quick Navigation to Video Library
                        IconButton(
                          tooltip: 'Open Video Library',
                          icon: const Icon(
                            LucideIcons.film,
                            color: Colors.white70,
                            size: 18,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VideoRecordingsScreen(),
                              ),
                            );
                          },
                        ),

                        // Quick Camera Settings navigation
                        IconButton(
                          tooltip: 'Camera Network Settings',
                          icon: const Icon(
                            LucideIcons.settings,
                            color: Colors.white70,
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
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'Groundspeed',
                          telemetry.isConnected
                              ? '${telemetry.speed.toStringAsFixed(1)} m/s'
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'Flight distance',
                          telemetry.isConnected
                              ? '${telemetry.distance.toStringAsFixed(0)} m'
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'Heading Angle',
                          telemetry.isConnected
                              ? '${telemetry.heading.toStringAsFixed(0)}°'
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'Battery Volt',
                          telemetry.isConnected && telemetry.batteryVoltage > 0
                              ? '${telemetry.batteryVoltage} V'
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'GPS Satellites',
                          telemetry.isConnected
                              ? '${telemetry.satellites} Sats'
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'RF Signal RSSI',
                          telemetry.isConnected
                              ? '${telemetry.rssi.toStringAsFixed(0)}%'
                              : 'Unavailable',
                        ),
                        _buildHUDItem(
                          'MAVLink Link',
                          telemetry.isConnected
                              ? (telemetry.isArmed ? 'ARMED' : 'DISARMED')
                              : 'OFFLINE',
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
