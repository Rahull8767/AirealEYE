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
    expect(find.text('Test All Motors (Simultaneous)'), findsOneWidget);

    // Verify default throttle percentage (10%)
    expect(find.text('THROTTLE PERCENTAGE'), findsOneWidget);
    expect(find.text('10% (Def)'), findsOneWidget);

    // Verify default duration (3s)
    expect(find.text('TEST DURATION'), findsOneWidget);
    expect(find.text('3s (Def)'), findsOneWidget);
    expect(find.byKey(const Key('duration_text_field')), findsOneWidget);
    expect(find.byKey(const Key('duration_unit_seconds')), findsOneWidget);
    expect(find.byKey(const Key('duration_unit_minutes')), findsOneWidget);

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
    final allMotorsChip = find.text('Test All Motors (Simultaneous)');
    expect(allMotorsChip, findsOneWidget);
    await tester.tap(allMotorsChip);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('START TEST ALL MOTORS'), findsOneWidget);
    expect(find.text('Test All Motors (Simultaneous)'), findsWidgets);

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

  testWidgets('Individual motor testing remains unchanged and functions independently', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // Select Motor 2 (B)
    await tester.tap(find.text('Motor 2 (B)'));
    await tester.pump(const Duration(milliseconds: 100));

    // Confirm propellers removed
    await tester.tap(find.byKey(const Key('props_confirmed_checkbox')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('START TEST MOTOR B'), findsOneWidget);

    // Tap Start Test
    await tester.tap(find.byKey(const Key('start_motor_test_button')));
    await tester.pump();

    // Confirm safety modal dialog if visible
    if (find.text('I Confirm: Props Removed').evaluate().isNotEmpty) {
      await tester.tap(find.text('I Confirm: Props Removed'));
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Verify individual motor test is running
    expect(find.textContaining('MOTOR B SPINNING'), findsWidgets);

    // Press Stop
    await tester.tap(find.byKey(const Key('stop_motor_test_button')));
    await tester.pump(const Duration(milliseconds: 200));

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Test All Motors starts simultaneous execution of all 4 motors and stops cleanly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // Select Test All Motors
    await tester.tap(find.text('Test All Motors (Simultaneous)'));
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

    // Verify it is running the simultaneous test for all 4 motors
    expect(find.textContaining('ALL 4 MOTORS ACTIVE'), findsWidgets);
    expect(find.textContaining('ALL 4 MOTORS SPINNING SIMULTANEOUSLY'), findsWidgets);
    expect(find.text('STOP ALL MOTORS'), findsOneWidget);

    // Press Stop All Motors
    await tester.tap(find.byKey(const Key('stop_motor_test_button')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Emergency stop confirmed'), findsWidgets);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Refuses to start motor test when vehicle is armed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    await tester.pumpWidget(buildTestApp(droneService: mockService));
    mockService.connect();
    await tester.pump(const Duration(milliseconds: 600));
    await mockService.arm();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify armed safety banner is shown
    expect(find.textContaining('SAFETY INTERLOCK ACTIVE — MOTORS ARMED'), findsOneWidget);

    // Confirm propellers checkbox
    await tester.tap(find.byKey(const Key('props_confirmed_checkbox')));
    await tester.pump(const Duration(milliseconds: 100));

    // Start button should remain disabled when armed
    final startButton = tester.widget<ElevatedButton>(find.byKey(const Key('start_motor_test_button')));
    expect(startButton.onPressed, isNull);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('User can enter custom seconds or minutes for motor test duration', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockDroneService();
    mockService.connect();

    await tester.pumpWidget(buildTestApp(droneService: mockService));
    await tester.pump(const Duration(milliseconds: 600));

    // 1. Enter custom seconds (e.g., 25s)
    final durationInput = find.byKey(const Key('duration_text_field'));
    expect(durationInput, findsOneWidget);

    await tester.enterText(durationInput, '25');
    await tester.pump(const Duration(milliseconds: 100));

    // Verify badge updates to 25s
    expect(find.text('25s'), findsWidgets);

    // 2. Switch to Minutes unit
    final minutesToggle = find.byKey(const Key('duration_unit_minutes'));
    expect(minutesToggle, findsOneWidget);
    await tester.tap(minutesToggle);
    await tester.pump(const Duration(milliseconds: 100));

    // Enter 2 minutes
    await tester.enterText(durationInput, '2');
    await tester.pump(const Duration(milliseconds: 100));

    // Verify badge updates to 2m (120s)
    expect(find.text('2m (120s)'), findsOneWidget);

    // 3. Tap a preset chip (e.g., 1m)
    final preset1m = find.byKey(const Key('duration_preset_1m'));
    expect(preset1m, findsOneWidget);
    await tester.tap(preset1m);
    await tester.pump(const Duration(milliseconds: 100));

    // Verify badge updates to 1m (60s)
    expect(find.text('1m (60s)'), findsOneWidget);

    mockService.disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
