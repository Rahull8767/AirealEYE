import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aerial_eye/services/user_location_service.dart';
import 'package:aerial_eye/providers/user_location_provider.dart';

void main() {
  group('User Location Service & State Tests', () {
    test(
      'UserLocationResult correctly represents successful phone GPS acquisition',
      () {
        const result = UserLocationResult(
          position: LatLng(12.9716, 77.5946),
          accuracy: 5.0,
          altitude: 920.0,
          heading: 180.0,
        );

        expect(result.isSuccess, isTrue);
        expect(result.position?.latitude, 12.9716);
        expect(result.position?.longitude, 77.5946);
        expect(result.accuracy, 5.0);
        expect(result.isPermissionDenied, isFalse);
        expect(result.isServiceDisabled, isFalse);
      },
    );

    test('UserLocationResult gracefully handles permission denied state', () {
      const deniedResult = UserLocationResult(
        errorMessage: 'Location permission was denied by user.',
        isPermissionDenied: true,
      );

      expect(deniedResult.isSuccess, isFalse);
      expect(deniedResult.position, isNull);
      expect(deniedResult.isPermissionDenied, isTrue);
      expect(deniedResult.errorMessage, contains('denied'));
    });

    test(
      'UserLocationResult gracefully handles disabled location services',
      () {
        const disabledResult = UserLocationResult(
          errorMessage: 'Location services are disabled on this device.',
          isServiceDisabled: true,
        );

        expect(disabledResult.isSuccess, isFalse);
        expect(disabledResult.isServiceDisabled, isTrue);
      },
    );

    test('UserLocationState copyWith functions correctly', () {
      var state = UserLocationState.initial();
      expect(state.userPosition, isNull);
      expect(state.isLoading, isFalse);

      state = state.copyWith(
        userPosition: const LatLng(28.6139, 77.2090),
        accuracy: 10.0,
        isLoading: false,
      );

      expect(state.userPosition?.latitude, 28.6139);
      expect(state.userPosition?.longitude, 77.2090);
      expect(state.accuracy, 10.0);

      state = state.copyWith(clearPosition: true);
      expect(state.userPosition, isNull);
    });
  });
}
