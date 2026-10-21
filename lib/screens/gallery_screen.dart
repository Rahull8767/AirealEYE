import 'dart:io';
import 'dart:math';
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
        actions: [
          if (detections.isNotEmpty)
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
                    '${detections.length} Saved Records',
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
      body: detections.isEmpty
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
                    'No detection frames logged',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Qualified Raspberry Pi detections will auto-save here.',
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
              itemCount: detections.length,
              itemBuilder: (context, index) {
                final d = detections[index];
                final hasRealImage =
                    d.imagePath.isNotEmpty && File(d.imagePath).existsSync();

                return GestureDetector(
                  onTap: () => _openFullscreenViewer(context, d, ref),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. Image background: Real saved file or stylized fallback
                        if (hasRealImage)
                          Image.file(
                            File(d.imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildFallbackCard(d),
                          )
                        else
                          _buildFallbackCard(d),

                        // 2. Sequential Detection Tag Pill (Top Left)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: d.color.withValues(alpha: 0.6),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '#${d.sequenceNumber > 0 ? d.sequenceNumber : index + 1}',
                              style: TextStyle(
                                color: d.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),

                        // 3. Severity Pill (Top Right)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: d.color.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              d.severity.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),

                        // 4. Bottom Info Overlay
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
                                  Colors.black.withValues(alpha: 0.10),
                                ],
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${(d.confidence * 100).toStringAsFixed(0)}% Match',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 9,
                                      ),
                                    ),
                                    Text(
                                      d.latitude != 0.0
                                          ? '${d.latitude.toStringAsFixed(3)}, ${d.longitude.toStringAsFixed(3)}'
                                          : 'GPS N/A',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 8,
                                        fontFamily: 'monospace',
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
    );
  }

  Widget _buildFallbackCard(AiDetection d) {
    return Container(
      decoration: BoxDecoration(
        color: d.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.color.withValues(alpha: 0.3), width: 1.0),
      ),
      child: Center(child: Icon(d.icon, color: d.color, size: 40)),
    );
  }

  void _openFullscreenViewer(
    BuildContext context,
    AiDetection d,
    WidgetRef ref,
  ) {
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
              Stack(
                children: [
                  // Fullscreen Image Frame
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 280,
                      color: Colors.black,
                      child: hasRealImage
                          ? InteractiveViewer(
                              maxScale: 4.0,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(d.imagePath),
                                    fit: BoxFit.contain,
                                  ),
                                  // Draw detection bounding box if available
                                  if (d.boundingBox != null &&
                                      d.boundingBox!.length >= 4)
                                    CustomPaint(
                                      painter: _SavedBoundingBoxPainter(
                                        box: d.boundingBox!,
                                        color: d.color,
                                        label:
                                            '#${d.sequenceNumber} ${d.typeLabel.toUpperCase()}',
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(d.icon, color: d.color, size: 72),
                                  const SizedBox(height: 12),
                                  Text(
                                    '[ RAW FRAME RECORD ]',
                                    style: TextStyle(
                                      color: d.color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: d.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
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
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              d.typeLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: d.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
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
                    const SizedBox(height: 12),
                    _buildDetailRow('Event ID', d.id),
                    _buildDetailRow(
                      'Timestamp',
                      '${d.timestamp.toLocal()}'.split('.')[0],
                    ),
                    _buildDetailRow(
                      'AI Confidence',
                      '${(d.confidence * 100).toStringAsFixed(1)}% Genuine Match',
                    ),
                    _buildDetailRow(
                      'GPS Coordinates',
                      d.latitude != 0.0
                          ? '${d.latitude.toStringAsFixed(6)}, ${d.longitude.toStringAsFixed(6)}'
                          : 'Unavailable (0.0, 0.0)',
                    ),
                    if (d.altitude != 0.0)
                      _buildDetailRow(
                        'Altitude (AGL)',
                        '${d.altitude.toStringAsFixed(1)} m',
                      ),
                    if (hasRealImage)
                      _buildDetailRow('Local File', d.imagePath),
                    const Divider(color: AppTheme.border, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton.icon(
                          icon: const Icon(
                            LucideIcons.share2,
                            color: AppTheme.secondary,
                            size: 16,
                          ),
                          label: const Text(
                            'Share Record',
                            style: TextStyle(color: AppTheme.secondary),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Detection evidence: ${d.typeLabel} at [${d.latitude}, ${d.longitude}]',
                                ),
                              ),
                            );
                            Navigator.pop(context);
                          },
                        ),
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
                          onPressed: () {
                            ref
                                .read(detectionProvider.notifier)
                                .deleteDetection(d.id);
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
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedBoundingBoxPainter extends CustomPainter {
  final List<double> box;
  final Color color;
  final String label;

  _SavedBoundingBoxPainter({
    required this.box,
    required this.color,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (box.length < 4 || size.width <= 0 || size.height <= 0) return;

    final left = (box[0] * size.width).clamp(0.0, size.width);
    final top = (box[1] * size.height).clamp(0.0, size.height);
    final right = (box[2] * size.width).clamp(0.0, size.width);
    final bottom = (box[3] * size.height).clamp(0.0, size.height);

    final rect = Rect.fromLTRB(left, top, right, bottom);

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);

    final textSpan = TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    final pillRect = Rect.fromLTWH(
      left,
      max(0.0, top - 18),
      textPainter.width + 8,
      18,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(3)),
      Paint()..color = color,
    );
    textPainter.paint(canvas, Offset(left + 4, max(0.0, top - 18) + 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
