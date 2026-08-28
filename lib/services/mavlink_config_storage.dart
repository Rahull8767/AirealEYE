import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aerial_eye/models/mavlink_connection_config.dart';

class MavlinkConfigStorage {
  static const String _storageKey = 'mavlink_connection_config_v1';

  static Future<MavlinkConnectionConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return MavlinkConnectionConfig.fromJson(map);
      }
    } catch (e) {
      // Fall back to defaults on any reading/parsing issue
    }
    return MavlinkConnectionConfig.defaultConfig();
  }

  static Future<void> saveConfig(MavlinkConnectionConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(config.toJson());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      // Error saving
    }
  }

  static Future<MavlinkConnectionConfig> resetDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      // Error clearing
    }
    return MavlinkConnectionConfig.defaultConfig();
  }
}
