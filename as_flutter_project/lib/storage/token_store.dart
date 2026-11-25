/// Shared persistence boundary for application authentication tokens.
abstract class TokenStore {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> saveAccessToken(String accessToken);

  Future<void> saveTokens(String accessToken, {String? refreshToken});

  Future<void> clearAccessToken();

  Future<void> clearTokens();
}
