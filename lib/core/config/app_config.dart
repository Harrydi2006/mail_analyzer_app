import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _baseUrlOverrideKey = 'api_base_url_override';
  static String? _baseUrlOverride;

  // TODO: release build时改为正式域名
  static String get baseUrl {
    if (_baseUrlOverride != null && _baseUrlOverride!.isNotEmpty) {
      return _baseUrlOverride!;
    }
    return defaultBaseUrl;
  }

  static String get defaultBaseUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      return 'http://$host:5000';
    }
    // Android emulator 访问宿主机应使用 10.0.2.2
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://127.0.0.1:5000';
  }

  static Future<void> loadBaseUrlOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_baseUrlOverrideKey);
    _baseUrlOverride = (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  static Future<void> setBaseUrlOverride(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = (value == null || value.trim().isEmpty) ? null : value.trim();
    _baseUrlOverride = normalized;
    if (normalized == null) {
      await prefs.remove(_baseUrlOverrideKey);
    } else {
      await prefs.setString(_baseUrlOverrideKey, normalized);
    }
  }

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
