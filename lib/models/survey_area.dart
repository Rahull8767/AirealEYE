import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Survey Grid Generation Parameters
class SurveyParameters {
  final double flightAltitude; // meters AGL (e.g. 30.0 - 120.0m)
  final double flightSpeed; // m/s (e.g. 5.0 m/s)
  final double
  cameraFovHorizontal; // degrees (e.g. 78.0 for standard drone camera)
  final double cameraFovVertical; // degrees (e.g. 54.0)
  final double forwardOverlapPercent; // e.g. 75%
  final double sideOverlapPercent; // e.g. 60%
  final double gridAngle; // degrees rotation (0-360)

  const SurveyParameters({
    this.flightAltitude = 35.0,
    this.flightSpeed = 5.0,
    this.cameraFovHorizontal = 78.0,
    this.cameraFovVertical = 54.0,
    this.forwardOverlapPercent = 70.0,
    this.sideOverlapPercent = 60.0,
    this.gridAngle = 0.0,
  });

  SurveyParameters copyWith({
    double? flightAltitude,
    double? flightSpeed,
    double? cameraFovHorizontal,
    double? cameraFovVertical,
    double? forwardOverlapPercent,
    double? sideOverlapPercent,
    double? gridAngle,
  }) {
    return SurveyParameters(
      flightAltitude: flightAltitude ?? this.flightAltitude,
      flightSpeed: flightSpeed ?? this.flightSpeed,
      cameraFovHorizontal: cameraFovHorizontal ?? this.cameraFovHorizontal,
      cameraFovVertical: cameraFovVertical ?? this.cameraFovVertical,
      forwardOverlapPercent:
          forwardOverlapPercent ?? this.forwardOverlapPercent,
      sideOverlapPercent: sideOverlapPercent ?? this.sideOverlapPercent,
      gridAngle: gridAngle ?? this.gridAngle,
    );
  }
}

/// Represents a polygonal geographic survey area
class SurveyArea {
  final String id;
  final String name;
  final List<LatLng> vertices;
  final bool isClosed;
  final SurveyParameters parameters;

  const SurveyArea({
    required this.id,
    this.name = 'Survey Area',
    required this.vertices,
    this.isClosed = false,
    this.parameters = const SurveyParameters(),
  });

  factory SurveyArea.empty() {
    return SurveyArea(
      id: 'survey_${DateTime.now().millisecondsSinceEpoch}',
      vertices: const [],
      isClosed: false,
    );
  }

  SurveyArea copyWith({
    String? id,
    String? name,
    List<LatLng>? vertices,
    bool? isClosed,
    SurveyParameters? parameters,
  }) {
    return SurveyArea(
      id: id ?? this.id,
      name: name ?? this.name,
      vertices: vertices ?? this.vertices,
      isClosed: isClosed ?? this.isClosed,
      parameters: parameters ?? this.parameters,
    );
  }

  /// Calculates accurate geodesic surface area in square meters using projected Shoelace formula
  double get areaSquareMeters {
    if (vertices.length < 3) return 0.0;

    const double earthRadius = 6378137.0; // WGS84 major radius in meters
    final double centerLatRad =
        (center?.latitude ?? vertices.first.latitude) * (math.pi / 180.0);
    final double cosCenterLat = math.cos(centerLatRad);

    double totalArea = 0.0;
    final int len = vertices.length;

    for (int i = 0; i < len; i++) {
      final LatLng p1 = vertices[i];
      final LatLng p2 = vertices[(i + 1) % len];

      // Project spherical coords to local metric tangent plane (x, y in meters)
      final double x1 =
          p1.longitude * (math.pi / 180.0) * earthRadius * cosCenterLat;
      final double y1 = p1.latitude * (math.pi / 180.0) * earthRadius;

      final double x2 =
          p2.longitude * (math.pi / 180.0) * earthRadius * cosCenterLat;
      final double y2 = p2.latitude * (math.pi / 180.0) * earthRadius;

      totalArea += (x1 * y2) - (x2 * y1);
    }

    return (totalArea / 2.0).abs();
  }

  /// Formatted area string for UI readouts
  String get formattedArea {
    final double sqm = areaSquareMeters;
    if (sqm <= 0) return '0 m²';
    if (sqm < 10000) {
      return '${sqm.toStringAsFixed(1)} m²';
    } else if (sqm < 1000000) {
      final double hectares = sqm / 10000.0;
      return '${hectares.toStringAsFixed(2)} ha';
    } else {
      final double sqkm = sqm / 1000000.0;
      return '${sqkm.toStringAsFixed(2)} km²';
    }
  }

  /// Perimeter in meters
  double get perimeterMeters {
    if (vertices.length < 2) return 0.0;
    const Distance distance = Distance();
    double total = 0.0;
    for (int i = 0; i < vertices.length; i++) {
      final LatLng next = vertices[(i + 1) % vertices.length];
      if (i == vertices.length - 1 && !isClosed) break;
      total += distance.as(LengthUnit.Meter, vertices[i], next);
    }
    return total;
  }

  /// Bounding center point
  LatLng? get center {
    if (vertices.isEmpty) return null;
    double latSum = 0;
    double lngSum = 0;
    for (final v in vertices) {
      latSum += v.latitude;
      lngSum += v.longitude;
    }
    return LatLng(latSum / vertices.length, lngSum / vertices.length);
  }
}
