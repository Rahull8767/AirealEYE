import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/report.dart';
import 'package:aerial_eye/providers/report_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _activeReportIndex = 0;

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportProvider);

    if (reports.isEmpty) {
      return Scaffold(
        body: Center(
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
                'Complete an autonomous flight to log road data.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final activeRep = reports[_activeReportIndex.clamp(0, reports.length - 1)];

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Report Selector Dropdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DropdownButton<int>(
                  value: _activeReportIndex,
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
                          fontSize: 16,
                          color: AppTheme.textPrimary,
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
                Text(
                  '${activeRep.date.month}/${activeRep.date.day}/${activeRep.date.year}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Metrics summary
            _buildSpecsSummary(context, activeRep),
            const SizedBox(height: 24),

            // 3. Pie Chart Anomaly Distribution
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
                        centerSpaceRadius: 40,
                        sections: _buildPieSections(activeRep),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildPieLegend(activeRep),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4. Bar Chart: Comparative defects across last missions
            Text(
              'ANOMALIES COUNT COMPARATIVE',
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
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < reports.length) {
                            // Shortened names
                            final words = reports[idx].missionName.split(' ');
                            final shortName = words.isNotEmpty
                                ? words.first
                                : '';
                            return Text(
                              shortName,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(reports.length, (idx) {
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: reports[idx].totalDetections.toDouble(),
                          color: AppTheme.secondary,
                          width: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 5. Actions
            Row(
              children: [
                Expanded(
                  child: AnimatedButton(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Generating PDF Report... Saved to Documents/AerialEye',
                          ),
                        ),
                      );
                    },
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(LucideIcons.fileText, size: 18),
                      label: const Text('Download PDF'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedButton(
                    color: AppTheme.surface,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report details shared successfully.'),
                        ),
                      );
                    },
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(LucideIcons.share2, size: 18),
                      label: const Text('Share Specs'),
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
          'Inspection Area',
          '${activeRep.totalDistanceKm.toStringAsFixed(1)} km²',
        ),
        _buildMetricTile(
          'Path Coverage',
          '${activeRep.coveragePercent.toStringAsFixed(1)}%',
        ),
        _buildMetricTile('Flight Time', '${activeRep.duration.inMinutes} mins'),
        _buildMetricTile('Images Saved', '${activeRep.totalImages} Frames'),
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
      Colors.red,
      Colors.orange,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.cyan,
      Colors.yellow,
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
      return [const Text('No issues identified.')];
    }

    final colors = [
      Colors.red,
      Colors.orange,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.cyan,
      Colors.yellow,
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
