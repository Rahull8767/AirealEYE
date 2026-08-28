import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class UserLocationResult {
  final LatLng? position;
  final double? accuracy;
  final double? altitude;
  final double? heading;
  final String? errorMessage;
  final bool isPermissionDenied;
  final bool isServiceDisabled;

  const UserLocationResult({
    this.position,
    this.accuracy,
    this.altitude,
    this.heading,
    this.errorMessage,
    this.isPermissionDenied = false,
    this.isServiceDisabled = false,
  });

  bool get isSuccess => position != null;
}

class UserLocationService {
  /// Check if location services are enabled on the phone
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check current permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permissions from user
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Fetch the phone's current GPS position with robust error and permission handling
  Future<UserLocationResult> determineCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const UserLocationResult(
        errorMessage: 'Location services are disabled on this device. Please turn on GPS.',
        isServiceDisabled: true,
      );
    }

    // 2. Check and request location permission.
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return const UserLocationResult(
          errorMessage: 'Location permission was denied by user.',
          isPermissionDenied: true,
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return const UserLocationResult(
        errorMessage: 'Location permission is permanently denied. Enable in device App Settings.',
        isPermissionDenied: true,
      );
    }

    // 3. Obtain position with a timeout
    try {
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return UserLocationResult(
        position: LatLng(pos.latitude, pos.longitude),
        accuracy: pos.accuracy,
        altitude: pos.altitude,
        heading: pos.heading,
      );
    } catch (e) {
      // Try last known position as fallback if available
      try {
        final Position? lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          return UserLocationResult(
            position: LatLng(lastPos.latitude, lastPos.longitude),
            accuracy: lastPos.accuracy,
            altitude: lastPos.altitude,
            heading: lastPos.heading,
          );
        }
      } catch (_) {}

      return UserLocationResult(
        errorMessage: 'Failed to acquire phone GPS fix: $e',
      );
    }
  }

  /// Open app settings to enable permission
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Open location settings to enable GPS
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}
