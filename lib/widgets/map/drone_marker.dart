import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/telemetry.dart';

/// Live animated Drone Marker displaying heading rotation, arming status, and altitude
class DroneMarkerWidget extends StatelessWidget {
  final DroneTelemetry telemetry;
  final VoidCallback? onTap;

  const DroneMarkerWidget({super.key, required this.telemetry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final double headingRad = telemetry.heading * (math.pi / 180.0);
    final bool isArmed = telemetry.armed;
    final bool isConnected = telemetry.isConnected;

    final Color beaconColor = !isConnected
        ? AppTheme.textSecondary
        : (isArmed ? AppTheme.danger : AppTheme.secondary);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Altitude Badge Pill
          if (telemetry.hasReceivedPosition || isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: beaconColor.withValues(alpha: 0.6),
                  width: 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '${telemetry.altitude.toStringAsFixed(1)}m',
                style: TextStyle(
                  color: beaconColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 2),

          // Directional Drone Icon with Pulse Glow Ring
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer radar aura
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: beaconColor.withValues(alpha: 0.18),
                  border: Border.all(
                    color: beaconColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
              ),

              // Rotating Drone Icon
              Transform.rotate(
                angle: headingRad,
                child: Icon(
                  LucideIcons.plane,
                  color: isArmed ? AppTheme.secondary : Colors.white,
                  size: 26,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
              ),

              // Small Center GPS Fix Beacon
              Positioned(
                bottom: 8,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: telemetry.satellites >= 6
                        ? AppTheme.success
                        : AppTheme.warning,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
