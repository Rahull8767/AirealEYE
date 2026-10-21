import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/providers/map_provider.dart';
import 'package:aerial_eye/providers/flight_track_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

/// Floating Glassmorphic Map Control Toolbar
class MapControlsWidget extends ConsumerWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecenterDrone;
  final VoidCallback? onMyLocation;
  final VoidCallback? onToggleSurvey;
  final bool isSurveyActive;

  const MapControlsWidget({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecenterDrone,
    this.onMyLocation,
    this.onToggleSurvey,
    this.isSurveyActive = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapState = ref.watch(mapProvider);
    final flightTrack = ref.watch(flightTrackProvider);

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom In
          _buildBtn(
            icon: LucideIcons.plus,
            tooltip: 'Zoom In',
            onTap: onZoomIn,
          ),
          const SizedBox(height: 4),

          // Zoom Out
          _buildBtn(
            icon: LucideIcons.minus,
            tooltip: 'Zoom Out',
            onTap: onZoomOut,
          ),
          const Divider(color: AppTheme.border, height: 12),

          // My Location (Phone GPS)
          if (onMyLocation != null) ...[
            _buildBtn(
              icon: LucideIcons.locate,
              tooltip: 'My Location (Phone GPS)',
              color: Colors.blueAccent,
              onTap: onMyLocation!,
            ),
            const SizedBox(height: 4),
          ],

          // Recenter on Drone (MAVLink Telemetry GPS)
          _buildBtn(
            icon: LucideIcons.crosshair,
            tooltip: 'Center on Drone',
            color: AppTheme.secondary,
            onTap: onRecenterDrone,
          ),
          const SizedBox(height: 4),

          // Follow Drone Toggle
          _buildBtn(
            icon: LucideIcons.compass,
            tooltip: mapState.followDrone
                ? 'Follow Drone (ON)'
                : 'Follow Drone (OFF)',
            isActive: mapState.followDrone,
            activeColor: AppTheme.secondary,
            onTap: () => ref.read(mapProvider.notifier).toggleFollowDrone(),
          ),
          const Divider(color: AppTheme.border, height: 12),

          // Survey Area Drawing Mode Toggle (if callback provided)
          if (onToggleSurvey != null) ...[
            _buildBtn(
              icon: LucideIcons.shapes,
              tooltip: isSurveyActive ? 'Exit Survey Mode' : 'Draw Survey Area',
              isActive: isSurveyActive,
              activeColor: AppTheme.warning,
              onTap: onToggleSurvey!,
            ),
            const SizedBox(height: 4),
          ],

          // Clear / Reset Flight Trail
          if (flightTrack.breadcrumbs.isNotEmpty) ...[
            _buildBtn(
              icon: LucideIcons.rotateCcw,
              tooltip:
                  'Clear Flight Trail (${flightTrack.breadcrumbs.length} pts)',
              color: AppTheme.danger,
              onTap: () {
                ref.read(flightTrackProvider.notifier).clearTrack();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Flight track trail reset.'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
          ],

          // Fullscreen Toggle
          _buildBtn(
            icon: mapState.isFullscreen
                ? LucideIcons.minimize2
                : LucideIcons.maximize2,
            tooltip: mapState.isFullscreen
                ? 'Exit Fullscreen'
                : 'Fullscreen Map',
            isActive: mapState.isFullscreen,
            onTap: () => ref.read(mapProvider.notifier).toggleFullscreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
    bool isActive = false,
    Color? activeColor,
  }) {
    final effectiveColor = isActive
        ? (activeColor ?? AppTheme.secondary)
        : (color ?? AppTheme.textPrimary);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive
                ? (activeColor ?? AppTheme.secondary).withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: effectiveColor),
        ),
      ),
    );
  }
}
