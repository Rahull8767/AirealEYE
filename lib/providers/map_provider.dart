import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/config/map_config.dart';

enum MapTileLoadingStatus {
  idle,
  loading,
  ready,
  networkError,
}

class MapState {
  final MapTileStyle activeStyle;
  final bool followDrone;
  final bool isFullscreen;
  final bool showDetections;
  final bool showFlightTrack;
  final bool showMissionRoute;
  final bool showSurveyPolygon;
  final MapTileLoadingStatus tileStatus;
  final LatLng currentCenter;
  final double currentZoom;

  const MapState({
    required this.activeStyle,
    this.followDrone = true,
    this.isFullscreen = false,
    this.showDetections = true,
    this.showFlightTrack = true,
    this.showMissionRoute = true,
    this.showSurveyPolygon = true,
    this.tileStatus = MapTileLoadingStatus.ready,
    required this.currentCenter,
    required this.currentZoom,
  });

  factory MapState.initial() {
    return MapState(
      activeStyle: MapTileStyle.dark,
      followDrone: true,
      isFullscreen: false,
      currentCenter: LatLng(MapConfig.defaultLatitude, MapConfig.defaultLongitude),
      currentZoom: MapConfig.defaultZoom,
    );
  }

  MapState copyWith({
    MapTileStyle? activeStyle,
    bool? followDrone,
    bool? isFullscreen,
    bool? showDetections,
    bool? showFlightTrack,
    bool? showMissionRoute,
    bool? showSurveyPolygon,
    MapTileLoadingStatus? tileStatus,
    LatLng? currentCenter,
    double? currentZoom,
  }) {
    return MapState(
      activeStyle: activeStyle ?? this.activeStyle,
      followDrone: followDrone ?? this.followDrone,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      showDetections: showDetections ?? this.showDetections,
      showFlightTrack: showFlightTrack ?? this.showFlightTrack,
      showMissionRoute: showMissionRoute ?? this.showMissionRoute,
      showSurveyPolygon: showSurveyPolygon ?? this.showSurveyPolygon,
      tileStatus: tileStatus ?? this.tileStatus,
      currentCenter: currentCenter ?? this.currentCenter,
      currentZoom: currentZoom ?? this.currentZoom,
    );
  }
}

class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(MapState.initial());

  void setMapStyle(MapTileStyle style) {
    state = state.copyWith(activeStyle: style);
  }

  void toggleFollowDrone([bool? follow]) {
    state = state.copyWith(followDrone: follow ?? !state.followDrone);
  }

  void toggleFullscreen([bool? fullscreen]) {
    state = state.copyWith(isFullscreen: fullscreen ?? !state.isFullscreen);
  }

  void toggleLayerVisibility({
    bool? detections,
    bool? flightTrack,
    bool? missionRoute,
    bool? surveyPolygon,
  }) {
    state = state.copyWith(
      showDetections: detections ?? state.showDetections,
      showFlightTrack: flightTrack ?? state.showFlightTrack,
      showMissionRoute: missionRoute ?? state.showMissionRoute,
      showSurveyPolygon: surveyPolygon ?? state.showSurveyPolygon,
    );
  }

  void updatePosition(LatLng center, double zoom) {
    state = state.copyWith(
      currentCenter: center,
      currentZoom: zoom,
    );
  }

  void setTileStatus(MapTileLoadingStatus status) {
    state = state.copyWith(tileStatus: status);
  }
}

final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier();
});
