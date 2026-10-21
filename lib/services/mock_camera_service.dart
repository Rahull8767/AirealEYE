import 'dart:math';
import 'package:flutter/material.dart';

class SimulatedDetectionBox {
  final String label;
  final double confidence;
  final double xPercent;
  final double yPercent;
  final double width;
  final double height;
  final Color color;

  SimulatedDetectionBox({
    required this.label,
    required this.confidence,
    required this.xPercent,
    required this.yPercent,
    required this.width,
    required this.height,
    required this.color,
  });
}

class DroneCameraPainter extends CustomPainter {
  final double animationValue;
  final bool isRecording;
  final double zoomLevel;
  final List<SimulatedDetectionBox> activeDetections;

  DroneCameraPainter({
    required this.animationValue,
    required this.isRecording,
    required this.zoomLevel,
    required this.activeDetections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFF0C101A)
      ..style = PaintingStyle.fill;

    // Draw background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw simulated road stretching vertically
    final roadPaint = Paint()
      ..color = const Color(0xFF1E2433)
      ..style = PaintingStyle.fill;
    final roadWidth = size.width * 0.45;
    final roadLeft = (size.width - roadWidth) / 2;
    canvas.drawRect(
      Rect.fromLTWH(roadLeft, 0, roadWidth, size.height),
      roadPaint,
    );

    // Draw road shoulders
    final shoulderPaint = Paint()
      ..color = const Color(0xFF2E3748)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(roadLeft, 0),
      Offset(roadLeft, size.height),
      shoulderPaint,
    );
    canvas.drawLine(
      Offset(roadLeft + roadWidth, 0),
      Offset(roadLeft + roadWidth, size.height),
      shoulderPaint,
    );

    // Draw road markings (scrolling dashes)
    final markingPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final double dashLength = 30.0;
    final double dashSpacing = 20.0;
    final double dashCycle = dashLength + dashSpacing;
    final double offset = (animationValue * dashCycle) % dashCycle;

    for (double y = -dashCycle + offset; y < size.height; y += dashCycle) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + dashLength),
        markingPaint,
      );
    }

    // Draw green environment lines for dynamic feel
    final environmentPaint = Paint()
      ..color = Colors.green.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, roadLeft, size.height),
      environmentPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        roadLeft + roadWidth,
        0,
        size.width - (roadLeft + roadWidth),
        size.height,
      ),
      environmentPaint,
    );

    // Draw subtle grid scan lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withOpacity(0.4)
      ..strokeWidth = 0.5;
    final double gridSpacing = 40.0;
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw futuristic HUD Crosshair
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    final hudPaint = Paint()
      ..color = const Color(0xFF42A5F5).withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Center reticle
    canvas.drawCircle(Offset(centerX, centerY), 45, hudPaint);
    canvas.drawCircle(
      Offset(centerX, centerY),
      4,
      Paint()..color = const Color(0xFF42A5F5).withOpacity(0.7),
    );

    // Pitch ticks
    canvas.drawLine(
      Offset(centerX - 80, centerY),
      Offset(centerX - 20, centerY),
      hudPaint,
    );
    canvas.drawLine(
      Offset(centerX + 20, centerY),
      Offset(centerX + 80, centerY),
      hudPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - 80),
      Offset(centerX, centerY - 20),
      hudPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY + 20),
      Offset(centerX, centerY + 80),
      hudPaint,
    );

    // Dynamic HUD Horizon indicator
    final double horizonOffset = sin(animationValue * pi * 2) * 12;
    final double horizonAngle = cos(animationValue * pi * 2) * 0.05; // radians

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(horizonAngle);

    final horizonPaint = Paint()
      ..color = const Color(0xFF4CAF50).withOpacity(0.6)
      ..strokeWidth = 1.0;

    // Left horizon line
    canvas.drawLine(
      Offset(-150, horizonOffset),
      Offset(-60, horizonOffset),
      horizonPaint,
    );
    canvas.drawLine(
      Offset(-60, horizonOffset),
      Offset(-60, horizonOffset + 10),
      horizonPaint,
    );
    // Right horizon line
    canvas.drawLine(
      Offset(60, horizonOffset),
      Offset(150, horizonOffset),
      horizonPaint,
    );
    canvas.drawLine(
      Offset(60, horizonOffset),
      Offset(60, horizonOffset + 10),
      horizonPaint,
    );

    canvas.restore();

    // Draw AI Bounding Boxes
    final boxPaint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final cornerPaint = Paint()
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var box in activeDetections) {
      // Animate detection boxes scrolling down with the road
      final double speedMultiplier = 180.0;
      final double initialY = box.yPercent * size.height;
      final double animatedY =
          (initialY + (animationValue * speedMultiplier)) %
              (size.height + 100) -
          50;
      final double xPos = box.xPercent * size.width;

      if (animatedY > 0 && animatedY < size.height) {
        boxPaint.color = box.color;
        cornerPaint.color = box.color;

        final rect = Rect.fromCenter(
          center: Offset(xPos, animatedY),
          width: box.width * zoomLevel,
          height: box.height * zoomLevel,
        );

        // Draw dashed bounding box
        canvas.drawRect(rect, boxPaint);

        // Draw premium heavy corners
        final double len = 12.0;
        // Top Left
        canvas.drawLine(
          rect.topLeft,
          rect.topLeft + Offset(len, 0),
          cornerPaint,
        );
        canvas.drawLine(
          rect.topLeft,
          rect.topLeft + Offset(0, len),
          cornerPaint,
        );
        // Top Right
        canvas.drawLine(
          rect.topRight,
          rect.topRight + Offset(-len, 0),
          cornerPaint,
        );
        canvas.drawLine(
          rect.topRight,
          rect.topRight + Offset(0, len),
          cornerPaint,
        );
        // Bottom Left
        canvas.drawLine(
          rect.bottomLeft,
          rect.bottomLeft + Offset(len, 0),
          cornerPaint,
        );
        canvas.drawLine(
          rect.bottomLeft,
          rect.bottomLeft + Offset(0, -len),
          cornerPaint,
        );
        // Bottom Right
        canvas.drawLine(
          rect.bottomRight,
          rect.bottomRight + Offset(-len, 0),
          cornerPaint,
        );
        canvas.drawLine(
          rect.bottomRight,
          rect.bottomRight + Offset(0, -len),
          cornerPaint,
        );

        // Label Tag Background
        final labelBgPaint = Paint()
          ..color = box.color
          ..style = PaintingStyle.fill;

        final textSpan = TextSpan(
          text:
              '${box.label.toUpperCase()} ${(box.confidence * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        );
        textPainter.text = textSpan;
        textPainter.layout();

        final double labelPadding = 4.0;
        final labelRect = Rect.fromLTWH(
          rect.left,
          rect.top - textPainter.height - (labelPadding * 2),
          textPainter.width + (labelPadding * 2),
          textPainter.height + (labelPadding * 2),
        );

        canvas.drawRect(labelRect, labelBgPaint);
        textPainter.paint(
          canvas,
          Offset(
            rect.left + labelPadding,
            rect.top - textPainter.height - labelPadding,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant DroneCameraPainter oldDelegate) => true;
}
