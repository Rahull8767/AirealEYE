import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/models/telemetry.dart';

/// Represents a single recorded point along a drone's flight trail
class FlightBreadcrumb {
  final LatLng position;
  final double altitude;
  final double heading;
  final double speed;
  final DateTime timestamp;

  const FlightBreadcrumb({
    required this.position,
    required this.altitude,
    required this.heading,
    required this.speed,
    required this.timestamp,
  });
}

/// Service to maintain, filter, and stream live drone flight breadcrumbs
class FlightTrackService {
  final List<FlightBreadcrumb> _breadcrumbs = [];
  final int maxPoints;
  final double minDistanceThresholdMeters;
  bool isRecording = true;

  FlightTrackService({
    this.maxPoints = 2000,
    this.minDistanceThresholdMeters = 1.5,
  });

  List<FlightBreadcrumb> get breadcrumbs => List.unmodifiable(_breadcrumbs);
  List<LatLng> get polylinePoints =>
      _breadcrumbs.map((b) => b.position).toList();

  int get pointCount => _breadcrumbs.length;

  /// Ingests a new telemetry sample. Returns true if a new breadcrumb was added.
  bool ingestTelemetry(DroneTelemetry telemetry) {
    if (!isRecording) return false;
    if (!telemetry.isConnected) return false;
    if (telemetry.latitude == 0.0 && telemetry.longitude == 0.0) return false;
    if (telemetry.latitude < -90.0 || telemetry.latitude > 90.0) return false;
    if (telemetry.longitude < -180.0 || telemetry.longitude > 180.0)
      return false;

    final LatLng newPos = LatLng(telemetry.latitude, telemetry.longitude);

    if (_breadcrumbs.isNotEmpty) {
      final FlightBreadcrumb last = _breadcrumbs.last;
      const Distance distanceCalculator = Distance();
      final double distanceMeters = distanceCalculator.as(
        LengthUnit.Meter,
        last.position,
        newPos,
      );

      final double headingDiff = (last.heading - telemetry.heading).abs();
      final double normalizedHeadingDiff = headingDiff > 180
          ? 360 - headingDiff
          : headingDiff;

      // Filter stationary jitter unless there's meaningful movement (>1.5m) or heading change while in motion
      if (distanceMeters < minDistanceThresholdMeters &&
          (normalizedHeadingDiff < 20 || telemetry.speed < 0.5)) {
        return false;
      }
    }

    if (_breadcrumbs.length >= maxPoints) {
      _breadcrumbs.removeAt(
        0,
      ); // Evict oldest point to keep memory strictly bounded
    }

    _breadcrumbs.add(
      FlightBreadcrumb(
        position: newPos,
        altitude: telemetry.altitude,
        heading: telemetry.heading,
        speed: telemetry.speed,
        timestamp: DateTime.now(),
      ),
    );

    return true;
  }

  /// Reset the flight trail
  void clear() {
    _breadcrumbs.clear();
  }

  /// Total distance traveled along the track in meters
  double get totalDistanceMeters {
    if (_breadcrumbs.length < 2) return 0.0;
    const Distance dist = Distance();
    double sum = 0.0;
    for (int i = 0; i < _breadcrumbs.length - 1; i++) {
      sum += dist.as(
        LengthUnit.Meter,
        _breadcrumbs[i].position,
        _breadcrumbs[i + 1].position,
      );
    }
    return sum;
  }
}
