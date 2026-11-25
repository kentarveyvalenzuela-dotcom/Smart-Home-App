import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';
import '../auth/auth_repository.dart';

import 'auth_service.dart';
import '../storage/preferences_token_store.dart';
import '../storage/token_store.dart';

const _googleClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: '',
);

/// Google OAuth and optional second-factor requests use the app's PostgreSQL API.
class GoogleSignIn2FAService {
  static final GoogleSignIn2FAService _instance =
      GoogleSignIn2FAService._internal();
  factory GoogleSignIn2FAService() => _instance;
  GoogleSignIn2FAService._internal();

  final TokenStore _tokenStore = PreferencesTokenStore();
  final ApiService _apiService = ApiService();
  final AuthRepository _authRepository = AuthRepository();

  String get backendUrl => _apiService.baseUrl;
  GoogleSignIn get _googleSignIn => AuthService().googleSignIn;
  Stream<GoogleSignInAccount?> get googleSignInEvents =>
      _googleSignIn.onCurrentUserChanged;
  bool get isSignedIn => false;

  Future<Map<String, dynamic>?> signInWithGoogleAccount(
    GoogleSignInAccount account,
  ) async {
    final result = await _authRepository.exchangeGoogleAccount(account);
    if (result == null) return null;
    if (result['success'] == true) return result;
    return {
      ...result,
      'error': result['error'] ?? result['message'] ?? 'Google sign-in failed',
    };
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      if (_googleClientId.isEmpty && !kIsWeb) {
        return {
          'success': false,
          'message':
              'Google OAuth client ID is missing. Build with --dart-define=GOOGLE_CLIENT_ID=<Web client ID>.'
        };
      }
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return {'success': false, 'message': 'Sign-in canceled'};
      }
      final result = await signInWithGoogleAccount(account);
      if (result?['success'] != true) {
        return {
          'success': false,
          'message': result?['error'] ?? 'Google sign-in failed',
        };
      }
      return {
        ...result!,
        'email': result['email'] ?? account.email,
        'message': 'Sign-in successful',
      };
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verify2FACode(String email, String code) async {
    final result = await _authRepository.verifyGoogle2FA(email, code);
    return _compatibilityResult(result);
  }

  Future<Map<String, dynamic>> request2FACode(String email) async {
    final result = await _authRepository.requestGoogle2FA(email);
    return _compatibilityResult(result);
  }

  Map<String, dynamic> _compatibilityResult(Map<String, dynamic>? result) {
    if (result == null) {
      return {'success': false, 'message': 'Authentication request failed'};
    }
    return {
      ...result,
      if (result['error'] != null && result['message'] == null)
        'message': result['error'],
    };
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {bool storeToken = false}) async {
    try {
      final token = await _tokenStore.readAccessToken();
      final response = await _apiService
          .post(Uri.parse('$backendUrl$path'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (storeToken && data['access_token'] != null) {
          await _tokenStore.saveAccessToken(data['access_token'].toString());
        }
        return {'success': true, ...data};
      }
      return {'success': false, 'message': data['detail'] ?? 'Request failed'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> enable2FA() async =>
      (await _post('/settings/2fa/enable', {}))['success'] == true;
  Future<bool> disable2FA() async =>
      (await _post('/settings/2fa/disable', {}))['success'] == true;
  Future<void> signOut() async => _googleSignIn.signOut();

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final token = await _tokenStore.readAccessToken();
      if (token == null) return null;
      final response = await _apiService.get(Uri.parse('$backendUrl/auth/me'),
          headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['user'] is Map
          ? Map<String, dynamic>.from(body['user'])
          : null;
    } catch (e) {
      debugPrint('Profile lookup failed: $e');
      return null;
    }
  }
}
