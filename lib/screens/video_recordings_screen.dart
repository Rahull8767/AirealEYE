import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/providers/evidence_provider.dart';
import 'package:aerial_eye/services/evidence_storage_service.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class VideoRecordingsScreen extends ConsumerWidget {
  const VideoRecordingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidenceState = ref.watch(evidenceProvider);
    final recordings = evidenceState.videos;

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth < 600
        ? 1
        : screenWidth < 960
        ? 2
        : 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Recordings Library'),
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
                  '${recordings.length} Recorded Videos',
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
      body: recordings.isEmpty
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
                      LucideIcons.film,
                      size: 48,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No stream recordings saved yet',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Start a video recording on the Live Inspection camera.',
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
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.6,
              ),
              itemCount: recordings.length,
              itemBuilder: (context, index) {
                final rec = recordings[index];
                return _buildRecordingCard(context, rec, ref);
              },
            ),
    );
  }

  Widget _buildRecordingCard(
    BuildContext context,
    EvidenceItem rec,
    WidgetRef ref,
  ) {
    final fileExists = File(rec.filePath).existsSync();

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.video,
                  color: Color(0xFFEC4899),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.missionId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rec.timestamp.year}-${rec.timestamp.month.toString().padLeft(2, '0')}-${rec.timestamp.day.toString().padLeft(2, '0')} ${rec.timestamp.hour.toString().padLeft(2, '0')}:${rec.timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  rec.formattedDuration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                LucideIcons.hardDrive,
                size: 12,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                rec.formattedSize,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              const Icon(
                LucideIcons.mapPin,
                size: 12,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                rec.hasValidGps && rec.latitude != null
                    ? '${rec.latitude!.toStringAsFixed(3)}, ${rec.longitude!.toStringAsFixed(3)}'
                    : 'GPS N/A',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Divider(color: AppTheme.border, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Play button
              TextButton.icon(
                icon: const Icon(
                  LucideIcons.play,
                  size: 14,
                  color: AppTheme.secondary,
                ),
                label: const Text(
                  'Play',
                  style: TextStyle(color: AppTheme.secondary, fontSize: 12),
                ),
                onPressed: fileExists
                    ? () => _openPlayerDialog(context, rec)
                    : null,
              ),
              const SizedBox(width: 4),
              // Share button
              IconButton(
                icon: const Icon(
                  LucideIcons.share2,
                  size: 16,
                  color: Colors.white70,
                ),
                tooltip: 'Share Video',
                onPressed: fileExists
                    ? () async {
                        try {
                          await EvidenceStorageService.shareEvidence(rec);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to share: $e'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        }
                      }
                    : null,
              ),
              // Save to Device Gallery
              IconButton(
                icon: const Icon(
                  LucideIcons.download,
                  size: 16,
                  color: Colors.white70,
                ),
                tooltip: 'Save to Device Storage',
                onPressed: fileExists
                    ? () async {
                        final path =
                            await EvidenceStorageService.exportToDevice(rec);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                path != null
                                    ? 'Recording exported to $path'
                                    : 'Export completed to Movies/AerialEYE',
                              ),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      }
                    : null,
              ),
              // Delete button
              IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: AppTheme.danger,
                ),
                tooltip: 'Delete Recording',
                onPressed: () => _confirmDelete(context, rec, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openPlayerDialog(BuildContext context, EvidenceItem rec) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _VideoPlayerModal(item: rec),
    );
  }

  void _confirmDelete(BuildContext context, EvidenceItem rec, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: Text(
          'Permanently remove video recording "${rec.id}" and delete file from device storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              ref.read(evidenceProvider.notifier).deleteEvidence(rec.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recording safely deleted.'),
                  backgroundColor: AppTheme.success,
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerModal extends StatefulWidget {
  final EvidenceItem item;
  const _VideoPlayerModal({required this.item});

  @override
  State<_VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<_VideoPlayerModal> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final file = File(widget.item.filePath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      setState(
        () => _error = 'Recording file is empty or missing from storage.',
      );
      return;
    }

    try {
      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() => _isInitialized = true);
      _controller!.play();
    } catch (e) {
      setState(() => _error = 'Player error: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.card,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Playback: ${widget.item.id}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Video Canvas
            Container(
              width: double.infinity,
              height: 280,
              color: Colors.black,
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              LucideIcons.alertTriangle,
                              color: AppTheme.danger,
                              size: 36,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _isInitialized && _controller != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio > 0
                              ? _controller!.value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(_controller!),
                        ),
                        if (!_controller!.value.isPlaying)
                          GestureDetector(
                            onTap: () => _controller!.play(),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(12),
                              child: const Icon(
                                LucideIcons.play,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.secondary,
                      ),
                    ),
            ),
            // Controls Bar
            if (_isInitialized && _controller != null)
              Container(
                color: AppTheme.card,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: AppTheme.secondary,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(
                            _controller!.value.isPlaying
                                ? LucideIcons.pause
                                : LucideIcons.play,
                            size: 20,
                            color: AppTheme.secondary,
                          ),
                          onPressed: () {
                            if (_controller!.value.isPlaying) {
                              _controller!.pause();
                            } else {
                              _controller!.play();
                            }
                          },
                        ),
                        Text(
                          '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            fontFamily: 'monospace',
                          ),
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

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}
