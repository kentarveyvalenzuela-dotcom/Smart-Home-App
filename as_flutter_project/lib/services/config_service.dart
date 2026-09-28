import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

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

  /// 🧠 INTELLIGENT Auto-detection: Web/App + Local/Heroku
  static String _getDefaultBackendUrl() {
    // Priority 1: Check for environment variable (production builds)
    const envUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) {
      debugPrint('✅ Using BACKEND_URL from environment: $envUrl');
      return envUrl;
    }

    // Priority 2: Detect if running on WEB or MOBILE/DESKTOP
    bool isWeb = kIsWeb;
    
    // Priority 3: Detect if localhost is available (local dev)
    // For now, default to localhost for all local development
    String backendUrl;
    
    if (isWeb) {
      // 🌐 WEB APP
      debugPrint('🌐 Detected: Flutter Web');
      // Always use Heroku production for web (matches mobile/desktop release mode)
      backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
      debugPrint('🔗 Web app using: $backendUrl');
    } else {
      // 📱 MOBILE/DESKTOP APP
      String platform = '';
      if (kDebugMode) {
        try {
          if (Platform.isAndroid) {
            platform = '(Android)';
            // Android emulator can't use localhost - use Heroku for reliability
            // If you want local dev, use 10.0.2.2 instead of localhost
            backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
          } else if (Platform.isIOS) {
            platform = '(iOS)';
            // iOS simulator can use localhost, but Heroku is more reliable
            backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
          } else if (Platform.isWindows) {
            platform = '(Windows)';
            backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
          } else if (Platform.isLinux) {
            platform = '(Linux)';
            backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
          } else {
            platform = '(Unknown)';
            backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
          }
        } catch (e) {
          platform = '(Fallback)';
          backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
        }
      } else {
        // Release mode - use Heroku production
        platform = '(Release)';
        backendUrl = 'https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com';
      }
      
      debugPrint('📱 Detected: Mobile/Desktop App $platform');
      debugPrint('🔗 Using: $backendUrl');
    }

    return backendUrl;
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
      _backendUrl = prefs.getString(_backendKey) ?? _backendUrl;
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
    _backendUrl = url.trim();
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
    await setBackendUrl('https://as-flutter-backend-prod-8ea99290c3d0.herokuapp.com');
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
Other APIs use localhost when in debug mode
═══════════════════════════════════════
    ''';
  }
}


