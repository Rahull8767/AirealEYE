import 'package:flutter/material.dart';

/// Supported Map Layer Styles
enum MapTileStyle {
  dark,
  light,
  osm,
  satellite,
  terrain,
}

/// Metadata definition for a map tile layer provider
class MapTileLayerConfig {
  final MapTileStyle style;
  final String id;
  final String displayName;
  final String urlTemplate;
  final List<String> subdomains;
  final String attribution;
  final bool hasRetinaTag;
  final int minZoom;
  final int maxZoom;
  final IconData icon;

  const MapTileLayerConfig({
    required this.style,
    required this.id,
    required this.displayName,
    required this.urlTemplate,
    this.subdomains = const ['a', 'b', 'c', 'd'],
    required this.attribution,
    this.hasRetinaTag = false,
    this.minZoom = 1,
    this.maxZoom = 19,
    required this.icon,
  });
}

/// Centralized Map Configuration
///
/// Ensures all tile URLs, attribution texts, coordinate boundaries, zoom levels,
/// and API keys are modular and configurable rather than hardcoded.
class MapConfig {
  // Configurable fallback coordinates (used when drone GPS fix is not yet available)
  // Can be overridden via environment variables:
  //   flutter run --dart-define=DEFAULT_MAP_LAT=37.7749 --dart-define=DEFAULT_MAP_LNG=-122.4194
  static double get defaultLatitude {
    const fromEnv = String.fromEnvironment('DEFAULT_MAP_LAT');
    if (fromEnv.isNotEmpty) {
      return double.tryParse(fromEnv) ?? 37.7749;
    }
    return 37.7749; // Default central fallback
  }

  static double get defaultLongitude {
    const fromEnv = String.fromEnvironment('DEFAULT_MAP_LNG');
    if (fromEnv.isNotEmpty) {
      return double.tryParse(fromEnv) ?? -122.4194;
    }
    return -122.4194;
  }

  static double get defaultZoom {
    const fromEnv = String.fromEnvironment('DEFAULT_MAP_ZOOM');
    if (fromEnv.isNotEmpty) {
      return double.tryParse(fromEnv) ?? 16.0;
    }
    return 16.0;
  }

  static const double minZoom = 2.0;
  static const double maxZoom = 20.0;

  // Package identifier sent with tile HTTP requests to comply with OSM/Carto usage policies
  static const String userAgentPackageName = 'com.aerialeye.app';

  // Optional custom tile keys/endpoints passed via --dart-define
  static const String mapboxApiKey = String.fromEnvironment('MAPBOX_API_KEY', defaultValue: '');
  static const String customSatelliteUrl = String.fromEnvironment('CUSTOM_SATELLITE_URL', defaultValue: '');

  /// Available Real Map Tile Styles
  static final Map<MapTileStyle, MapTileLayerConfig> tileLayers = {
    MapTileStyle.dark: const MapTileLayerConfig(
      style: MapTileStyle.dark,
      id: 'dark',
      displayName: 'Dark HUD',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      attribution: '© OpenStreetMap contributors, © CARTO',
      hasRetinaTag: true,
      minZoom: 1,
      maxZoom: 20,
      icon: Icons.dark_mode_outlined,
    ),
    MapTileStyle.light: const MapTileLayerConfig(
      style: MapTileStyle.light,
      id: 'light',
      displayName: 'Light',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      attribution: '© OpenStreetMap contributors, © CARTO',
      hasRetinaTag: true,
      minZoom: 1,
      maxZoom: 20,
      icon: Icons.light_mode_outlined,
    ),
    MapTileStyle.osm: const MapTileLayerConfig(
      style: MapTileStyle.osm,
      id: 'osm',
      displayName: 'Street (OSM)',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
      attribution: '© OpenStreetMap contributors',
      hasRetinaTag: false,
      minZoom: 1,
      maxZoom: 19,
      icon: Icons.map_outlined,
    ),
    MapTileStyle.satellite: MapTileLayerConfig(
      style: MapTileStyle.satellite,
      id: 'satellite',
      displayName: 'Satellite HD',
      // High-resolution ESRI World Imagery (Global coverage with zero API key requirement)
      // Or override via CUSTOM_SATELLITE_URL if local orthomosaic server is used
      urlTemplate: customSatelliteUrl.isNotEmpty
          ? customSatelliteUrl
          : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      subdomains: const [],
      attribution: 'Source: Esri, Maxar, Earthstar Geographics, CNES/Airbus DS',
      hasRetinaTag: false,
      minZoom: 1,
      maxZoom: 19,
      icon: Icons.satellite_alt_outlined,
    ),
    MapTileStyle.terrain: const MapTileLayerConfig(
      style: MapTileStyle.terrain,
      id: 'terrain',
      displayName: 'Topo / Terrain',
      urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
      attribution: 'Map data: © OpenStreetMap contributors, SRTM | Map style: © OpenTopoMap (CC-BY-SA)',
      hasRetinaTag: false,
      minZoom: 1,
      maxZoom: 17,
      icon: Icons.terrain_outlined,
    ),
  };

  /// Helper to get configuration by style enum
  static MapTileLayerConfig getConfig(MapTileStyle style) {
    return tileLayers[style] ?? tileLayers[MapTileStyle.dark]!;
  }
}
