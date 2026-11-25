import 'dart:async';
import 'dart:convert';

import '../services/api_service.dart';
import '../storage/preferences_token_store.dart';
import '../storage/token_store.dart';

/// Owns account settings endpoints while preserving the existing response
/// maps and endpoint contracts used by the settings screen.
class SettingsRepository {
  SettingsRepository({ApiService? apiService, TokenStore? tokenStore})
      : _apiService = apiService ?? ApiService(),
        _tokenStore = tokenStore ?? PreferencesTokenStore();

  final ApiService _apiService;
  final TokenStore _tokenStore;

  String get _baseUrl => _apiService.baseUrl;

  Future<Map<String, dynamic>?> getUserProfile() => _request('GET', '/settings/profile');

  Future<Map<String, dynamic>?> updateUserProfile(String name, String email) =>
      _request('POST', '/settings/profile/update', {'name': name, 'email': email});

  Future<Map<String, dynamic>?> changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) => _request('POST', '/settings/password/change', {
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      }, true);

  Future<Map<String, dynamic>?> getUserPreferences() =>
      _request('GET', '/settings/preferences');

  Future<Map<String, dynamic>?> updateUserPreferences(
    Map<String, dynamic> preferences,
  ) => _request('POST', '/settings/preferences/update', preferences);

  Future<Map<String, dynamic>?> getSensorThresholds() =>
      _request('GET', '/settings/sensor-thresholds');

  Future<Map<String, dynamic>?> updateSensorThresholds({
    required double voltageMin,
    required double voltageMax,
    required double amperageMax,
  }) => _request('PUT', '/settings/sensor-thresholds', {
        'voltage_min': voltageMin,
        'voltage_max': voltageMax,
        'amperage_max': amperageMax,
      });

  Future<Map<String, dynamic>?> get2FAStatus() => _request('GET', '/settings/2fa/status');

  Future<Map<String, dynamic>?> enable2FA(String email) =>
      _request('POST', '/settings/2fa/enable', {'email': email});

  Future<Map<String, dynamic>?> verify2FACode(String code) =>
      _request('POST', '/settings/2fa/verify', {'code': code});

  Future<Map<String, dynamic>?> disable2FA(String password) =>
      _request('POST', '/settings/2fa/disable', {'password': password});

  Future<Map<String, dynamic>?> deleteAccount() async {
    try {
      final token = await _tokenStore.readAccessToken();
      if (token != null && token.isNotEmpty) {
        await _apiService
            .delete(
              Uri.parse('$_baseUrl/settings/account'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 10));
      }
      await _tokenStore.clearAccessToken();
      return {'success': true, 'message': 'Account deleted successfully'};
    } catch (error) {
      return {'success': false, 'error': error.toString()};
    }
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
    bool preserveErrorResponse = false,
  ]) async {
    try {
      final token = await _tokenStore.readAccessToken();
      if (token == null || token.isEmpty) return null;
      final headers = {
        'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      final uri = Uri.parse('$_baseUrl$path');
      final response = switch (method) {
        'GET' => await _apiService.get(uri, headers: headers),
        'POST' => await _apiService.post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          ),
        'PUT' => await _apiService.put(
            uri,
            headers: headers,
            body: jsonEncode(body),
          ),
        _ => throw ArgumentError('Unsupported settings method: $method'),
      };
      final decoded = _decode(response.body);
      if (response.statusCode == 200 || preserveErrorResponse) return decoded;
      return null;
    } catch (error) {
      return {'success': false, 'error': error.toString()};
    }
  }

  Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {'data': decoded};
  }
}
