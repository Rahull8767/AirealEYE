import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/auth_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';

// Import screens (will be created in next steps)
import 'package:aerial_eye/screens/dashboard_screen.dart';
import 'package:aerial_eye/screens/mission_planner_screen.dart';
import 'package:aerial_eye/screens/live_monitoring_screen.dart';
import 'package:aerial_eye/screens/map_screen.dart';
import 'package:aerial_eye/screens/reports_screen.dart';

// Standalone Screens
import 'package:aerial_eye/screens/connect_screen.dart';
import 'package:aerial_eye/screens/camera_connection_screen.dart';
import 'package:aerial_eye/screens/ai_detections_screen.dart';
import 'package:aerial_eye/screens/mission_history_screen.dart';
import 'package:aerial_eye/screens/gallery_screen.dart';
import 'package:aerial_eye/screens/notifications_screen.dart';
import 'package:aerial_eye/screens/settings_screen.dart';

class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({super.key});

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {
  int _currentTabIndex = 0;

  final List<Widget> _tabs = [
    const DashboardScreen(),
    const MissionPlannerScreen(),
    const LiveMonitoringScreen(),
    const MapScreen(),
    const ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final authState = ref.watch(authProvider);
    final notifications = ref.watch(notificationProvider);
    final unreadNotifs = notifications.where((n) => !n.isRead).length;
    final missionState = ref.watch(missionProvider);

    // Active Mission indicator
    String missionStatusText = 'No Mission Active';
    Color missionStatusColor = AppTheme.textSecondary;
    if (missionState.activeMission != null) {
      missionStatusText = missionState.activeMission!.name;
      missionStatusColor = AppTheme.success;
    } else if (telemetry.isConnected) {
      missionStatusText = 'Drone Connected (Standby)';
      missionStatusColor = AppTheme.secondary;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(seconds: 1),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: telemetry.isConnected
                    ? AppTheme.success.withOpacity(0.12)
                    : AppTheme.danger.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.plane,
                color: telemetry.isConnected
                    ? AppTheme.success
                    : AppTheme.danger,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AerialEye',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  missionStatusText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: missionStatusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.bell, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              if (unreadNotifs > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$unreadNotifs',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primary,
            child: Text(
              authState.name != null ? authState.name![0] : 'E',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: _buildDrawer(context, authState, telemetry),
      body: IndexedStack(index: _currentTabIndex, children: _tabs),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(left: 24, right: 24, bottom: 20),
        height: 68,
        decoration: BoxDecoration(
          color: AppTheme.card.withOpacity(0.85),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(0, LucideIcons.layoutDashboard, 'Dashboard'),
              _buildBottomNavItem(1, LucideIcons.mapPin, 'Mission'),
              _buildBottomNavItem(2, LucideIcons.camera, 'Camera'),
              _buildBottomNavItem(3, LucideIcons.map, 'Map'),
              _buildBottomNavItem(4, LucideIcons.fileBarChart, 'Reports'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(int index, IconData icon, String label) {
    final isSelected = _currentTabIndex == index;
    final activeColor = AppTheme.secondary;

    return InkWell(
      onTap: () => setState(() => _currentTabIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: isSelected
            ? BoxDecoration(
                color: activeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              )
            : const BoxDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    AuthState authState,
    DroneTelemetry telemetry,
  ) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer Header
          DrawerHeader(
            decoration: const BoxDecoration(
              color: AppTheme.card,
              border: Border(
                bottom: BorderSide(color: AppTheme.border, width: 1.0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppTheme.primary,
                      child: Text(
                        authState.name != null ? authState.name![0] : 'E',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authState.name ?? 'Municipal Engineer',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            authState.role ?? 'Road Inspector',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: telemetry.isConnected
                            ? AppTheme.success
                            : AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      telemetry.isConnected
                          ? 'Pixhawk Connected (${telemetry.flightMode})'
                          : 'Pixhawk Disconnected',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildDrawerItem(LucideIcons.layoutDashboard, 'Dashboard', () {
            Navigator.pop(context);
            setState(() => _currentTabIndex = 0);
          }),
          _buildDrawerItem(LucideIcons.mapPin, 'Mission Planner', () {
            Navigator.pop(context);
            setState(() => _currentTabIndex = 1);
          }),
          _buildDrawerItem(LucideIcons.camera, 'Live Monitoring', () {
            Navigator.pop(context);
            setState(() => _currentTabIndex = 2);
          }),
          _buildDrawerItem(LucideIcons.video, 'Pi Camera Settings', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CameraConnectionScreen(),
              ),
            );
          }),
          _buildDrawerItem(LucideIcons.network, 'Hardware Connections', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ConnectScreen()),
            );
          }),
          _buildDrawerItem(LucideIcons.scanFace, 'AI Detection Feed', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AiDetectionsScreen(),
              ),
            );
          }),
          _buildDrawerItem(LucideIcons.history, 'Mission History', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MissionHistoryScreen(),
              ),
            );
          }),
          _buildDrawerItem(LucideIcons.fileBarChart, 'Reports Summary', () {
            Navigator.pop(context);
            setState(() => _currentTabIndex = 4);
          }),
          _buildDrawerItem(LucideIcons.image, 'Gallery Grid', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const GalleryScreen()),
            );
          }),
          _buildDrawerItem(LucideIcons.bell, 'Notifications Log', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          }),
          const Divider(
            color: AppTheme.border,
            thickness: 1,
            indent: 16,
            endIndent: 16,
          ),
          _buildDrawerItem(LucideIcons.settings, 'Settings', () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          }),
          _buildDrawerItem(LucideIcons.helpCircle, 'Help Desk', () {
            Navigator.pop(context);
            _showHelpDialog(context);
          }),
          _buildDrawerItem(LucideIcons.info, 'About System', () {
            Navigator.pop(context);
            _showAboutDialog(context);
          }),
          _buildDrawerItem(LucideIcons.logOut, 'Logout', () {
            ref.read(authProvider.notifier).logout();
            Navigator.pop(context);
          }, color: AppTheme.danger),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help Desk'),
        content: const Text(
          'Connect the drone via the Dashboard or Connect screen. Make sure your Pixhawk has telemetry running. For missions, tap points on the map and hit "Upload", then "Start".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About AerialEye'),
        content: const Text(
          'AerialEye Smart Road Inspection & Environmental Monitoring System v1.0.0-Beta.\n\nDesigned for municipal engineers to plan autonomous drone flights, track vehicle parameters, and log roadside defects using deep learning vision systems.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
