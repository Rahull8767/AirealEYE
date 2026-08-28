import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _followDrone = true;
  
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
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final plannerState = ref.watch(missionProvider);
    final plannedPoints = plannerState.plannedWaypoints;

    // Follow drone logic
    if (_followDrone && telemetry.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(LatLng(telemetry.latitude, telemetry.longitude), _mapController.camera.zoom);
      });
    }

    final pathPoints = plannedPoints.map((wp) => LatLng(wp.latitude, wp.longitude)).toList();

    // Create marker widgets from detections
    final List<Marker> markers = detections.map((d) {
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

    // Add waypoint markers
    for (var wp in plannedPoints) {
      markers.add(
        Marker(
          point: LatLng(wp.latitude, wp.longitude),
          width: 24,
          height: 24,
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
            child: Center(
              child: Text(
                '${wp.id}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),
          ),
        ),
      );
    }

    final homeLatLng = LatLng(37.7749, -122.4194);

    // Add home marker and drone marker
    if (telemetry.isConnected) {
      markers.add(
        Marker(
          point: homeLatLng,
          width: 32,
          height: 32,
          child: const Icon(
            LucideIcons.home,
            color: AppTheme.success,
            size: 24,
          ),
        ),
      );

      markers.add(
        Marker(
          point: LatLng(telemetry.latitude, telemetry.longitude),
          width: 40,
          height: 40,
          child: Transform.rotate(
            angle: telemetry.heading * (3.1415926535 / 180),
            child: const Icon(
              LucideIcons.plane,
              color: AppTheme.secondary,
              size: 32,
            ),
          ),
        ),
      );
    }

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
              if (pathPoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: pathPoints,
                      color: AppTheme.secondary,
                      strokeWidth: 3.0,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),

          // 2. Follow Drone Button
          Positioned(
            right: 16,
            bottom: 200,
            child: FloatingActionButton.small(
              heroTag: 'follow_drone_fab',
              onPressed: () {
                setState(() {
                  _followDrone = !_followDrone;
                });
              },
              backgroundColor: _followDrone ? AppTheme.secondary : AppTheme.card,
              foregroundColor: _followDrone ? Colors.white : AppTheme.textSecondary,
              child: const Icon(LucideIcons.compass, size: 18),
            ),
          ),

          // 3. Floating Map Layer Controller
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

          // 4. Pin Legend Panel (Left Top)
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

          // 5. Flight Info Panel (Left Bottom)
          Positioned(
            left: 16,
            bottom: 16,
            child: GlassPanel(
              width: 200,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FLIGHT OVERVIEW',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 8),
                  _buildSpecRow('Link State', telemetry.isConnected ? 'CONNECTED' : 'DISCONNECTED'),
                  _buildSpecRow('Flight Mode', telemetry.flightMode),
                  _buildSpecRow('Altitude AGL', '${telemetry.altitude.toStringAsFixed(1)} m'),
                  _buildSpecRow('Ground Speed', '${telemetry.speed.toStringAsFixed(1)} m/s'),
                  _buildSpecRow('GPS Locked', telemetry.isConnected ? '${telemetry.satellites} Sats' : 'No Signal'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
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
