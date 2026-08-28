import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/models/waypoint.dart';
import 'package:aerial_eye/models/survey_area.dart';

/// Service for generating autonomous survey flight paths and grid lines from polygon boundaries
class SurveyGridService {
  /// Generates an optimized lawnmower survey flight plan inside a polygon
  List<Waypoint> generateSurveyGrid({
    required SurveyArea surveyArea,
    SurveyParameters? customParameters,
  }) {
    final params = customParameters ?? surveyArea.parameters;
    final vertices = surveyArea.vertices;

    if (vertices.length < 3) {
      return [];
    }

    // 1. Calculate camera footprint on ground based on altitude & FOV
    final double alt = params.flightAltitude.clamp(10.0, 300.0);
    final double fovHRad = params.cameraFovHorizontal * (math.pi / 180.0);

    // Ground footprint in meters
    final double footprintWidth = 2 * alt * math.tan(fovHRad / 2);

    // Line spacing (side overlap)
    final double sideOverlapFraction = (params.sideOverlapPercent / 100.0).clamp(0.1, 0.9);
    final double lineSpacingMeters = (footprintWidth * (1.0 - sideOverlapFraction)).clamp(5.0, 200.0);

    // Approx meters per degree latitude
    const double metersPerDegreeLat = 111320.0;
    final double latStep = lineSpacingMeters / metersPerDegreeLat;

    // 2. Find bounding box of the polygon
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final v in vertices) {
      if (v.latitude < minLat) minLat = v.latitude;
      if (v.latitude > maxLat) maxLat = v.latitude;
      if (v.longitude < minLng) minLng = v.longitude;
      if (v.longitude > maxLng) maxLng = v.longitude;
    }

    // 3. Sweep parallel transect lines across bounding box
    final List<List<LatLng>> transects = [];
    double currentLat = minLat + (latStep / 2.0);

    while (currentLat <= maxLat) {
      // Find intersections of horizontal line at `currentLat` with all polygon edges
      final List<double> intersections = [];
      final int n = vertices.length;

      for (int i = 0; i < n; i++) {
        final LatLng p1 = vertices[i];
        final LatLng p2 = vertices[(i + 1) % n];

        // Check if horizontal line intersects line segment (p1, p2)
        if ((p1.latitude <= currentLat && p2.latitude > currentLat) ||
            (p2.latitude <= currentLat && p1.latitude > currentLat)) {
          final double t = (currentLat - p1.latitude) / (p2.latitude - p1.latitude);
          final double intersectLng = p1.longitude + t * (p2.longitude - p1.longitude);
          intersections.add(intersectLng);
        }
      }

      intersections.sort();

      // Pair up intersection points (entry & exit points inside polygon)
      for (int i = 0; i < intersections.length - 1; i += 2) {
        final double lng1 = intersections[i];
        final double lng2 = intersections[i + 1];
        transects.add([
          LatLng(currentLat, lng1),
          LatLng(currentLat, lng2),
        ]);
      }

      currentLat += latStep;
    }

    if (transects.isEmpty) {
      // Fallback: If area is small, create a simple bounding perimeter route
      return _generatePerimeterRoute(vertices, params);
    }

    // 4. Connect transects in a continuous serpentine (lawnmower) path
    final List<Waypoint> waypoints = [];
    int wpId = 1;
    bool reverse = false;

    for (int t = 0; t < transects.length; t++) {
      final line = transects[t];
      final LatLng start = reverse ? line[1] : line[0];
      final LatLng end = reverse ? line[0] : line[1];

      waypoints.add(Waypoint(
        id: wpId++,
        latitude: start.latitude,
        longitude: start.longitude,
        altitude: params.flightAltitude,
        speed: params.flightSpeed,
        hoverTime: 1,
      ));

      waypoints.add(Waypoint(
        id: wpId++,
        latitude: end.latitude,
        longitude: end.longitude,
        altitude: params.flightAltitude,
        speed: params.flightSpeed,
        hoverTime: 1,
      ));

      reverse = !reverse; // Alternate direction on each sweep
    }

    return waypoints;
  }

  /// Generates a boundary inspection route tracing polygon perimeter
  List<Waypoint> _generatePerimeterRoute(List<LatLng> vertices, SurveyParameters params) {
    final List<Waypoint> list = [];
    for (int i = 0; i < vertices.length; i++) {
      list.add(Waypoint(
        id: i + 1,
        latitude: vertices[i].latitude,
        longitude: vertices[i].longitude,
        altitude: params.flightAltitude,
        speed: params.flightSpeed,
        hoverTime: 2,
      ));
    }
    return list;
  }
}
