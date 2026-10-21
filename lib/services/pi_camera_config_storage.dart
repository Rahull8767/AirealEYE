import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aerial_eye/models/camera_connection_config.dart';

class PiCameraConfigStorage {
  static const String _storageKey = 'pi_camera_connection_config_v1';

  static Future<CameraConnectionConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return CameraConnectionConfig.fromJson(map);
      }
    } catch (_) {
      // Fall back to defaults on any reading/parsing issue
    }
    return CameraConnectionConfig.defaultConfig();
  }

  static Future<void> saveConfig(CameraConnectionConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(config.toJson());
      await prefs.setString(_storageKey, jsonStr);
    } catch (_) {
      // Ignore write errors or log
    }
  }

  static Future<CameraConnectionConfig> resetDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Ignore clearing error
    }
    return CameraConnectionConfig.defaultConfig();
  }
}
