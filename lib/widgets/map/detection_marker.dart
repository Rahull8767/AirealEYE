import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/models/detection.dart';

/// Anomaly Defect Marker on the map with category icon and severity color
class DetectionMarkerWidget extends StatelessWidget {
  final AiDetection detection;
  final VoidCallback? onTap;

  const DetectionMarkerWidget({super.key, required this.detection, this.onTap});

  IconData _iconForType(DetectionType type) {
    switch (type) {
      case DetectionType.person:
        return LucideIcons.user;
      case DetectionType.animal:
        return LucideIcons.dog;
      case DetectionType.pothole:
        return LucideIcons.circle;
      case DetectionType.waste:
      case DetectionType.garbage:
        return LucideIcons.trash2;
      case DetectionType.roadCrack:
        return LucideIcons.gitCommit;
      case DetectionType.waterLogging:
        return LucideIcons.droplets;
      case DetectionType.obstacle:
        return LucideIcons.construction;
      case DetectionType.brokenRoadSign:
        return LucideIcons.alertOctagon;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: detection.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.0),
          boxShadow: [
            BoxShadow(
              color: detection.color.withValues(alpha: 0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          _iconForType(detection.type),
          color: Colors.white,
          size: 15,
        ),
      ),
    );
  }
}
