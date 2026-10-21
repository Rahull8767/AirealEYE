class DroneTelemetry {
  final double altitude; // meters
  final double speed; // m/s
  final double distance; // meters traveled
  final double heading; // degrees (0-360)
  final double batteryPercent; // 0.0 to 1.0
  final double batteryVoltage; // volts
  final double latitude;
  final double longitude;
  final int satellites;
  final String flightMode; // e.g. GUIDED, AUTO, RTL, LAND, LOITER, STABILIZE
  final double rssi; // signal strength 0 to 100
  final bool isConnected;
  final bool isStale;

  // Additional telemetry fields
  final bool armed;
  final double relativeAltitude;
  final double groundSpeed;
  final double airSpeed;
  final double roll; // degrees
  final double pitch; // degrees
  final double yaw; // degrees
  final double batteryPercentage; // 0 to 100
  final double batteryCurrent; // Amps
  final int gpsFix; // 0-1: no fix, 2: 2D, 3: 3D, etc.
  final double climbRate; // m/s
  final DateTime? lastUpdate;

  // Mission & Navigation
  final int currentWaypoint;
  final int totalWaypoints;
  final double? homeLatitude;
  final double? homeLongitude;

  // Per-stream availability flags and timestamps
  final bool hasReceivedGps;
  final bool hasReceivedBattery;
  final bool hasReceivedPosition;
  final bool hasReceivedAttitude;
  final bool hasReceivedVfrHud;
  final DateTime? lastHeartbeat;
  final DateTime? lastGlobalPosition;
  final DateTime? lastBatteryUpdate;
  final DateTime? lastGpsUpdate;
  final DateTime? lastAttitudeUpdate;
  final DateTime? lastVfrHudUpdate;

  DroneTelemetry({
    required this.altitude,
    required this.speed,
    required this.distance,
    required this.heading,
    required this.batteryPercent,
    required this.batteryVoltage,
    required this.latitude,
    required this.longitude,
    required this.satellites,
    required this.flightMode,
    required this.rssi,
    required this.isConnected,
    this.isStale = false,
    required this.armed,
    required this.relativeAltitude,
    required this.groundSpeed,
    required this.airSpeed,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.batteryPercentage,
    required this.batteryCurrent,
    required this.gpsFix,
    required this.climbRate,
    this.currentWaypoint = 0,
    this.totalWaypoints = 0,
    this.homeLatitude,
    this.homeLongitude,
    this.lastUpdate,
    this.hasReceivedGps = false,
    this.hasReceivedBattery = false,
    this.hasReceivedPosition = false,
    this.hasReceivedAttitude = false,
    this.hasReceivedVfrHud = false,
    this.lastHeartbeat,
    this.lastGlobalPosition,
    this.lastBatteryUpdate,
    this.lastGpsUpdate,
    this.lastAttitudeUpdate,
    this.lastVfrHudUpdate,
  });

  factory DroneTelemetry.initial() {
    return DroneTelemetry(
      altitude: 0.0,
      speed: 0.0,
      distance: 0.0,
      heading: 0.0,
      batteryPercent: 0.0,
      batteryVoltage: 0.0,
      latitude: 0.0,
      longitude: 0.0,
      satellites: 0,
      flightMode: 'DISCONNECTED',
      rssi: 0.0,
      isConnected: false,
      isStale: false,
      armed: false,
      relativeAltitude: 0.0,
      groundSpeed: 0.0,
      airSpeed: 0.0,
      roll: 0.0,
      pitch: 0.0,
      yaw: 0.0,
      batteryPercentage: 0.0,
      batteryCurrent: 0.0,
      gpsFix: 0,
      climbRate: 0.0,
      currentWaypoint: 0,
      totalWaypoints: 0,
      homeLatitude: null,
      homeLongitude: null,
      lastUpdate: null,
      hasReceivedGps: false,
      hasReceivedBattery: false,
      hasReceivedPosition: false,
      hasReceivedAttitude: false,
      hasReceivedVfrHud: false,
      lastHeartbeat: null,
      lastGlobalPosition: null,
      lastBatteryUpdate: null,
      lastGpsUpdate: null,
      lastAttitudeUpdate: null,
      lastVfrHudUpdate: null,
    );
  }

  // Formatting helpers to prevent fake zeroes when data hasn't arrived
  String get altitudeDisplay => hasReceivedPosition || isConnected
      ? '${altitude.toStringAsFixed(1)} m'
      : '--';
  String get speedDisplay => hasReceivedVfrHud || isConnected
      ? '${speed.toStringAsFixed(1)} m/s'
      : '--';
  String get headingDisplay => hasReceivedPosition || isConnected
      ? '${heading.toStringAsFixed(0)}°'
      : '--';
  String get batteryVoltageDisplay =>
      hasReceivedBattery ? '${batteryVoltage.toStringAsFixed(1)} V' : '--';
  String get batteryPercentDisplay =>
      hasReceivedBattery ? '${batteryPercentage.toStringAsFixed(0)}%' : '--';
  String get satellitesDisplay =>
      hasReceivedGps ? '$satellites Sats' : 'Waiting...';
  String get waypointProgressDisplay =>
      totalWaypoints > 0 ? 'WP $currentWaypoint / $totalWaypoints' : '--';

  DroneTelemetry copyWith({
    double? altitude,
    double? speed,
    double? distance,
    double? heading,
    double? batteryPercent,
    double? batteryVoltage,
    double? latitude,
    double? longitude,
    int? satellites,
    String? flightMode,
    double? rssi,
    bool? isConnected,
    bool? isStale,
    bool? armed,
    double? relativeAltitude,
    double? groundSpeed,
    double? airSpeed,
    double? roll,
    double? pitch,
    double? yaw,
    double? batteryPercentage,
    double? batteryCurrent,
    int? gpsFix,
    double? climbRate,
    int? currentWaypoint,
    int? totalWaypoints,
    double? homeLatitude,
    double? homeLongitude,
    DateTime? lastUpdate,
    bool? hasReceivedGps,
    bool? hasReceivedBattery,
    bool? hasReceivedPosition,
    bool? hasReceivedAttitude,
    bool? hasReceivedVfrHud,
    DateTime? lastHeartbeat,
    DateTime? lastGlobalPosition,
    DateTime? lastBatteryUpdate,
    DateTime? lastGpsUpdate,
    DateTime? lastAttitudeUpdate,
    DateTime? lastVfrHudUpdate,
  }) {
    return DroneTelemetry(
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      distance: distance ?? this.distance,
      heading: heading ?? this.heading,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      satellites: satellites ?? this.satellites,
      flightMode: flightMode ?? this.flightMode,
      rssi: rssi ?? this.rssi,
      isConnected: isConnected ?? this.isConnected,
      isStale: isStale ?? this.isStale,
      armed: armed ?? this.armed,
      relativeAltitude: relativeAltitude ?? this.relativeAltitude,
      groundSpeed: groundSpeed ?? this.groundSpeed,
      airSpeed: airSpeed ?? this.airSpeed,
      roll: roll ?? this.roll,
      pitch: pitch ?? this.pitch,
      yaw: yaw ?? this.yaw,
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      batteryCurrent: batteryCurrent ?? this.batteryCurrent,
      gpsFix: gpsFix ?? this.gpsFix,
      climbRate: climbRate ?? this.climbRate,
      currentWaypoint: currentWaypoint ?? this.currentWaypoint,
      totalWaypoints: totalWaypoints ?? this.totalWaypoints,
      homeLatitude: homeLatitude ?? this.homeLatitude,
      homeLongitude: homeLongitude ?? this.homeLongitude,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      hasReceivedGps: hasReceivedGps ?? this.hasReceivedGps,
      hasReceivedBattery: hasReceivedBattery ?? this.hasReceivedBattery,
      hasReceivedPosition: hasReceivedPosition ?? this.hasReceivedPosition,
      hasReceivedAttitude: hasReceivedAttitude ?? this.hasReceivedAttitude,
      hasReceivedVfrHud: hasReceivedVfrHud ?? this.hasReceivedVfrHud,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      lastGlobalPosition: lastGlobalPosition ?? this.lastGlobalPosition,
      lastBatteryUpdate: lastBatteryUpdate ?? this.lastBatteryUpdate,
      lastGpsUpdate: lastGpsUpdate ?? this.lastGpsUpdate,
      lastAttitudeUpdate: lastAttitudeUpdate ?? this.lastAttitudeUpdate,
      lastVfrHudUpdate: lastVfrHudUpdate ?? this.lastVfrHudUpdate,
    );
  }
}
