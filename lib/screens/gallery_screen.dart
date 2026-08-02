import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/providers/detection_provider.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detectionState = ref.watch(detectionProvider);
    final detections = detectionState.detections;

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth < 600
        ? 2
        : screenWidth < 960
            ? 3
            : 4;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anomalies Gallery'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: detections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.image, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'No detection frames logged',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: detections.length,
              itemBuilder: (context, index) {
                final d = detections[index];
                return GestureDetector(
                  onTap: () => _openFullscreenViewer(context, d, ref),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Card Canvas drawing background
                        Container(
                          decoration: BoxDecoration(
                            color: d.color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: d.color.withOpacity(0.3), width: 1.0),
                          ),
                          child: Center(
                            child: Icon(
                              _iconForType(d.type),
                              color: d.color,
                              size: 40,
                            ),
                          ),
                        ),

                        // Bottom info overlay
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black.withOpacity(0.85), Colors.black.withOpacity(0.2)],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  d.typeLabel,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${(d.confidence * 100).toStringAsFixed(0)}% Match',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
                                    ),
                                    Text(
                                      d.severity.toUpperCase(),
                                      style: TextStyle(color: d.color, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openFullscreenViewer(BuildContext context, AiDetection d, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                // Fullscreen mock frame
                Container(
                  width: 340,
                  height: 260,
                  decoration: BoxDecoration(
                    color: d.color.withOpacity(0.12),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: d.color, width: 1.5),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _iconForType(d.type),
                          color: d.color,
                          size: 72,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '[ MOCK INSPECTION IMAGE FRAME ]',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black45,
                    child: IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: 340,
              color: AppTheme.card,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.typeLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text('Classification: Road Anomaly Defect', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  Text('Precision Match: ${(d.confidence * 100).toStringAsFixed(0)}%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  Text('Latitude: ${d.latitude.toStringAsFixed(6)}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  Text('Longitude: ${d.longitude.toStringAsFixed(6)}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const Divider(color: AppTheme.border, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.share2, color: AppTheme.secondary),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('File shared successfully.')),
                          );
                          Navigator.pop(context);
                        },
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.trash2, color: AppTheme.danger),
                        onPressed: () {
                          ref.read(detectionProvider.notifier).deleteDetection(d.id);
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
      ),
    );
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
}
