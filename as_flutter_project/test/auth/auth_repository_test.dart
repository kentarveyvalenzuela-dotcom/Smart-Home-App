import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/auth/auth_repository.dart';
import 'package:smart_home_app/services/api_service.dart';
import 'package:smart_home_app/storage/preferences_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('login preserves the response shape and stores the access token',
      () async {
    final repository = AuthRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/login');
          expect(jsonDecode(request.body), {
            'email': 'user@example.com',
            'password': 'secret',
          });
          return http.Response(
            jsonEncode({
              'access_token': 'repository-token',
              'user': {'id': 7, 'email': 'user@example.com', 'name': 'User'},
            }),
            200,
          );
        }),
      ),
    );

    final result =
        await repository.signInWithEmail('user@example.com', 'secret');

    expect(result, {
      'success': true,
      'user': {'id': 7, 'email': 'user@example.com', 'name': 'User'},
    });
    expect(
      await PreferencesTokenStore().readAccessToken(),
      'repository-token',
    );
  });

  test('current-user lookup uses the shared stored token', () async {
    final api = ApiService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/auth/user');
        expect(request.headers['authorization'], 'Bearer stored-token');
        return http.Response(
          jsonEncode({'id': 7, 'email': 'user@example.com', 'name': 'User'}),
          200,
        );
      }),
    );
    await api.setTokens('stored-token');
    final repository = AuthRepository(apiService: api);

    final result = await repository.getCurrentUser();

    expect(result?['success'], isTrue);
    expect(result?['user']['id'], 7);
  });

  test('legacy profile lookup preserves the /auth/me endpoint', () async {
    await PreferencesTokenStore().saveAccessToken('profile-token');
    final repository = AuthRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/auth/me');
          expect(request.headers['authorization'], 'Bearer profile-token');
          return http.Response(
            jsonEncode({
              'user': {'id': 9, 'email': 'profile@example.com'},
            }),
            200,
          );
        }),
      ),
    );

    expect(await repository.getCurrentUserProfile(), {
      'id': 9,
      'email': 'profile@example.com',
    });
  });

  test('OAuth callback token is stored and validated by AuthRepository',
      () async {
    final repository = AuthRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/auth/user');
          expect(
              request.headers['authorization'], 'Bearer oauth-callback-token');
          return http.Response(
            jsonEncode({'id': 7, 'email': 'oauth@example.com'}),
            200,
          );
        }),
      ),
    );

    expect(await repository.storeAccessToken('oauth-callback-token'), isTrue);
    expect(
      await PreferencesTokenStore().readAccessToken(),
      'oauth-callback-token',
    );
  });

  test('Google 2FA request preserves endpoint and payload', () async {
    final repository = AuthRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/request-2fa');
          expect(jsonDecode(request.body), {
            'email': 'user@example.com',
            'method': 'email',
          });
          return http.Response(jsonEncode({'message': 'Code sent'}), 200);
        }),
      ),
    );

    expect(await repository.requestGoogle2FA('user@example.com'), {
      'success': true,
      'message': 'Code sent',
    });
  });

  test('Google 2FA verification stores the returned application token',
      () async {
    final repository = AuthRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/verify-2fa');
          expect(jsonDecode(request.body), {
            'email': 'user@example.com',
            'code': '123456',
          });
          return http.Response(
            jsonEncode({
              'access_token': '2fa-token',
              'user': {'id': 7}
            }),
            200,
          );
        }),
      ),
    );

    final result = await repository.verifyGoogle2FA(
      'user@example.com',
      '123456',
    );

    expect(result?['success'], isTrue);
    expect(await PreferencesTokenStore().readAccessToken(), '2fa-token');
  });
}
