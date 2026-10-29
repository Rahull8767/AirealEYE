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
  final String? pdfFilePath;
  final String? executiveSummary;
  final String? concludingSummary;
  final List<String> includedImagePaths;
  final List<String> unavailableNotes;

  const InspectionReport({
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
    this.pdfFilePath,
    this.executiveSummary,
    this.concludingSummary,
    this.includedImagePaths = const [],
    this.unavailableNotes = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'missionId': missionId,
      'missionName': missionName,
      'date': date.toIso8601String(),
      'coveragePercent': coveragePercent,
      'totalDistanceKm': totalDistanceKm,
      'durationSeconds': duration.inSeconds,
      'totalImages': totalImages,
      'totalDetections': totalDetections,
      'anomalyDistribution': anomalyDistribution,
      'pdfFilePath': pdfFilePath,
      'executiveSummary': executiveSummary,
      'concludingSummary': concludingSummary,
      'includedImagePaths': includedImagePaths,
      'unavailableNotes': unavailableNotes,
    };
  }

  factory InspectionReport.fromJson(Map<String, dynamic> json) {
    final distRaw = json['anomalyDistribution'] as Map<String, dynamic>? ?? {};
    final dist = distRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    final imgsRaw = json['includedImagePaths'] as List<dynamic>? ?? [];
    final imgs = imgsRaw.map((e) => e.toString()).toList();

    final unavailRaw = json['unavailableNotes'] as List<dynamic>? ?? [];
    final unavail = unavailRaw.map((e) => e.toString()).toList();

    return InspectionReport(
      id: json['id'] as String,
      missionId: json['missionId'] as String? ?? 'MANUAL_INSPECTION',
      missionName: json['missionName'] as String? ?? 'Inspection Run',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      coveragePercent: (json['coveragePercent'] as num?)?.toDouble() ?? 100.0,
      totalDistanceKm: (json['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
      duration: Duration(
        seconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      ),
      totalImages: (json['totalImages'] as num?)?.toInt() ?? 0,
      totalDetections: (json['totalDetections'] as num?)?.toInt() ?? 0,
      anomalyDistribution: dist,
      pdfFilePath: json['pdfFilePath'] as String?,
      executiveSummary: json['executiveSummary'] as String?,
      concludingSummary: json['concludingSummary'] as String?,
      includedImagePaths: imgs,
      unavailableNotes: unavail,
    );
  }
}
