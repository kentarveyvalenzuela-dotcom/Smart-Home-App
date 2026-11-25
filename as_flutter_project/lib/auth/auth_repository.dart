import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/api_service.dart';
import '../services/config_service.dart';
import '../storage/preferences_token_store.dart';
import '../storage/token_store.dart';

/// Authentication endpoint boundary used by AuthService during migration.
/// Existing endpoint paths and response maps are intentionally preserved.
class AuthRepository {
  AuthRepository({ApiService? apiService, TokenStore? tokenStore})
      : _apiService = apiService ?? ApiService(),
        _tokenStore = tokenStore ?? PreferencesTokenStore();

  final ApiService _apiService;
  final TokenStore _tokenStore;

  String get _baseUrl => _apiService.baseUrl;

  Future<Map<String, dynamic>?> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    try {
      final backend = ConfigService();
      if (!backend.hasValidBackendUrl) {
        return {
          'success': false,
          'error':
              'Backend URL is not configured. Please set a valid backend URL before signing up.'
        };
      }

      final response = await _apiService
          .post(
            Uri.parse('$_baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
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
      final data = _decode(response.body);

      if (response.statusCode != 200) {
        return {'success': false, 'error': _error(data, 'Registration failed')};
      }
      if (data['requires_email_verification'] == true) {
        return {
          'success': true,
          'requiresEmailVerification': true,
          'email': data['user']?['email'] ?? email,
          'message':
              data['message'] ?? 'Check your email for a verification code.',
        };
      }
      return {
        'success': true,
        'requiresEmailVerification':
            data['requires_email_verification'] == true,
        'message': data['message'] ??
            'Account created successfully! Please login with your credentials.',
        'user': data['user'],
      };
    } catch (e) {
      debugPrint('Sign up error: $e');
      return {'success': false, 'error': _networkError(e)};
    }
  }

  Future<Map<String, dynamic>?> signInWithEmail(
    String email,
    String password,
  ) async {
    try {
      final backend = ConfigService();
      if (!backend.hasValidBackendUrl) {
        return {
          'success': false,
          'error':
              'Backend URL is not configured. Please set a valid backend URL before signing in.'
        };
      }

      final response = await _apiService
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Login request timed out'),
          );
      final data = _decode(response.body);

      if (response.statusCode != 200) {
        return {'success': false, 'error': _error(data, 'Sign in failed')};
      }
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
          'user': data['user'],
        };
      }

      await _storeToken(data['access_token']?.toString() ?? '');
      return {'success': true, 'user': data['user']};
    } catch (e) {
      debugPrint('Sign in error: $e');
      return {'success': false, 'error': _networkError(e)};
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final token = await _tokenStore.readAccessToken();
      if (token == null || token.isEmpty) {
        return {'success': false, 'error': 'Session expired'};
      }
      final response = await _apiService.get(
        Uri.parse('$_baseUrl/auth/user'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Get user request timed out'),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'user': _decode(response.body)};
      }
      await _tokenStore.clearAccessToken();
      return {'success': false, 'error': 'Session expired'};
    } catch (e) {
      debugPrint('Get current user error: $e');
      return {'success': false, 'error': _networkError(e)};
    }
  }

  /// Compatibility profile lookup that preserves the existing /auth/me
  /// endpoint used by legacy screens during migration.
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final token = await _tokenStore.readAccessToken();
      if (token == null || token.isEmpty) return null;
      final response = await _apiService.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = _decode(response.body);
      return data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : null;
    } catch (e) {
      debugPrint('Current user profile lookup failed: $e');
      return null;
    }
  }

  /// Stores an OAuth callback token and validates the resulting app session.
  Future<bool> storeAccessToken(String accessToken) async {
    try {
      if (accessToken.isEmpty) return false;
      await _storeToken(accessToken);
      final result = await getCurrentUser();
      return result?['success'] == true;
    } catch (e) {
      debugPrint('Error storing access token: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> verifyEmailAddress(
    String email,
    String code,
  ) async {
    return _postAuthForm(
      '/auth/verify-email',
      {'email': email, 'code': code},
      success: (data) => {'success': true, ...data},
      failure: 'Email verification failed',
    );
  }

  Future<Map<String, dynamic>?> requestPasswordReset(String email) async {
    final result = await _postAuthForm(
      '/auth/password-reset',
      {'email': email},
      acceptedStatusCodes: {200, 202},
      success: (_) => {
        'success': true,
        'message': 'Password reset link sent to your email',
      },
      failure: 'Failed to send reset email',
    );
    return result;
  }

  Future<Map<String, dynamic>?> verifyResetToken(String token) async {
    return _postAuthForm(
      '/auth/password-reset/verify',
      {'token': token},
      success: (data) => {'success': true, 'email': data['email']},
      failure: 'Invalid or expired token',
    );
  }

  Future<Map<String, dynamic>?> resetPassword(
    String token,
    String newPassword,
  ) async {
    return _postAuthForm(
      '/auth/password-reset/confirm',
      {'token': token, 'new_password': newPassword},
      success: (_) =>
          {'success': true, 'message': 'Password reset successfully'},
      failure: 'Failed to reset password',
    );
  }

  Future<Map<String, dynamic>?> exchangeGoogleAccount(
    GoogleSignInAccount account,
  ) async {
    try {
      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        return {'success': false, 'error': 'Google did not return an ID token'};
      }
      final response = await _apiService
          .post(
            Uri.parse('$_baseUrl/auth/google-signin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));
      final data = _decode(response.body);
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': _error(data, 'Google sign-in failed')
        };
      }
      if (data['requires_2fa'] == true) {
        return {
          'success': true,
          'requires2FA': true,
          'email': data['user']?['email'] ?? account.email,
        };
      }
      final token = data['access_token']?.toString() ?? '';
      if (token.isEmpty) {
        return {
          'success': false,
          'error': 'Backend did not issue an application token'
        };
      }
      await _storeToken(token);
      return {
        'success': true,
        'requires2FA': false,
        'user': data['user'],
        'token': token,
      };
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return {'success': false, 'error': _networkError(e)};
    }
  }

  Future<Map<String, dynamic>?> requestGoogle2FA(String email) {
    return _postAuthForm(
      '/auth/request-2fa',
      {'email': email, 'method': 'email'},
      success: (data) => {'success': true, ...data},
      failure: 'Failed to request 2FA code',
    );
  }

  Future<Map<String, dynamic>?> verifyGoogle2FA(
    String email,
    String code,
  ) async {
    try {
      final response = await _apiService
          .post(
            Uri.parse('$_baseUrl/auth/verify-2fa'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 12));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {'success': false, 'error': _error(data, 'Invalid 2FA code')};
      }
      await _storeToken(data['access_token']?.toString() ?? '');
      return {'success': true, ...data};
    } catch (error) {
      return {'success': false, 'error': _networkError(error)};
    }
  }

  Future<void> logout() => _tokenStore.clearAccessToken();

  Future<void> _storeToken(String token) async {
    if (token.isNotEmpty) await _tokenStore.saveAccessToken(token);
  }

  Future<Map<String, dynamic>?> _postAuthForm(
    String path,
    Map<String, dynamic> body, {
    Set<int> acceptedStatusCodes = const {200},
    required Map<String, dynamic> Function(Map<String, dynamic>) success,
    required String failure,
  }) async {
    try {
      final response = await _apiService
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      final data = _decode(response.body);
      if (acceptedStatusCodes.contains(response.statusCode)) {
        return success(data);
      }
      return {'success': false, 'error': _error(data, failure)};
    } catch (e) {
      return {'success': false, 'error': _networkError(e)};
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {'data': decoded};
    } catch (_) {
      return {'detail': body};
    }
  }

  String _error(dynamic data, String fallback) {
    if (data is Map) {
      if (data['detail'] is String) return data['detail'] as String;
      if (data['message'] is String) return data['message'] as String;
      if (data['error'] is String) return data['error'] as String;
    }
    return fallback;
  }

  String _networkError(Object error) {
    final message = error.toString();
    if (message.contains('ClientException') ||
        message.contains('Failed to fetch') ||
        message.contains('SocketException')) {
      return 'Backend server is unavailable or the API URL is incorrect. Please check the backend configuration or start the backend service.';
    }
    return message;
  }
}
