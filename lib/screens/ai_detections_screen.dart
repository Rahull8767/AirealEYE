import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

class AiDetectionsScreen extends ConsumerWidget {
  const AiDetectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detectionState = ref.watch(detectionProvider);
    final notifier = ref.read(detectionProvider.notifier);

    // Apply confidence filter
    var filteredList = detectionState.detections.where((d) {
      return d.confidence >= detectionState.confidenceFilter;
    }).toList();

    // Apply class type filter
    if (detectionState.typeFilter != null) {
      filteredList = filteredList.where((d) => d.type == detectionState.typeFilter).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Detections Log'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 1. Filter Panel
          Container(
            color: AppTheme.card,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Confidence Slider
                Row(
                  children: [
                    const Text('Confidence: ', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text('${(detectionState.confidenceFilter * 100).toStringAsFixed(0)}%+',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                    Expanded(
                      child: Slider(
                        value: detectionState.confidenceFilter,
                        min: 0.50,
                        max: 0.95,
                        activeColor: AppTheme.secondary,
                        onChanged: (val) => notifier.updateConfidenceFilter(val),
                      ),
                    ),
                  ],
                ),
                // Type Filter Scroll List
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildFilterChip(
                        context,
                        'All Classes',
                        detectionState.typeFilter == null,
                        () => notifier.updateTypeFilter(null),
                      ),
                      ...DetectionType.values.map((type) {
                        final label = _typeLabel(type);
                        final isSelected = detectionState.typeFilter == type;
                        return _buildFilterChip(
                          context,
                          label,
                          isSelected,
                          () => notifier.updateTypeFilter(type),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Feed list
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.scanFace, size: 48, color: AppTheme.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          'No anomalies match filters',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final d = filteredList[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildDetectionCard(context, d, notifier),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: AppTheme.secondary.withOpacity(0.2),
        backgroundColor: AppTheme.surface,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.secondary : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildDetectionCard(BuildContext context, AiDetection d, DetectionNotifier notifier) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mock Image thumbnail matching severity
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: d.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: d.color.withOpacity(0.3), width: 1.0),
                ),
                child: Center(
                  child: Icon(
                    _iconForType(d.type),
                    color: d.color,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Text specs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          d.typeLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        // Severity badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _severityColor(d.severity).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            d.severity.toUpperCase(),
                            style: TextStyle(
                              color: _severityColor(d.severity),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Confidence: ${(d.confidence * 100).toStringAsFixed(0)}% • Mission: ${d.missionId}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(LucideIcons.mapPin, size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${d.latitude.toStringAsFixed(6)}, ${d.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: AppTheme.border, height: 20),
          
          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildCardActionBtn(context, LucideIcons.eye, 'View', () {
                _showFullscreenImage(context, d);
              }),
              const SizedBox(width: 8),
              _buildCardActionBtn(context, LucideIcons.trash2, 'Delete', () {
                notifier.deleteDetection(d.id);
              }, textColor: AppTheme.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardActionBtn(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? textColor}) {
    return AnimatedButton(
      color: AppTheme.surface,
      onTap: onTap,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: textColor ?? AppTheme.secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor ?? AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreenImage(BuildContext context, AiDetection d) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 320,
              height: 240,
              decoration: BoxDecoration(
                color: d.color.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border.all(color: d.color, width: 1.5),
              ),
              child: Center(
                child: Icon(
                  _iconForType(d.type),
                  color: d.color,
                  size: 64,
                ),
              ),
            ),
            Container(
              width: 320,
              color: AppTheme.card,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.typeLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('Confidence: ${(d.confidence * 100).toStringAsFixed(0)}%'),
                  Text('GPS: [${d.latitude.toStringAsFixed(5)}, ${d.longitude.toStringAsFixed(5)}]'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close Preview'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(DetectionType type) {
    switch (type) {
      case DetectionType.pothole:
        return 'Pothole';
      case DetectionType.roadCrack:
        return 'Road Crack';
      case DetectionType.garbage:
        return 'Garbage';
      case DetectionType.waterLogging:
        return 'Water Logging';
      case DetectionType.animal:
        return 'Animal';
      case DetectionType.obstacle:
        return 'Obstacle';
      case DetectionType.brokenRoadSign:
        return 'Broken Road Sign';
    }
  }

  IconData _iconForType(DetectionType type) {
    switch (type) {
      case DetectionType.pothole:
        return LucideIcons.circle;
      case DetectionType.roadCrack:
        return LucideIcons.gitCommit;
      case DetectionType.garbage:
        return LucideIcons.trash2;
      case DetectionType.waterLogging:
        return LucideIcons.droplets;
      case DetectionType.animal:
        return LucideIcons.dog;
      case DetectionType.obstacle:
        return LucideIcons.construction;
      case DetectionType.brokenRoadSign:
        return LucideIcons.alertOctagon;
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return AppTheme.danger;
      case 'high':
        return AppTheme.warning;
      case 'medium':
        return AppTheme.secondary;
      default:
        return AppTheme.success;
    }
  }
}
