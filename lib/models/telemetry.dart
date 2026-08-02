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
  });

  factory DroneTelemetry.initial() {
    return DroneTelemetry(
      altitude: 0.0,
      speed: 0.0,
      distance: 0.0,
      heading: 0.0,
      batteryPercent: 1.0,
      batteryVoltage: 16.8,
      latitude: 37.7749,
      longitude: -122.4194,
      satellites: 0,
      flightMode: 'DISCONNECTED',
      rssi: 0.0,
      isConnected: false,
    );
  }

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
    );
  }
}
