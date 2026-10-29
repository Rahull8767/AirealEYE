import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';

class EvidenceStorageService {
  static const String _rootDirName = 'aerialeye_evidence';
  static const String _photosDirName = 'photos';
  static const String _videosDirName = 'videos';
  static const String _registryFileName = 'evidence_registry.json';

  static int _sequenceCounter = 0;

  static Future<Directory> _getRootDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/$_rootDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _getPhotosDir() async {
    final root = await _getRootDir();
    final dir = Directory('${root.path}/$_photosDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _getVideosDir() async {
    final root = await _getRootDir();
    final dir = Directory('${root.path}/$_videosDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Loads all persisted evidence records (photos and videos)
  static Future<List<EvidenceItem>> loadAllEvidence() async {
    try {
      final root = await _getRootDir();
      final regFile = File('${root.path}/$_registryFileName');
      if (!await regFile.exists()) {
        return [];
      }

      final jsonStr = await regFile.readAsString();
      if (jsonStr.trim().isEmpty) return [];

      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        final list = <EvidenceItem>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            try {
              final ev = EvidenceItem.fromJson(item);
              // Verify file still exists on disk
              if (File(ev.filePath).existsSync()) {
                list.add(ev);
              }
            } catch (e) {
              debugPrint('[EvidenceStorage] Parse error: $e');
            }
          }
        }

        // Sort latest first
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      }
    } catch (e) {
      debugPrint('[EvidenceStorage] Error loading evidence: $e');
    }
    return [];
  }

  /// Saves a captured photo frame and persists its metadata
  static Future<EvidenceItem> savePhoto({
    required Uint8List bytes,
    required String missionId,
    DetectionType? detectionType,
    double? confidence,
    bool hasValidGps = false,
    double? latitude,
    double? longitude,
    double? altitude,
    String? flightMode,
    bool isSimulated = false,
    bool isManuallyVerified = false,
    String? notes,
  }) async {
    _sequenceCounter++;
    final now = DateTime.now();
    final photosDir = await _getPhotosDir();
    final id = 'photo_${now.millisecondsSinceEpoch}_$_sequenceCounter';
    final fileName = '$id.jpg';
    final file = File('${photosDir.path}/$fileName');

    // 1. Write image bytes to persistent storage
    await file.writeAsBytes(bytes, flush: true);

    // Verify written file
    if (!await file.exists() || await file.length() == 0) {
      throw FileSystemException(
        'Failed to write photo frame to ${file.path}',
        file.path,
      );
    }

    final fileSize = await file.length();

    final item = EvidenceItem(
      id: id,
      filePath: file.path,
      mediaType: EvidenceMediaType.photo,
      timestamp: now,
      missionId: missionId,
      detectionType: detectionType,
      confidence: confidence,
      hasValidGps: hasValidGps && latitude != null && latitude != 0.0,
      latitude: hasValidGps ? latitude : null,
      longitude: hasValidGps ? longitude : null,
      altitude: altitude != null && altitude != 0.0 ? altitude : null,
      flightMode: flightMode,
      fileSizeBytes: fileSize,
      isSimulated: isSimulated,
      isManuallyVerified: isManuallyVerified,
      notes: notes,
      originalFilePath: file.path,
    );

    // 2. Append to registry
    await _appendItemToRegistry(item);

    // 3. Gracefully attempt public pictures copy
    await _exportToPublicGallery(fileName, bytes);

    return item;
  }

  /// Saves a finalized video recording and persists its metadata
  static Future<EvidenceItem> saveVideoFile({
    required File sourceFile,
    required String missionId,
    required int durationSeconds,
    bool hasValidGps = false,
    double? latitude,
    double? longitude,
    double? altitude,
    String? flightMode,
    DetectionType? detectionType,
    double? confidence,
    bool isSimulated = false,
    String? notes,
  }) async {
    if (!await sourceFile.exists()) {
      throw FileSystemException(
        'Source video file does not exist: ${sourceFile.path}',
        sourceFile.path,
      );
    }

    final sourceSize = await sourceFile.length();
    if (sourceSize == 0) {
      throw FileSystemException(
        'Source video file is empty (0 bytes).',
        sourceFile.path,
      );
    }

    _sequenceCounter++;
    final now = DateTime.now();
    final videosDir = await _getVideosDir();
    final id = 'rec_${now.millisecondsSinceEpoch}_$_sequenceCounter';
    final fileName = '$id.mp4';
    final destFile = File('${videosDir.path}/$fileName');

    // Copy source to persistent videos directory
    await sourceFile.copy(destFile.path);

    if (!await destFile.exists() || await destFile.length() == 0) {
      throw FileSystemException(
        'Failed to verify saved video at ${destFile.path}',
        destFile.path,
      );
    }

    final fileSize = await destFile.length();

    final item = EvidenceItem(
      id: id,
      filePath: destFile.path,
      mediaType: EvidenceMediaType.video,
      timestamp: now,
      missionId: missionId,
      detectionType: detectionType,
      confidence: confidence,
      hasValidGps: hasValidGps && latitude != null && latitude != 0.0,
      latitude: hasValidGps ? latitude : null,
      longitude: hasValidGps ? longitude : null,
      altitude: altitude != null && altitude != 0.0 ? altitude : null,
      flightMode: flightMode,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSize,
      isSimulated: isSimulated,
      notes: notes,
      originalFilePath: destFile.path,
    );

    await _appendItemToRegistry(item);

    return item;
  }

  /// Deletes an evidence item and its underlying files
  static Future<void> deleteEvidence(String id) async {
    try {
      final all = await loadAllEvidence();
      final target = all.where((e) => e.id == id).firstOrNull;
      if (target != null) {
        final f = File(target.filePath);
        if (await f.exists()) {
          await f.delete();
        }
        if (target.originalFilePath != null &&
            target.originalFilePath != target.filePath) {
          final orig = File(target.originalFilePath!);
          if (await orig.exists()) {
            await orig.delete();
          }
        }
      }

      final filtered = all.where((e) => e.id != id).toList();
      await _writeRegistry(filtered);
      debugPrint('[EvidenceStorage] Deleted evidence record $id');
    } catch (e) {
      debugPrint('[EvidenceStorage] Error deleting evidence $id: $e');
    }
  }

  /// Shares an evidence media file via native share sheet
  static Future<void> shareEvidence(EvidenceItem item) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      throw FileSystemException(
        'File not found: ${item.filePath}',
        item.filePath,
      );
    }

    final text =
        'AerialEYE Evidence [${item.classLabel}] captured on ${item.timestamp.toLocal()}';
    await Share.shareXFiles([XFile(item.filePath)], text: text);
  }

  /// Exports the image/video to public device storage (e.g. Pictures / Movies)
  static Future<String?> exportToDevice(EvidenceItem item) async {
    try {
      final source = File(item.filePath);
      if (!await source.exists()) return null;

      if (Platform.isAndroid) {
        final folder = item.mediaType == EvidenceMediaType.photo
            ? '/storage/emulated/0/Pictures/AerialEYE'
            : '/storage/emulated/0/Movies/AerialEYE';
        final dir = Directory(folder);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final destName = File(item.filePath).uri.pathSegments.last;
        final dest = File('${dir.path}/$destName');
        await source.copy(dest.path);
        return dest.path;
      }
    } catch (e) {
      debugPrint('[EvidenceStorage] Public storage export exception: $e');
    }
    return null;
  }

  static Future<void> _appendItemToRegistry(EvidenceItem newItem) async {
    final all = await loadAllEvidence();
    final updated = [newItem, ...all.where((e) => e.id != newItem.id)];
    await _writeRegistry(updated);
  }

  static Future<void> _writeRegistry(List<EvidenceItem> list) async {
    final root = await _getRootDir();
    final regFile = File('${root.path}/$_registryFileName');
    final jsonList = list.map((e) => e.toJson()).toList();
    await regFile.writeAsString(jsonEncode(jsonList), flush: true);
  }

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
    } catch (_) {}
  }
}
