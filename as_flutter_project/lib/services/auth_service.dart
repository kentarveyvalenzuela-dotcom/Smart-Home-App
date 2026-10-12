import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

const _googleClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: '',
);

class AuthService {
  String get _baseUrl => ConfigService().backendUrl;

  String _normalizeNetworkError(Object error) {
    final message = error.toString();

    if (message.contains('ClientException') ||
        message.contains('Failed to fetch') ||
        message.contains('SocketException')) {
      return 'Backend server is unavailable or the API URL is incorrect. Please check the backend configuration or start the backend service.';
    }

    if (message.contains('timed out')) {
      return 'The backend request timed out. Please check the server and internet connection.';
    }

    return message;
  }

  String? _currentUserId;
  String? _currentUserEmail;
  String? _currentUserName;

  // Current user getters
  String? get currentUserId => _currentUserId;
  String? get currentUserEmail => _currentUserEmail;
  String? get currentUserName => _currentUserName;
  bool get isAuthenticated => _currentUserId != null;

  /// Helper to extract error message from various API response formats
  String _extractErrorMessage(dynamic data, String defaultMsg) {
    if (data == null) return defaultMsg;
    if (data is String) return data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final firstError = detail.first;
        if (firstError is Map && firstError['msg'] != null) {
          return firstError['msg'].toString();
        }
        return firstError.toString();
      }
      // Try message field
      if (data['message'] is String) return data['message'];
      if (data['error'] is String) return data['error'];
    }
    return defaultMsg;
  }

  // Email/Password Registration - Updated for new backend
  Future<Map<String, dynamic>?> signUpWithEmail(
      String email, String password, String name) async {
    try {
      final backend = ConfigService();
      if (!backend.hasValidBackendUrl) {
        return {
          'success': false,
          'error':
              'Backend URL is not configured. Please set a valid backend URL before signing up.'
        };
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': password,
              'name': name,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Registration request timed out'),
          );

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        data = {'detail': response.body};
      }

      if (response.statusCode == 200) {
        if (data['requires_email_verification'] == true) {
          return {
            'success': true,
            'requiresEmailVerification': true,
            'email': data['user']?['email'] ?? email,
            'message':
                data['message'] ?? 'Check your email for a verification code.',
          };
        }
        // Don't auto-login on registration, just return success message
        return {
          'success': true,
          'requiresEmailVerification':
              data['requires_email_verification'] == true,
          'message': data['message'] ??
              'Account created successfully! Please login with your credentials.',
          'user': data['user']
        };
      } else {
        return {
          'success': false,
          'error': _extractErrorMessage(data, 'Registration failed')
        };
      }
    } catch (e) {
      debugPrint('Sign up error: $e');
      return {'success': false, 'error': _normalizeNetworkError(e)};
    }
  }

  // Email/Password Sign In - Updated for new backend
  Future<Map<String, dynamic>?> signInWithEmail(
      String email, String password) async {
    try {
      final backend = ConfigService();
      if (!backend.hasValidBackendUrl) {
        return {
          'success': false,
          'error':
              'Backend URL is not configured. Please set a valid backend URL before signing in.'
        };
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Login request timed out'),
          );

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        data = {'detail': response.body};
      }

      if (response.statusCode == 200) {
        if (data['requires_email_verification'] == true) {
          return {
            'success': true,
            'requiresEmailVerification': true,
            'email': data['email'] ?? email,
          };
        }
        if (data['requires_2fa'] == true) {
          return {
            'success': true,
            'requires2FA': true,
            'email': data['email'] ?? data['user']?['email'],
            'user': data['user']
          };
        }
        // Store user info from new backend structure
        _currentUserId = data['user']?['id']?.toString();
        _currentUserEmail = data['user']?['email']?.toString();
        _currentUserName = data['user']?['name']?.toString();

        // Store access token
        await _storeToken(data['access_token']?.toString() ?? '');

        return {'success': true, 'user': data['user']};
      } else {
        return {
          'success': false,
          'error': _extractErrorMessage(data, 'Sign in failed')
        };
      }
    } catch (e) {
      debugPrint('Sign in error: $e');
      return {'success': false, 'error': _normalizeNetworkError(e)};
    }
  }

  Future<Map<String, dynamic>?> verifyEmailAddress(
      String email, String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/verify-email'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, ...Map<String, dynamic>.from(data)};
      }
      return {
        'success': false,
        'error': data['detail'] ?? 'Email verification failed'
      };
    } catch (e) {
      return {'success': false, 'error': _normalizeNetworkError(e)};
    }
  }

  // Password Reset Request
  Future<Map<String, dynamic>?> requestPasswordReset(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/password-reset'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Password reset request timed out'),
          );

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        data = {'detail': response.body};
      }

      if (response.statusCode == 200 || response.statusCode == 202) {
        debugPrint('✅ Password reset email sent to $email');
        return {
          'success': true,
          'message': 'Password reset link sent to your email'
        };
      } else {
        return {
          'success': false,
          'error': _extractErrorMessage(data, 'Failed to send reset email')
        };
      }
    } catch (e) {
      debugPrint('Password reset error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Verify Password Reset Token
  Future<Map<String, dynamic>?> verifyResetToken(String token) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/password-reset/verify'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'email': data['email']};
      } else {
        return {
          'success': false,
          'error': data['detail'] ?? 'Invalid or expired token'
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Reset Password with Token
  Future<Map<String, dynamic>?> resetPassword(
      String token, String newPassword) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/password-reset/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token, 'new_password': newPassword}),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Password reset successfully'};
      } else {
        return {
          'success': false,
          'error': data['detail'] ?? 'Failed to reset password'
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get current user profile
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final headers = await getAuthHeaders();

      final response = await http
          .get(
            Uri.parse('$_baseUrl/auth/user'),
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Get user request timed out'),
          );

      if (response.statusCode == 200) {
        final user = json.decode(response.body);
        _currentUserId = user['id']?.toString();
        _currentUserEmail = user['email']?.toString();
        _currentUserName = user['name']?.toString();

        return {'success': true, 'user': user};
      } else {
        await _clearToken();
        return {'success': false, 'error': 'Session expired'};
      }
    } catch (e) {
      debugPrint('Get current user error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Exchange a Google OAuth identity token for an application session.
  Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      if (_googleClientId.isEmpty) {
        return {
          'success': false,
          'error':
              'Google OAuth client ID is missing. Build with --dart-define=GOOGLE_CLIENT_ID=<Web client ID>.',
        };
      }
      final account = await GoogleSignIn(
        clientId: kIsWeb ? _googleClientId : null,
        serverClientId: _googleClientId,
        scopes: ['email', 'profile'],
      ).signIn();
      if (account == null) {
        return {'success': false, 'error': 'Google sign-in was cancelled'};
      }
      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        return {'success': false, 'error': 'Google did not return an ID token'};
      }
      final response = await http
          .post(Uri.parse('$_baseUrl/auth/google-signin'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'id_token': idToken}))
          .timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': _extractErrorMessage(data, 'Google sign-in failed')
        };
      }
      if (data['requires_2fa'] == true) {
        return {
          'success': true,
          'requires2FA': true,
          'email': data['user']?['email'] ?? account.email
        };
      }
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final token = data['access_token']?.toString() ?? '';
      if (token.isEmpty) {
        return {
          'success': false,
          'error': 'Backend did not issue an application token'
        };
      }
      await _storeToken(token);
      _currentUserId = user['id']?.toString();
      _currentUserEmail = user['email']?.toString() ?? account.email;
      _currentUserName = user['name']?.toString() ?? account.displayName;
      return {
        'success': true,
        'requires2FA': false,
        'user': user,
        'token': token
      };
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return {'success': false, 'error': _normalizeNetworkError(e)};
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      // Clear local user data
      _currentUserId = null;
      _currentUserEmail = null;
      _currentUserName = null;

      // Clear token
      await _clearToken();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/auth/me'),
          headers: await getAuthHeaders());
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      return data['user'] is Map
          ? Map<String, dynamic>.from(data['user'])
          : null;
    } catch (e) {
      debugPrint('Current user lookup failed: $e');
      return null;
    }
  }

  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAccessToken();

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ESP32 Device Registration - Updated for new backend
  Future<Map<String, dynamic>?> registerESP32Device(
      String deviceName, String macAddress,
      {String? ipAddress, String? locationName}) async {
    try {
      final headers = await getAuthHeaders();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/register'),
            headers: headers,
            body: json.encode({
              'device_name': deviceName,
              'esp32_mac': macAddress,
              'location': locationName,
              'device_type': 'esp32',
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Device registration request timed out'),
          );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'device_id': data['device_id']};
      } else {
        return {
          'success': false,
          'error': data['detail'] ?? 'Device registration failed'
        };
      }
    } catch (e) {
      debugPrint('ESP32 device registration error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🎯 NEW: Configure ESP32 device (sends device_id via MQTT)
  Future<Map<String, dynamic>?> configureESP32Device(String deviceId) async {
    try {
      final headers = await getAuthHeaders();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/$deviceId/configure'),
            headers: headers,
            body: json.encode({}),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
                'Device configuration request timed out'),
          );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
          'mqtt_client_id': data['mqtt_client_id'],
        };
      } else {
        return {
          'success': false,
          'error': data['detail'] ?? 'Device configuration failed'
        };
      }
    } catch (e) {
      debugPrint('ESP32 device configuration error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🎯 Register a new device with backend
  Future<Map<String, dynamic>?> ensureEnergyDeviceRegistered() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/register-energy'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'device': data['device']};
      }
      return {
        'success': false,
        'error': data['detail'] ?? 'Energy device registration failed',
      };
    } catch (e) {
      debugPrint('Energy device registration error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> registerDevice({
    required String deviceName,
    required String mqttClientId,
    String? location,
    String deviceType = 'esp32',
  }) async {
    try {
      final headers = await getAuthHeaders();

      debugPrint(
          '📤 Registering device: name=$deviceName, mqttClientId=$mqttClientId');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/register'),
            headers: headers,
            body: json.encode({
              'device_name': deviceName,
              'mqtt_client_id': mqttClientId,
              'location': location ?? '',
              'device_type': deviceType,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Device registration request timed out'),
          );

      debugPrint('📊 Register response status: ${response.statusCode}');
      debugPrint('📦 Register response body: ${response.body}');

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        data = {'detail': response.body};
      }

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Device registered',
          'device_id': data['device_id'],
          'device': data['device'],
        };
      } else {
        String errorMsg = data['detail']?.toString() ??
            data['message']?.toString() ??
            'Device registration failed (${response.statusCode})';
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      debugPrint('❌ Device registration error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🎯 Delete a device from backend
  Future<Map<String, dynamic>> deleteDevice({
    required String deviceId,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      debugPrint('🗑️ Deleting device from backend: $deviceId');

      final response = await http.delete(
        Uri.parse('$_baseUrl/devices/$deviceId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('📊 Delete response status: ${response.statusCode}');
      debugPrint('📦 Delete response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Device deleted',
        };
      } else if (response.statusCode == 404) {
        // Device not found - consider it deleted
        return {
          'success': true,
          'message': 'Device already deleted or not found',
        };
      } else {
        final data = json.decode(response.body);
        String errorMsg = data['detail']?.toString() ??
            data['message']?.toString() ??
            'Device deletion failed (${response.statusCode})';
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      debugPrint('❌ Device deletion error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🎯 NEW: Send device control command via backend API
  Future<Map<String, dynamic>?> sendDeviceControl({
    required String deviceId,
    required int pinNumber,
    required String action,
  }) async {
    try {
      final headers = await getAuthHeaders();

      debugPrint(
          '📤 Sending control to backend: device=$deviceId, pin=$pinNumber, action=$action');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/control'),
            headers: headers,
            body: json.encode({
              'device_id': deviceId,
              'pin_number': pinNumber,
              'action': action,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Device control request timed out'),
          );

      debugPrint('📊 Control response status: ${response.statusCode}');
      debugPrint('📦 Control response body: ${response.body}');

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        data = {'detail': response.body};
      }

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Command sent',
          'mqtt_published': data['mqtt_published'] ?? false,
        };
      } else {
        // Extract error message from various formats
        String errorMsg = 'Device control failed';
        if (data is Map) {
          errorMsg = data['detail']?.toString() ??
              data['message']?.toString() ??
              data['error']?.toString() ??
              'Device control failed (${response.statusCode})';
        }
        debugPrint('❌ Control error: $errorMsg');
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      debugPrint('❌ Device control exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Store sensor reading
  Future<Map<String, dynamic>?> storeSensorReading(
      String deviceId, String sensorType, int pinNumber, double value,
      {String unit = 'V', String quality = 'good'}) async {
    try {
      final headers = await getAuthHeaders();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/sensors/data'),
            headers: headers,
            body: json.encode({
              'device_id': deviceId,
              'sensor_type': sensorType,
              'value': value,
              'unit': unit,
              'quality': quality,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
                'Store sensor reading request timed out'),
          );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {
          'success': false,
          'error': data['detail'] ?? 'Failed to store sensor reading'
        };
      }
    } catch (e) {
      debugPrint('Store sensor reading error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get latest sensor readings
  Future<List<Map<String, dynamic>>> getLatestSensorReadings(
      {String? deviceId}) async {
    try {
      final headers = await getAuthHeaders();
      String url = deviceId == null
          ? '$_baseUrl/sensors/all?limit=100'
          : '$_baseUrl/sensors/device/$deviceId/latest';

      final response = await http
          .get(
            Uri.parse(url),
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Get sensor readings request timed out'),
          );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded
              .map((reading) => Map<String, dynamic>.from(reading as Map))
              .toList();
        }
        return decoded is Map ? [Map<String, dynamic>.from(decoded)] : [];
      } else {
        debugPrint('Failed to get sensor readings: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Get sensor readings error: $e');
      return [];
    }
  }

  // Auto-login on app start
  Future<bool> autoLogin() async {
    try {
      final token = await getAccessToken();
      if (token != null) {
        final result = await getCurrentUser();
        return result?['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Auto login error: $e');
      return false;
    }
  }

  // Verify OTP for email verification (legacy compatibility)
  Future<Map<String, dynamic>?> verifyOtp(String email, String otp) async {
    try {
      // For the new backend, OTP verification is not implemented yet
      // This is a placeholder for compatibility with existing UI
      debugPrint('OTP verification not implemented in new backend yet');
      return {'success': false, 'error': 'OTP verification not available'};
    } catch (e) {
      debugPrint('OTP verification error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Resend OTP (legacy compatibility)
  Future<Map<String, dynamic>?> resendOtp(String email) async {
    try {
      // For the new backend, OTP resend is not implemented yet
      // This is a placeholder for compatibility with existing UI
      debugPrint('OTP resend not implemented in new backend yet');
      return {'success': false, 'error': 'OTP resend not available'};
    } catch (e) {
      debugPrint('OTP resend error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ====================== LOGS API ======================

  /// Get all logs for the current user (with optional filters)
  Future<Map<String, dynamic>?> getLogs({
    int skip = 0,
    int limit = 100,
    String? logType,
    String? severity,
    int hours = 24,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final queryParams = {
        'limit': limit.toString(),
        'hours': hours.toString(),
        'skip': skip.toString(),
      };
      if (logType != null) queryParams['log_type'] = logType;
      if (severity != null) queryParams['severity'] = severity;

      final uri = Uri.parse('$_baseUrl/logs/list')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Transform to expected format
        return {
          'logs': data['logs'] ?? [],
          'total_count': data['total'] ?? data['count'] ?? 0,
        };
      }
      debugPrint('Get logs failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('Get logs error: $e');
      return null;
    }
  }

  /// Get device control logs (device_control type)
  Future<Map<String, dynamic>?> getDeviceControlLogs({
    int skip = 0,
    int limit = 20,
    String? deviceId,
    int hours = 24,
  }) async {
    // Use the general logs endpoint with log_type filter
    if (deviceId != null) {
      return getDeviceLogs(deviceId: deviceId, hours: hours, limit: limit);
    }
    return getLogs(
      skip: skip,
      limit: limit,
      logType: 'device_control',
      hours: hours,
    );
  }

  /// Get sensor readings logs (sensor_alert type)
  Future<Map<String, dynamic>?> getSensorReadings({
    int skip = 0,
    int limit = 20,
    String? deviceId,
    String? sensorType,
    int hours = 24,
  }) async {
    // Use the general logs endpoint with log_type filter
    return getLogs(
      skip: skip,
      limit: limit,
      logType: 'sensor_alert',
      hours: hours,
    );
  }

  /// Get logs for a specific device
  Future<Map<String, dynamic>?> getDeviceLogs({
    required String deviceId,
    int hours = 24,
    int limit = 100,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final uri = Uri.parse('$_baseUrl/logs/device/$deviceId').replace(
        queryParameters: {
          'hours': hours.toString(),
          'limit': limit.toString(),
        },
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final logs = data is List ? data : (data['logs'] ?? []);
        return {
          'logs': logs,
          'total_count': data is List
              ? data.length
              : (data['total'] ?? data['count'] ?? 0),
        };
      }
      return null;
    } catch (e) {
      debugPrint('Get device logs error: $e');
      return null;
    }
  }

  /// Create a new log entry
  Future<bool> createLog({
    required String logType,
    required String message,
    String? deviceId,
    Map<String, dynamic>? details,
    String severity = 'info',
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null) return false;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/logs/create'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'log_type': logType,
              'message': message,
              if (deviceId != null) 'device_id': deviceId,
              if (details != null) 'details': details,
              'severity': severity,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Create log error: $e');
      return false;
    }
  }

  // ====================== ALERTS API ======================
  Future<Map<String, dynamic>?> getAlertsSummary() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/alerts/summary'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Get alerts summary error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getAlertsList({
    int skip = 0,
    int limit = 20,
    String? deviceId,
    bool? resolved,
    int hours = 168,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final queryParams = {
        'offset': skip.toString(),
        'limit': limit.toString(),
        'hours': hours.toString(),
        if (deviceId != null) 'device_id': deviceId,
        if (resolved != null) 'resolved': resolved.toString(),
      };

      final response = await http.get(
        Uri.parse('$_baseUrl/alerts/list')
            .replace(queryParameters: queryParams),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Get alerts list error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> resolveAlert(String alertId) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/alerts/resolve/$alertId'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Resolve alert error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> clearAllAlerts() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/alerts/clear-all'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Clear all alerts error: $e');
      return null;
    }
  }

  // ====================== SETTINGS API ======================
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/settings/profile'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Get profile error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateUserProfile(
      String name, String email) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/settings/profile/update'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'name': name, 'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Update profile error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/settings/password/change'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'current_password': currentPassword,
              'new_password': newPassword,
              'confirm_password': confirmPassword,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Change password error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> getUserPreferences() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/settings/preferences'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Get preferences error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateUserPreferences(
      Map<String, dynamic> preferences) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/settings/preferences/update'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode(preferences),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Update preferences error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getSensorThresholds() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;
      final response = await http
          .get(Uri.parse('$_baseUrl/settings/sensor-thresholds'), headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('Get sensor thresholds error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateSensorThresholds({
    required double voltageMin,
    required double voltageMax,
    required double amperageMax,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;
      final response = await http
          .put(Uri.parse('$_baseUrl/settings/sensor-thresholds'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json'
              },
              body: json.encode({
                'voltage_min': voltageMin,
                'voltage_max': voltageMax,
                'amperage_max': amperageMax
              }))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('Update sensor thresholds error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> deleteAccount() async {
    try {
      // First, try to delete from backend
      final token = await getAccessToken();
      if (token != null) {
        try {
          final response = await http.delete(
            Uri.parse('$_baseUrl/settings/account'),
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            debugPrint('✅ Account deleted from backend');
          } else {
            debugPrint('⚠️ Backend delete failed: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('⚠️ Backend delete error: $e');
        }
      }

      // Clear local storage
      await logout();

      return {'success': true, 'message': 'Account deleted successfully'};
    } catch (e) {
      debugPrint('❌ Delete account error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ====================== 2FA API ======================
  Future<Map<String, dynamic>?> get2FAStatus() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/settings/2fa/status'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Get 2FA status error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> enable2FA(String email) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/settings/2fa/enable'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'error': error['detail'] ?? 'Failed to enable 2FA'
        };
      }
    } catch (e) {
      debugPrint('Enable 2FA error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> verify2FACode(String code) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/settings/2fa/verify'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'code': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        return {'success': false, 'error': error['detail'] ?? 'Invalid code'};
      }
    } catch (e) {
      debugPrint('Verify 2FA code error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> disable2FA(String password) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/settings/2fa/disable'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'error': error['detail'] ?? 'Failed to disable 2FA'
        };
      }
    } catch (e) {
      debugPrint('Disable 2FA error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Device Registration for 2FA OTP verification
  Future<Map<String, dynamic>?> registerDeviceFor2FA() async {
    try {
      final token = await getAccessToken();
      if (token == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/register'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'device_name':
                  'flutter_web_${DateTime.now().millisecondsSinceEpoch}',
              'location': 'Web Browser',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'error': error['detail'] ?? 'Failed to register device'
        };
      }
    } catch (e) {
      debugPrint('Device registration error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Verify OTP for device trust
  Future<Map<String, dynamic>?> verifyDeviceOTP(
      String deviceId, String otp) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'device_id': deviceId,
              'otp': otp,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        // Store tokens from OTP verification
        if (data['access_token'] != null) {
          await _storeToken(data['access_token']);
        }

        // Update user info if provided
        if (data['user'] != null) {
          _currentUserId = data['user']['id']?.toString();
          _currentUserEmail = data['user']['email']?.toString();
          _currentUserName = data['user']['name']?.toString();
        }

        return {'success': true, 'message': 'Device verified successfully'};
      } else {
        return {
          'success': false,
          'error': data['detail'] ?? 'OTP verification failed'
        };
      }
    } catch (e) {
      debugPrint('OTP verification error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> logout() async {
    await _clearToken();
    _currentUserId = null;
    _currentUserEmail = null;
    _currentUserName = null;
  }

  // Private methods
  Future<void> _storeToken(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
  }

  /// Public helper: store an access token (from OAuth callback) and attempt to load the user
  Future<bool> storeAccessToken(String accessToken) async {
    try {
      await _storeToken(accessToken);
      final result = await getCurrentUser();
      return result != null && result['success'] == true;
    } catch (e) {
      debugPrint('Error storing access token: $e');
      return false;
    }
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }
}
