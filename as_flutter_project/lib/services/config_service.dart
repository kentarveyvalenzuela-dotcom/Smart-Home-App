import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Simple runtime configuration for endpoints and toggles.
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  static const _backendKey = 'backend_base_url';
  static const _voltageMinKey = 'threshold_voltage_min';
  static const _voltageMaxKey = 'threshold_voltage_max';
  static const _amperageMaxKey = 'threshold_amperage_max';
  static const _themeModeKey = 'theme_mode';

  // Defaults
  double _voltageMin = 200;
  double _voltageMax = 240;
  double _amperageMax = 30;
  String _themeMode = 'light';
  String _backendUrl = _getDefaultBackendUrl();
  bool _initialized = false;

  static String _normalizeBackendUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return 'http://localhost:8000';
    }

    String normalized = trimmed;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  bool get hasValidBackendUrl {
    final uri = Uri.tryParse(_backendUrl);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Local development defaults to the FastAPI server running on port 8000.
  /// Heroku remains available as an override for production deployments.
  static String _getDefaultBackendUrl() {
    const envUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) {
      debugPrint('✅ Using BACKEND_URL from environment: $envUrl');
      return envUrl;
    }

    const localUrl = 'http://localhost:8000';
    const productionUrl =
        'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';

    if (kDebugMode || kIsWeb) {
      debugPrint('🧪 Using local backend for development: $localUrl');
      return localUrl;
    }

    debugPrint('🚀 Using production backend: $productionUrl');
    return productionUrl;
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
      _backendUrl =
          _normalizeBackendUrl(prefs.getString(_backendKey) ?? _backendUrl);
      _voltageMin = prefs.getDouble(_voltageMinKey) ?? _voltageMin;
      _voltageMax = prefs.getDouble(_voltageMaxKey) ?? _voltageMax;
      _amperageMax = prefs.getDouble(_amperageMaxKey) ?? _amperageMax;
      _themeMode = prefs.getString(_themeModeKey) ?? _themeMode;
      _initialized = true;
      debugPrint('✅ ConfigService initialized. Backend: $_backendUrl');
    } catch (e) {
      debugPrint('⚠️ ConfigService init failed, using defaults. Error: $e');
    }
  }

  Future<void> setBackendUrl(String url) async {
    _backendUrl = _normalizeBackendUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, _backendUrl);
    debugPrint('🔧 Backend URL updated to: $_backendUrl');
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

  /// 🔧 Helper: Switch to Localhost
  Future<void> useLocalBackend() async {
    await setBackendUrl('http://localhost:8000');
  }

  /// 🔧 Helper: Switch to Heroku Production
  Future<void> useHerokuBackend() async {
    await setBackendUrl(
        'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com');
  }

  /// 🔐 IMPORTANT: Google OAuth ALWAYS uses Heroku (requires HTTPS!)
  /// Localhost doesn't work because Google OAuth requires HTTPS + production domain
  String getGoogleOAuthUrl() {
    // Google OAuth MUST use HTTPS + production domain
    // Localhost won't work even if it's the default backend
    return 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
  }

  /// 📊 Helper: Get Current Configuration Info
  String getConfigInfo() {
    String platform = kIsWeb ? 'Web' : 'Mobile/Desktop';
    String mode = kDebugMode ? 'Debug' : 'Release';
    return '''
═══════════════════════════════════════
📊 CONFIGURATION INFO
═══════════════════════════════════════
Platform: $platform
Mode: $mode
API Backend URL: $_backendUrl
Google OAuth URL: ${getGoogleOAuthUrl()}
Voltage Min: $_voltageMin V
Voltage Max: $_voltageMax V
Amperage Max: $_amperageMax A
Theme: $_themeMode
═══════════════════════════════════════
Note: Google OAuth always uses Heroku (HTTPS required)
API backend defaults to localhost:8000 for local development
═══════════════════════════════════════
    ''';
  }
}
