import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('sends the endpoint, auth header, and query parameters', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'value': 42}), 200);
    });
    final service = ApiService(client: client, baseUrl: 'http://test.local');
    await service.setTokens('test-token');

    final result = await service.getRequest<int>(
      '/energy/history',
      queryParams: {'limit': '1'},
      parser: (data) => (data as Map)['value'] as int,
    );

    expect(result.success, isTrue);
    expect(result.data, 42);
    expect(captured.method, 'GET');
    expect(captured.url.toString(), 'http://test.local/energy/history?limit=1');
    expect(captured.headers['authorization'], 'Bearer test-token');
  });

  test('encodes JSON request bodies without changing the endpoint contract',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{}', 201);
    });
    final service = ApiService(client: client, baseUrl: 'http://test.local');

    final result = await service.postRequest<dynamic>(
      '/energy/readings',
      body: {'voltage': 220.0, 'energy': 1.25},
      parser: (data) => data,
    );

    expect(result.success, isTrue);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/energy/readings');
    expect(captured.headers['content-type'], contains('application/json'));
    expect(jsonDecode(captured.body), {
      'voltage': 220.0,
      'energy': 1.25,
    });
  });

  test('returns the existing authentication error for unauthorized responses',
      () async {
    final service = ApiService(
      client:
          MockClient((_) async => http.Response('{"detail":"expired"}', 401)),
      baseUrl: 'http://test.local',
    );

    final result = await service.getRequest<dynamic>(
      '/auth/me',
      parser: (data) => data,
    );

    expect(result.success, isFalse);
    expect(result.statusCode, 401);
    expect(result.error, 'Authentication failed. Please login again.');
  });
}
