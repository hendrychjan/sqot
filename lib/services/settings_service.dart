import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqot/models/settings.dart';
import 'package:sqot/models/influx_settings.dart';
import 'package:sqot/models/theme_settings.dart';

class SettingsService extends GetxService {
  SettingsService._();
  factory SettingsService() => instance;
  static final SettingsService instance = SettingsService._();

  static const String _keyThemeMode = "theme_mode";
  static const String _keyInfluxUrl = "influx_url";
  static const String _keyInfluxOrg = "influx_org";
  static const String _keyInfluxBucket = "influx_bucket";
  static const String _keyInfluxToken = "influx_token";

  ThemeSettings _themeSettings = ThemeSettings(mode: ThemeMode.system);
  InfluxSettings _influxSettings = InfluxSettings(
    url: '',
    org: '',
    bucket: '',
    token: '',
  );

  late SharedPreferences _prefs;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Loads settigs from persistant storage
  Future<void> loadSettings() async {
    // Load settings should only be called once, during app initialization
    assert(!_initialized);

    _prefs = await SharedPreferences.getInstance();

    final savedThemeMode = _prefs.getString(_keyThemeMode);
    final loadedThemeMode = _themeModeFromString(savedThemeMode);
    _themeSettings = ThemeSettings(mode: loadedThemeMode);
    Get.changeThemeMode(loadedThemeMode);

    _influxSettings = InfluxSettings(
      url: _prefs.getString(_keyInfluxUrl) ?? '',
      org: _prefs.getString(_keyInfluxOrg) ?? '',
      bucket: _prefs.getString(_keyInfluxBucket) ?? '',
      token: _prefs.getString(_keyInfluxToken) ?? '',
    );

    _initialized = true;
  }

  Settings getCurrentSettings() {
    return Settings(
      themeSettings: ThemeSettings(mode: _themeSettings.mode),
      influxSettings: InfluxSettings(
        url: _influxSettings.url,
        org: _influxSettings.org,
        bucket: _influxSettings.bucket,
        token: _influxSettings.token,
      ),
    );
  }

  bool get isInfluxSettingsComplete {
    return _influxSettings.url.trim().isNotEmpty &&
        _influxSettings.org.trim().isNotEmpty &&
        _influxSettings.bucket.trim().isNotEmpty &&
        _influxSettings.token.trim().isNotEmpty;
  }

  String get influxSettingsStatusLabel {
    return isInfluxSettingsComplete
        ? 'Influx settings complete'
        : 'Influx settings incomplete';
  }

  Future<void> updateSetting({
    ThemeMode? themeMode,
    String? influxUrl,
    String? influxOrg,
    String? influxBucket,
    String? influxToken,
  }) async {
    assert(_initialized);

    if (themeMode != null && _themeSettings.mode != themeMode) {
      _themeSettings.mode = themeMode;
      await _prefs.setString(_keyThemeMode, _themeModeToString(themeMode));
      Get.changeThemeMode(themeMode);
    }
    if (influxUrl != null && _influxSettings.url != influxUrl) {
      _influxSettings.url = influxUrl;
      await _prefs.setString(_keyInfluxUrl, influxUrl);
    }
    if (influxOrg != null && _influxSettings.org != influxOrg) {
      _influxSettings.org = influxOrg;
      await _prefs.setString(_keyInfluxOrg, influxOrg);
    }
    if (influxBucket != null && _influxSettings.bucket != influxBucket) {
      _influxSettings.bucket = influxBucket;
      await _prefs.setString(_keyInfluxBucket, influxBucket);
    }
    if (influxToken != null && _influxSettings.token != influxToken) {
      _influxSettings.token = influxToken;
      await _prefs.setString(_keyInfluxToken, influxToken);
    }
  }

  ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
