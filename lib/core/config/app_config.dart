class AppConfig {
  // Drone Communication Settings
  static const String droneHostIp = '192.168.1.100';
  static const int pixhawkPort = 14550;
  static const String telemetryFrequencyHz = '10 Hz';
  
  // Video & AI Settings
  static const String videoFeedUrl = 'rtsp://192.168.1.100:8554/live';
  static const double defaultAiConfidenceThreshold = 0.75;
  static const String cameraResolution = '1080p (FHD)';
  static const int videoFps = 30;

  // Third-Party Services
  static const String firebaseSyncEndpoint = 'https://mock-firebase-aerialeye.firebaseio.com';
  static const String firebaseApiKey = 'AIzaSyMockKeyForAerialEyeM3';
  static const String mapboxAccessToken = 'pk.mockAccessTokenForAerialEye';

  // App Metadata
  static const String appName = 'AerialEye';
  static const String appVersion = 'v1.0.0-Beta';
}
