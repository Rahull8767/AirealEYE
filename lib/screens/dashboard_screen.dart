import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/auth_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/evidence_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/providers/report_provider.dart';
import 'package:aerial_eye/screens/ai_detections_screen.dart';
import 'package:aerial_eye/screens/connect_screen.dart';
import 'package:aerial_eye/screens/gallery_screen.dart';
import 'package:aerial_eye/screens/mission_history_screen.dart';
import 'package:aerial_eye/screens/reports_screen.dart';
import 'package:aerial_eye/screens/video_recordings_screen.dart';
import 'package:aerial_eye/widgets/animated_button.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/telemetry_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final missionState = ref.watch(missionProvider);
    final detectionState = ref.watch(detectionProvider);
    final detections = detectionState.detections;
    final notifications = ref.watch(notificationProvider);
    final cameraService = ref.watch(piCameraServiceProvider);
    final cameraStateAsync = ref.watch(piCameraStateProvider);
    final cameraState = cameraStateAsync.value ?? cameraService.currentState;
    final evidenceState = ref.watch(evidenceProvider);
    final reports = ref.watch(reportProvider);

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth < 600
        ? 2
        : screenWidth < 960
        ? 3
        : 4;

    final String localTime =
        '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    final String greetingName = authState.firstName;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(evidenceProvider.notifier).loadEvidence();
          await ref.read(reportProvider.notifier).loadReports();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Personalized Welcome Card
              _buildWelcomeCard(
                context,
                greetingName,
                localTime,
                telemetry,
                cameraState,
              ),
              const SizedBox(height: 24),

              // 2. Summary & Evidence Repository Cards (Requirement 9)
              Text(
                'INSPECTION EVIDENCE & REPOSITORY',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              _buildEvidenceSummaryGrid(
                context,
                ref,
                evidenceState,
                detections,
                reports,
              ),
              const SizedBox(height: 24),

              // 3. Truthful Telemetry Grid (Requirement 2)
              Text(
                'LIVE TELEMETRY & MEASUREMENTS',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  // Autopilot Status
                  TelemetryCard(
                    icon: LucideIcons.planeTakeoff,
                    title: 'Autopilot Status',
                    value: telemetry.isConnected
                        ? (telemetry.isStale
                              ? '${telemetry.flightMode} (STALE)'
                              : telemetry.flightMode)
                        : 'DISCONNECTED',
                    statusColor: telemetry.isConnected
                        ? (telemetry.isStale
                              ? AppTheme.warning
                              : AppTheme.success)
                        : AppTheme.danger,
                    subWidget: Text(
                      telemetry.isConnected
                          ? (telemetry.isArmed
                                ? 'Motors Armed / Ready'
                                : 'Motors Disarmed / Standby')
                          : 'Check Pixhawk telemetry port',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // Battery Cell
                  TelemetryCard(
                    icon: LucideIcons.batteryCharging,
                    title: 'Battery Cell',
                    value: telemetry.isConnected && telemetry.batteryVoltage > 0
                        ? '${(telemetry.batteryPercent * 100).toStringAsFixed(0)}% (${telemetry.batteryVoltage}V)'
                        : 'Unavailable',
                    statusColor:
                        telemetry.isConnected && telemetry.batteryVoltage > 0
                        ? (telemetry.batteryPercent > 0.3
                              ? AppTheme.success
                              : AppTheme.danger)
                        : AppTheme.textSecondary,
                    subWidget: Text(
                      telemetry.isConnected && telemetry.batteryVoltage > 0
                          ? 'Cell pack: ${telemetry.batteryVoltage}V'
                          : 'Battery sensor unlinked',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // GPS Satellites
                  TelemetryCard(
                    icon: LucideIcons.satellite,
                    title: 'GPS Satellites',
                    value: telemetry.isConnected
                        ? '${telemetry.satellites} Sats'
                        : 'Unavailable',
                    statusColor:
                        telemetry.isConnected && telemetry.satellites >= 6
                        ? AppTheme.success
                        : telemetry.isConnected
                        ? AppTheme.warning
                        : AppTheme.textSecondary,
                    subWidget: Text(
                      telemetry.isConnected
                          ? (telemetry.isGpsValid
                                ? '3D GPS Fix Locked'
                                : 'Searching for satellites...')
                          : 'GPS receiver offline',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // Altitude (AGL)
                  TelemetryCard(
                    icon: LucideIcons.arrowUpRight,
                    title: 'Altitude (AGL)',
                    value: telemetry.isConnected
                        ? '${telemetry.altitude.toStringAsFixed(1)} m'
                        : 'Unavailable',
                    statusColor: telemetry.isConnected
                        ? AppTheme.secondary
                        : AppTheme.textSecondary,
                    subWidget: Text(
                      telemetry.isConnected
                          ? 'Relative: ${telemetry.relativeAltitude.toStringAsFixed(1)} m'
                          : 'Barometer offline',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // Ground Speed
                  TelemetryCard(
                    icon: LucideIcons.gauge,
                    title: 'Ground Speed',
                    value: telemetry.isConnected
                        ? '${telemetry.speed.toStringAsFixed(1)} m/s'
                        : 'Unavailable',
                    statusColor: telemetry.isConnected
                        ? AppTheme.warning
                        : AppTheme.textSecondary,
                    subWidget: Text(
                      telemetry.isConnected
                          ? 'Climb: ${telemetry.climbRate.toStringAsFixed(1)} m/s'
                          : 'Speed sensor offline',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // AI Detections
                  TelemetryCard(
                    icon: LucideIcons.scanFace,
                    title: 'AI Detections',
                    value: '${detections.length} Defects',
                    statusColor: detections.isNotEmpty
                        ? AppTheme.warning
                        : AppTheme.success,
                    subWidget: Text(
                      detections.isNotEmpty
                          ? '${detections.where((d) => d.severity == 'Critical').length} critical issues'
                          : 'Zero road defects logged',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // Evidence Storage
                  TelemetryCard(
                    icon: LucideIcons.hardDrive,
                    title: 'Evidence Storage',
                    value: '${evidenceState.items.length} Files',
                    statusColor: AppTheme.secondary,
                    subWidget: Text(
                      '${evidenceState.photos.length} photos, ${evidenceState.videos.length} videos',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  // Camera Payload
                  TelemetryCard(
                    icon: LucideIcons.camera,
                    title: 'Camera Payload',
                    value: cameraState.isConnected
                        ? 'STREAMING'
                        : cameraState.statusDisplay.toUpperCase(),
                    statusColor: cameraState.isConnected
                        ? AppTheme.success
                        : AppTheme.danger,
                    subWidget: Text(
                      cameraState.isConnected
                          ? 'FPS: ${cameraState.fps.toStringAsFixed(0)} | ${cameraState.latencyMs}ms'
                          : (cameraState.errorMessage ??
                                'Check IP & Port in Settings'),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Quick Actions
              Text(
                'QUICK OPERATIONS CONTROL',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.link,
                    'MAVLink Link',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ConnectScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.scanFace,
                    'AI Detection Feed',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AiDetectionsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.image,
                    'Photos & Evidence',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GalleryScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.film,
                    'Video Recordings',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VideoRecordingsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.fileBarChart,
                    'Inspection Reports',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.history,
                    'Mission Logs',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MissionHistoryScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 5. Recent Missions
              Text(
                'RECENT INSPECTION MISSIONS',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              if (missionState.missionHistory.isEmpty)
                const Text(
                  'No historical missions loaded.',
                  style: TextStyle(color: AppTheme.textSecondary),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: missionState.missionHistory.take(3).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final m = missionState.missionHistory[idx];
                    return GlassPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: m.status == MissionStatus.completed
                                  ? AppTheme.success.withValues(alpha: 0.12)
                                  : AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              m.status == MissionStatus.completed
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.alertTriangle,
                              color: m.status == MissionStatus.completed
                                  ? AppTheme.success
                                  : AppTheme.danger,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${m.distance.toStringAsFixed(1)} km | ${m.duration.inMinutes} mins | ${m.date.month}/${m.date.day}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(
    BuildContext context,
    String name,
    String localTime,
    DroneTelemetry telemetry,
    CameraStreamState cameraState,
  ) {
    final bool isOnline = telemetry.isConnected || cameraState.isConnected;
    final String statusText = telemetry.isConnected && cameraState.isConnected
        ? 'SYSTEMS READY'
        : telemetry.isConnected
        ? 'MAVLINK ONLY'
        : cameraState.isConnected
        ? 'CAMERA ONLY'
        : 'SYSTEM OFFLINE';

    final Color statusColor = telemetry.isConnected && cameraState.isConnected
        ? AppTheme.success
        : isOnline
        ? AppTheme.warning
        : AppTheme.danger;

    return GlassPanel(
      padding: const EdgeInsets.all(20),
      color: AppTheme.primary.withValues(alpha: 0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $name 👋',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ready for your next inspection?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                localTime,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceSummaryGrid(
    BuildContext context,
    WidgetRef ref,
    EvidenceState evState,
    List<AiDetection> detections,
    List<dynamic> reports,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final int count = screenWidth < 600 ? 2 : 4;

    return GridView.count(
      crossAxisCount: count,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.4,
      children: [
        // 1. Captured Photos
        _buildRepoCard(
          context,
          icon: LucideIcons.camera,
          title: 'Captured Photos',
          count: '${evState.photos.length}',
          subtitle: 'Tap to view gallery',
          color: const Color(0xFF00D2FF),
          onTap: () {
            ref
                .read(evidenceProvider.notifier)
                .setFilterMediaType(EvidenceMediaType.photo);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GalleryScreen()),
            );
          },
        ),

        // 2. Detections by Class
        _buildRepoCard(
          context,
          icon: LucideIcons.scanFace,
          title: 'Defects Logged',
          count: '${detections.length}',
          subtitle: 'Person, Animal, Pothole, Crack, Waste',
          color: const Color(0xFFEF4444),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiDetectionsScreen()),
            );
          },
        ),

        // 3. Stored Video Recordings
        _buildRepoCard(
          context,
          icon: LucideIcons.film,
          title: 'Video Library',
          count: '${evState.videos.length}',
          subtitle: 'Playback & sharing',
          color: const Color(0xFFEC4899),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VideoRecordingsScreen()),
            );
          },
        ),

        // 4. Inspection Reports
        _buildRepoCard(
          context,
          icon: LucideIcons.fileBarChart,
          title: 'Inspection Reports',
          count: '${reports.length}',
          subtitle: 'Generate & share PDF',
          color: const Color(0xFF10B981),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRepoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String count,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: color),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return AnimatedButton(
      color: AppTheme.surface,
      onTap: onTap,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.secondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
