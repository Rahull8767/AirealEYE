import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/config/map_config.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/providers/mission_provider.dart';
import 'package:aerial_eye/providers/detection_provider.dart';
import 'package:aerial_eye/providers/map_provider.dart';
import 'package:aerial_eye/providers/flight_track_provider.dart';
import 'package:aerial_eye/providers/survey_provider.dart';
import 'package:aerial_eye/providers/user_location_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';
import 'package:aerial_eye/widgets/map/drone_marker.dart';
import 'package:aerial_eye/widgets/map/user_location_marker.dart';
import 'package:aerial_eye/widgets/map/waypoint_marker.dart';
import 'package:aerial_eye/widgets/map/detection_marker.dart';
import 'package:aerial_eye/widgets/map/map_controls.dart';
import 'package:aerial_eye/widgets/map/map_style_selector.dart';
import 'package:aerial_eye/widgets/map/survey_drawing_toolbar.dart';
import 'package:aerial_eye/widgets/map/flight_hud_overlay.dart';
import 'package:aerial_eye/widgets/map/detection_details_modal.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _surveyModeActive = false;

  @override
  void initState() {
    super.initState();
    // On map screen open, check location and center on phone if drone is not active
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userPos = await ref
          .read(userLocationProvider.notifier)
          .fetchCurrentLocation(silent: true);
      final telemetry = ref.read(droneTelemetryProvider).value;
      if (userPos != null && mounted) {
        // If drone GPS is not actively streaming, initial focus on user's real phone location!
        if (telemetry == null ||
            !telemetry.isConnected ||
            (telemetry.latitude == 0.0 && telemetry.longitude == 0.0)) {
          _mapController.move(userPos, 16.0);
        }
      }
    });
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < MapConfig.maxZoom) {
      _mapController.move(_mapController.camera.center, currentZoom + 1.0);
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom > MapConfig.minZoom) {
      _mapController.move(_mapController.camera.center, currentZoom - 1.0);
    }
  }

  void _recenterOnDrone(DroneTelemetry telemetry) {
    if (telemetry.isConnected &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0)) {
      _mapController.move(
        LatLng(telemetry.latitude, telemetry.longitude),
        16.5,
      );
    } else {
      // Fallback to user phone location if available, otherwise configurable default center
      final userLoc = ref.read(userLocationProvider).userPosition;
      if (userLoc != null) {
        _mapController.move(userLoc, 16.0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Drone GPS offline. Centered on phone location.'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        _mapController.move(
          LatLng(MapConfig.defaultLatitude, MapConfig.defaultLongitude),
          MapConfig.defaultZoom,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Drone GPS offline. Centered on default operations zone.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _moveToUserLocation() async {
    // Disable follow drone so map focuses on user phone
    ref.read(mapProvider.notifier).toggleFollowDrone(false);

    final pos = await ref
        .read(userLocationProvider.notifier)
        .fetchCurrentLocation();
    final userLocState = ref.read(userLocationProvider);

    if (pos != null && mounted) {
      _mapController.move(pos, 16.5);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Centered on Phone GPS [${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}]',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (mounted && userLocState.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userLocState.errorMessage!),
          backgroundColor: AppTheme.warning,
          action:
              (userLocState.isPermissionDenied ||
                  userLocState.isServiceDisabled)
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.black,
                  onPressed: () =>
                      ref.read(userLocationProvider.notifier).openSettings(),
                )
              : null,
        ),
      );
    }
  }

  void _showSurveySettingsModal() {
    final surveyState = ref.read(surveyProvider);
    final params = surveyState.activeArea.parameters;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double alt = params.flightAltitude;
            double speed = params.flightSpeed;
            double sideOverlap = params.sideOverlapPercent;
            double forwardOverlap = params.forwardOverlapPercent;

            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Survey Grid Parameters',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Flight Altitude: ${alt.toStringAsFixed(0)} m AGL'),
                  Slider(
                    value: alt,
                    min: 15,
                    max: 120,
                    divisions: 21,
                    activeColor: AppTheme.secondary,
                    onChanged: (val) {
                      setSheetState(() => alt = val);
                      ref
                          .read(surveyProvider.notifier)
                          .updateParameters(
                            params.copyWith(flightAltitude: val),
                          );
                    },
                  ),
                  Text('Survey Transit Speed: ${speed.toStringAsFixed(1)} m/s'),
                  Slider(
                    value: speed,
                    min: 2,
                    max: 15,
                    divisions: 13,
                    activeColor: AppTheme.warning,
                    onChanged: (val) {
                      setSheetState(() => speed = val);
                      ref
                          .read(surveyProvider.notifier)
                          .updateParameters(params.copyWith(flightSpeed: val));
                    },
                  ),
                  Text(
                    'Side Overlap: ${sideOverlap.toStringAsFixed(0)}% (Transect Spacing)',
                  ),
                  Slider(
                    value: sideOverlap,
                    min: 30,
                    max: 85,
                    divisions: 11,
                    activeColor: AppTheme.primary,
                    onChanged: (val) {
                      setSheetState(() => sideOverlap = val);
                      ref
                          .read(surveyProvider.notifier)
                          .updateParameters(
                            params.copyWith(sideOverlapPercent: val),
                          );
                    },
                  ),
                  Text(
                    'Forward Overlap: ${forwardOverlap.toStringAsFixed(0)}%',
                  ),
                  Slider(
                    value: forwardOverlap,
                    min: 40,
                    max: 90,
                    divisions: 10,
                    activeColor: AppTheme.success,
                    onChanged: (val) {
                      setSheetState(() => forwardOverlap = val);
                      ref
                          .read(surveyProvider.notifier)
                          .updateParameters(
                            params.copyWith(forwardOverlapPercent: val),
                          );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(surveyProvider.notifier).generateSurveyGrid();
                      },
                      child: const Text('Apply & Recompute Grid'),
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
    final mapState = ref.watch(mapProvider);
    final layerConfig = MapConfig.getConfig(mapState.activeStyle);
    final telemetryAsync = ref.watch(droneTelemetryProvider);
    final telemetry = telemetryAsync.value ?? DroneTelemetry.initial();
    final missionState = ref.watch(missionProvider);
    final plannedPoints = missionState.plannedWaypoints;
    final detectionState = ref.watch(detectionProvider);
    final detections = detectionState.detections;
    final flightTrack = ref.watch(flightTrackProvider);
    final surveyState = ref.watch(surveyProvider);
    final surveyArea = surveyState.activeArea;
    final userLocation = ref.watch(userLocationProvider);

    // Follow Drone camera tracking logic
    if (mapState.followDrone &&
        telemetry.isConnected &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            LatLng(telemetry.latitude, telemetry.longitude),
            _mapController.camera.zoom,
          );
        }
      });
    }

    // Determine initial center coordinates (Drone -> User Phone -> Config Default)
    final LatLng centerCoord =
        telemetry.isConnected && telemetry.latitude != 0.0
        ? LatLng(telemetry.latitude, telemetry.longitude)
        : (userLocation.userPosition ??
              LatLng(MapConfig.defaultLatitude, MapConfig.defaultLongitude));

    // Prepare Markers
    final List<Marker> markers = [];

    // 1. User Phone Location Marker (Real Physical GPS)
    if (userLocation.userPosition != null) {
      markers.add(
        Marker(
          point: userLocation.userPosition!,
          width: 44,
          height: 44,
          child: UserLocationMarkerWidget(
            accuracyMeters: userLocation.accuracy,
            heading: userLocation.heading,
            onTap: _moveToUserLocation,
          ),
        ),
      );
    }

    // 2. Detection Markers
    if (mapState.showDetections) {
      for (final d in detections) {
        markers.add(
          Marker(
            point: LatLng(d.latitude, d.longitude),
            width: 34,
            height: 34,
            child: DetectionMarkerWidget(
              detection: d,
              onTap: () => DetectionDetailsModal.show(context, d),
            ),
          ),
        );
      }
    }

    // 3. Mission Waypoint Markers
    if (mapState.showMissionRoute) {
      for (int i = 0; i < plannedPoints.length; i++) {
        final wp = plannedPoints[i];
        final bool isActive =
            missionState.activeMission != null &&
            (telemetry.currentWaypoint == wp.id ||
                missionState.activeMission!.currentWaypointIndex == wp.id);

        markers.add(
          Marker(
            point: LatLng(wp.latitude, wp.longitude),
            width: isActive ? 36 : 30,
            height: isActive ? 46 : 30,
            child: WaypointMarkerWidget(waypoint: wp, isActive: isActive),
          ),
        );
      }
    }

    // 4. Home Position Marker
    final double? homeLat = telemetry.homeLatitude;
    final double? homeLng = telemetry.homeLongitude;
    if (homeLat != null && homeLng != null && homeLat != 0.0) {
      markers.add(
        Marker(
          point: LatLng(homeLat, homeLng),
          width: 32,
          height: 32,
          child: const HomeMarkerWidget(),
        ),
      );
    }

    // 5. Live Drone Marker (MAVLink Telemetry GPS)
    if (telemetry.isConnected &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0)) {
      markers.add(
        Marker(
          point: LatLng(telemetry.latitude, telemetry.longitude),
          width: 50,
          height: 60,
          child: DroneMarkerWidget(
            telemetry: telemetry,
            onTap: () => _recenterOnDrone(telemetry),
          ),
        ),
      );
    }

    // 6. Survey Area Polygon Vertex Markers
    if (_surveyModeActive || surveyArea.vertices.isNotEmpty) {
      for (int i = 0; i < surveyArea.vertices.length; i++) {
        final v = surveyArea.vertices[i];
        markers.add(
          Marker(
            point: v,
            width: 18,
            height: 18,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.warning,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4),
                ],
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Prepare Polylines
    final List<Polyline> polylines = [];

    // Flight Track Breadcrumb Trail
    if (mapState.showFlightTrack && flightTrack.polylinePoints.length > 1) {
      polylines.add(
        Polyline(
          points: flightTrack.polylinePoints,
          color: AppTheme.secondary.withValues(alpha: 0.85),
          strokeWidth: 3.0,
        ),
      );
    }

    // Planned Mission Route
    if (mapState.showMissionRoute && plannedPoints.length > 1) {
      polylines.add(
        Polyline(
          points: plannedPoints
              .map((wp) => LatLng(wp.latitude, wp.longitude))
              .toList(),
          color: Colors.amber.withValues(alpha: 0.85),
          strokeWidth: 2.5,
        ),
      );
    }

    // Survey Polygon Outline (when not yet closed or in drawing mode)
    if (surveyArea.vertices.length > 1 && !surveyArea.isClosed) {
      polylines.add(
        Polyline(
          points: surveyArea.vertices,
          color: AppTheme.warning,
          strokeWidth: 2.0,
        ),
      );
    }

    // Prepare Polygon Layers
    final List<Polygon> polygons = [];
    if (surveyArea.vertices.length >= 3 && mapState.showSurveyPolygon) {
      polygons.add(
        Polygon(
          points: surveyArea.vertices,
          color: AppTheme.warning.withValues(alpha: 0.20),
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
                errorTileCallback: (tile, error, stackTrace) {
                  ref
                      .read(mapProvider.notifier)
                      .setTileStatus(MapTileLoadingStatus.networkError);
                },
              ),
              if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
              if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),

          // 2. Map Attribution Badge (Bottom Right)
          const Positioned(right: 12, bottom: 6, child: MapAttributionBadge()),

          // 3. Tile Offline Warning Badge (if map tiles fail)
          if (mapState.tileStatus == MapTileLoadingStatus.networkError)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 8),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.wifiOff, size: 14, color: Colors.black),
                      SizedBox(width: 6),
                      Text(
                        'Map Tiles Offline (MAVLink telemetry remains active)',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 4. Left Top: Defect Legend Panel
          if (!mapState.isFullscreen)
            Positioned(
              left: 16,
              top: 16,
              child: GlassPanel(
                width: 175,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'AI ANOMALY LEGEND',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildLegendRow('Potholes', Colors.red),
                    _buildLegendRow('Road Cracks', Colors.orange),
                    _buildLegendRow('Garbage', Colors.green),
                    _buildLegendRow('Water Log', Colors.blue),
                    _buildLegendRow('Animal', Colors.cyan),
                    _buildLegendRow('Obstacles', Colors.purple),
                  ],
                ),
              ),
            ),

          // 5. Left Bottom: Live Telemetry HUD Card
          if (!mapState.isFullscreen)
            Positioned(
              left: 16,
              bottom: 24,
              child: FlightHudOverlayWidget(
                telemetry: telemetry,
                waypointCount: plannedPoints.length,
                trackDistanceMeters: flightTrack.totalDistanceMeters,
              ),
            ),

          // 6. Right Side: Map Layer Style Switcher
          Positioned(
            right: 16,
            bottom: 24,
            child: const MapStyleSelectorWidget(),
          ),

          // 7. Right Side: Map Action Controls (Zoom, My Location, Recenter Drone, Follow, Survey, Fullscreen)
          Positioned(
            right: 16,
            top: 16,
            child: MapControlsWidget(
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onMyLocation: _moveToUserLocation,
              onRecenterDrone: () => _recenterOnDrone(telemetry),
              isSurveyActive: _surveyModeActive,
              onToggleSurvey: () {
                setState(() {
                  _surveyModeActive = !_surveyModeActive;
                });
                if (_surveyModeActive && surveyArea.vertices.isEmpty) {
                  ref.read(surveyProvider.notifier).startDrawing();
                }
              },
            ),
          ),

          // 8. Survey Drawing Area Toolbar (Top Center)
          if (_surveyModeActive)
            Positioned(
              top: 16,
              left: 200,
              right: 80,
              child: SurveyDrawingToolbarWidget(
                onSettingsTap: _showSurveySettingsModal,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendRow(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}
