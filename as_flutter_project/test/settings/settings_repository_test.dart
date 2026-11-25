import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/services/api_service.dart';
import 'package:smart_home_app/settings/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings repository preserves profile endpoint and auth header',
      () async {
    SharedPreferences.setMockInitialValues({'access_token': 'settings-token'});
    final repository = SettingsRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/settings/profile');
          expect(request.headers['authorization'], 'Bearer settings-token');
          return http.Response(
            jsonEncode({'name': 'User', 'email': 'user@example.com'}),
            200,
          );
        }),
      ),
    );

    expect(await repository.getUserProfile(), {
      'name': 'User',
      'email': 'user@example.com',
    });
  });

  test('settings repository preserves threshold PUT payload', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'settings-token'});
    final repository = SettingsRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/settings/sensor-thresholds');
          expect(jsonDecode(request.body), {
            'voltage_min': 210.0,
            'voltage_max': 240.0,
            'amperage_max': 15.0,
          });
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      ),
    );

    expect(
      await repository.updateSensorThresholds(
        voltageMin: 210,
        voltageMax: 240,
        amperageMax: 15,
      ),
      {'success': true},
    );
  });

  test('settings repository reads configured sensor thresholds', () async {
    SharedPreferences.setMockInitialValues({'access_token': 'settings-token'});
    final repository = SettingsRepository(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/settings/sensor-thresholds');
          expect(request.headers['authorization'], 'Bearer settings-token');
          return http.Response(
            jsonEncode({
              'voltage_min': 210.0,
              'voltage_max': 240.0,
              'amperage_max': 15.0,
              'configured': true,
            }),
            200,
          );
        }),
      ),
    );

    expect(await repository.getSensorThresholds(), {
      'voltage_min': 210.0,
      'voltage_max': 240.0,
      'amperage_max': 15.0,
      'configured': true,
    });
  });
}
