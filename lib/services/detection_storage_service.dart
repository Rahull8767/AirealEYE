import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerial_eye/models/detection.dart';

class DetectionStorageService {
  static const String _folderName = 'aerialeye_detections';
  static const String _imagesFolderName = 'images';
  static const String _historyFileName = 'detections_history.json';

  /// Directory where detection images and JSON metadata are persisted
  static Future<Directory> _getStorageDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory('${appDocDir.path}/$_folderName');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  /// Directory where image files are stored
  static Future<Directory> _getImagesDirectory() async {
    final baseDir = await _getStorageDirectory();
    final imagesDir = Directory('${baseDir.path}/$_imagesFolderName');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// Loads all saved detections from persistent local JSON storage
  static Future<List<AiDetection>> loadPersistedDetections() async {
    try {
      final baseDir = await _getStorageDirectory();
      final file = File('${baseDir.path}/$_historyFileName');
      if (!await file.exists()) {
        debugPrint(
          '[DetectionStorageService] No existing history file found at ${file.path}',
        );
        return [];
      }

      final jsonString = await file.readAsString();
      if (jsonString.trim().isEmpty) return [];

      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        final list = <AiDetection>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            try {
              list.add(AiDetection.fromJson(item));
            } catch (e) {
              debugPrint('[DetectionStorageService] Error parsing item: $e');
            }
          }
        }
        debugPrint(
          '[DetectionStorageService] Loaded ${list.length} persisted detections.',
        );
        return list;
      }
      return [];
    } catch (e) {
      debugPrint(
        '[DetectionStorageService] Failed to load persisted detections: $e',
      );
      return [];
    }
  }

  /// Saves a newly captured image frame and appends the detection metadata to persistent storage
  static Future<AiDetection> saveDetection({
    required AiDetection detection,
    required Uint8List imageBytes,
  }) async {
    try {
      final imagesDir = await _getImagesDirectory();
      final fileName = '${detection.id}.jpg';
      final imageFile = File('${imagesDir.path}/$fileName');

      // 1. Write the JPEG image bytes to persistent storage
      await imageFile.writeAsBytes(imageBytes, flush: true);

      // 2. Also attempt to export copy to public Pictures folder on Android for native Gallery visibility
      await _exportToPublicGallery(fileName, imageBytes);

      // 3. Create updated detection record with absolute path
      final updatedDetection = AiDetection(
        id: detection.id,
        missionId: detection.missionId,
        type: detection.type,
        confidence: detection.confidence,
        timestamp: detection.timestamp,
        latitude: detection.latitude,
        longitude: detection.longitude,
        altitude: detection.altitude,
        boundingBox: detection.boundingBox,
        severity: detection.severity,
        imagePath: imageFile.path,
        isSimulated: false,
        sequenceNumber: detection.sequenceNumber,
      );

      // 4. Update the JSON registry file
      final allDetections = await loadPersistedDetections();
      // Remove existing with same id if any, and insert new at top
      final newList = [
        updatedDetection,
        ...allDetections.where((d) => d.id != updatedDetection.id),
      ];

      await _writeDetectionsJson(newList);
      debugPrint(
        '[DetectionStorageService] Persisted detection ${updatedDetection.id} at ${imageFile.path}',
      );
      return updatedDetection;
    } catch (e) {
      debugPrint('[DetectionStorageService] Error saving detection: $e');
      return detection;
    }
  }

  /// Deletes a detection record and removes its image file from storage
  static Future<void> deleteDetection(String id) async {
    try {
      final allDetections = await loadPersistedDetections();
      final target = allDetections.where((d) => d.id == id).firstOrNull;
      if (target != null && target.imagePath.isNotEmpty) {
        final img = File(target.imagePath);
        if (await img.exists()) {
          await img.delete();
        }
      }

      final filtered = allDetections.where((d) => d.id != id).toList();
      await _writeDetectionsJson(filtered);
      debugPrint('[DetectionStorageService] Deleted detection $id');
    } catch (e) {
      debugPrint('[DetectionStorageService] Error deleting detection: $e');
    }
  }

  /// Clears all saved detections and removes image files
  static Future<void> clearAll() async {
    try {
      final baseDir = await _getStorageDirectory();
      if (await baseDir.exists()) {
        await baseDir.delete(recursive: true);
        await baseDir.create();
      }
      debugPrint('[DetectionStorageService] Cleared all detections.');
    } catch (e) {
      debugPrint('[DetectionStorageService] Error clearing detections: $e');
    }
  }

  static Future<void> _writeDetectionsJson(List<AiDetection> list) async {
    final baseDir = await _getStorageDirectory();
    final file = File('${baseDir.path}/$_historyFileName');
    final jsonList = list.map((d) => d.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList), flush: true);
  }

  /// Tries to copy image to /storage/emulated/0/Pictures/AerialEYE for native gallery access on Android
  static Future<void> _exportToPublicGallery(
    String fileName,
    Uint8List bytes,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      final publicDir = Directory('/storage/emulated/0/Pictures/AerialEYE');
      if (!await publicDir.exists()) {
        await publicDir.create(recursive: true);
      }
      final destFile = File('${publicDir.path}/$fileName');
      await destFile.writeAsBytes(bytes, flush: true);
      debugPrint(
        '[DetectionStorageService] Exported to native gallery: ${destFile.path}',
      );
    } catch (e) {
      // Graceful fallback if Android scoped storage restricts direct writes to public Pictures
      debugPrint(
        '[DetectionStorageService] Public pictures export notice (app-local storage is safe): $e',
      );
    }
  }
}
