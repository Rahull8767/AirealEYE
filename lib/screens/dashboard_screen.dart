import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/notification.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/providers/auth_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/telemetry_card.dart';
import 'package:aerial_eye/widgets/mini_chart.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

// Standalone Screens for Routing
import 'package:aerial_eye/screens/connect_screen.dart';
import 'package:aerial_eye/screens/ai_detections_screen.dart';
import 'package:aerial_eye/screens/mission_history_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final missionState = ref.watch(missionProvider);
    final detections = ref.watch(detectionProvider).detections;
    final notifications = ref.watch(notificationProvider);

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth < 600
        ? 2
        : screenWidth < 960
        ? 3
        : 4;

    final String localTime =
        '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    final String welcomeName = authState.name?.split(' ').last ?? 'Operator';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // Simply triggers a rebuilding callback
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Welcome Card
              _buildWelcomeCard(context, welcomeName, localTime, missionState),
              const SizedBox(height: 24),

              // 2. Telemetry Grid (Responsive)
              Text(
                'LIVE TELEMETRY',
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
                  TelemetryCard(
                    icon: LucideIcons.planeTakeoff,
                    title: 'Autopilot Status',
                    value: telemetry.isConnected
                        ? telemetry.flightMode
                        : 'DISCONNECTED',
                    statusColor: telemetry.isConnected
                        ? AppTheme.success
                        : AppTheme.danger,
                    subWidget: Text(
                      telemetry.isConnected
                          ? 'MAVLink arm checklist OK'
                          : 'Check Pixhawk power & USB/IP',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TelemetryCard(
                    icon: LucideIcons.batteryCharging,
                    title: 'Battery Cell',
                    value: telemetry.isConnected
                        ? '${(telemetry.batteryPercent * 100).toStringAsFixed(0)}% (${telemetry.batteryVoltage}V)'
                        : '0.0V',
                    statusColor: telemetry.isConnected
                        ? (telemetry.batteryPercent > 0.3
                              ? AppTheme.success
                              : AppTheme.danger)
                        : AppTheme.textSecondary,
                    subWidget: telemetry.isConnected
                        ? MiniChart(
                            dataPoints: const [
                              16.8,
                              16.6,
                              16.3,
                              16.0,
                              15.7,
                              15.3,
                              14.8,
                            ],
                            lineColor: telemetry.batteryPercent > 0.3
                                ? AppTheme.success
                                : AppTheme.danger,
                          )
                        : null,
                  ),
                  TelemetryCard(
                    icon: LucideIcons.satellite,
                    title: 'GPS Satellites',
                    value: telemetry.isConnected
                        ? '${telemetry.satellites} Sats'
                        : 'No Signal',
                    statusColor:
                        telemetry.isConnected && telemetry.satellites >= 10
                        ? AppTheme.success
                        : telemetry.isConnected
                        ? AppTheme.warning
                        : AppTheme.danger,
                    subWidget: Text(
                      telemetry.isConnected
                          ? 'Lock type: RTK Float'
                          : 'Check GPS antenna line',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TelemetryCard(
                    icon: LucideIcons.arrowUpRight,
                    title: 'Altitude (AGL)',
                    value: telemetry.isConnected
                        ? '${telemetry.altitude.toStringAsFixed(1)} m'
                        : '0.0 m',
                    statusColor: AppTheme.secondary,
                    subWidget: telemetry.isConnected
                        ? MiniChart(
                            dataPoints: const [
                              0.0,
                              10.0,
                              20.0,
                              30.0,
                              30.0,
                              29.5,
                              30.0,
                            ],
                            lineColor: AppTheme.secondary,
                          )
                        : null,
                  ),
                  TelemetryCard(
                    icon: LucideIcons.gauge,
                    title: 'Ground Speed',
                    value: telemetry.isConnected
                        ? '${telemetry.speed.toStringAsFixed(1)} m/s'
                        : '0.0 m/s',
                    statusColor: AppTheme.warning,
                    subWidget: telemetry.isConnected
                        ? MiniChart(
                            dataPoints: const [
                              0.0,
                              2.5,
                              4.8,
                              5.0,
                              5.0,
                              4.2,
                              5.0,
                            ],
                            lineColor: AppTheme.warning,
                          )
                        : null,
                  ),
                  TelemetryCard(
                    icon: LucideIcons.scanFace,
                    title: 'AI Detections',
                    value: '${detections.length} Defects',
                    statusColor: detections.isNotEmpty
                        ? AppTheme.warning
                        : AppTheme.success,
                    subWidget: Text(
                      detections.isNotEmpty
                          ? '${detections.where((d) => d.severity == 'Critical').length} critical issues flag'
                          : 'No road defects spotted',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TelemetryCard(
                    icon: LucideIcons.hardDrive,
                    title: 'Local Disk Storage',
                    value: '14.2 GB Free',
                    statusColor: AppTheme.secondary,
                    subWidget: const Text(
                      'SD Card: 90% capacity left',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TelemetryCard(
                    icon: LucideIcons.camera,
                    title: 'Camera Payload',
                    value: telemetry.isConnected ? 'STREAMING' : 'OFFLINE',
                    statusColor: telemetry.isConnected
                        ? AppTheme.success
                        : AppTheme.danger,
                    subWidget: Text(
                      telemetry.isConnected
                          ? 'FPS: 30 | Latency: 42ms'
                          : 'Payload not ready',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 3. Quick Actions
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
                    'Connect MAVLink',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ConnectScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.scanFace,
                    'Inspect Feed',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AiDetectionsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    context,
                    LucideIcons.history,
                    'Logs History',
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MissionHistoryScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Recent Missions & Notifications (Horizontal or Side-by-Side)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RECENT INSPECTION RUNS',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (missionState.missionHistory.isEmpty)
                          const Text('No historical missions loaded.')
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: missionState.missionHistory
                                .take(3)
                                .length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
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
                                        color:
                                            m.status == MissionStatus.completed
                                            ? AppTheme.success.withOpacity(0.12)
                                            : AppTheme.danger.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        m.status == MissionStatus.completed
                                            ? LucideIcons.checkCircle
                                            : LucideIcons.alertTriangle,
                                        color:
                                            m.status == MissionStatus.completed
                                            ? AppTheme.success
                                            : AppTheme.danger,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                  if (screenWidth > 800) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RECENT SAFETY ALERTS',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: notifications.take(3).length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final n = notifications[idx];
                              return GlassPanel(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      n.type == NotificationType.critical
                                          ? LucideIcons.alertTriangle
                                          : LucideIcons.info,
                                      color: n.type == NotificationType.critical
                                          ? AppTheme.danger
                                          : AppTheme.secondary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        n.title,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
                  ],
                ],
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
    MissionPlannerState mState,
  ) {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      color: AppTheme.primary.withOpacity(0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $name',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      LucideIcons.cloudSun,
                      color: AppTheme.secondary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Clear sky • 24°C • 3.2 m/s Wind',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
              Text(
                'SYSTEM OK',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.success,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.secondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
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
