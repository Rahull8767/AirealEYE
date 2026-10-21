import 'dart:io';
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

    // Filter list by confidence
    var filteredList = detectionState.detections.where((d) {
      return d.confidence >= detectionState.confidenceFilter;
    }).toList();

    // Filter list by selected class
    if (detectionState.typeFilter != null) {
      filteredList = filteredList
          .where((d) => d.type == detectionState.typeFilter)
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Detections Log'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${filteredList.length} of ${detectionState.detections.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Filter Panel (Confidence threshold + Trained classes)
          Container(
            color: AppTheme.card,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Confidence Slider
                Row(
                  children: [
                    const Text(
                      'Confidence: ',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '${(detectionState.confidenceFilter * 100).toStringAsFixed(0)}%+',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: detectionState.confidenceFilter,
                        min: 0.50,
                        max: 0.95,
                        activeColor: AppTheme.secondary,
                        onChanged: (val) =>
                            notifier.updateConfidenceFilter(val),
                      ),
                    ),
                  ],
                ),
                // Trained Class Chips
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
                      ...[
                        DetectionType.person,
                        DetectionType.animal,
                        DetectionType.pothole,
                        DetectionType.waste,
                      ].map((type) {
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
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.scanFace,
                            size: 48,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No anomalies match filters',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Detections from Raspberry Pi camera will appear in real time.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
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

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: AppTheme.secondary.withValues(alpha: 0.2),
        backgroundColor: AppTheme.surface,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.secondary : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildDetectionCard(
    BuildContext context,
    AiDetection d,
    DetectionNotifier notifier,
  ) {
    final hasRealImage =
        d.imagePath.isNotEmpty && File(d.imagePath).existsSync();

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Thumbnail: Real saved frame or icon canvas
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 76,
                  height: 76,
                  color: d.color.withValues(alpha: 0.10),
                  child: hasRealImage
                      ? Image.file(
                          File(d.imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildIconThumbnail(d),
                        )
                      : _buildIconThumbnail(d),
                ),
              ),
              const SizedBox(width: 14),

              // 2. Text specs & details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: d.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: d.color.withValues(alpha: 0.6),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '#${d.sequenceNumber}',
                                style: TextStyle(
                                  color: d.color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              d.typeLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        // Severity badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _severityColor(
                              d.severity,
                            ).withValues(alpha: 0.15),
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
                      'Confidence: ${(d.confidence * 100).toStringAsFixed(0)}% • ${d.timestamp.toLocal().toString().split('.')[0]}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.mapPin,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            d.latitude != 0.0
                                ? '${d.latitude.toStringAsFixed(6)}, ${d.longitude.toStringAsFixed(6)}'
                                : 'Location: GPS Unavailable',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontFamily: 'monospace',
                            ),
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
              _buildCardActionBtn(
                context,
                LucideIcons.eye,
                'View Evidence',
                () {
                  _showFullscreenImage(context, d);
                },
              ),
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

  Widget _buildIconThumbnail(AiDetection d) {
    return Center(child: Icon(d.icon, color: d.color, size: 32));
  }

  Widget _buildCardActionBtn(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? textColor,
  }) {
    return AnimatedButton(
      color: AppTheme.surface,
      onTap: onTap,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: textColor ?? AppTheme.secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor ?? AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreenImage(BuildContext context, AiDetection d) {
    final hasRealImage =
        d.imagePath.isNotEmpty && File(d.imagePath).existsSync();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  width: double.infinity,
                  height: 250,
                  color: Colors.black,
                  child: hasRealImage
                      ? Image.file(File(d.imagePath), fit: BoxFit.contain)
                      : Center(child: Icon(d.icon, color: d.color, size: 64)),
                ),
              ),
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '#${d.sequenceNumber} ${d.typeLabel}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: d.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.severity.toUpperCase(),
                            style: TextStyle(
                              color: d.color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'AI Confidence: ${(d.confidence * 100).toStringAsFixed(1)}% Genuine Prediction',
                    ),
                    Text(
                      'Recorded: ${d.timestamp.toLocal().toString().split('.')[0]}',
                    ),
                    Text(
                      'GPS Coordinates: [${d.latitude.toStringAsFixed(6)}, ${d.longitude.toStringAsFixed(6)}]',
                    ),
                    if (d.altitude != 0.0)
                      Text(
                        'Altitude (AGL): ${d.altitude.toStringAsFixed(1)} m',
                      ),
                    if (hasRealImage)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Path: ${d.imagePath}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
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
      ),
    );
  }

  String _typeLabel(DetectionType type) {
    switch (type) {
      case DetectionType.person:
        return 'Person';
      case DetectionType.animal:
        return 'Animal';
      case DetectionType.pothole:
        return 'Pothole';
      case DetectionType.waste:
      case DetectionType.garbage:
        return 'Waste';
      case DetectionType.roadCrack:
        return 'Road Crack';
      case DetectionType.waterLogging:
        return 'Water Logging';
      case DetectionType.obstacle:
        return 'Obstacle';
      case DetectionType.brokenRoadSign:
        return 'Broken Road Sign';
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
