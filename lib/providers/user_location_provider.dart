import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/services/user_location_service.dart';

class UserLocationState {
  final LatLng? userPosition;
  final double? accuracy;
  final double? altitude;
  final double? heading;
  final bool isLoading;
  final String? errorMessage;
  final bool isPermissionDenied;
  final bool isServiceDisabled;
  final DateTime? lastUpdated;

  const UserLocationState({
    this.userPosition,
    this.accuracy,
    this.altitude,
    this.heading,
    this.isLoading = false,
    this.errorMessage,
    this.isPermissionDenied = false,
    this.isServiceDisabled = false,
    this.lastUpdated,
  });

  factory UserLocationState.initial() {
    return const UserLocationState();
  }

  UserLocationState copyWith({
    LatLng? userPosition,
    double? accuracy,
    double? altitude,
    double? heading,
    bool? isLoading,
    String? errorMessage,
    bool? isPermissionDenied,
    bool? isServiceDisabled,
    DateTime? lastUpdated,
    bool clearError = false,
    bool clearPosition = false,
  }) {
    return UserLocationState(
      userPosition: clearPosition ? null : (userPosition ?? this.userPosition),
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isPermissionDenied: isPermissionDenied ?? this.isPermissionDenied,
      isServiceDisabled: isServiceDisabled ?? this.isServiceDisabled,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class UserLocationNotifier extends StateNotifier<UserLocationState> {
  final UserLocationService _service = UserLocationService();

  UserLocationNotifier() : super(UserLocationState.initial());

  /// Request permission and fetch current phone GPS location
  Future<LatLng?> fetchCurrentLocation({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    final result = await _service.determineCurrentPosition();

    if (result.isSuccess && result.position != null) {
      state = state.copyWith(
        userPosition: result.position,
        accuracy: result.accuracy,
        altitude: result.altitude,
        heading: result.heading,
        isLoading: false,
        clearError: true,
        isPermissionDenied: false,
        isServiceDisabled: false,
        lastUpdated: DateTime.now(),
      );
      return result.position;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: result.errorMessage,
        isPermissionDenied: result.isPermissionDenied,
        isServiceDisabled: result.isServiceDisabled,
      );
      return null;
    }
  }

  Future<void> openSettings() async {
    if (state.isServiceDisabled) {
      await _service.openLocationSettings();
    } else if (state.isPermissionDenied) {
      await _service.openAppSettings();
    }
  }
}

final userLocationServiceProvider = Provider<UserLocationService>((ref) {
  return UserLocationService();
});

final userLocationProvider = StateNotifierProvider<UserLocationNotifier, UserLocationState>((ref) {
  return UserLocationNotifier();
});
