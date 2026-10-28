import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/telemetry.dart';
import 'package:aerial_eye/models/motor_test_state.dart';
import 'package:aerial_eye/providers/drone_provider.dart';
import 'package:aerial_eye/services/drone_service.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

enum DurationUnit {
  seconds,
  minutes,
}

class MotorTestScreen extends ConsumerStatefulWidget {
  const MotorTestScreen({super.key});

  @override
  ConsumerState<MotorTestScreen> createState() => _MotorTestScreenState();
}

class _MotorTestScreenState extends ConsumerState<MotorTestScreen>
    with SingleTickerProviderStateMixin {
  // Configuration State
  MotorSelection _selectedMotor = MotorSelection.motor1;
  double _throttlePercent = 10.0;
  int _durationSeconds = 3;
  DurationUnit _durationUnit = DurationUnit.seconds;

  // Safety State
  bool _propsRemovedConfirmed = false;
  bool _hasAcknowledgedSafetyDialog = false;

  // Execution State
  MotorTestExecutionStatus _status = MotorTestExecutionStatus.idle;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  MotorTestResult? _lastResult;
  String? _statusDetails;
  MotorSelection? _currentlyActiveMotor;
  late final TextEditingController _throttleTextController;
  late final TextEditingController _durationTextController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _throttleTextController = TextEditingController(
      text: _throttlePercent.toInt().toString(),
    );
    _durationTextController = TextEditingController(
      text: _durationSeconds.toString(),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _throttleTextController.dispose();
    _durationTextController.dispose();
    _pulseController.dispose();
    if (_status == MotorTestExecutionStatus.running ||
        _status == MotorTestExecutionStatus.sendingCommand) {
      try {
        ref.read(droneServiceProvider).stopMotorTest();
      } catch (_) {}
    }
    super.dispose();
  }

  void _onThrottleSliderChanged(double value) {
    setState(() {
      _throttlePercent = value;
      _throttleTextController.text = value.toInt().toString();
    });
  }

  void _onThrottleTextChanged(String text) {
    final parsed = double.tryParse(text);
    if (parsed != null) {
      final clamped = parsed.clamp(0.0, 100.0);
      setState(() {
        _throttlePercent = clamped;
      });
    }
  }

  void _onDurationTextChanged(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed != null && parsed > 0) {
      int totalSec;
      if (_durationUnit == DurationUnit.minutes) {
        totalSec = (parsed * 60).round();
      } else {
        totalSec = parsed.round();
      }
      if (totalSec < 1) totalSec = 1;
      if (totalSec > 600) totalSec = 600;
      setState(() {
        _durationSeconds = totalSec;
      });
    }
  }

  void _setDurationUnit(DurationUnit unit) {
    if (_durationUnit == unit) return;
    setState(() {
      _durationUnit = unit;
      if (unit == DurationUnit.minutes) {
        final mins = _durationSeconds / 60.0;
        _durationTextController.text = (mins % 1 == 0)
            ? mins.toInt().toString()
            : mins.toStringAsFixed(1);
      } else {
        _durationTextController.text = _durationSeconds.toString();
      }
    });
  }

  String _formatDurationBadge(int totalSeconds) {
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    if (secs == 0) {
      return '${mins}m (${totalSeconds}s)';
    }
    return '${mins}m ${secs}s (${totalSeconds}s)';
  }

  String _formatCountdown(int remainingSeconds) {
    if (remainingSeconds < 60) {
      return '${remainingSeconds}s';
    }
    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  Future<void> _startMotorTest() async {
    final telemetry = ref.read(droneTelemetryProvider).value ?? DroneTelemetry.initial();
    final droneService = ref.read(droneServiceProvider);

    // 1. Safety check: Armed Interlock
    if (telemetry.armed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SAFETY INTERLOCK: Drone is ARMED. Disarm before performing motor tests.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // 2. Safety check: Connection
    if (!telemetry.isConnected && droneService.connectionState != DroneConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'MAVLink link disconnected. Connect to flight controller before testing.',
          ),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    // 3. Safety check: Propeller removal checkbox
    if (!_propsRemovedConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'MANDATORY: Confirm that all propellers have been removed before testing.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // 4. First-time confirmation modal
    if (!_hasAcknowledgedSafetyDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.danger, width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: AppTheme.danger, size: 24),
              SizedBox(width: 10),
              Text(
                'Critical Safety Protocol',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Propellers can produce unexpected lift, violent movement, or severe lacerations even at low throttle.\n',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.shieldAlert, color: AppTheme.danger, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Do you physically verify that ALL PROPELLERS are removed from Motors 1, 2, 3, and 4?',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text('I Confirm: Props Removed'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      setState(() => _hasAcknowledgedSafetyDialog = true);
    }

    // 5. Execute Command (Single Motor or Simultaneous All-Motors)
    if (_selectedMotor.isAllMotors) {
      await _runTestAllMotorsSimultaneous(droneService);
    } else {
      await _runSingleMotorTest(droneService);
    }
  }

  Future<void> _runSingleMotorTest(DroneService droneService) async {
    setState(() {
      _status = MotorTestExecutionStatus.sendingCommand;
      _statusDetails = 'Transmitting MAV_CMD_DO_MOTOR_TEST for Motor ${_selectedMotor.letterCode}...';
      _currentlyActiveMotor = _selectedMotor;
    });

    try {
      final targetIndex = _selectedMotor.motorIndex;

      final result = await droneService.testMotor(
        motorInstance: targetIndex,
        throttlePercent: _throttlePercent,
        durationSeconds: _durationSeconds,
        testAll: false,
      );

      if (!mounted) return;

      setState(() {
        _lastResult = result;
      });

      if (result.success) {
        setState(() {
          _status = MotorTestExecutionStatus.running;
          _remainingSeconds = _durationSeconds;
          _statusDetails = result.message;
        });

        _countdownTimer?.cancel();
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_remainingSeconds <= 1) {
            timer.cancel();
            setState(() {
              _status = MotorTestExecutionStatus.completed;
              _remainingSeconds = 0;
              _currentlyActiveMotor = null;
              _statusDetails =
                  'Test complete (${_formatDurationBadge(_durationSeconds)} duration elapsed). Autopilot watchdog cut throttle.';
            });
          } else {
            setState(() {
              _remainingSeconds--;
            });

            // Keepalive renewal for APM 2.8 30s hardware watchdog if test duration is long
            final elapsed = _durationSeconds - _remainingSeconds;
            if (elapsed > 0 && elapsed % 20 == 0 && _remainingSeconds > 5) {
              droneService.testMotor(
                motorInstance: targetIndex,
                throttlePercent: _throttlePercent,
                durationSeconds: _remainingSeconds > 30 ? 30 : _remainingSeconds,
                testAll: false,
              ).catchError((_) => MotorTestResult(
                success: false,
                message: 'Keepalive refresh error',
                commandId: 209,
                motorIndex: targetIndex,
                throttlePercent: _throttlePercent,
                durationSeconds: _remainingSeconds,
                timestamp: DateTime.now(),
              ));
            }
          }
        });
      } else {
        setState(() {
          _status = MotorTestExecutionStatus.failed;
          _currentlyActiveMotor = null;
          _statusDetails = result.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = MotorTestExecutionStatus.failed;
        _currentlyActiveMotor = null;
        _statusDetails = 'Error: $e';
      });
    }
  }

  Future<void> _runTestAllMotorsSimultaneous(DroneService droneService) async {
    _countdownTimer?.cancel();

    setState(() {
      _status = MotorTestExecutionStatus.sendingCommand;
      _statusDetails = 'Transmitting simultaneous test commands for all 4 motors...';
      _currentlyActiveMotor = MotorSelection.allMotors;
    });

    try {
      final result = await droneService.testAllMotors(
        throttlePercent: _throttlePercent,
        durationSeconds: _durationSeconds,
      );

      if (!mounted) return;

      setState(() {
        _lastResult = result;
      });

      if (result.success) {
        setState(() {
          _status = MotorTestExecutionStatus.running;
          _remainingSeconds = _durationSeconds;
          _statusDetails = 'Simultaneous test running: All 4 motors spinning at ${_throttlePercent.toInt()}% throttle.';
        });

        _countdownTimer?.cancel();
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_remainingSeconds <= 1) {
            timer.cancel();
            setState(() {
              _status = MotorTestExecutionStatus.completed;
              _remainingSeconds = 0;
              _currentlyActiveMotor = null;
              _statusDetails =
                  'Simultaneous test complete (${_formatDurationBadge(_durationSeconds)} duration elapsed). All motors halted.';
            });
            droneService.stopMotorTest().catchError((_) => MotorTestResult(
              success: false,
              message: 'Stop error',
              commandId: 209,
              motorIndex: 1,
              throttlePercent: 0,
              durationSeconds: 0,
              timestamp: DateTime.now(),
            ));
          } else {
            setState(() {
              _remainingSeconds--;
            });

            // Keepalive renewal for APM 2.8 30s hardware watchdog if test duration is long
            final elapsed = _durationSeconds - _remainingSeconds;
            if (elapsed > 0 && elapsed % 20 == 0 && _remainingSeconds > 5) {
              droneService.testAllMotors(
                throttlePercent: _throttlePercent,
                durationSeconds: _remainingSeconds > 30 ? 30 : _remainingSeconds,
              ).catchError((_) => MotorTestResult(
                success: false,
                message: 'Keepalive refresh error',
                commandId: 209,
                motorIndex: 1,
                throttlePercent: _throttlePercent,
                durationSeconds: _remainingSeconds,
                timestamp: DateTime.now(),
              ));
            }
          }
        });
      } else {
        setState(() {
          _status = MotorTestExecutionStatus.failed;
          _currentlyActiveMotor = null;
          _statusDetails = result.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = MotorTestExecutionStatus.failed;
        _currentlyActiveMotor = null;
        _statusDetails = 'Error: $e';
      });
    }
  }

  Future<void> _stopMotorTest() async {
    _countdownTimer?.cancel();

    setState(() {
      _status = MotorTestExecutionStatus.stopping;
      _statusDetails = 'Sending emergency stop packet (throttle=0, duration=0)...';
      _currentlyActiveMotor = null;
    });

    try {
      final droneService = ref.read(droneServiceProvider);
      final result = await droneService.stopMotorTest();
      if (mounted) {
        setState(() {
          _lastResult = result;
          _status = MotorTestExecutionStatus.stopped;
          _remainingSeconds = 0;
          _statusDetails = 'Emergency stop confirmed: throttle cut to 0%.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = MotorTestExecutionStatus.failed;
          _statusDetails = 'Stop error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = ref.watch(droneTelemetryProvider).value ?? DroneTelemetry.initial();
    final diagnostics = ref.watch(droneDiagnosticsProvider).value;
    final isArmed = telemetry.armed;
    final isConnected = telemetry.isConnected;
    final isRunning = _status == MotorTestExecutionStatus.running ||
        _status == MotorTestExecutionStatus.sendingCommand;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Motor Test Panel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Mission Planner Diagnostic Benchmark',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? AppTheme.success : AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? (isArmed ? 'ARMED' : 'DISARMED') : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isConnected
                        ? (isArmed ? AppTheme.danger : AppTheme.success)
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Critical Armed Safety Banner
            if (isArmed) ...[
              _buildArmedSafetyBanner(),
              const SizedBox(height: 16),
            ] else if (!isConnected) ...[
              _buildDisconnectedBanner(),
              const SizedBox(height: 16),
            ],

            // 2. Propeller-Removal Mandatory Safety Card
            _buildPropellerWarningCard(),
            const SizedBox(height: 16),

            // 3. Quadcopter Visual Diagram & Motor Selection
            _buildVisualMotorSelector(),
            const SizedBox(height: 16),

            // 4. Throttle Controls (Slider & Manual Input)
            _buildThrottleControlCard(isRunning),
            const SizedBox(height: 16),

            // 5. Duration Selector (1-5s)
            _buildDurationControlCard(isRunning),
            const SizedBox(height: 16),

            // 6. Action Buttons: Start & Emergency Stop
            _buildActionButtons(isArmed, isConnected, isRunning),
            const SizedBox(height: 16),

            // 7. Status & MAVLink Diagnostics Card
            _buildDiagnosticsCard(diagnostics),
            const SizedBox(height: 16),

            // 8. Motor Numbering & Sequence Reference Guide
            _buildReferenceAccordion(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildArmedSafetyBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger, width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.shieldAlert, color: AppTheme.danger, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SAFETY INTERLOCK ACTIVE — MOTORS ARMED',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Flight controller reports armed state. Motor testing is strictly blocked until the drone is disarmed.',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.wifiOff, color: AppTheme.warning, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'MAVLink disconnected. Connect to Raspberry Pi UDP (:14550) or APM serial to test physical motors.',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropellerWarningCard() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.alertTriangle, color: AppTheme.danger, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROPELLER REMOVAL PROTOCOL',
                      style: TextStyle(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'All propellers must be physically removed before testing',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Even at 10% throttle, high-torque brushless motors can cause serious cuts. Never test motors on the bench with propellers installed.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              setState(() {
                _propsRemovedConfirmed = !_propsRemovedConfirmed;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _propsRemovedConfirmed
                    ? AppTheme.success.withValues(alpha: 0.12)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _propsRemovedConfirmed ? AppTheme.success : AppTheme.border,
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    key: const Key('props_confirmed_checkbox'),
                    value: _propsRemovedConfirmed,
                    onChanged: (val) {
                      setState(() {
                        _propsRemovedConfirmed = val ?? false;
                      });
                    },
                    activeColor: AppTheme.success,
                    checkColor: Colors.black,
                  ),
                  const Expanded(
                    child: Text(
                      'I confirm that all propellers are removed from all 4 motors.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualMotorSelector() {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MOTOR SELECTION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedMotor.displayLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Visual Quad-X Frame Display
          Center(
            child: SizedBox(
              height: 190,
              width: 250,
              child: CustomPaint(
                painter: _QuadXFramePainter(
                  selectedMotor: _selectedMotor,
                  activeMotor: _currentlyActiveMotor,
                  pulseValue: _pulseController.value,
                ),
                child: Stack(
                  children: [
                    // Motor 1 (A) — Top-Right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _buildDiagramMotorButton(MotorSelection.motor1),
                    ),
                    // Motor 4 (D) — Top-Left
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _buildDiagramMotorButton(MotorSelection.motor4),
                    ),
                    // Motor 2 (B) — Bottom-Right
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: _buildDiagramMotorButton(MotorSelection.motor2),
                    ),
                    // Motor 3 (C) — Bottom-Left
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: _buildDiagramMotorButton(MotorSelection.motor3),
                    ),
                    // Center FC Label
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Text(
                          'APM 2.8\nQuad-X',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Selection Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...[
                MotorSelection.motor1,
                MotorSelection.motor2,
                MotorSelection.motor3,
                MotorSelection.motor4,
              ].map((m) {
                final isSelected = _selectedMotor == m;
                return ChoiceChip(
                  label: Text('Motor ${m.motorIndex} (${m.letterCode})'),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedMotor = m);
                  },
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surface,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }),
              // Test All Motors Option
              ChoiceChip(
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCw, size: 14),
                    SizedBox(width: 4),
                    Text('Test All Motors (Simultaneous)'),
                  ],
                ),
                selected: _selectedMotor == MotorSelection.allMotors,
                onSelected: (val) {
                  if (val) setState(() => _selectedMotor = MotorSelection.allMotors);
                },
                selectedColor: AppTheme.primary,
                backgroundColor: AppTheme.surface,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: _selectedMotor == MotorSelection.allMotors
                      ? Colors.white
                      : AppTheme.textSecondary,
                  fontWeight: _selectedMotor == MotorSelection.allMotors
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiagramMotorButton(MotorSelection motor) {
    final isCurrentlyActive = _currentlyActiveMotor == motor;
    final isSelected = _currentlyActiveMotor != null
        ? isCurrentlyActive
        : (_selectedMotor == motor || _selectedMotor == MotorSelection.allMotors);

    return GestureDetector(
      onTap: () {
        if (_status == MotorTestExecutionStatus.running ||
            _status == MotorTestExecutionStatus.sendingCommand) {
          return;
        }
        setState(() => _selectedMotor = motor);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isCurrentlyActive
              ? AppTheme.secondary
              : (isSelected ? AppTheme.primary : AppTheme.card),
          shape: BoxShape.circle,
          border: Border.all(
            color: isCurrentlyActive
                ? Colors.white
                : (isSelected ? AppTheme.secondary : AppTheme.border),
            width: (isCurrentlyActive || isSelected) ? 2.5 : 1.0,
          ),
          boxShadow: (isCurrentlyActive || isSelected)
              ? [
                  BoxShadow(
                    color: (isCurrentlyActive ? AppTheme.secondary : AppTheme.primary)
                        .withValues(alpha: 0.6),
                    blurRadius: isCurrentlyActive ? 14 : 10,
                    spreadRadius: isCurrentlyActive ? 4 : 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'M${motor.motorIndex}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: (isCurrentlyActive || isSelected) ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            Text(
              '(${motor.letterCode})',
              style: TextStyle(
                fontSize: 10,
                color: (isCurrentlyActive || isSelected) ? Colors.white70 : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThrottleControlCard(bool isRunning) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'THROTTLE PERCENTAGE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              // Manual Numeric Input Box
              SizedBox(
                width: 75,
                height: 38,
                child: TextField(
                  key: const Key('throttle_input_field'),
                  controller: _throttleTextController,
                  enabled: !isRunning,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondary,
                  ),
                  decoration: InputDecoration(
                    suffixText: '%',
                    suffixStyle: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.secondary),
                    ),
                  ),
                  onChanged: _onThrottleTextChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Slider: 0% to 100%
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _throttlePercent > 30 ? AppTheme.warning : AppTheme.secondary,
              inactiveTrackColor: AppTheme.surface,
              thumbColor: _throttlePercent > 30 ? AppTheme.warning : AppTheme.secondary,
              overlayColor: AppTheme.secondary.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              trackHeight: 6,
            ),
            child: Slider(
              value: _throttlePercent,
              min: 0.0,
              max: 100.0,
              divisions: 100,
              onChanged: isRunning ? null : _onThrottleSliderChanged,
            ),
          ),

          // Quick Presets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [5, 10, 15, 25, 50].map((pct) {
              final isCurrent = _throttlePercent.toInt() == pct;
              return InkWell(
                onTap: isRunning
                    ? null
                    : () {
                        setState(() {
                          _throttlePercent = pct.toDouble();
                          _throttleTextController.text = pct.toString();
                        });
                      },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isCurrent ? AppTheme.primary : AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCurrent ? AppTheme.secondary : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    '$pct%${pct == 10 ? ' (Def)' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          if (_throttlePercent > 25) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.alertCircle, color: AppTheme.warning, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Caution: High throttle (>25%). Ensure motors are securely bolted to frame.',
                      style: TextStyle(fontSize: 11, color: AppTheme.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDurationControlCard(bool isRunning) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TEST DURATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _formatDurationBadge(_durationSeconds),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Custom Input Row: Numeric TextField + Unit Toggle (Seconds / Minutes)
          Row(
            children: [
              // Numeric text input for custom duration
              Expanded(
                flex: 4,
                child: TextField(
                  key: const Key('duration_text_field'),
                  controller: _durationTextController,
                  enabled: !isRunning,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Duration',
                    labelStyle: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    suffixText: _durationUnit == DurationUnit.seconds ? 'sec' : 'min',
                    suffixStyle: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.secondary),
                    ),
                  ),
                  onChanged: _onDurationTextChanged,
                ),
              ),
              const SizedBox(width: 10),

              // Unit selector pills: Seconds / Minutes
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: const Key('duration_unit_seconds'),
                          onTap: isRunning ? null : () => _setDurationUnit(DurationUnit.seconds),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _durationUnit == DurationUnit.seconds
                                  ? AppTheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Seconds (s)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _durationUnit == DurationUnit.seconds
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _durationUnit == DurationUnit.seconds
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          key: const Key('duration_unit_minutes'),
                          onTap: isRunning ? null : () => _setDurationUnit(DurationUnit.minutes),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _durationUnit == DurationUnit.minutes
                                  ? AppTheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Minutes (m)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _durationUnit == DurationUnit.minutes
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _durationUnit == DurationUnit.minutes
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick Preset Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPresetChip('3s (Def)', 3, DurationUnit.seconds, '3', isRunning),
              _buildPresetChip('5s', 5, DurationUnit.seconds, '5', isRunning),
              _buildPresetChip('10s', 10, DurationUnit.seconds, '10', isRunning),
              _buildPresetChip('30s', 30, DurationUnit.seconds, '30', isRunning),
              _buildPresetChip('1m', 60, DurationUnit.minutes, '1', isRunning),
              _buildPresetChip('2m', 120, DurationUnit.minutes, '2', isRunning),
              _buildPresetChip('5m', 300, DurationUnit.minutes, '5', isRunning),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter any custom seconds or minutes (1s up to 10m). Autopilot watchdog & keepalive will protect the aircraft.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(
    String label,
    int seconds,
    DurationUnit preferredUnit,
    String textValue,
    bool isRunning,
  ) {
    final isSelected = _durationSeconds == seconds;
    return InkWell(
      key: Key('duration_preset_$label'),
      onTap: isRunning
          ? null
          : () {
              setState(() {
                _durationSeconds = seconds;
                _durationUnit = preferredUnit;
                _durationTextController.text = textValue;
              });
            },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppTheme.secondary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool isArmed, bool isConnected, bool isRunning) {
    final canStart = !isArmed && isConnected && _propsRemovedConfirmed && !isRunning;

    return Row(
      children: [
        // Start Test Button
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            key: const Key('start_motor_test_button'),
            onPressed: canStart ? _startMotorTest : null,
            icon: Icon(isRunning ? LucideIcons.loader : LucideIcons.play, size: 16),
            label: Text(
              isRunning
                  ? (_selectedMotor.isAllMotors
                      ? 'ALL 4 MOTORS ACTIVE (${_formatCountdown(_remainingSeconds)})'
                      : 'TEST IN PROGRESS (${_formatCountdown(_remainingSeconds)})')
                  : (_selectedMotor.isAllMotors
                      ? 'START TEST ALL MOTORS'
                      : 'START TEST MOTOR ${_selectedMotor.letterCode}'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.surface,
              disabledForegroundColor: AppTheme.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Emergency Stop Button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            key: const Key('stop_motor_test_button'),
            onPressed: _stopMotorTest,
            icon: const Icon(LucideIcons.square, size: 16),
            label: Text(
              _selectedMotor.isAllMotors && isRunning ? 'STOP ALL MOTORS' : 'STOP TEST',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticsCard(dynamic diagnostics) {
    Color statusColor;
    String statusLabel;

    switch (_status) {
      case MotorTestExecutionStatus.idle:
        statusColor = AppTheme.textSecondary;
        statusLabel = 'READY / IDLE';
        break;
      case MotorTestExecutionStatus.sendingCommand:
        statusColor = AppTheme.warning;
        statusLabel = 'TRANSMITTING COMMAND 209';
        break;
      case MotorTestExecutionStatus.running:
        statusColor = AppTheme.success;
        statusLabel = _selectedMotor.isAllMotors
            ? 'ALL 4 MOTORS SPINNING SIMULTANEOUSLY (${_remainingSeconds}s)'
            : 'MOTOR ${_selectedMotor.letterCode} SPINNING (${_remainingSeconds}s)';
        break;
      case MotorTestExecutionStatus.stopping:
        statusColor = AppTheme.warning;
        statusLabel = 'STOPPING...';
        break;
      case MotorTestExecutionStatus.stopped:
        statusColor = AppTheme.warning;
        statusLabel = 'TEST STOPPED BY USER';
        break;
      case MotorTestExecutionStatus.completed:
        statusColor = AppTheme.success;
        statusLabel = 'TEST COMPLETED SAFELY';
        break;
      case MotorTestExecutionStatus.timedOut:
      case MotorTestExecutionStatus.failed:
        statusColor = AppTheme.danger;
        statusLabel = 'COMMAND REJECTED / FAILED';
        break;
    }

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MAVLINK COMMAND DIAGNOSTICS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_status == MotorTestExecutionStatus.running) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _durationSeconds > 0
                    ? 1.0 - (_remainingSeconds / _durationSeconds)
                    : 0.0,
                backgroundColor: AppTheme.surface,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
          ],

          _buildDiagRow('MAVLink Command', 'MAV_CMD_DO_MOTOR_TEST (ID: 209)'),
          _buildDiagRow(
            'Target Parameters',
            _selectedMotor.isAllMotors
                ? 'Motors: ALL 4 SIMULTANEOUS (Motors 1, 2, 3, 4) | Type: 0 (%) | Throttle: ${_throttlePercent.toInt()}% | Timeout: ${_durationSeconds}s'
                : 'Motor: ${_selectedMotor.motorIndex} (${_selectedMotor.letterCode}) | Type: 0 (%) | Throttle: ${_throttlePercent.toInt()}% | Timeout: ${_durationSeconds}s',
          ),
          if (_lastResult != null) ...[
            _buildDiagRow(
              'Autopilot ACK',
              _lastResult!.ackResult != null
                  ? MotorTestResult.describeMavResult(_lastResult!.ackResult)
                  : 'No ACK returned (Timeout)',
              valueColor: _lastResult!.success ? AppTheme.success : AppTheme.danger,
            ),
            _buildDiagRow(
              'Service Origin',
              _lastResult!.isSimulated
                  ? 'Simulated Mode (Mock Test)'
                  : 'Live Flight Controller MAVLink Transport',
              valueColor: _lastResult!.isSimulated ? AppTheme.warning : AppTheme.secondary,
            ),
          ],
          if (_statusDetails != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusDetails!,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceAccordion() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text(
          'Motor Numbering & Wiring Reference',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Mission Planner Test Sequence vs APM 2.8 Outputs',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        leading: const Icon(LucideIcons.helpCircle, color: AppTheme.secondary),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Understanding Motor Order in ArduCopter Quad-X:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                SizedBox(height: 6),
                Text(
                  '• Individual motor test order (A -> B -> C -> D) is clockwise around the frame starting with front-right.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  '• "Test All Motors" operates all 4 motors simultaneously at the configured throttle.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  '• Test Motor A (1): Front-Right (CCW) -> Servo Output 1',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  '• Test Motor B (2): Rear-Right (CW)   -> Servo Output 4',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  '• Test Motor C (3): Rear-Left (CCW)   -> Servo Output 2',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  '• Test Motor D (4): Front-Left (CW)   -> Servo Output 3',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                SizedBox(height: 8),
                Text(
                  'Why does Mission Planner use letters?\nLetters (A, B, C, D) verify that ESCs are wired correctly without needing to memorize internal output numbers.',
                  style: TextStyle(fontSize: 11, color: AppTheme.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom Painter for Quad-X Frame Schematic
class _QuadXFramePainter extends CustomPainter {
  final MotorSelection selectedMotor;
  final MotorSelection? activeMotor;
  final double pulseValue;

  _QuadXFramePainter({
    required this.selectedMotor,
    this.activeMotor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final armPaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final nosePaint = Paint()
      ..color = AppTheme.secondary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw X-arms
    final m1Pos = Offset(size.width - 36, 36); // Top-Right (A)
    final m4Pos = Offset(36, 36); // Top-Left (D)
    final m2Pos = Offset(size.width - 36, size.height - 36); // Bottom-Right (B)
    final m3Pos = Offset(36, size.height - 36); // Bottom-Left (C)

    canvas.drawLine(center, m1Pos, armPaint);
    canvas.drawLine(center, m4Pos, armPaint);
    canvas.drawLine(center, m2Pos, armPaint);
    canvas.drawLine(center, m3Pos, armPaint);

    // Draw Forward Nose Indicator
    final path = Path()
      ..moveTo(center.dx, center.dy - 35)
      ..lineTo(center.dx - 12, center.dy - 15)
      ..lineTo(center.dx + 12, center.dy - 15)
      ..close();
    canvas.drawPath(path, nosePaint);

    // Draw Pulse halos around selected / active motors
    final target = activeMotor ?? selectedMotor;
    final isAll = (selectedMotor == MotorSelection.allMotors) ||
        (activeMotor == MotorSelection.allMotors);
    if (target == MotorSelection.motor1 || isAll) {
      _drawHalo(canvas, m1Pos);
    }
    if (target == MotorSelection.motor2 || isAll) {
      _drawHalo(canvas, m2Pos);
    }
    if (target == MotorSelection.motor3 || isAll) {
      _drawHalo(canvas, m3Pos);
    }
    if (target == MotorSelection.motor4 || isAll) {
      _drawHalo(canvas, m4Pos);
    }
  }

  void _drawHalo(Canvas canvas, Offset pos) {
    final haloPaint = Paint()
      ..color = AppTheme.secondary.withValues(alpha: 0.25 * (1.0 - pulseValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 + (pulseValue * 8.0);
    canvas.drawCircle(pos, 28, haloPaint);
  }

  @override
  bool shouldRepaint(covariant _QuadXFramePainter oldDelegate) {
    return oldDelegate.selectedMotor != selectedMotor ||
        oldDelegate.activeMotor != activeMotor ||
        oldDelegate.pulseValue != pulseValue;
  }
}
