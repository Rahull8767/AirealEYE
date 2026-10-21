import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/camera_stream_state.dart';
import 'package:aerial_eye/models/real_detection_event.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/pi_camera_provider.dart';
import 'package:aerial_eye/screens/camera_connection_screen.dart';

class PiCameraView extends ConsumerWidget {
  final double zoomLevel;
  final bool isRecording;
  final VoidCallback? onOpenSettings;

  const PiCameraView({
    super.key,
    this.zoomLevel = 1.0,
    this.isRecording = false,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraService = ref.watch(piCameraServiceProvider);
    final stateAsync = ref.watch(piCameraStateProvider);
    final frameAsync = ref.watch(piCameraFrameProvider);
    final detectionsAsync = ref.watch(liveDetectionsStreamProvider);
    final realDetectionService = ref.watch(realDetectionServiceProvider);

    final streamState = stateAsync.value ?? cameraService.currentState;
    final frameBytes = frameAsync.value ?? cameraService.latestFrame;
    final liveDetections =
        detectionsAsync.value ?? realDetectionService.currentLiveDetections;

    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Primary Video/Stream Display with Bounding Box Overlays
          _buildStreamContent(
            context,
            ref,
            streamState,
            frameBytes,
            liveDetections,
          ),

          // 2. Futuristic Reticle Overlay (Active when connected)
          if (streamState.isConnected && frameBytes != null)
            _buildFuturisticReticleOverlay(),

          // 3. Status Badge & Active Detections Pill (Top Center)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusPill(streamState),
                  if (liveDetections.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildActiveDetectionsPill(liveDetections),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamContent(
    BuildContext context,
    WidgetRef ref,
    CameraStreamState state,
    Uint8List? frameBytes,
    List<RealDetectionEvent> liveDetections,
  ) {
    switch (state.status) {
      case CameraStatus.connected:
        if (frameBytes != null && frameBytes.isNotEmpty) {
          final double aspectRatio =
              (state.imageWidth > 0 && state.imageHeight > 0)
              ? state.imageWidth / state.imageHeight
              : 4 / 3;

          return Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRect(
                child: Transform.scale(
                  scale: zoomLevel,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        frameBytes,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildErrorState(
                            context,
                            ref,
                            state,
                            'Frame decoding error: ${error.toString()}',
                          );
                        },
                      ),
                      // Real YOLO Bounding Box Overlay
                      if (liveDetections.isNotEmpty)
                        CustomPaint(
                          painter: _BoundingBoxPainter(
                            detections: liveDetections,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          return _buildLoadingState(
            state,
            'Waiting for camera frame stream...',
          );
        }

      case CameraStatus.connecting:
        return _buildLoadingState(
          state,
          'Establishing connection to Raspberry Pi...',
        );

      case CameraStatus.reconnecting:
        return _buildLoadingState(
          state,
          'Reconnecting (${state.retryAttempt}/${state.maxRetries})...',
        );

      case CameraStatus.error:
        return _buildErrorState(context, ref, state, state.errorMessage);

      case CameraStatus.disconnected:
        return _buildDisconnectedState(context, ref, state);
    }
  }

  Widget _buildLoadingState(CameraStreamState state, String message) {
    return Container(
      color: const Color(0xFF0A0E17),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.secondary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              state.connectedUrl.isNotEmpty
                  ? state.connectedUrl
                  : 'http://10.174.17.87:8080',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            if (state.diagnosticDetails != null) ...[
              const SizedBox(height: 12),
              Text(
                state.diagnosticDetails!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedState(
    BuildContext context,
    WidgetRef ref,
    CameraStreamState state,
  ) {
    final cameraService = ref.read(piCameraServiceProvider);

    return Container(
      color: const Color(0xFF0A0E17),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: const Icon(
                LucideIcons.camera,
                color: AppTheme.textSecondary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Raspberry Pi Camera Standby',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Target: ${cameraService.config.baseUrl}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => cameraService.connect(),
                  icon: const Icon(LucideIcons.play, size: 16),
                  label: const Text('Start Stream'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    if (onOpenSettings != null) {
                      onOpenSettings!();
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CameraConnectionScreen(),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.settings, size: 16),
                  label: const Text('Configure IP'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    CameraStreamState state,
    String? errorText,
  ) {
    final cameraService = ref.read(piCameraServiceProvider);

    return Container(
      color: const Color(0xFF0F0B10),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  LucideIcons.alertTriangle,
                  color: AppTheme.danger,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera Connection Failed',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  errorText ?? 'Failed to open video feed from Raspberry Pi.',
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (state.diagnosticDetails != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    state.diagnosticDetails!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => cameraService.retry(),
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (onOpenSettings != null) {
                        onOpenSettings!();
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const CameraConnectionScreen(),
                          ),
                        );
                      }
                    },
                    icon: const Icon(LucideIcons.settings, size: 16),
                    label: const Text('Edit IP'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(CameraStreamState state) {
    Color color;
    IconData icon;
    String label;

    switch (state.status) {
      case CameraStatus.connected:
        color = AppTheme.success;
        icon = LucideIcons.radio;
        label =
            'PI CAM: ${state.fps.toStringAsFixed(0)} FPS | ${state.latencyMs}ms';
        break;
      case CameraStatus.connecting:
      case CameraStatus.reconnecting:
        color = Colors.orange;
        icon = LucideIcons.loader;
        label = state.statusDisplay;
        break;
      case CameraStatus.error:
        color = AppTheme.danger;
        icon = LucideIcons.alertCircle;
        label = 'FEED ERROR';
        break;
      case CameraStatus.disconnected:
        color = Colors.white54;
        icon = LucideIcons.videoOff;
        label = 'STANDBY';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuturisticReticleOverlay() {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 80,
          height: 80,
          child: CustomPaint(painter: _ReticlePainter()),
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF42A5F5).withValues(alpha: 0.45)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 28, paint);
    canvas.drawCircle(
      center,
      3,
      Paint()..color = const Color(0xFF42A5F5).withValues(alpha: 0.6),
    );

    // Corner cross lines
    final lineLen = 14.0;
    canvas.drawLine(
      Offset(center.dx - 40, center.dy),
      Offset(center.dx - 40 + lineLen, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + 40 - lineLen, center.dy),
      Offset(center.dx + 40, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 40),
      Offset(center.dx, center.dy - 40 + lineLen),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + 40 - lineLen),
      Offset(center.dx, center.dy + 40),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension PiCameraViewDetectionPill on PiCameraView {
  Widget _buildActiveDetectionsPill(List<RealDetectionEvent> detections) {
    final count = detections.length;
    final topDet = detections.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: topDet.color.withValues(alpha: 0.8),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: topDet.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count TARGET${count > 1 ? "S" : ""}: ${detections.map((d) => "#${d.sequenceNumber} ${d.type.name.toUpperCase()}").join(", ")}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: topDet.color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  final List<RealDetectionEvent> detections;

  const _BoundingBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || size.width <= 0 || size.height <= 0) return;

    for (final det in detections) {
      if (det.boundingBox.length < 4) continue;

      final left = (det.boundingBox[0] * size.width).clamp(0.0, size.width);
      final top = (det.boundingBox[1] * size.height).clamp(0.0, size.height);
      final right = (det.boundingBox[2] * size.width).clamp(0.0, size.width);
      final bottom = (det.boundingBox[3] * size.height).clamp(0.0, size.height);

      if (right <= left || bottom <= top) continue;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      final boxColor = det.color;

      // 1. Semi-transparent fill inside box
      final fillPaint = Paint()
        ..color = boxColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      // 2. Translucent bounding line
      final borderPaint = Paint()
        ..color = boxColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, borderPaint);

      // 3. High-tech corner reticle brackets (thickened corners)
      final cornerPaint = Paint()
        ..color = boxColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.square
        ..style = PaintingStyle.stroke;

      final cornerLen = (rect.width * 0.25).clamp(8.0, 18.0);

      // Top-left corner
      canvas.drawLine(
        Offset(rect.left, rect.top),
        Offset(rect.left + cornerLen, rect.top),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top),
        Offset(rect.left, rect.top + cornerLen),
        cornerPaint,
      );

      // Top-right corner
      canvas.drawLine(
        Offset(rect.right, rect.top),
        Offset(rect.right - cornerLen, rect.top),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + cornerLen),
        cornerPaint,
      );

      // Bottom-left corner
      canvas.drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.left + cornerLen, rect.bottom),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.left, rect.bottom - cornerLen),
        cornerPaint,
      );

      // Bottom-right corner
      canvas.drawLine(
        Offset(rect.right, rect.bottom),
        Offset(rect.right - cornerLen, rect.bottom),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(rect.right, rect.bottom),
        Offset(rect.right, rect.bottom - cornerLen),
        cornerPaint,
      );

      // 4. Label badge (e.g. "#1 POTHOLE 89%")
      final textSpan = TextSpan(
        text: det.displayTag,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final pillHeight = textPainter.height + 6;
      final pillWidth = textPainter.width + 12;

      // Position pill above box, or inside top if near upper boundary
      final pillTop = (rect.top - pillHeight >= 0)
          ? rect.top - pillHeight
          : rect.top;
      final pillLeft = rect.left;

      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const Radius.circular(4),
      );

      final pillBgPaint = Paint()
        ..color = boxColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(pillRect, pillBgPaint);

      textPainter.paint(canvas, Offset(pillLeft + 6, pillTop + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
