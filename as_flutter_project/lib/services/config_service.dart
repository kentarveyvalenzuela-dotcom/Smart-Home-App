import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Runtime configuration for API endpoints and app preferences.
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  static const _backendKey = 'backend_base_url';
  static const _voltageMinKey = 'threshold_voltage_min';
  static const _voltageMaxKey = 'threshold_voltage_max';
  static const _amperageMaxKey = 'threshold_amperage_max';
  static const _themeModeKey = 'theme_mode';

  double _voltageMin = 200;
  double _voltageMax = 240;
  double _amperageMax = 30;
  String _themeMode = 'light';
  String _backendUrl = _getDefaultBackendUrl();
  bool _initialized = false;

  static String _normalizeBackendUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return 'http://localhost:8000';
    var normalized = trimmed;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool get hasValidBackendUrl {
    final uri = Uri.tryParse(_backendUrl);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static String _getDefaultBackendUrl() {
    const envUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    final localUrl = defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';
    const productionUrl =
        'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
    return (kDebugMode || kIsWeb) ? localUrl : productionUrl;
  }

  String get backendUrl => _backendUrl;
  double get voltageMin => _voltageMin;
  double get voltageMax => _voltageMax;
  double get amperageMax => _amperageMax;
  String get themeMode => _themeMode;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedBackendUrl = prefs.getString(_backendKey);
      // Migrate the old localhost default so Android emulators reach the host.
      final savedUrlIsOldLocalDefault =
          savedBackendUrl == 'http://localhost:8000' ||
              savedBackendUrl == 'http://127.0.0.1:8000';
      _backendUrl = _normalizeBackendUrl(
        savedBackendUrl == null ||
                (defaultTargetPlatform == TargetPlatform.android &&
                    savedUrlIsOldLocalDefault)
            ? _getDefaultBackendUrl()
            : savedBackendUrl,
      );
      if (savedUrlIsOldLocalDefault &&
          defaultTargetPlatform == TargetPlatform.android) {
        await prefs.setString(_backendKey, _backendUrl);
      }
      _voltageMin = prefs.getDouble(_voltageMinKey) ?? _voltageMin;
      _voltageMax = prefs.getDouble(_voltageMaxKey) ?? _voltageMax;
      _amperageMax = prefs.getDouble(_amperageMaxKey) ?? _amperageMax;
      _themeMode = prefs.getString(_themeModeKey) ?? _themeMode;
      _initialized = true;
      debugPrint('ConfigService initialized. Backend: $_backendUrl');
    } catch (e) {
      debugPrint('ConfigService init failed, using defaults: $e');
    }
  }

  Future<void> setBackendUrl(String url) async {
    _backendUrl = _normalizeBackendUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, _backendUrl);
  }

  Future<void> setVoltageMin(double value) async {
    _voltageMin = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_voltageMinKey, value);
  }

  Future<void> setVoltageMax(double value) async {
    _voltageMax = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_voltageMaxKey, value);
  }

  Future<void> setAmperageMax(double value) async {
    _amperageMax = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_amperageMaxKey, value);
  }

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode);
  }

  Future<void> useLocalBackend() => setBackendUrl(
        defaultTargetPlatform == TargetPlatform.android
            ? 'http://10.0.2.2:8000'
            : 'http://localhost:8000',
      );

  Future<void> useHerokuBackend() => setBackendUrl(
        'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com',
      );

  /// Verify Google sign-in tokens through the app's configured backend.
  String getGoogleOAuthUrl() => backendUrl;

  String getConfigInfo() {
    final platform = kIsWeb ? 'Web' : 'Mobile/Desktop';
    final mode = kDebugMode ? 'Debug' : 'Release';
    return '''
CONFIGURATION INFO
Platform: $platform
Mode: $mode
API Backend URL: $_backendUrl
Google OAuth URL: ${getGoogleOAuthUrl()}
Voltage Min: $_voltageMin V
Voltage Max: $_voltageMax V
Amperage Max: $_amperageMax A
Theme: $_themeMode
Google sign-in token verification uses the configured API backend.
''';
  }
}
