import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Distinctive glowing blue marker representing the user's physical phone location
class UserLocationMarkerWidget extends StatelessWidget {
  final double? accuracyMeters;
  final double? heading;
  final VoidCallback? onTap;

  const UserLocationMarkerWidget({
    super.key,
    this.accuracyMeters,
    this.heading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer Soft Blue Accuracy Halo
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.blueAccent.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
          ),

          // Inner Solid Blue User Beacon with White Ring
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.blueAccent.shade400,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                LucideIcons.user,
                color: Colors.white,
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
