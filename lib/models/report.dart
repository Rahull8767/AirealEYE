class InspectionReport {
  final String id;
  final String missionId;
  final String missionName;
  final DateTime date;
  final double coveragePercent;
  final double totalDistanceKm;
  final Duration duration;
  final int totalImages;
  final int totalDetections;
  final Map<String, int> anomalyDistribution; // e.g. 'Pothole': 5

  InspectionReport({
    required this.id,
    required this.missionId,
    required this.missionName,
    required this.date,
    required this.coveragePercent,
    required this.totalDistanceKm,
    required this.duration,
    required this.totalImages,
    required this.totalDetections,
    required this.anomalyDistribution,
  });
}
