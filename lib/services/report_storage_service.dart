import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aerial_eye/models/report.dart';

class ReportStorageService {
  static const String _folderName = 'aerialeye_reports';
  static const String _historyFileName = 'reports_history.json';

  static Future<Directory> getReportsDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docDir.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Loads all saved inspection reports
  static Future<List<InspectionReport>> loadReports() async {
    try {
      final dir = await getReportsDirectory();
      final file = File('${dir.path}/$_historyFileName');
      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      if (jsonString.trim().isEmpty) return [];

      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        final list = <InspectionReport>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            try {
              list.add(InspectionReport.fromJson(item));
            } catch (e) {
              debugPrint('[ReportStorageService] Error parsing report: $e');
            }
          }
        }
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      }
    } catch (e) {
      debugPrint('[ReportStorageService] Error loading reports: $e');
    }
    return [];
  }

  /// Saves a newly generated inspection report to persistent history
  static Future<void> saveReport(InspectionReport report) async {
    try {
      final existing = await loadReports();
      final updated = [report, ...existing.where((r) => r.id != report.id)];
      final dir = await getReportsDirectory();
      final file = File('${dir.path}/$_historyFileName');
      final jsonList = updated.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
      debugPrint('[ReportStorageService] Saved report ${report.id}');
    } catch (e) {
      debugPrint('[ReportStorageService] Error saving report: $e');
    }
  }

  /// Deletes a report record and its associated PDF file
  static Future<void> deleteReport(String id) async {
    try {
      final existing = await loadReports();
      final target = existing.where((r) => r.id == id).firstOrNull;
      if (target != null && target.pdfFilePath != null) {
        final pdf = File(target.pdfFilePath!);
        if (await pdf.exists()) {
          await pdf.delete();
        }
      }
      final updated = existing.where((r) => r.id != id).toList();
      final dir = await getReportsDirectory();
      final file = File('${dir.path}/$_historyFileName');
      final jsonList = updated.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (e) {
      debugPrint('[ReportStorageService] Error deleting report: $e');
    }
  }
}
