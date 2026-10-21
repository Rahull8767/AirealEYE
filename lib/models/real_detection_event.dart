import 'dart:math';
import 'package:flutter/material.dart';
import 'package:aerial_eye/models/detection.dart';

/// Represents a single live object detection emitted by the Raspberry Pi YOLO model
class RealDetectionEvent {
  final int sequenceNumber;
  final DetectionType type;
  final String label;
  final double confidence; // 0.0 to 1.0
  final List<double>
  boundingBox; // [xMin, yMin, xMax, yMax] normalized 0.0 to 1.0
  final DateTime timestamp;
  final int? piTrackId;

  RealDetectionEvent({
    required this.sequenceNumber,
    required this.type,
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.timestamp,
    this.piTrackId,
  });

  String get displayTag =>
      '#$sequenceNumber ${type.name.toUpperCase()} ${(confidence * 100).toStringAsFixed(0)}%';

  Color get color {
    switch (type) {
      case DetectionType.person:
        return const Color(0xFF38BDF8); // Bright Sky Blue
      case DetectionType.animal:
        return const Color(0xFFF59E0B); // Vivid Amber
      case DetectionType.pothole:
        return const Color(0xFFEF4444); // Bright Crimson
      case DetectionType.waste:
      case DetectionType.garbage:
        return const Color(0xFF10B981); // Emerald Green
      default:
        return const Color(0xFFA855F7); // Purple
    }
  }

  /// Calculates Intersection over Union (IoU) between two normalized [xMin, yMin, xMax, yMax] bounding boxes
  static double computeIoU(List<double> boxA, List<double> boxB) {
    if (boxA.length < 4 || boxB.length < 4) return 0.0;

    final xA = max(boxA[0], boxB[0]);
    final yA = max(boxA[1], boxB[1]);
    final xB = min(boxA[2], boxB[2]);
    final yB = min(boxA[3], boxB[3]);

    final interWidth = max(0.0, xB - xA);
    final interHeight = max(0.0, yB - yA);
    final interArea = interWidth * interHeight;

    final areaA = max(0.0, boxA[2] - boxA[0]) * max(0.0, boxA[3] - boxA[1]);
    final areaB = max(0.0, boxB[2] - boxB[0]) * max(0.0, boxB[3] - boxB[1]);
    final unionArea = areaA + areaB - interArea;

    if (unionArea <= 0.0) return 0.0;
    return interArea / unionArea;
  }

  /// Calculates Euclidean distance between the centroids of two bounding boxes
  static double computeCentroidDistance(List<double> boxA, List<double> boxB) {
    if (boxA.length < 4 || boxB.length < 4) return 1.0;
    final cAx = (boxA[0] + boxA[2]) / 2.0;
    final cAy = (boxA[1] + boxA[3]) / 2.0;
    final cBx = (boxB[0] + boxB[2]) / 2.0;
    final cBy = (boxB[1] + boxB[3]) / 2.0;
    final dx = cAx - cBx;
    final dy = cAy - cBy;
    return sqrt(dx * dx + dy * dy);
  }

  /// Parses a detection entry from the Raspberry Pi JSON output
  /// Supports both [xMin, yMin, xMax, yMax] and [ymin, xmin, ymax, xmax] or {left, top, right, bottom}
  static RealDetectionEvent? fromPiJson(
    Map<String, dynamic> json, {
    int defaultSequenceNumber = 1,
  }) {
    try {
      final rawClass = (json['class'] ?? json['label'] ?? json['name'] ?? '')
          .toString();
      if (rawClass.isEmpty) return null;
      final parsedType = DetectionType.fromString(rawClass);

      final conf =
          (json['confidence'] ?? json['conf'] ?? json['score'] ?? 0.85 as num)
              .toDouble();

      List<double> box = [0.1, 0.1, 0.9, 0.9];
      if (json['box'] is List) {
        final list = (json['box'] as List)
            .map((e) => (e as num).toDouble())
            .toList();
        if (list.length >= 4) {
          box = _normalizeBox(list);
        }
      } else if (json['bbox'] is List) {
        final list = (json['bbox'] as List)
            .map((e) => (e as num).toDouble())
            .toList();
        if (list.length >= 4) {
          box = _normalizeBox(list);
        }
      } else if (json['rect'] != null && json['rect'] is Map) {
        final r = json['rect'] as Map;
        final x1 = (r['x1'] ?? r['left'] ?? r['x'] ?? 0 as num).toDouble();
        final y1 = (r['y1'] ?? r['top'] ?? r['y'] ?? 0 as num).toDouble();
        final x2 =
            (r['x2'] ?? r['right'] ?? (x1 + (r['w'] ?? 0.2 as num)) as num)
                .toDouble();
        final y2 =
            (r['y2'] ?? r['bottom'] ?? (y1 + (r['h'] ?? 0.2 as num)) as num)
                .toDouble();
        box = _normalizeBox([x1, y1, x2, y2]);
      }

      int? trackId;
      if (json['id'] != null || json['track_id'] != null) {
        trackId = (json['id'] ?? json['track_id'] as num?)?.toInt();
      }

      final seq =
          (json['seq'] ??
                  json['sequenceNumber'] ??
                  defaultSequenceNumber as num)
              .toInt();

      return RealDetectionEvent(
        sequenceNumber: seq,
        type: parsedType,
        label: rawClass,
        confidence: conf.clamp(0.0, 1.0),
        boundingBox: box,
        timestamp: DateTime.now(),
        piTrackId: trackId,
      );
    } catch (e) {
      return null;
    }
  }

  /// Ensures box coordinates are within 0.0 - 1.0 and properly ordered [xMin, yMin, xMax, yMax]
  static List<double> _normalizeBox(List<double> raw) {
    // Check if coordinates are in pixel space (e.g. > 1.0) and assume standard 640x480 resolution if so
    double x1 = raw[0];
    double y1 = raw[1];
    double x2 = raw[2];
    double y2 = raw[3];

    if (x1 > 1.0 || x2 > 1.0 || y1 > 1.0 || y2 > 1.0) {
      final maxCoord = [x1, y1, x2, y2].reduce(max);
      final scale = maxCoord > 640 ? 1280.0 : 640.0;
      x1 /= scale;
      x2 /= scale;
      y1 /= (scale * 0.75);
      y2 /= (scale * 0.75);
    }

    final xMin = min(x1, x2).clamp(0.0, 1.0);
    final yMin = min(y1, y2).clamp(0.0, 1.0);
    final xMax = max(x1, x2).clamp(0.0, 1.0);
    final yMax = max(y1, y2).clamp(0.0, 1.0);

    return [xMin, yMin, xMax, yMax];
  }
}
