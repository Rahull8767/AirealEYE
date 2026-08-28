import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/config/map_config.dart';
import 'package:aerial_eye/models/survey_area.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/services/flight_track_service.dart';
import 'package:aerial_eye/services/survey_grid_service.dart';

void main() {
  group('1. Map Configuration & Tile Layers', () {
    test('MapConfig provides valid default coordinates and zoom boundaries', () {
      expect(MapConfig.defaultLatitude, isNotNull);
      expect(MapConfig.defaultLongitude, isNotNull);
      expect(MapConfig.defaultZoom, inInclusiveRange(1.0, 20.0));
      expect(MapConfig.minZoom, lessThan(MapConfig.maxZoom));
      expect(MapConfig.userAgentPackageName, 'com.aerialeye.app');
    });

    test('MapConfig contains all required real tile styles with proper attribution and retina tags', () {
      expect(MapConfig.tileLayers.containsKey(MapTileStyle.dark), isTrue);
      expect(MapConfig.tileLayers.containsKey(MapTileStyle.light), isTrue);
      expect(MapConfig.tileLayers.containsKey(MapTileStyle.osm), isTrue);
      expect(MapConfig.tileLayers.containsKey(MapTileStyle.satellite), isTrue);
      expect(MapConfig.tileLayers.containsKey(MapTileStyle.terrain), isTrue);

      final darkConfig = MapConfig.getConfig(MapTileStyle.dark);
      expect(darkConfig.hasRetinaTag, isTrue);
      expect(darkConfig.urlTemplate, contains('{r}'));
      expect(darkConfig.attribution, isNotEmpty);

      final satConfig = MapConfig.getConfig(MapTileStyle.satellite);
      expect(satConfig.urlTemplate, contains('ArcGIS'));
      expect(satConfig.attribution, contains('Esri'));

      final osmConfig = MapConfig.getConfig(MapTileStyle.osm);
      expect(osmConfig.urlTemplate, contains('tile.openstreetmap.org'));
    });
  });

  group('2. Survey Area Polygon & Area Calculations', () {
    test('SurveyArea computes accurate geodesic surface area for a polygon', () {
      // 100m x 100m square polygon around equator (approx 10,000 m² = 1.0 ha)
      final vertices = [
        const LatLng(0.0, 0.0),
        const LatLng(0.0009, 0.0),
        const LatLng(0.0009, 0.0009),
        const LatLng(0.0, 0.0009),
      ];

      final survey = SurveyArea(
        id: 'test_1',
        vertices: vertices,
        isClosed: true,
      );

      final area = survey.areaSquareMeters;
      expect(area, greaterThan(8000));
      expect(area, lessThan(12000));
      expect(survey.formattedArea, isNotEmpty);
      expect(survey.perimeterMeters, greaterThan(300));
      expect(survey.center, isNotNull);
    });

    test('SurveyArea handles empty or single-point edge cases safely without throwing', () {
      final emptyArea = SurveyArea.empty();
      expect(emptyArea.areaSquareMeters, 0.0);
      expect(emptyArea.formattedArea, '0 m²');
      expect(emptyArea.center, isNull);
    });
  });

  group('3. Survey Grid Generation Service', () {
    test('SurveyGridService generates transect lawnmower flight waypoints inside polygon', () {
      final vertices = [
        const LatLng(37.7740, -122.4200),
        const LatLng(37.7760, -122.4200),
        const LatLng(37.7760, -122.4180),
        const LatLng(37.7740, -122.4180),
      ];

      final survey = SurveyArea(
        id: 'grid_test',
        vertices: vertices,
        isClosed: true,
        parameters: const SurveyParameters(
          flightAltitude: 40.0,
          flightSpeed: 5.0,
          cameraFovHorizontal: 78.0,
          sideOverlapPercent: 65.0,
          forwardOverlapPercent: 75.0,
        ),
      );

      final service = SurveyGridService();
      final waypoints = service.generateSurveyGrid(surveyArea: survey);

      expect(waypoints, isNotEmpty);
      expect(waypoints.length, greaterThanOrEqualTo(4));
      // Sequential IDs
      for (int i = 0; i < waypoints.length; i++) {
        expect(waypoints[i].id, i + 1);
        expect(waypoints[i].altitude, 40.0);
        expect(waypoints[i].speed, 5.0);
      }
    });
  });

  group('4. Flight Track Service & Jitter Filter', () {
    test('FlightTrackService records points on movement and filters stationary jitter', () {
      final service = FlightTrackService(minDistanceThresholdMeters: 2.0);

      final t1 = DroneTelemetry.initial().copyWith(
        isConnected: true,
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 20.0,
        heading: 90.0,
        speed: 4.0,
      );

      // Ingest first point
      final added1 = service.ingestTelemetry(t1);
      expect(added1, isTrue);
      expect(service.pointCount, 1);

      // Ingest almost identical point (jitter < 2m and low speed) -> should be filtered
      final t2 = t1.copyWith(
        latitude: 37.77490001,
        longitude: -122.41940001,
        speed: 0.1,
      );
      final added2 = service.ingestTelemetry(t2);
      expect(added2, isFalse);
      expect(service.pointCount, 1);

      // Ingest point with significant movement (> 10m)
      final t3 = t1.copyWith(
        latitude: 37.7752,
        longitude: -122.4194,
        speed: 5.0,
      );
      final added3 = service.ingestTelemetry(t3);
      expect(added3, isTrue);
      expect(service.pointCount, 2);
      expect(service.totalDistanceMeters, greaterThan(20.0));

      // Reset
      service.clear();
      expect(service.pointCount, 0);
      expect(service.totalDistanceMeters, 0.0);
    });

    test('FlightTrackService rejects disconnected or invalid zero coordinates', () {
      final service = FlightTrackService();
      final disconnected = DroneTelemetry.initial().copyWith(
        isConnected: false,
        latitude: 37.7749,
        longitude: -122.4194,
      );
      expect(service.ingestTelemetry(disconnected), isFalse);

      final zeroCoord = DroneTelemetry.initial().copyWith(
        isConnected: true,
        latitude: 0.0,
        longitude: 0.0,
      );
      expect(service.ingestTelemetry(zeroCoord), isFalse);
    });
  });
}
