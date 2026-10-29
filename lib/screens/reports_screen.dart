import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:printing/printing.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/evidence_item.dart';
import 'package:aerial_eye/models/report.dart';
import 'package:aerial_eye/providers/evidence_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/report_provider.dart';
import 'package:aerial_eye/services/pdf_report_service.dart';
import 'package:aerial_eye/widgets/animated_button.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _activeReportIndex = 0;
  bool _isGenerating = false;

  void _openGenerateReportDialog() {
    final evidenceState = ref.read(evidenceProvider);
    final missionState = ref.read(missionProvider);

    String selectedMissionId = 'ALL';
    final selectedClasses = <DetectionType>{
      DetectionType.person,
      DetectionType.animal,
      DetectionType.pothole,
      DetectionType.roadCrack,
      DetectionType.waste,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final matchingPhotos = evidenceState.photos.where((p) {
            if (selectedMissionId != 'ALL' &&
                p.missionId != selectedMissionId) {
              return false;
            }
            if (p.detectionType != null &&
                !selectedClasses.contains(p.detectionType)) {
              return false;
            }
            return true;
          }).toList();

          return Container(
            decoration: const BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Generate Inspection Report',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 1. Mission / Inspection Target
                const Text(
                  'SELECT INSPECTION TARGET',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: DropdownButton<String>(
                    value: selectedMissionId,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: AppTheme.surface,
                    items: [
                      const DropdownMenuItem(
                        value: 'ALL',
                        child: Text('All Available Evidence Photos'),
                      ),
                      ...missionState.missionHistory.map((m) {
                        return DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.name} (${m.id})'),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedMissionId = val);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Detection Classes to Include
                const Text(
                  'DETECTION CLASSES TO INCLUDE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                        DetectionType.person,
                        DetectionType.animal,
                        DetectionType.pothole,
                        DetectionType.roadCrack,
                        DetectionType.waste,
                      ].map((type) {
                        final label = type == DetectionType.roadCrack
                            ? 'Road Crack'
                            : type.name[0].toUpperCase() +
                                  type.name.substring(1);
                        final isChecked = selectedClasses.contains(type);
                        return FilterChip(
                          label: Text(
                            label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: isChecked,
                          selectedColor: AppTheme.secondary.withValues(
                            alpha: 0.25,
                          ),
                          checkmarkColor: AppTheme.secondary,
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedClasses.add(type);
                              } else {
                                selectedClasses.remove(type);
                              }
                            });
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 16),

                // 3. Matched Evidence Counter
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.camera,
                        size: 18,
                        color: AppTheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${matchingPhotos.length} verified photos selected for report compilation.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Generate Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.fileCheck, size: 18),
                    label: Text(
                      _isGenerating
                          ? 'Compiling PDF Report...'
                          : 'Compile & Generate PDF',
                    ),
                    onPressed: _isGenerating
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _executeReportGeneration(
                              missionId: selectedMissionId,
                              selectedEvidence: matchingPhotos,
                              selectedClasses: selectedClasses,
                            );
                          },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeReportGeneration({
    required String missionId,
    required List<EvidenceItem> selectedEvidence,
    required Set<DetectionType> selectedClasses,
  }) async {
    setState(() => _isGenerating = true);
    try {
      final missionState = ref.read(missionProvider);
      final matchedMission = missionState.missionHistory
          .where((m) => m.id == missionId)
          .firstOrNull;

      final report = await PdfReportService.generateReport(
        missionId: missionId,
        missionName:
            matchedMission?.name ??
            (missionId == 'ALL' ? 'Comprehensive Inspection Run' : missionId),
        inspectionDate: matchedMission?.date ?? DateTime.now(),
        duration: matchedMission?.duration ?? const Duration(minutes: 15),
        selectedEvidence: selectedEvidence,
        selectedClasses: selectedClasses,
        totalDistanceKm: matchedMission?.distance,
      );

      ref.read(reportProvider.notifier).addReport(report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Inspection report PDF compiled successfully!'),
                ),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    _openPdfViewer(report);
                  },
                  child: const Text(
                    'PREVIEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _openPdfViewer(InspectionReport report) {
    if (report.pdfFilePath == null || !File(report.pdfFilePath!).existsSync())
      return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(report.id),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.share2),
                tooltip: 'Share PDF',
                onPressed: () => PdfReportService.shareReportPdf(report),
              ),
              IconButton(
                icon: const Icon(LucideIcons.printer),
                tooltip: 'Print',
                onPressed: () => PdfReportService.printReport(report),
              ),
            ],
          ),
          body: PdfPreview(
            build: (format) async => File(report.pdfFilePath!).readAsBytes(),
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportProvider);

    return Scaffold(
      body: reports.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.fileBarChart,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No inspection reports compiled yet',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Generate a downloadable PDF report from captured photo evidence.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(LucideIcons.filePlus, size: 18),
                    label: const Text('Generate Inspection Report'),
                    onPressed: _openGenerateReportDialog,
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Generate Button & Report Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(LucideIcons.filePlus, size: 16),
                        label: const Text('Generate Report'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        onPressed: _openGenerateReportDialog,
                      ),
                      DropdownButton<int>(
                        value: _activeReportIndex.clamp(0, reports.length - 1),
                        dropdownColor: AppTheme.card,
                        underline: const SizedBox(),
                        icon: const Icon(
                          LucideIcons.chevronDown,
                          color: AppTheme.secondary,
                        ),
                        items: List.generate(reports.length, (index) {
                          return DropdownMenuItem(
                            value: index,
                            child: Text(
                              reports[index].missionName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _activeReportIndex = val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Active Report Details Card
                  _buildActiveReportCard(
                    reports[_activeReportIndex.clamp(0, reports.length - 1)],
                  ),
                  const SizedBox(height: 24),

                  // Metrics summary
                  _buildSpecsSummary(
                    context,
                    reports[_activeReportIndex.clamp(0, reports.length - 1)],
                  ),
                  const SizedBox(height: 24),

                  // Pie Chart: Anomaly Distribution
                  Text(
                    'ANOMALY RATIO DISTRIBUTION',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassPanel(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 3,
                              centerSpaceRadius: 36,
                              sections: _buildPieSections(
                                reports[_activeReportIndex.clamp(
                                  0,
                                  reports.length - 1,
                                )],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildPieLegend(
                              reports[_activeReportIndex.clamp(
                                0,
                                reports.length - 1,
                              )],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons: Preview PDF, Share, Delete
                  _buildReportActions(
                    reports[_activeReportIndex.clamp(0, reports.length - 1)],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveReportCard(InspectionReport report) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REPORT: ${report.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.secondary,
                ),
              ),
              Text(
                '${report.date.month}/${report.date.day}/${report.date.year}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (report.executiveSummary != null) ...[
            const SizedBox(height: 8),
            Text(
              report.executiveSummary!,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecsSummary(BuildContext context, InspectionReport activeRep) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        _buildMetricTile(
          'Evidence Analyzed',
          '${activeRep.totalImages} Photos',
        ),
        _buildMetricTile(
          'Defects Found',
          '${activeRep.totalDetections} Anomalies',
        ),
        _buildMetricTile(
          'Inspection Duration',
          '${activeRep.duration.inMinutes} mins',
        ),
        _buildMetricTile(
          'PDF Document',
          activeRep.pdfFilePath != null ? 'Compiled' : 'Draft',
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            val,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportActions(InspectionReport report) {
    final hasPdf =
        report.pdfFilePath != null && File(report.pdfFilePath!).existsSync();

    return Row(
      children: [
        // Preview & Print PDF
        Expanded(
          child: AnimatedButton(
            onTap: () {
              if (hasPdf) {
                _openPdfViewer(report);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No PDF compiled for this report yet.'),
                  ),
                );
              }
            },
            child: ElevatedButton.icon(
              onPressed: () {
                if (hasPdf) _openPdfViewer(report);
              },
              icon: const Icon(LucideIcons.fileText, size: 16),
              label: const Text('Preview PDF'),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Share PDF
        Expanded(
          child: AnimatedButton(
            color: AppTheme.surface,
            onTap: () {
              if (hasPdf) {
                PdfReportService.shareReportPdf(report);
              }
            },
            child: OutlinedButton.icon(
              onPressed: () {
                if (hasPdf) PdfReportService.shareReportPdf(report);
              },
              icon: const Icon(LucideIcons.share2, size: 16),
              label: const Text('Share PDF'),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Delete Report
        IconButton(
          icon: const Icon(
            LucideIcons.trash2,
            color: AppTheme.danger,
            size: 20,
          ),
          tooltip: 'Delete Report',
          onPressed: () async {
            await ref.read(reportProvider.notifier).deleteReport(report.id);
            if (mounted) {
              setState(() => _activeReportIndex = 0);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report deleted successfully.')),
              );
            }
          },
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections(InspectionReport activeRep) {
    final Map<String, int> counts = activeRep.anomalyDistribution;
    final total = counts.values.fold(0, (sum, val) => sum + val);

    if (total == 0) {
      return [
        PieChartSectionData(
          color: AppTheme.secondary,
          value: 100,
          title: 'Clean',
          radius: 20,
          titleStyle: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ];
    }

    final colors = [
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFF10B981),
      const Color(0xFF38BDF8),
      const Color(0xFFF59E0B),
    ];
    int colorIdx = 0;

    return counts.entries.where((e) => e.value > 0).map((entry) {
      final color = colors[colorIdx % colors.length];
      colorIdx++;
      final double percent = (entry.value / total) * 100;
      return PieChartSectionData(
        color: color,
        value: entry.value.toDouble(),
        title: '${percent.toStringAsFixed(0)}%',
        radius: 22,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<Widget> _buildPieLegend(InspectionReport activeRep) {
    final Map<String, int> counts = activeRep.anomalyDistribution;
    final total = counts.values.fold(0, (sum, val) => sum + val);

    if (total == 0) {
      return [
        const Text(
          'Zero defects logged.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ];
    }

    final colors = [
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFF10B981),
      const Color(0xFF38BDF8),
      const Color(0xFFF59E0B),
    ];
    int colorIdx = 0;

    return counts.entries.where((e) => e.value > 0).map((entry) {
      final color = colors[colorIdx % colors.length];
      colorIdx++;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${entry.key}: ${entry.value}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ],
        ),
      );
    }).toList();
  }
}
