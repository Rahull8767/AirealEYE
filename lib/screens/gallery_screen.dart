import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/providers/evidence_provider.dart';
import 'package:aerial_eye/services/evidence_storage_service.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidenceState = ref.watch(evidenceProvider);
    final notifier = ref.read(evidenceProvider.notifier);
    final items = evidenceState.photos.where((e) {
      if (evidenceState.filterType != null) {
        return e.detectionType == evidenceState.filterType;
      }
      return true;
    }).toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth < 600
        ? 2
        : screenWidth < 960
        ? 3
        : 4;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Photos & Evidence'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.secondary.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${items.length} Photos',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            color: AppTheme.card,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(
                    'All Photos',
                    evidenceState.filterType == null,
                    () {
                      notifier.setFilterType(null);
                    },
                  ),
                  _buildFilterChip(
                    'Person',
                    evidenceState.filterType == DetectionType.person,
                    () {
                      notifier.setFilterType(DetectionType.person);
                    },
                  ),
                  _buildFilterChip(
                    'Animal',
                    evidenceState.filterType == DetectionType.animal,
                    () {
                      notifier.setFilterType(DetectionType.animal);
                    },
                  ),
                  _buildFilterChip(
                    'Pothole',
                    evidenceState.filterType == DetectionType.pothole,
                    () {
                      notifier.setFilterType(DetectionType.pothole);
                    },
                  ),
                  _buildFilterChip(
                    'Road Crack',
                    evidenceState.filterType == DetectionType.roadCrack,
                    () {
                      notifier.setFilterType(DetectionType.roadCrack);
                    },
                  ),
                  _buildFilterChip(
                    'Waste',
                    evidenceState.filterType == DetectionType.waste,
                    () {
                      notifier.setFilterType(DetectionType.waste);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Photos Grid
          Expanded(
            child: items.isEmpty
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
                            LucideIcons.image,
                            size: 48,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No evidence photos logged',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Captured camera frames will automatically persist here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
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
                      childAspectRatio: 0.88,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final fileExists = File(item.filePath).existsSync();

                      return GestureDetector(
                        onTap: () => _openFullscreenViewer(context, item, ref),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Image file display
                              if (fileExists)
                                Image.file(
                                  File(item.filePath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildFallbackThumbnail(item),
                                )
                              else
                                _buildFallbackThumbnail(item),

                              // Detection Class Badge (Top Left)
                              Positioned(
                                left: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.80),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: item.color.withValues(alpha: 0.6),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        item.icon,
                                        size: 10,
                                        color: item.color,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.classLabel,
                                        style: TextStyle(
                                          color: item.color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Bottom Info Gradient Overlay
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: 0.90),
                                        Colors.black.withValues(alpha: 0.05),
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.confidence != null
                                            ? '${(item.confidence! * 100).toStringAsFixed(0)}% Match'
                                            : 'Photo Capture',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            item.hasValidGps &&
                                                    item.latitude != null
                                                ? '${item.latitude!.toStringAsFixed(3)}, ${item.longitude!.toStringAsFixed(3)}'
                                                : 'GPS N/A',
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 9,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          Text(
                                            item.formattedSize,
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 8,
                                            ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
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

  Widget _buildFallbackThumbnail(EvidenceItem item) {
    return Container(
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.color.withValues(alpha: 0.3)),
      ),
      child: Center(child: Icon(item.icon, color: item.color, size: 36)),
    );
  }

  void _openFullscreenViewer(
    BuildContext context,
    EvidenceItem item,
    WidgetRef ref,
  ) {
    final file = File(item.filePath);
    final fileExists = file.existsSync();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 280,
                      color: Colors.black,
                      child: fileExists
                          ? InteractiveViewer(
                              maxScale: 4.0,
                              child: Image.file(file, fit: BoxFit.contain),
                            )
                          : Center(
                              child: Icon(
                                item.icon,
                                color: item.color,
                                size: 64,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(
                          LucideIcons.x,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(item.icon, color: item.color, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              item.classLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        if (item.confidence != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${(item.confidence! * 100).toStringAsFixed(0)}% MATCH',
                              style: TextStyle(
                                color: item.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Item ID', item.id),
                    _buildDetailRow(
                      'Timestamp',
                      '${item.timestamp.toLocal()}'.split('.')[0],
                    ),
                    _buildDetailRow('Mission ID', item.missionId),
                    _buildDetailRow(
                      'GPS Coordinates',
                      item.hasValidGps && item.latitude != null
                          ? '${item.latitude!.toStringAsFixed(6)}, ${item.longitude!.toStringAsFixed(6)}'
                          : 'Unavailable (No GPS Lock)',
                    ),
                    _buildDetailRow(
                      'Altitude (AGL)',
                      item.altitude != null
                          ? '${item.altitude!.toStringAsFixed(1)} m'
                          : 'Unavailable',
                    ),
                    _buildDetailRow('File Size', item.formattedSize),
                    _buildDetailRow('Storage Location', item.filePath),

                    const Divider(color: AppTheme.border, height: 24),

                    // Actions Row: Save to Device, Share, Delete
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Save to Device (Requirement 3)
                        TextButton.icon(
                          icon: const Icon(
                            LucideIcons.download,
                            color: AppTheme.success,
                            size: 16,
                          ),
                          label: const Text(
                            'Save to Device',
                            style: TextStyle(color: AppTheme.success),
                          ),
                          onPressed: () async {
                            final exportPath =
                                await EvidenceStorageService.exportToDevice(
                                  item,
                                );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    exportPath != null
                                        ? 'Photo saved to $exportPath'
                                        : 'Photo exported to device Pictures/AerialEYE',
                                  ),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            }
                          },
                        ),

                        // Share
                        TextButton.icon(
                          icon: const Icon(
                            LucideIcons.share2,
                            color: AppTheme.secondary,
                            size: 16,
                          ),
                          label: const Text(
                            'Share',
                            style: TextStyle(color: AppTheme.secondary),
                          ),
                          onPressed: () async {
                            try {
                              await EvidenceStorageService.shareEvidence(item);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Share error: $e'),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                              }
                            }
                          },
                        ),

                        // Delete
                        TextButton.icon(
                          icon: const Icon(
                            LucideIcons.trash2,
                            color: AppTheme.danger,
                            size: 16,
                          ),
                          label: const Text(
                            'Delete',
                            style: TextStyle(color: AppTheme.danger),
                          ),
                          onPressed: () async {
                            await ref
                                .read(evidenceProvider.notifier)
                                .deleteEvidence(item.id);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Photo deleted successfully.'),
                                ),
                              );
                            }
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
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
