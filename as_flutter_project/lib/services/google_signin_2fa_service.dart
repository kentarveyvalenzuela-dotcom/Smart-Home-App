import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config_service.dart';

const _googleClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: '541021035552-46c0utctt41vjagp4a8u7jdasu2csmk3.apps.googleusercontent.com',
);

/// Google OAuth and optional second-factor requests use the app's PostgreSQL API.
class GoogleSignIn2FAService {
  static final GoogleSignIn2FAService _instance = GoogleSignIn2FAService._internal();
  factory GoogleSignIn2FAService() => _instance;
  GoogleSignIn2FAService._internal();

  String get backendUrl => ConfigService().backendUrl;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _googleClientId : null,
    serverClientId: _googleClientId,
    scopes: ['email', 'profile'],
  );
  bool get isSignedIn => false;

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return {'success': false, 'message': 'Sign-in canceled'};
      final idToken = (await account.authentication).idToken;
      if (idToken == null) return {'success': false, 'message': 'Google did not return an ID token'};
      final response = await http.post(Uri.parse('$backendUrl/auth/google-signin'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'id_token': idToken})).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) return {'success': false, 'message': data['detail'] ?? 'Google sign-in failed'};
      if (data['requires_2fa'] == true) return {'success': true, 'requires2FA': true, 'email': account.email};
      final token = data['access_token']?.toString() ?? '';
      if (token.isEmpty) return {'success': false, 'message': 'Backend did not issue an application token'};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      return {'success': true, 'requires2FA': false, 'user': data['user'], 'email': account.email, 'message': 'Sign-in successful'};
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verify2FACode(String email, String code) async => _post('/auth/verify-2fa', {'email': email, 'code': code}, storeToken: true);
  Future<Map<String, dynamic>> request2FACode(String email) async => _post('/auth/request-2fa', {'email': email, 'method': 'email'});

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {bool storeToken = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final response = await http.post(Uri.parse('$backendUrl$path'), headers: {
        'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token',
      }, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (storeToken && data['access_token'] != null) await prefs.setString('access_token', data['access_token'].toString());
        return {'success': true, ...data};
      }
      return {'success': false, 'message': data['detail'] ?? 'Request failed'};
    } catch (e) { return {'success': false, 'message': e.toString()}; }
  }

  Future<bool> enable2FA() async => (await _post('/settings/2fa/enable', {}))['success'] == true;
  Future<bool> disable2FA() async => (await _post('/settings/2fa/disable', {}))['success'] == true;
  Future<void> signOut() async => _googleSignIn.signOut();

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null) return null;
      final response = await http.get(Uri.parse('$backendUrl/auth/me'), headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['user'] is Map ? Map<String, dynamic>.from(body['user']) : null;
    } catch (e) { debugPrint('Profile lookup failed: $e'); return null; }
  }
}
