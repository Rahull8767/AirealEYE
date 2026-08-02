import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  
  // Custom Map Layer Types
  String _activeTileLayer = 'dark'; // dark, light, osm, terrain

  final Map<String, String> _tileProviders = {
    'dark': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    'light': 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain': 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
  };

  void _showMarkerPopup(AiDetection d) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: d.color.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Center(
                child: Icon(_iconForType(d.type), color: d.color, size: 48),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.typeLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text('Confidence: ${(d.confidence * 100).toStringAsFixed(0)}%'),
                  Text('Mission ID: ${d.missionId}'),
                  Text('Coords: [${d.latitude.toStringAsFixed(5)}, ${d.longitude.toStringAsFixed(5)}]'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(LucideIcons.navigation, size: 16),
                        label: const Text('Directions'),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Calculating route to anomaly site...')),
                          );
                          Navigator.pop(context);
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(LucideIcons.share2, size: 16),
                        label: const Text('Share'),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Report copied to clipboard.')),
                          );
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detectionState = ref.watch(detectionProvider);
    final detections = detectionState.detections;

    // Create marker widgets from detections
    final List<Marker> mapMarkers = detections.map((d) {
      return Marker(
        point: LatLng(d.latitude, d.longitude),
        width: 32,
        height: 32,
        child: GestureDetector(
          onTap: () => _showMarkerPopup(d),
          child: Container(
            decoration: BoxDecoration(
              color: d.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.0),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, spreadRadius: 1)],
            ),
            child: Icon(
              _iconForType(d.type),
              color: Colors.white,
              size: 14,
            ),
          ),
        ),
      );
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map Canvas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
              initialZoom: AppConstants.defaultZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: _tileProviders[_activeTileLayer]!,
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              MarkerLayer(markers: mapMarkers),
            ],
          ),

          // 2. Floating Map Layer Controller
          Positioned(
            right: 16,
            bottom: 16,
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMapTypeBtn('dark', LucideIcons.moon, 'Dark'),
                  const SizedBox(height: 6),
                  _buildMapTypeBtn('light', LucideIcons.sun, 'Light'),
                  const SizedBox(height: 6),
                  _buildMapTypeBtn('osm', LucideIcons.map, 'OSM'),
                  const SizedBox(height: 6),
                  _buildMapTypeBtn('terrain', LucideIcons.mountain, 'Terrain'),
                ],
              ),
            ),
          ),

          // 3. Pin Legend Panel (Left Top)
          Positioned(
            left: 16,
            top: 16,
            child: GlassPanel(
              width: 180,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'DEFECT PIN LEGEND',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 8),
                  _buildLegendRow('Potholes', Colors.red),
                  _buildLegendRow('Cracks', Colors.orange),
                  _buildLegendRow('Garbage', Colors.green),
                  _buildLegendRow('Water Log', Colors.blue),
                  _buildLegendRow('Obstacles', Colors.purple),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTypeBtn(String id, IconData icon, String label) {
    final bool isSelected = _activeTileLayer == id;
    return InkWell(
      onTap: () => setState(() => _activeTileLayer = id),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.secondary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? AppTheme.secondary : AppTheme.textSecondary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildLegendRow(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  IconData _iconForType(DetectionType type) {
    switch (type) {
      case DetectionType.pothole:
        return LucideIcons.circle;
      case DetectionType.roadCrack:
        return LucideIcons.gitCommit;
      case DetectionType.garbage:
        return LucideIcons.trash2;
      case DetectionType.waterLogging:
        return LucideIcons.droplets;
      case DetectionType.animal:
        return LucideIcons.dog;
      case DetectionType.obstacle:
        return LucideIcons.construction;
      case DetectionType.brokenRoadSign:
        return LucideIcons.alertOctagon;
    }
  }
}
