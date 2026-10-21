import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/detection.dart';

/// Modal dialog for inspecting and taking action on AI defect detections
class DetectionDetailsModal extends StatelessWidget {
  final AiDetection detection;

  const DetectionDetailsModal({super.key, required this.detection});

  static void show(BuildContext context, AiDetection detection) {
    showDialog(
      context: context,
      builder: (context) => DetectionDetailsModal(detection: detection),
    );
  }

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
    return AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header banner with defect color
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: detection.color.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Center(
              child: Icon(
                _iconForType(detection.type),
                color: detection.color,
                size: 46,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      detection.typeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    if (detection.isSimulated)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'SIMULATED',
                          style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  'Confidence',
                  '${(detection.confidence * 100).toStringAsFixed(0)}%',
                ),
                _buildInfoRow('Severity', detection.severity),
                _buildInfoRow(
                  'Altitude AGL',
                  '${detection.altitude.toStringAsFixed(1)} m',
                ),
                _buildInfoRow(
                  'Coordinates',
                  '[${detection.latitude.toStringAsFixed(5)}, ${detection.longitude.toStringAsFixed(5)}]',
                ),
                _buildInfoRow(
                  'Timestamp',
                  '${detection.timestamp.hour.toString().padLeft(2, '0')}:${detection.timestamp.minute.toString().padLeft(2, '0')}:${detection.timestamp.second.toString().padLeft(2, '0')}',
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(LucideIcons.navigation, size: 16),
                      label: const Text('Directions'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Route calculated to anomaly coordinates.',
                            ),
                          ),
                        );
                        Navigator.pop(context);
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(LucideIcons.share2, size: 16),
                      label: const Text('Export'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Anomaly details copied to clipboard.',
                            ),
                          ),
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
