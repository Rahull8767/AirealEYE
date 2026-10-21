import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MiniChart extends StatelessWidget {
  final List<double> dataPoints;
  final Color lineColor;

  const MiniChart({
    super.key,
    required this.dataPoints,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) {
      return const SizedBox(height: 30, child: Center(child: Text('No data')));
    }

    final spots = List.generate(dataPoints.length, (index) {
      return FlSpot(index.toDouble(), dataPoints[index]);
    });

    final double minVal = dataPoints.reduce((a, b) => a < b ? a : b);
    final double maxVal = dataPoints.reduce((a, b) => a > b ? a : b);
    final double padding = (maxVal - minVal) == 0
        ? 1.0
        : (maxVal - minVal) * 0.15;

    return SizedBox(
      height: 32,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (dataPoints.length - 1).toDouble(),
          minY: minVal - padding,
          maxY: maxVal + padding,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 1.8,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
