import 'package:flutter/foundation.dart';

/// Represents individual motor selection or simultaneous all-motors test.
enum MotorSelection {
  motor1,
  motor2,
  motor3,
  motor4,
  allMotors,
}

extension MotorSelectionExtension on MotorSelection {
  /// 1-indexed motor sequence number for MAVLink (1..4)
  int get motorIndex {
    switch (this) {
      case MotorSelection.motor1:
        return 1;
      case MotorSelection.motor2:
        return 2;
      case MotorSelection.motor3:
        return 3;
      case MotorSelection.motor4:
        return 4;
      case MotorSelection.allMotors:
        return 1;
    }
  }

  /// Mission Planner letter code (A, B, C, D)
  String get letterCode {
    switch (this) {
      case MotorSelection.motor1:
        return 'A';
      case MotorSelection.motor2:
        return 'B';
      case MotorSelection.motor3:
        return 'C';
      case MotorSelection.motor4:
        return 'D';
      case MotorSelection.allMotors:
        return 'ALL';
    }
  }

  /// Full display label with frame position
  String get displayLabel {
    switch (this) {
      case MotorSelection.motor1:
        return 'Motor 1 (A) — Front-Right';
      case MotorSelection.motor2:
        return 'Motor 2 (B) — Rear-Right';
      case MotorSelection.motor3:
        return 'Motor 3 (C) — Rear-Left';
      case MotorSelection.motor4:
        return 'Motor 4 (D) — Front-Left';
      case MotorSelection.allMotors:
        return 'Test All Motors (Simultaneous)';
    }
  }

  /// Physical APM 2.8 / Pixhawk servo rail pin output (for Quad-X frame)
  String get physicalPinInfo {
    switch (this) {
      case MotorSelection.motor1:
        return 'Servo Rail Out 1 (CW)';
      case MotorSelection.motor2:
        return 'Servo Rail Out 4 (CCW)';
      case MotorSelection.motor3:
        return 'Servo Rail Out 2 (CW)';
      case MotorSelection.motor4:
        return 'Servo Rail Out 3 (CCW)';
      case MotorSelection.allMotors:
        return 'Outputs 1, 4, 2, 3 simultaneously';
    }
  }

  /// Rotation direction on standard ArduCopter Quad-X frame
  String get rotationDirection {
    switch (this) {
      case MotorSelection.motor1:
        return 'CCW';
      case MotorSelection.motor2:
        return 'CW';
      case MotorSelection.motor3:
        return 'CCW';
      case MotorSelection.motor4:
        return 'CW';
      case MotorSelection.allMotors:
        return 'All Motors Active (A, B, C, D)';
    }
  }

  bool get isAllMotors => this == MotorSelection.allMotors;
}

/// Operational state of the motor test panel
enum MotorTestExecutionStatus {
  idle,
  sendingCommand,
  running,
  stopping,
  stopped,
  completed,
  timedOut,
  failed,
}

/// Detailed result of a MAVLink motor test request
@immutable
class MotorTestResult {
  final bool success;
  final int? ackResult;
  final String message;
  final int commandId;
  final int motorIndex;
  final bool testAll;
  final double throttlePercent;
  final int durationSeconds;
  final bool isSimulated;
  final DateTime timestamp;
  final String? rawAckText;

  const MotorTestResult({
    required this.success,
    this.ackResult,
    required this.message,
    this.commandId = 209,
    required this.motorIndex,
    this.testAll = false,
    required this.throttlePercent,
    required this.durationSeconds,
    this.isSimulated = false,
    required this.timestamp,
    this.rawAckText,
  });

  /// Human-readable explanation of MAV_RESULT acknowledgment codes
  static String describeMavResult(int? code) {
    if (code == null) return 'No ACK received (Connection timeout)';
    switch (code) {
      case 0:
        return 'MAV_RESULT_ACCEPTED (0): Command accepted and test routine executed.';
      case 1:
        return 'MAV_RESULT_TEMPORARILY_REJECTED (1): Rejected by autopilot. Ensure safety switch is pressed and drone is disarmed on ground.';
      case 2:
        return 'MAV_RESULT_DENIED (2): Denied by autopilot. Parameters out of bounds or autopilot safety check blocked execution.';
      case 3:
        return 'MAV_RESULT_UNSUPPORTED (3): Unsupported command. Connected flight controller firmware does not implement MAV_CMD_DO_MOTOR_TEST.';
      case 4:
        return 'MAV_RESULT_FAILED (4): Action failed during execution on autopilot.';
      case 5:
        return 'MAV_RESULT_IN_PROGRESS (5): Motor test is currently in progress.';
      case 6:
        return 'MAV_RESULT_CANCELLED (6): Motor test command was cancelled.';
      default:
        return 'Unknown MAV_RESULT code: $code';
    }
  }

  @override
  String toString() {
    return 'MotorTestResult(success: $success, ackResult: $ackResult, message: $message, motor: $motorIndex, throttle: $throttlePercent%, duration: ${durationSeconds}s, sim: $isSimulated)';
  }
}
