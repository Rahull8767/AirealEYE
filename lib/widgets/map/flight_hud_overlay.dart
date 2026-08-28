import 'package:flutter/material.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

/// Tactical HUD Overlay card showing link state, GPS satellite lock, and vehicle stats
class FlightHudOverlayWidget extends StatelessWidget {
  final DroneTelemetry telemetry;
  final int waypointCount;
  final double trackDistanceMeters;

  const FlightHudOverlayWidget({
    super.key,
    required this.telemetry,
    this.waypointCount = 0,
    this.trackDistanceMeters = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool isConnected = telemetry.isConnected;

    return GlassPanel(
      width: 220,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LIVE TELEMETRY HUD',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? AppTheme.success : AppTheme.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildSpecRow('MAVLink Link', isConnected ? 'CONNECTED' : 'OFFLINE',
              isConnected ? AppTheme.success : AppTheme.danger),
          _buildSpecRow('Flight Mode', telemetry.flightMode, AppTheme.secondary),
          _buildSpecRow('Motors', telemetry.armed ? 'ARMED' : 'DISARMED',
              telemetry.armed ? AppTheme.warning : AppTheme.textSecondary),
          _buildSpecRow('Altitude AGL', telemetry.altitudeDisplay, AppTheme.textPrimary),
          _buildSpecRow('Ground Speed', telemetry.speedDisplay, AppTheme.textPrimary),
          _buildSpecRow('GPS Fix', telemetry.satellitesDisplay,
              telemetry.satellites >= 6 ? AppTheme.success : AppTheme.warning),
          if (trackDistanceMeters > 0)
            _buildSpecRow('Track Dist', '${(trackDistanceMeters / 1000).toStringAsFixed(2)} km',
                AppTheme.textSecondary),
          if (waypointCount > 0)
            _buildSpecRow('Target WP', 'WP ${telemetry.currentWaypoint} / $waypointCount',
                AppTheme.primary),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          Text(
            value,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
