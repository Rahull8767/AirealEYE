import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/main.dart';
import 'package:aerial_eye/screens/splash_screen.dart';

void main() {
  testWidgets('AerialEye App builds and loads SplashScreen', (WidgetTester tester) async {
    // Set a standard responsive screen size to prevent layout overflows during testing
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;

    // Reset size after test completes
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: AerialEyeApp()));

    // Verify that SplashScreen is displayed.
    expect(find.byType(SplashScreen), findsOneWidget);

    // Verify that the title text "AerialEye" is present.
    expect(find.text('AerialEye'), findsOneWidget);

    // Let the splash screen timer complete to avoid pending timer error.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
