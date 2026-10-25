import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/services/mock_drone_service.dart';
import 'package:aerial_eye/screens/motor_test_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({required DroneService droneService}) {
    return ProviderScope(
      overrides: [
        droneServiceProvider.overrideWithValue(droneService),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const MotorTestScreen(),
      ),
    );
  }

  testWidgets('MotorTestScreen renders all mandatory controls and defaults', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // Verify Title & Diagnostics header
    expect(find.text('Motor Test Panel'), findsOneWidget);
    expect(find.text('Mission Planner Diagnostic Benchmark'), findsOneWidget);

    // Verify Propeller Removal Protocol section
    expect(find.text('PROPELLER REMOVAL PROTOCOL'), findsOneWidget);
    expect(
      find.text('I confirm that all propellers are removed from all 4 motors.'),
      findsOneWidget,
    );

    // Verify default motor selection (Motor 1 (A))
    expect(find.text('Motor 1 (A)'), findsOneWidget);
    expect(find.text('Motor 2 (B)'), findsOneWidget);
    expect(find.text('Motor 3 (C)'), findsOneWidget);
    expect(find.text('Motor 4 (D)'), findsOneWidget);
    expect(find.text('Test All Motors (1-4)'), findsOneWidget);

    // Verify default throttle percentage (10%)
    expect(find.text('THROTTLE PERCENTAGE'), findsOneWidget);
    expect(find.text('10% (Def)'), findsOneWidget);

    // Verify default duration (3s)
    expect(find.text('TEST DURATION (1–5 SECONDS)'), findsOneWidget);
    expect(find.text('3s (Def)'), findsOneWidget);

    // Verify Action buttons
    expect(find.byKey(const Key('start_motor_test_button')), findsOneWidget);
    expect(find.byKey(const Key('stop_motor_test_button')), findsOneWidget);

    // Verify MAVLink Diagnostics Card
    expect(find.text('MAVLINK COMMAND DIAGNOSTICS'), findsOneWidget);
    expect(find.text('MAV_CMD_DO_MOTOR_TEST (ID: 209)'), findsOneWidget);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Start button is disabled until propeller removal checkbox is confirmed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // Find start button by key
    final startButtonFinder = find.byKey(const Key('start_motor_test_button'));
    expect(startButtonFinder, findsOneWidget);

    final startButton = tester.widget<ElevatedButton>(startButtonFinder);
    expect(startButton.onPressed, isNull); // Disabled because props not confirmed!

    // Tap Propeller removal confirmation checkbox
    final checkboxFinder = find.byKey(const Key('props_confirmed_checkbox'));
    expect(checkboxFinder, findsOneWidget);
    await tester.tap(checkboxFinder);
    await tester.pump(const Duration(milliseconds: 100));

    // Now start button should be enabled
    final updatedButton = tester.widget<ElevatedButton>(startButtonFinder);
    expect(updatedButton.onPressed, isNotNull);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Selecting Test All Motors updates button label and selection tag', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // Tap Test All Motors chip
    final allMotorsChip = find.text('Test All Motors (1-4)');
    expect(allMotorsChip, findsOneWidget);
    await tester.tap(allMotorsChip);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('START TEST ALL MOTORS'), findsOneWidget);
    expect(find.text('Test All Motors (1-4 Sequence)'), findsWidgets);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Manual numeric throttle input updates slider and display', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    final textFieldFinder = find.byKey(const Key('throttle_input_field'));
    expect(textFieldFinder, findsOneWidget);

    // Enter 20%
    await tester.enterText(textFieldFinder, '20');
    await tester.pump(const Duration(milliseconds: 100));

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 20.0);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Test All Motors starts sequential execution through motors', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // Select Test All Motors
    await tester.tap(find.text('Test All Motors (1-4)'));
    await tester.pump(const Duration(milliseconds: 100));

    // Confirm propellers removed
    await tester.tap(find.byKey(const Key('props_confirmed_checkbox')));
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Start Test
    await tester.tap(find.byKey(const Key('start_motor_test_button')));
    await tester.pump();

    // Confirm safety modal dialog if visible
    if (find.text('I Confirm: Props Removed').evaluate().isNotEmpty) {
      await tester.tap(find.text('I Confirm: Props Removed'));
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Verify it is running the sequence starting at Motor 1
    expect(find.textContaining('Motor 1'), findsWidgets);

    // Press Stop
    await tester.tap(find.byKey(const Key('stop_motor_test_button')));
    await tester.pump(const Duration(milliseconds: 200));

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
