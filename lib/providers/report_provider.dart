import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/report.dart';
import 'package:aerial_eye/services/report_storage_service.dart';

class ReportNotifier extends StateNotifier<List<InspectionReport>> {
  ReportNotifier() : super([]) {
    loadReports();
  }

  Future<void> loadReports() async {
    try {
      final persisted = await ReportStorageService.loadReports();
      state = persisted;
    } catch (_) {}
  }

  void addReport(InspectionReport report) {
    state = [report, ...state.where((r) => r.id != report.id)];
  }

  Future<void> deleteReport(String id) async {
    state = state.where((r) => r.id != id).toList();
    await ReportStorageService.deleteReport(id);
  }
}

final reportProvider =
    StateNotifierProvider<ReportNotifier, List<InspectionReport>>((ref) {
      return ReportNotifier();
    });
