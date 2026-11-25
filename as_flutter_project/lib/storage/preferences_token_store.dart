import 'package:shared_preferences/shared_preferences.dart';

import 'token_store.dart';

/// SharedPreferences-backed authentication token storage.
class PreferencesTokenStore implements TokenStore {
  static final PreferencesTokenStore _instance =
      PreferencesTokenStore._internal();

  factory PreferencesTokenStore() => _instance;

  PreferencesTokenStore._internal();

  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  @override
  Future<String?> readAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(accessTokenKey);
  }

  @override
  Future<String?> readRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(refreshTokenKey);
  }

  @override
  Future<void> saveAccessToken(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, accessToken);
  }

  @override
  Future<void> saveTokens(String accessToken, {String? refreshToken}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, accessToken);
    if (refreshToken != null) {
      await prefs.setString(refreshTokenKey, refreshToken);
    }
  }

  @override
  Future<void> clearAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
  }

  @override
  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
  }
}
