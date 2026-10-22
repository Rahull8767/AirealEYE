import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aerial_eye/models/pi_shutdown_config.dart';

class PiShutdownStorage {
  static const String _storageKey = 'pi_shutdown_config_v1';

  static Future<PiShutdownConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return PiShutdownConfig.fromJson(map);
      }
    } catch (_) {}
    return PiShutdownConfig.defaultConfig();
  }

  static Future<void> saveConfig(PiShutdownConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(config.toJson());
      await prefs.setString(_storageKey, jsonStr);
    } catch (_) {}
  }

  static Future<PiShutdownConfig> resetDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
    return PiShutdownConfig.defaultConfig();
  }
}
