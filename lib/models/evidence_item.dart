import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/models/detection.dart';

enum EvidenceMediaType {
  photo,
  video;

  String get label => this == EvidenceMediaType.photo ? 'Photo' : 'Video';
}

/// Represents a persistent inspection record (photo or video) with verified telemetry
class EvidenceItem {
  final String id;
  final String filePath;
  final EvidenceMediaType mediaType;
  final DateTime timestamp;
  final String missionId;
  final DetectionType? detectionType;
  final double? confidence;
  final bool hasValidGps;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final String? flightMode;
  final int? durationSeconds;
  final int fileSizeBytes;
  final bool isSimulated;
  final bool isManuallyVerified;
  final String? notes;
  final String? originalFilePath;

  const EvidenceItem({
    required this.id,
    required this.filePath,
    required this.mediaType,
    required this.timestamp,
    required this.missionId,
    this.detectionType,
    this.confidence,
    this.hasValidGps = false,
    this.latitude,
    this.longitude,
    this.altitude,
    this.flightMode,
    this.durationSeconds,
    this.fileSizeBytes = 0,
    this.isSimulated = false,
    this.isManuallyVerified = false,
    this.notes,
    this.originalFilePath,
  });

  String get classLabel {
    if (detectionType != null) {
      return detectionType!.name[0].toUpperCase() +
          detectionType!.name.substring(1);
    }
    return mediaType == EvidenceMediaType.photo
        ? 'Manual Inspection'
        : 'Stream Recording';
  }

  Color get color {
    if (detectionType != null) {
      switch (detectionType!) {
        case DetectionType.person:
          return const Color(0xFF38BDF8); // Cyan
        case DetectionType.animal:
          return const Color(0xFFF59E0B); // Amber
        case DetectionType.pothole:
          return const Color(0xFFEF4444); // Red
        case DetectionType.roadCrack:
          return const Color(0xFFF97316); // Orange
        case DetectionType.waste:
        case DetectionType.garbage:
          return const Color(0xFF10B981); // Emerald Green
        default:
          return const Color(0xFFA855F7); // Purple
      }
    }
    return mediaType == EvidenceMediaType.video
        ? const Color(0xFFEC4899) // Pink / Recording
        : const Color(0xFF00D2FF); // Cyan / Photo
  }

  IconData get icon {
    if (detectionType != null) {
      switch (detectionType!) {
        case DetectionType.person:
          return LucideIcons.user;
        case DetectionType.animal:
          return LucideIcons.dog;
        case DetectionType.pothole:
          return LucideIcons.alertCircle;
        case DetectionType.roadCrack:
          return LucideIcons.gitCommit;
        case DetectionType.waste:
        case DetectionType.garbage:
          return LucideIcons.trash2;
        default:
          return LucideIcons.crosshair;
      }
    }
    return mediaType == EvidenceMediaType.video
        ? LucideIcons.video
        : LucideIcons.camera;
  }

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds == 0) return '00:00';
    final mins = (durationSeconds! ~/ 60).toString().padLeft(2, '0');
    final secs = (durationSeconds! % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'mediaType': mediaType.name,
      'timestamp': timestamp.toIso8601String(),
      'missionId': missionId,
      'detectionType': detectionType?.name,
      'confidence': confidence,
      'hasValidGps': hasValidGps,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'flightMode': flightMode,
      'durationSeconds': durationSeconds,
      'fileSizeBytes': fileSizeBytes,
      'isSimulated': isSimulated,
      'isManuallyVerified': isManuallyVerified,
      'notes': notes,
      'originalFilePath': originalFilePath,
    };
  }

  factory EvidenceItem.fromJson(Map<String, dynamic> json) {
    EvidenceMediaType type = EvidenceMediaType.photo;
    if (json['mediaType'] == 'video') {
      type = EvidenceMediaType.video;
    }

    DetectionType? detType;
    if (json['detectionType'] != null) {
      detType = DetectionType.fromString(json['detectionType'] as String);
    }

    return EvidenceItem(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      mediaType: type,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      missionId: json['missionId'] as String? ?? 'MANUAL_INSPECTION',
      detectionType: detType,
      confidence: (json['confidence'] as num?)?.toDouble(),
      hasValidGps: json['hasValidGps'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      flightMode: json['flightMode'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      isSimulated: json['isSimulated'] as bool? ?? false,
      isManuallyVerified: json['isManuallyVerified'] as bool? ?? false,
      notes: json['notes'] as String?,
      originalFilePath: json['originalFilePath'] as String?,
    );
  }

  EvidenceItem copyWith({
    String? id,
    String? filePath,
    EvidenceMediaType? mediaType,
    DateTime? timestamp,
    String? missionId,
    DetectionType? detectionType,
    double? confidence,
    bool? hasValidGps,
    double? latitude,
    double? longitude,
    double? altitude,
    String? flightMode,
    int? durationSeconds,
    int? fileSizeBytes,
    bool? isSimulated,
    bool? isManuallyVerified,
    String? notes,
    String? originalFilePath,
  }) {
    return EvidenceItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      mediaType: mediaType ?? this.mediaType,
      timestamp: timestamp ?? this.timestamp,
      missionId: missionId ?? this.missionId,
      detectionType: detectionType ?? this.detectionType,
      confidence: confidence ?? this.confidence,
      hasValidGps: hasValidGps ?? this.hasValidGps,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      flightMode: flightMode ?? this.flightMode,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      isSimulated: isSimulated ?? this.isSimulated,
      isManuallyVerified: isManuallyVerified ?? this.isManuallyVerified,
      notes: notes ?? this.notes,
      originalFilePath: originalFilePath ?? this.originalFilePath,
    );
  }
}
