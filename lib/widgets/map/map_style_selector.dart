import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/config/map_config.dart';
import 'package:aerial_eye/providers/map_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

/// Floating Map Style Selector & Attribution Badge
class MapStyleSelectorWidget extends ConsumerWidget {
  const MapStyleSelectorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapState = ref.watch(mapProvider);
    final currentStyle = mapState.activeStyle;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: MapTileStyle.values.map((style) {
          final config = MapConfig.getConfig(style);
          final bool isSelected = currentStyle == style;

          return Tooltip(
            message: config.displayName,
            child: InkWell(
              onTap: () {
                ref.read(mapProvider.notifier).setMapStyle(style);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.secondary.withValues(alpha: 0.25) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppTheme.secondary : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  config.icon,
                  size: 18,
                  color: isSelected ? AppTheme.secondary : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Map Attribution Badge to comply with OpenStreetMap / Carto / Esri terms
class MapAttributionBadge extends ConsumerWidget {
  const MapAttributionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapState = ref.watch(mapProvider);
    final config = MapConfig.getConfig(mapState.activeStyle);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        config.attribution,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
