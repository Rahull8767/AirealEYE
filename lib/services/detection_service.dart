import 'package:aerial_eye/models/detection.dart';
import 'package:latlong2/latlong.dart';

abstract class DetectionService {
  List<AiDetection> generateInitialDetections();
  AiDetection generateRandomDetection(
    double lat,
    double lng,
    String missionId,
    double altitude,
  );
}

abstract class GeolocationService {
  LatLng calculateGeotag(
    double droneLat,
    double droneLng,
    double heading,
    double pitch,
    double altitude,
  );
}

class GeolocationServiceImpl implements GeolocationService {
  @override
  LatLng calculateGeotag(
    double droneLat,
    double droneLng,
    double heading,
    double pitch,
    double altitude,
  ) {
    // Standard camera projection simulation
    return LatLng(droneLat, droneLng);
  }
}
