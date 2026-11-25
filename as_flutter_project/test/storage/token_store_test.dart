import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/services/api_service.dart';
import 'package:smart_home_app/services/auth_service.dart';
import 'package:smart_home_app/storage/preferences_token_store.dart';

class _TestApiService extends ApiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesTokenStore tokenStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tokenStore = PreferencesTokenStore();
  });

  test('saves and reads an access token using the existing key', () async {
    await tokenStore.saveAccessToken('access-value');

    expect(await tokenStore.readAccessToken(), 'access-value');
    expect(
      (await SharedPreferences.getInstance()).getString('access_token'),
      'access-value',
    );
  });

  test('overwrites an existing access token', () async {
    await tokenStore.saveAccessToken('old-value');
    await tokenStore.saveAccessToken('new-value');

    expect(await tokenStore.readAccessToken(), 'new-value');
  });

  test('saves and clears access and refresh tokens', () async {
    await tokenStore.saveTokens('access-value', refreshToken: 'refresh-value');

    expect(await tokenStore.readAccessToken(), 'access-value');
    expect(await tokenStore.readRefreshToken(), 'refresh-value');

    await tokenStore.clearTokens();

    expect(await tokenStore.readAccessToken(), isNull);
    expect(await tokenStore.readRefreshToken(), isNull);
  });

  test('clearing the access token preserves the refresh token', () async {
    await tokenStore.saveTokens('access-value', refreshToken: 'refresh-value');

    await tokenStore.clearAccessToken();

    expect(await tokenStore.readAccessToken(), isNull);
    expect(await tokenStore.readRefreshToken(), 'refresh-value');
  });

  test('missing tokens return null', () async {
    expect(await tokenStore.readAccessToken(), isNull);
    expect(await tokenStore.readRefreshToken(), isNull);
  });

  test('AuthService and ApiService share the same TokenStore instance', () {
    final authService = AuthService();
    final apiService = _TestApiService();

    expect(authService.tokenStore, same(apiService.tokenStore));
    expect(apiService.tokenStore, same(PreferencesTokenStore()));
  });

  test('ApiService writes tokens that AuthService can read', () async {
    final apiService = _TestApiService();
    final authService = AuthService();

    await apiService.setTokens('shared-access', refreshToken: 'shared-refresh');

    expect(await authService.getAccessToken(), 'shared-access');
    expect(await authService.tokenStore.readRefreshToken(), 'shared-refresh');
  });

  test('AuthService logout removes the shared access token', () async {
    final apiService = _TestApiService();
    final authService = AuthService();

    await apiService.setTokens('logout-access');
    await authService.logout();

    expect(await apiService.tokenStore.readAccessToken(), isNull);
  });
}
