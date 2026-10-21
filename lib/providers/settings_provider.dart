import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/core/config/app_config.dart';

class SystemSettings {
  final bool isDarkMode;
  final String themeColorName;
  final String mapType; // Standard, Satellite, Hybrid, Terrain
  final bool offlineMapsEnabled;
  final String droneIp;
  final int pixhawkPort;
  final String telemetryFreq;
  final String cameraResolution;
  final int videoFps;
  final double aiConfidenceThreshold;
  final List<String> enabledAiClasses;
  final bool firebaseSyncEnabled;

  SystemSettings({
    required this.isDarkMode,
    required this.themeColorName,
    required this.mapType,
    required this.offlineMapsEnabled,
    required this.droneIp,
    required this.pixhawkPort,
    required this.telemetryFreq,
    required this.cameraResolution,
    required this.videoFps,
    required this.aiConfidenceThreshold,
    required this.enabledAiClasses,
    required this.firebaseSyncEnabled,
  });

  factory SystemSettings.defaultSettings() {
    return SystemSettings(
      isDarkMode: true,
      themeColorName: 'Blue',
      mapType: 'Hybrid',
      offlineMapsEnabled: true,
      droneIp: AppConfig.droneHostIp,
      pixhawkPort: AppConfig.pixhawkPort,
      telemetryFreq: AppConfig.telemetryFrequencyHz,
      cameraResolution: AppConfig.cameraResolution,
      videoFps: AppConfig.videoFps,
      aiConfidenceThreshold: AppConfig.defaultAiConfidenceThreshold,
      enabledAiClasses: [
        'Pothole',
        'Road Crack',
        'Garbage',
        'Water Logging',
        'Obstacle',
      ],
      firebaseSyncEnabled: true,
    );
  }

  SystemSettings copyWith({
    bool? isDarkMode,
    String? themeColorName,
    String? mapType,
    bool? offlineMapsEnabled,
    String? droneIp,
    int? pixhawkPort,
    String? telemetryFreq,
    String? cameraResolution,
    int? videoFps,
    double? aiConfidenceThreshold,
    List<String>? enabledAiClasses,
    bool? firebaseSyncEnabled,
  }) {
    return SystemSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      themeColorName: themeColorName ?? this.themeColorName,
      mapType: mapType ?? this.mapType,
      offlineMapsEnabled: offlineMapsEnabled ?? this.offlineMapsEnabled,
      droneIp: droneIp ?? this.droneIp,
      pixhawkPort: pixhawkPort ?? this.pixhawkPort,
      telemetryFreq: telemetryFreq ?? this.telemetryFreq,
      cameraResolution: cameraResolution ?? this.cameraResolution,
      videoFps: videoFps ?? this.videoFps,
      aiConfidenceThreshold:
          aiConfidenceThreshold ?? this.aiConfidenceThreshold,
      enabledAiClasses: enabledAiClasses ?? this.enabledAiClasses,
      firebaseSyncEnabled: firebaseSyncEnabled ?? this.firebaseSyncEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<SystemSettings> {
  SettingsNotifier() : super(SystemSettings.defaultSettings());

  void updateDarkMode(bool value) {
    state = state.copyWith(isDarkMode: value);
  }

  void updateThemeColor(String name) {
    state = state.copyWith(themeColorName: name);
  }

  void updateMapType(String type) {
    state = state.copyWith(mapType: type);
  }

  void toggleOfflineMaps(bool value) {
    state = state.copyWith(offlineMapsEnabled: value);
  }

  void updateDroneConnection(String ip, int port) {
    state = state.copyWith(droneIp: ip, pixhawkPort: port);
  }

  void updateTelemetryFrequency(String freq) {
    state = state.copyWith(telemetryFreq: freq);
  }

  void updateCameraSettings(String res, int fps) {
    state = state.copyWith(cameraResolution: res, videoFps: fps);
  }

  void updateAiConfidence(double threshold) {
    state = state.copyWith(aiConfidenceThreshold: threshold);
  }

  void toggleAiClass(String className) {
    final list = List<String>.from(state.enabledAiClasses);
    if (list.contains(className)) {
      list.remove(className);
    } else {
      list.add(className);
    }
    state = state.copyWith(enabledAiClasses: list);
  }

  void toggleFirebaseSync(bool value) {
    state = state.copyWith(firebaseSyncEnabled: value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SystemSettings>((ref) {
      return SettingsNotifier();
    });
