import 'package:flutter/material.dart';

class AppConstants {
  // Border Radii
  static const double radiusLarge = 18.0;
  static const double radiusMedium = 16.0;
  static const double radiusSmall = 14.0;

  // Spacing / Paddings
  static const double paddingLarge = 24.0;
  static const double paddingMedium = 16.0;
  static const double paddingSmall = 8.0;
  static const double paddingTiny = 4.0;

  // Custom Elevation Shadow
  static List<BoxShadow> get premiumShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  // Map settings
  static const double defaultLat =
      37.7749; // Default focus (e.g. San Francisco or central area)
  static const double defaultLng = -122.4194;
  static const double defaultZoom = 15.0;
}
