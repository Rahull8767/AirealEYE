class Waypoint {
  final int id;
  final double latitude;
  final double longitude;
  final double altitude; // meters for this waypoint
  final double speed; // speed from previous waypoint in m/s
  final int hoverTime; // hover time in seconds

  Waypoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.altitude = 30.0,
    this.speed = 5.0,
    this.hoverTime = 2,
  });

  Waypoint copyWith({
    int? id,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    int? hoverTime,
  }) {
    return Waypoint(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      hoverTime: hoverTime ?? this.hoverTime,
    );
  }
}
