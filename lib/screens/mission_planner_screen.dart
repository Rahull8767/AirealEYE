import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/config/map_config.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/mission.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/map_provider.dart';
import 'package:aerial_eye/providers/survey_provider.dart';
import 'package:aerial_eye/providers/user_location_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/map/drone_marker.dart';
import 'package:aerial_eye/widgets/map/user_location_marker.dart';
import 'package:aerial_eye/widgets/map/waypoint_marker.dart';
import 'package:aerial_eye/widgets/map/map_style_selector.dart';
import 'package:aerial_eye/widgets/map/survey_drawing_toolbar.dart';

class MissionPlannerScreen extends ConsumerStatefulWidget {
  const MissionPlannerScreen({super.key});

  @override
  ConsumerState<MissionPlannerScreen> createState() =>
      _MissionPlannerScreenState();
}

class _MissionPlannerScreenState extends ConsumerState<MissionPlannerScreen> {
  final MapController _mapController = MapController();
  bool _surveyModeActive = false;

  void _showSaveMissionDialog() {
    final controller = TextEditingController(
      text:
          'Inspection Route ${ref.read(missionProvider).missionHistory.length + 1}',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Save Mission Template'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Mission Template Name',
            hintText: 'e.g. Oak Street Grid',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(missionProvider.notifier).saveCurrentMission(name);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLoadMissionDialog() {
    final history = ref.read(missionProvider).missionHistory;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Load Mission Template'),
        content: history.isEmpty
            ? const Text('No saved mission templates found.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, idx) {
                    final item = history[idx];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.inspectionType.label} • ${item.waypoints.length} points • ${item.distance.toStringAsFixed(2)} km',
                      ),
                      trailing: const Icon(LucideIcons.arrowUpRight, size: 16),
                      onTap: () {
                        ref.read(missionProvider.notifier).loadMission(item);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
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

  void _generateLawnmowerGrid() {
    final center = _mapController.camera.center;
    ref
        .read(missionProvider.notifier)
        .generateGrid(center.latitude, center.longitude);
  }

  void _showWaypointsManagerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final plannerState = ref.watch(missionProvider);
            final waypoints = plannerState.plannedWaypoints;

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.listOrdered,
                            color: AppTheme.secondary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Waypoints Manager (${waypoints.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    'Drag handles to reorder execution sequence or tap to configure altitude/speed.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Divider(color: AppTheme.border, height: 20),
                  Expanded(
                    child: waypoints.isEmpty
                        ? const Center(
                            child: Text(
                              'No waypoints added yet. Tap on the map to add points.',
                            ),
                          )
                        : ReorderableListView.builder(
                            itemCount: waypoints.length,
                            onReorder: (oldIdx, newIdx) {
                              ref
                                  .read(missionProvider.notifier)
                                  .reorderWaypoints(oldIdx, newIdx);
                            },
                            itemBuilder: (context, index) {
                              final wp = waypoints[index];
                              return Card(
                                key: ValueKey('wp_${wp.id}_$index'),
                                color: AppTheme.surface,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppTheme.primary,
                                    child: Text(
                                      '${wp.id}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    'WP ${wp.id}: [${wp.latitude.toStringAsFixed(5)}, ${wp.longitude.toStringAsFixed(5)}]',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Alt: ${wp.altitude.toStringAsFixed(0)}m • Spd: ${wp.speed.toStringAsFixed(1)}m/s • Hover: ${wp.hoverTime}s',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          LucideIcons.sliders,
                                          size: 16,
                                          color: AppTheme.secondary,
                                        ),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _editWaypointSheet(wp);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          LucideIcons.trash,
                                          size: 16,
                                          color: AppTheme.danger,
                                        ),
                                        onPressed: () {
                                          ref
                                              .read(missionProvider.notifier)
                                              .deleteWaypoint(wp.id);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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

  void _showPreFlightCheckDialog() {
    final telemetry =
        ref.read(droneTelemetryProvider).value ?? DroneTelemetry.initial();
    final plannerState = ref.read(missionProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(LucideIcons.shieldCheck, color: AppTheme.secondary, size: 22),
            SizedBox(width: 10),
            Text(
              'Pre-Flight Safety Check',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verify vehicle state before engaging autonomous AUTO mode:',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            _buildSafetyRow(
              'Inspection Type',
              plannerState.selectedInspectionType.label,
              Colors.white,
            ),
            _buildSafetyRow(
              'MAVLink Link',
              telemetry.isConnected ? 'CONNECTED' : 'DISCONNECTED',
              telemetry.isConnected ? AppTheme.success : AppTheme.danger,
            ),
            _buildSafetyRow(
              'Flight Mode',
              telemetry.flightMode,
              AppTheme.secondary,
            ),
            _buildSafetyRow(
              'Motor Armed',
              telemetry.armed ? 'ARMED' : 'DISARMED',
              telemetry.armed ? AppTheme.success : AppTheme.warning,
            ),
            _buildSafetyRow(
              'GPS Fix',
              telemetry.isConnected
                  ? '${telemetry.satellites} Satellites'
                  : 'No Fix',
              telemetry.satellites >= 6 ? AppTheme.success : AppTheme.warning,
            ),
            _buildSafetyRow(
              'Battery Pack',
              '${telemetry.batteryVoltageDisplay} (${telemetry.batteryPercentDisplay})',
              telemetry.batteryVoltage >= 14.8
                  ? AppTheme.success
                  : AppTheme.warning,
            ),
            _buildSafetyRow(
              'Waypoints in Queue',
              '${plannerState.plannedWaypoints.length} points',
              AppTheme.primary,
            ),
            const SizedBox(height: 12),
            if (!telemetry.armed)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      color: AppTheme.warning,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vehicle is currently disarmed. Starting mission will switch mode to AUTO; ensure motors are ready.',
                        style: TextStyle(fontSize: 11, color: AppTheme.warning),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () {
              Navigator.pop(context);
              ref.read(missionProvider.notifier).startMission();
            },
            child: const Text('Confirm & Launch Mission'),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.trash2,
                          color: AppTheme.danger,
                        ),
                        onPressed: () {
                          ref
                              .read(missionProvider.notifier)
                              .deleteWaypoint(wp.id);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Waypoint Altitude: ${localAlt.toStringAsFixed(0)} meters AGL',
                  ),
                  Slider(
                    value: localAlt,
                    min: 10,
                    max: 120,
                    activeColor: AppTheme.secondary,
                    onChanged: (val) {
                      setSheetState(() => localAlt = val);
                      ref
                          .read(missionProvider.notifier)
                          .updateWaypoint(wp.copyWith(altitude: val));
                    },
                  ),
                  Text('Transit Speed: ${localSpeed.toStringAsFixed(1)} m/s'),
                  Slider(
                    value: localSpeed,
                    min: 1,
                    max: 15,
                    activeColor: AppTheme.warning,
                    onChanged: (val) {
                      setSheetState(() => localSpeed = val);
                      ref
                          .read(missionProvider.notifier)
                          .updateWaypoint(wp.copyWith(speed: val));
                    },
                  ),
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
                                ref
                                    .read(missionProvider.notifier)
                                    .updateWaypoint(
                                      wp.copyWith(hoverTime: localHover),
                                    );
                              }
                            },
                          ),
                          Text(
                            '$localHover sec',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.plusCircle),
                            onPressed: () {
                              setSheetState(() => localHover++);
                              ref
                                  .read(missionProvider.notifier)
                                  .updateWaypoint(
                                    wp.copyWith(hoverTime: localHover),
                                  );
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
    final mapState = ref.watch(mapProvider);
    final layerConfig = MapConfig.getConfig(mapState.activeStyle);
    final surveyState = ref.watch(surveyProvider);
    final surveyArea = surveyState.activeArea;
    final userLocation = ref.watch(userLocationProvider);

    final pathPoints = plannedPoints
        .map((wp) => LatLng(wp.latitude, wp.longitude))
        .toList();

    final List<Marker> markers = [];

    // Add user phone marker if available
    if (userLocation.userPosition != null) {
      markers.add(
        Marker(
          point: userLocation.userPosition!,
          width: 44,
          height: 44,
          child: UserLocationMarkerWidget(
            accuracyMeters: userLocation.accuracy,
            heading: userLocation.heading,
            onTap: () {
              _mapController.move(userLocation.userPosition!, 16);
            },
          ),
        ),
      );
    }

    // Add drone marker if connected
    if (telemetry.isConnected &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0)) {
      markers.add(
        Marker(
          point: LatLng(telemetry.latitude, telemetry.longitude),
          width: 44,
          height: 52,
          child: DroneMarkerWidget(
            telemetry: telemetry,
            onTap: () {
              _mapController.move(
                LatLng(telemetry.latitude, telemetry.longitude),
                16,
              );
            },
          ),
        ),
      );
    }

    // Add waypoint markers
    for (int i = 0; i < plannedPoints.length; i++) {
      final wp = plannedPoints[i];
      final bool isActive =
          plannerState.activeMission != null &&
          (telemetry.currentWaypoint == wp.id ||
              plannerState.activeMission!.currentWaypointIndex == wp.id);

      markers.add(
        Marker(
          point: LatLng(wp.latitude, wp.longitude),
          width: isActive ? 34 : 28,
          height: isActive ? 44 : 28,
          child: WaypointMarkerWidget(
            waypoint: wp,
            isActive: isActive,
            onTap: () => _editWaypointSheet(wp),
          ),
        ),
      );
    }

    // Survey Polygon Vertex markers
    if (_surveyModeActive || surveyArea.vertices.isNotEmpty) {
      for (int i = 0; i < surveyArea.vertices.length; i++) {
        final v = surveyArea.vertices[i];
        markers.add(
          Marker(
            point: v,
            width: 16,
            height: 16,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.warning,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        );
      }
    }

    final double totalDistance = plannedPoints.length * 0.28;
    final int estimatedMinutes = (plannedPoints.length * 1.5).ceil();

    final LatLng centerCoord =
        telemetry.isConnected && telemetry.latitude != 0.0
        ? LatLng(telemetry.latitude, telemetry.longitude)
        : (userLocation.userPosition ??
              LatLng(MapConfig.defaultLatitude, MapConfig.defaultLongitude));

    final List<Polygon> polygons = [];
    if (surveyArea.vertices.length >= 3) {
      polygons.add(
        Polygon(
          points: surveyArea.vertices,
          color: AppTheme.warning.withValues(alpha: 0.18),
          borderColor: AppTheme.warning,
          borderStrokeWidth: 2.0,
          isFilled: true,
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Real Map Canvas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerCoord,
              initialZoom: MapConfig.defaultZoom,
              minZoom: MapConfig.minZoom,
              maxZoom: MapConfig.maxZoom,
              onTap: (tapPosition, point) {
                if (_surveyModeActive) {
                  ref
                      .read(surveyProvider.notifier)
                      .addVertex(point.latitude, point.longitude);
                } else {
                  ref
                      .read(missionProvider.notifier)
                      .addWaypoint(point.latitude, point.longitude);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: layerConfig.urlTemplate,
                subdomains: layerConfig.subdomains,
                userAgentPackageName: MapConfig.userAgentPackageName,
                retinaMode: layerConfig.hasRetinaTag
                    ? RetinaMode.isHighDensity(context)
                    : null,
              ),
              if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
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
              width: 260,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mission Specs',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          plannerState.missionStatus.name.toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.secondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Inspection Profile Dropdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Target:',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      DropdownButton<InspectionType>(
                        value: plannerState.selectedInspectionType,
                        dropdownColor: AppTheme.card,
                        underline: const SizedBox(),
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: InspectionType.generalSurvey,
                            child: Text('General Survey'),
                          ),
                          DropdownMenuItem(
                            value: InspectionType.animalSurvey,
                            child: Text('Animal Survey'),
                          ),
                          DropdownMenuItem(
                            value: InspectionType.roadInspection,
                            child: Text('Road Survey'),
                          ),
                          DropdownMenuItem(
                            value: InspectionType.wasteInspection,
                            child: Text('Waste Survey'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            ref
                                .read(missionProvider.notifier)
                                .setInspectionType(val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildSpecRow(
                    'Distance',
                    '${totalDistance.toStringAsFixed(2)} km',
                  ),
                  _buildSpecRow('Flight Duration', '$estimatedMinutes mins'),
                  _buildSpecRow(
                    'Waypoints added',
                    '${plannedPoints.length} points',
                  ),
                  const Divider(color: AppTheme.border, height: 14),

                  // Action Toolbar: Undo, Redo, Waypoint List, Clear
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.undo2, size: 16),
                        tooltip: 'Undo',
                        onPressed: plannerState.undoHistory.isNotEmpty
                            ? () => ref.read(missionProvider.notifier).undo()
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.redo2, size: 16),
                        tooltip: 'Redo',
                        onPressed: plannerState.redoHistory.isNotEmpty
                            ? () => ref.read(missionProvider.notifier).redo()
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.listOrdered,
                          size: 16,
                          color: AppTheme.secondary,
                        ),
                        tooltip: 'Manage List',
                        onPressed: plannedPoints.isNotEmpty
                            ? _showWaypointsManagerModal
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.trash,
                          size: 16,
                          color: AppTheme.danger,
                        ),
                        tooltip: 'Clear Mission',
                        onPressed: plannedPoints.isNotEmpty
                            ? () => ref
                                  .read(missionProvider.notifier)
                                  .clearMission()
                            : null,
                      ),
                    ],
                  ),
                  const Divider(color: AppTheme.border, height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(
                          LucideIcons.save,
                          size: 16,
                          color: AppTheme.secondary,
                        ),
                        tooltip: 'Save Template',
                        onPressed: plannedPoints.isNotEmpty
                            ? _showSaveMissionDialog
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.folderOpen,
                          size: 16,
                          color: AppTheme.secondary,
                        ),
                        tooltip: 'Load Template',
                        onPressed: _showLoadMissionDialog,
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.grid,
                          size: 16,
                          color: AppTheme.warning,
                        ),
                        tooltip: 'Auto Sweep Grid',
                        onPressed: _generateLawnmowerGrid,
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
                      _mapController.move(
                        LatLng(
                          plannedPoints.first.latitude,
                          plannedPoints.first.longitude,
                        ),
                        16,
                      );
                    } else if (telemetry.isConnected) {
                      _mapController.move(
                        LatLng(telemetry.latitude, telemetry.longitude),
                        16,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildFloatingActionBtn(
                  context,
                  LucideIcons.shapes,
                  _surveyModeActive
                      ? 'Exit Polygon Mode'
                      : 'Draw Survey Polygon',
                  () {
                    setState(() {
                      _surveyModeActive = !_surveyModeActive;
                    });
                    if (_surveyModeActive && surveyArea.vertices.isEmpty) {
                      ref.read(surveyProvider.notifier).startDrawing();
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildFloatingActionBtn(
                  context,
                  LucideIcons.uploadCloud,
                  'Upload to Autopilot',
                  plannedPoints.isEmpty ||
                          plannerState.missionStatus == MissionStatus.uploading
                      ? null
                      : () =>
                            ref.read(missionProvider.notifier).uploadMission(),
                ),
                const SizedBox(height: 8),
                _buildFloatingActionBtn(
                  context,
                  LucideIcons.play,
                  'Start Mission',
                  (!plannerState.isUploaded ||
                          plannerState.activeMission != null)
                      ? null
                      : () {
                          if (!telemetry.isConnected) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Drone disconnected. Power on telemetry first.',
                                ),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                            return;
                          }
                          _showPreFlightCheckDialog();
                        },
                ),
              ],
            ),
          ),

          // 4. Style Selector (Bottom Right)
          const Positioned(
            right: 16,
            bottom: 24,
            child: MapStyleSelectorWidget(),
          ),

          // 5. Survey Toolbar if in polygon drawing mode
          if (_surveyModeActive)
            Positioned(
              top: 16,
              left: 286,
              right: 76,
              child: const SurveyDrawingToolbarWidget(),
            ),

          // 6. Active Mission Running Status Overlay (Bottom Bar)
          if (plannerState.activeMission != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: GlassPanel(
                color: AppTheme.success.withValues(alpha: 0.12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.activity,
                          color: AppTheme.success,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'AUTOPILOT MISSION RUNNING',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppTheme.success,
                              ),
                            ),
                            Text(
                              'Target: WP ${telemetry.currentWaypoint} / ${plannedPoints.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: () =>
                              ref.read(missionProvider.notifier).pauseMission(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.warning,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text(
                            'PAUSE',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => ref
                              .read(missionProvider.notifier)
                              .stopMission(MissionStatus.failed),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text(
                            'RTL',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
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
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionBtn(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
  ) {
    final bool disabled = onTap == null;
    return FloatingActionButton.small(
      heroTag: 'fab_$tooltip',
      onPressed: onTap,
      backgroundColor: disabled
          ? AppTheme.surface.withValues(alpha: 0.5)
          : AppTheme.card,
      foregroundColor: disabled ? AppTheme.textSecondary : AppTheme.secondary,
      child: Icon(icon, size: 18),
    );
  }
}
