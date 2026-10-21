import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/waypoint.dart';

/// Interactive Waypoint Marker with active state animation & configuration trigger
class WaypointMarkerWidget extends StatelessWidget {
  final Waypoint waypoint;
  final bool isActive;
  final VoidCallback? onTap;

  const WaypointMarkerWidget({
    super.key,
    required this.waypoint,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double size = isActive ? 34.0 : 28.0;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: isActive ? Colors.amber : AppTheme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? Colors.white : Colors.white70,
                width: isActive ? 2.5 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isActive
                      ? Colors.amber.withValues(alpha: 0.5)
                      : Colors.black45,
                  blurRadius: isActive ? 8 : 4,
                  spreadRadius: isActive ? 2 : 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${waypoint.id}',
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: isActive ? 13 : 11,
                ),
              ),
            ),
          ),
          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Home Position Marker
class HomeMarkerWidget extends StatelessWidget {
  final VoidCallback? onTap;

  const HomeMarkerWidget({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.success,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 6, spreadRadius: 1),
          ],
        ),
        child: const Icon(LucideIcons.home, color: Colors.white, size: 18),
      ),
    );
  }
}
