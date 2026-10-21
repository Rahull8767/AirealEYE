import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

class MissionHistoryScreen extends ConsumerStatefulWidget {
  const MissionHistoryScreen({super.key});

  @override
  ConsumerState<MissionHistoryScreen> createState() =>
      _MissionHistoryScreenState();
}

class _MissionHistoryScreenState extends ConsumerState<MissionHistoryScreen> {
  String _activeFilter = 'ALL'; // ALL, COMPLETED, FAILED, RUNNING

  @override
  Widget build(BuildContext context) {
    final missionPlannerState = ref.watch(missionProvider);
    final history = missionPlannerState.missionHistory;

    // Apply Filter
    final filteredHistory = history.where((m) {
      if (_activeFilter == 'ALL') return true;
      if (_activeFilter == 'COMPLETED')
        return m.status == MissionStatus.completed;
      if (_activeFilter == 'FAILED') return m.status == MissionStatus.failed;
      if (_activeFilter == 'RUNNING') return m.status == MissionStatus.running;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mission History Logs'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 1. Filter Chips Row
          Container(
            color: AppTheme.card,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFilterChip('ALL'),
                _buildFilterChip('COMPLETED'),
                _buildFilterChip('FAILED'),
                _buildFilterChip('RUNNING'),
              ],
            ),
          ),

          // 2. Timeline List
          Expanded(
            child: filteredHistory.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.history,
                          size: 48,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No matching missions found',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredHistory.length,
                    itemBuilder: (context, index) {
                      final m = filteredHistory[index];
                      return _buildTimelineItem(
                        context,
                        m,
                        index == filteredHistory.length - 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter) {
    final isSelected = _activeFilter == filter;
    return ChoiceChip(
      label: Text(
        filter,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _activeFilter = filter),
      selectedColor: AppTheme.secondary.withOpacity(0.2),
      backgroundColor: AppTheme.surface,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.secondary : AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildTimelineItem(BuildContext context, Mission m, bool isLast) {
    final dateStr =
        '${m.date.month}/${m.date.day}/${m.date.year} • ${m.date.hour}:${m.date.minute.toString().padLeft(2, '0')}';
    final statusColor = _statusColor(m.status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline indicator column
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2.0, color: AppTheme.border)),
            ],
          ),
          const SizedBox(width: 16),

          // Timeline content card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          m.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            m.status.name.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStat('Distance', '${m.distance} km'),
                        _buildStat(
                          'Duration',
                          '${m.duration.inMinutes}m ${m.duration.inSeconds % 60}s',
                        ),
                        _buildStat('Waypoints', '${m.waypoints.length} points'),
                      ],
                    ),
                    const Divider(color: AppTheme.border, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildCardBtn('Replay', LucideIcons.rotateCcw, () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Simulating mission flight path...',
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 8),
                        _buildCardBtn('Report', LucideIcons.fileText, () {
                          // Quick dialog
                          _showReportDetails(context, m);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 8,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCardBtn(String label, IconData icon, VoidCallback onTap) {
    return AnimatedButton(
      color: AppTheme.surface,
      onTap: onTap,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 12, color: AppTheme.secondary),
        label: Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textPrimary),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _showReportDetails(BuildContext context, Mission m) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(m.name),
        content: Text(
          'Detailed inspection log for flight: ${m.id}.\n\nDistance: ${m.distance} km\nDuration: ${m.duration.inMinutes} mins\nStatus: ${m.status.name.toUpperCase()}\nDate: ${m.date.toString()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(MissionStatus status) {
    switch (status) {
      case MissionStatus.completed:
        return AppTheme.success;
      case MissionStatus.failed:
        return AppTheme.danger;
      case MissionStatus.running:
        return AppTheme.secondary;
      default:
        return AppTheme.textSecondary;
    }
  }
}
