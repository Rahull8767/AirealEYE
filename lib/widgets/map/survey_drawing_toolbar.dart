import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/providers/survey_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

/// Interactive Floating Toolbar for Drawing Survey Polygons and Generating Grids
class SurveyDrawingToolbarWidget extends ConsumerWidget {
  final VoidCallback? onSettingsTap;

  const SurveyDrawingToolbarWidget({super.key, this.onSettingsTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surveyState = ref.watch(surveyProvider);
    final area = surveyState.activeArea;
    final vertexCount = area.vertices.length;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Mode Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: surveyState.isDrawing
                          ? AppTheme.warning
                          : AppTheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    surveyState.isDrawing
                        ? 'DRAWING SURVEY AREA'
                        : 'SURVEY POLYGON READY',
                    style: TextStyle(
                      color: surveyState.isDrawing
                          ? AppTheme.warning
                          : AppTheme.success,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (onSettingsTap != null)
                IconButton(
                  icon: const Icon(
                    LucideIcons.sliders,
                    size: 16,
                    color: AppTheme.secondary,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Survey Grid Parameters',
                  onPressed: onSettingsTap,
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Area & Vertex Readout
          Row(
            children: [
              _buildMetric('Vertices', '$vertexCount'),
              const SizedBox(width: 16),
              _buildMetric('Area', area.formattedArea),
              const SizedBox(width: 16),
              _buildMetric(
                'Altitude',
                '${area.parameters.flightAltitude.toStringAsFixed(0)}m',
              ),
            ],
          ),
          const Divider(color: AppTheme.border, height: 16),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Undo last point
              IconButton(
                icon: const Icon(LucideIcons.undo2, size: 16),
                tooltip: 'Undo Vertex',
                onPressed: vertexCount > 0
                    ? () => ref.read(surveyProvider.notifier).undoVertex()
                    : null,
              ),

              // Finish Polygon (if >= 3 points)
              if (surveyState.isDrawing)
                ElevatedButton.icon(
                  icon: const Icon(LucideIcons.check, size: 14),
                  label: const Text(
                    'Finish Area',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: vertexCount >= 3
                      ? () => ref.read(surveyProvider.notifier).finishPolygon()
                      : null,
                ),

              // Generate Grid & Apply to Mission
              if (!surveyState.isDrawing && vertexCount >= 3)
                ElevatedButton.icon(
                  icon: const Icon(LucideIcons.grid, size: 14),
                  label: const Text(
                    'Create Grid',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () {
                    ref
                        .read(surveyProvider.notifier)
                        .applyGridToMissionPlanner();
                  },
                ),

              // Clear polygon
              IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: AppTheme.danger,
                ),
                tooltip: 'Clear Polygon',
                onPressed: vertexCount > 0
                    ? () => ref.read(surveyProvider.notifier).clearPolygon()
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
