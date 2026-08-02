import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/core/constants/app_constants.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/animated_button.dart';

class MissionPlannerScreen extends ConsumerStatefulWidget {
  const MissionPlannerScreen({super.key});

  @override
  ConsumerState<MissionPlannerScreen> createState() => _MissionPlannerScreenState();
}

class _MissionPlannerScreenState extends ConsumerState<MissionPlannerScreen> {
  final MapController _mapController = MapController();

  void _editWaypointSheet(Waypoint wp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double localAlt = wp.altitude;
            double localSpeed = wp.speed;
            int localHover = wp.hoverTime;

            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Waypoint #${wp.id} Config',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.trash2, color: AppTheme.danger),
                        onPressed: () {
                          ref.read(missionProvider.notifier).deleteWaypoint(wp.id);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Altitude Slider
                  Text('Waypoint Altitude: ${localAlt.toStringAsFixed(0)} meters AGL'),
                  Slider(
                    value: localAlt,
                    min: 10,
                    max: 120,
                    activeColor: AppTheme.secondary,
                    onChanged: (val) {
                      setSheetState(() => localAlt = val);
                      ref.read(missionProvider.notifier).updateWaypoint(wp.copyWith(altitude: val));
                    },
                  ),

                  // Speed Slider
                  Text('Transit Speed: ${localSpeed.toStringAsFixed(1)} m/s'),
                  Slider(
                    value: localSpeed,
                    min: 1,
                    max: 15,
                    activeColor: AppTheme.warning,
                    onChanged: (val) {
                      setSheetState(() => localSpeed = val);
                      ref.read(missionProvider.notifier).updateWaypoint(wp.copyWith(speed: val));
                    },
                  ),

                  // Hover Time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Hover Delay:'),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.minusCircle),
                            onPressed: () {
                              if (localHover > 0) {
                                setSheetState(() => localHover--);
                                ref.read(missionProvider.notifier).updateWaypoint(wp.copyWith(hoverTime: localHover));
                              }
                            },
                          ),
                          Text('$localHover sec', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(LucideIcons.plusCircle),
                            onPressed: () {
                              setSheetState(() => localHover++);
                              ref.read(missionProvider.notifier).updateWaypoint(wp.copyWith(hoverTime: localHover));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final plannerState = ref.watch(missionProvider);
    final plannedPoints = plannerState.plannedWaypoints;

    // Convert waypoints to LatLng list
    final pathPoints = plannedPoints.map((wp) => LatLng(wp.latitude, wp.longitude)).toList();

    // Map markers
    final List<Marker> markers = [];
    
    // Add drone marker if connected
    if (telemetry.isConnected) {
      markers.add(
        Marker(
          point: LatLng(telemetry.latitude, telemetry.longitude),
          width: 32,
          height: 32,
          child: Transform.rotate(
            angle: telemetry.heading * (3.14159 / 180),
            child: const Icon(
              LucideIcons.plane,
              color: AppTheme.secondary,
              size: 26,
            ),
          ),
        ),
      );
    }

    // Add waypoint markers
    for (var wp in plannedPoints) {
      markers.add(
        Marker(
          point: LatLng(wp.latitude, wp.longitude),
          width: 28,
          height: 28,
          child: GestureDetector(
            onTap: () => _editWaypointSheet(wp),
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4, spreadRadius: 1)],
              ),
              child: Center(
                child: Text(
                  '${wp.id}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final double totalDistance = plannedPoints.length * 0.28;
    final int estimatedMinutes = (plannedPoints.length * 1.5).ceil();

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map Canvas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
              initialZoom: AppConstants.defaultZoom,
              onTap: (tapPosition, point) {
                ref.read(missionProvider.notifier).addWaypoint(point.latitude, point.longitude);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
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

          // 2. Mission Overview Floating Panel
          Positioned(
            left: 16,
            top: 16,
            child: GlassPanel(
              width: 250,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mission Specs',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildSpecRow('Distance', '${totalDistance.toStringAsFixed(2)} km'),
                  _buildSpecRow('Flight Duration', '$estimatedMinutes mins'),
                  _buildSpecRow('Waypoints added', '${plannedPoints.length} points'),
                  const Divider(color: AppTheme.border, height: 16),
                  
                  // Undo / Redo / Clear
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.undo2, size: 18),
                        onPressed: plannerState.undoHistory.isNotEmpty
                            ? () => ref.read(missionProvider.notifier).undo()
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.redo2, size: 18),
                        onPressed: plannerState.redoHistory.isNotEmpty
                            ? () => ref.read(missionProvider.notifier).redo()
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.trash, size: 18, color: AppTheme.danger),
                        onPressed: plannedPoints.isNotEmpty
                            ? () => ref.read(missionProvider.notifier).clearMission()
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. Right Action Float Column
          Positioned(
            right: 16,
            top: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFloatingActionBtn(
                  context,
                  LucideIcons.compass,
                  'Center',
                  () {
                    if (plannedPoints.isNotEmpty) {
                      _mapController.move(LatLng(plannedPoints.first.latitude, plannedPoints.first.longitude), 16);
                    } else if (telemetry.isConnected) {
                      _mapController.move(LatLng(telemetry.latitude, telemetry.longitude), 16);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildFloatingActionBtn(
                  context,
                  LucideIcons.uploadCloud,
                  'Upload',
                  plannedPoints.isEmpty
                      ? null
                      : () => ref.read(missionProvider.notifier).uploadMission(),
                ),
                const SizedBox(height: 8),
                _buildFloatingActionBtn(
                  context,
                  LucideIcons.play,
                  'Start',
                  (!plannerState.isUploaded || plannerState.activeMission != null)
                      ? null
                      : () {
                          if (!telemetry.isConnected) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Drone disconnected. Power on telemetry first.'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                            return;
                          }
                          ref.read(missionProvider.notifier).startMission();
                        },
                ),
              ],
            ),
          ),

          // 4. Waypoint list drawer button or active status indicator
          if (plannerState.activeMission != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: GlassPanel(
                color: AppTheme.success.withOpacity(0.12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(LucideIcons.activity, color: AppTheme.success, size: 18),
                        SizedBox(width: 8),
                        Text('AUTOPILOT MISSION RUNNING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.success)),
                      ],
                    ),
                    AnimatedButton(
                      color: AppTheme.danger,
                      onTap: () => ref.read(missionProvider.notifier).stopMission(MissionStatus.failed),
                      child: ElevatedButton(
                        onPressed: () => ref.read(missionProvider.notifier).stopMission(MissionStatus.failed),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: const Text('RTL'),
                      ),
                    ),
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

  Widget _buildFloatingActionBtn(BuildContext context, IconData icon, String tooltip, VoidCallback? onTap) {
    final bool disabled = onTap == null;
    return FloatingActionButton.small(
      heroTag: 'fab_$tooltip',
      onPressed: onTap,
      backgroundColor: disabled ? AppTheme.surface.withOpacity(0.5) : AppTheme.card,
      foregroundColor: disabled ? AppTheme.textSecondary : AppTheme.secondary,
      child: Icon(icon, size: 18),
    );
  }
}
