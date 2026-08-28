import 'package:aerial_eye/models/detection.dart';
import 'package:aerial_eye/services/detection_service.dart';

class RealDetectionService implements DetectionService {
  @override
  List<AiDetection> generateInitialDetections() {
    // Real camera detection feeds will load from localized database
    return [];
  }

  @override
  AiDetection generateRandomDetection(double lat, double lng, String missionId, double altitude) {
    throw UnimplementedError("Real hardware camera stream AI processing is under development.");
  }
}
