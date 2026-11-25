import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/services/alert_service.dart';
import 'package:smart_home_app/services/api_service.dart';
import 'package:smart_home_app/services/device_service.dart';
import 'package:smart_home_app/services/log_service.dart';
import 'package:smart_home_app/services/notification_service.dart';
import 'package:smart_home_app/services/sensor_service.dart';
import 'package:smart_home_app/storage/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('DeviceService uses the shared API transport and parses devices',
      () async {
    late http.Request request;
    final service = DeviceService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode([
            {
              'id': 2,
              'name': 'Lamp',
              'type': 'light',
              'status': 'off',
              'is_online': true,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]),
          200,
        );
      }),
    );

    final result = await service.listDevices();

    expect(result.success, isTrue);
    expect(request.method, 'GET');
    expect(request.url.path, '/devices/list');
    expect(result.data!.single.name, 'Lamp');
  });

  test('screen device registration sends backend fields and returns both IDs',
      () async {
    late http.Request request;
    final service = DeviceService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'id': 12,
            'name': 'Sala',
            'mqtt_client_id': 'sala',
            'pin': 23,
            'topic': 'home/device/sala',
          }),
          200,
        );
      }),
    );

    final result = await service.registerScreenDevice(
      deviceName: 'Sala',
      mqttClientId: 'sala',
      pinNumber: 23,
    );

    expect(request.method, 'POST');
    expect(request.url.path, '/devices/register');
    expect(jsonDecode(request.body), {
      'name': 'Sala',
      'type': 'esp32',
      'pin': 23,
      'topic': 'home/device/sala',
      'mqtt_client_id': 'sala',
      'location': '',
    });
    expect(result['success'], isTrue);
    expect(result['device_id'], '12');
    expect(result['backend_device_id'], '12');
    expect(result['mqtt_client_id'], 'sala');
  });

  test('DeviceService preserves energy device registration response shape',
      () async {
    late http.Request request;
    final service = DeviceService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'success': true,
            'device': {'id': 9, 'name': 'Energy Monitor'},
            'device_id': '9',
          }),
          200,
        );
      }),
    );

    final result = await service.ensureEnergyDeviceRegistered();

    expect(result, {
      'success': true,
      'device': {'id': 9, 'name': 'Energy Monitor'},
    });
    expect(request.method, 'POST');
    expect(request.url.path, '/devices/register-energy');
  });

  test('AlertService preserves alert list query parameters', () async {
    late http.Request request;
    final service = AlertService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'alerts': []}), 200);
      }),
    );

    final result = await service.listAlerts(
      limit: 10,
      offset: 3,
      severity: 'high',
      onlyUnread: true,
    );

    expect(result.success, isTrue);
    expect(request.url.path, '/alerts/list');
    expect(request.url.queryParameters, {
      'limit': '10',
      'offset': '3',
      'severity': 'high',
      'unread_only': 'true',
    });
  });

  test('AlertService resolves an alert by marking it read then dismissing it',
      () async {
    final requests = <http.Request>[];
    final service = AlertService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'id': 'alert-1',
            'title': 'High voltage',
            'message': 'Voltage exceeded the configured threshold',
            'severity': 'high',
            'source': 'sensor',
            'is_read': true,
            'is_dismissed': true,
            'created_at': '2026-01-01T00:00:00Z',
          }),
          200,
        );
      }),
    );

    final result = await service.resolveAlert('alert-1');

    expect(result.success, isTrue);
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'PATCH /alerts/alert-1/read',
      'PATCH /alerts/alert-1/dismiss',
    ]);
    expect(result.data!.isDismissed, isTrue);
  });

  test('LogService preserves the user log endpoint and filters', () async {
    late http.Request request;
    final service = LogService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response('[]', 200);
      }),
    );

    final result = await service.getUserLogs(
      limit: 20,
      offset: 4,
      action: 'login',
      resourceType: 'user',
    );

    expect(result.success, isTrue);
    expect(request.url.path, '/logs/user');
    expect(request.url.queryParameters['action'], 'login');
    expect(request.url.queryParameters['resource_type'], 'user');
  });

  test('LogService exports JSON without changing the export contract',
      () async {
    late http.Request request;
    final service = LogService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode([
            {'action': 'device_control', 'details': 'Lamp turned on'},
          ]),
          200,
        );
      }),
    );

    final result = await service.exportLogs(format: 'json');

    expect(result.success, isTrue);
    expect(request.method, 'GET');
    expect(request.url.path, '/logs/export');
    expect(request.url.queryParameters, {'format': 'json'});
    expect(jsonDecode(result.data!), [
      {'action': 'device_control', 'details': 'Lamp turned on'},
    ]);
  });

  test('SensorService preserves device sensor endpoint and limit', () async {
    late http.Request request;
    final service = SensorService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'id': '4',
            'device_id': 'device-1',
            'sensor_type': 'temperature',
            'value': 25.5,
            'unit': 'C',
            'timestamp': '2026-01-01T00:00:00Z',
          }),
          200,
        );
      }),
    );

    final result = await service.getLatestReading('device-1');

    expect(result.success, isTrue);
    expect(request.url.path, '/sensors/device/device-1/latest');
    expect(result.data!.value, 25.5);
  });

  test('SensorService preserves sensor reading creation payload', () async {
    late http.Request request;
    final service = SensorService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'id': 'reading-1',
            'device_id': 'device-1',
            'sensor_type': 'voltage',
            'value': 230.5,
            'unit': 'V',
            'timestamp': '2026-01-01T00:00:00Z',
          }),
          201,
        );
      }),
    );

    final result = await service.createReading(
      deviceId: 'device-1',
      sensorType: 'voltage',
      value: 230.5,
      unit: 'V',
    );

    expect(result.success, isTrue);
    expect(request.method, 'POST');
    expect(request.url.path, '/sensors/create');
    expect(jsonDecode(request.body), {
      'device_id': 'device-1',
      'sensor_type': 'voltage',
      'value': 230.5,
      'unit': 'V',
    });
    expect(result.data!.sensorType, 'voltage');
  });

  test('SensorService parses statistics and preserves threshold query filters',
      () async {
    late http.Request request;
    final service = SensorService.forTesting(
      baseUrl: 'http://test.local',
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'min': 220,
            'max': 240,
            'average': 230,
            'reading_count': 12,
            'start_time': '2026-01-01T00:00:00Z',
            'end_time': '2026-01-01T01:00:00Z',
          }),
          200,
        );
      }),
    );

    final result = await service.getSensorStatistics(
      'device-1',
      sensorType: 'voltage',
      daysBack: 3,
    );

    expect(result.success, isTrue);
    expect(request.url.path, '/sensors/statistics/device-1');
    expect(request.url.queryParameters, {
      'sensor_type': 'voltage',
      'days_back': '3',
    });
    expect(result.data!.readingCount, 12);
    expect(result.data!.average, 230);
  });

  test('NotificationService persists, marks read, and clears notifications',
      () async {
    SharedPreferences.setMockInitialValues(
        {'access_token': 'notification-token'});
    final requests = <http.Request>[];
    final service = NotificationService.forTesting(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST' &&
              request.url.path == '/notifications') {
            return http.Response(
              jsonEncode({
                'id': 42,
                'type': 'emailSignIn',
                'title': 'Email Sign-In',
                'message':
                    'Successfully signed in with email: user@example.com',
                'created_at': '2026-01-01T00:00:00Z',
                'is_read': false,
                'metadata': {'email': 'user@example.com'},
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      ),
    );

    try {
      await service.addEmailSignInNotification('user@example.com');
      expect(service.notifications.single.id, '42');
      expect(service.unreadCount, 1);

      await service.markAsRead('42');
      expect(service.unreadCount, 0);

      await service.clearAll();
      expect(service.notifications, isEmpty);

      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'POST /notifications',
          'PATCH /notifications/42/read',
          'DELETE /notifications',
        ],
      );
      expect(
        (await SharedPreferences.getInstance())
            .getStringList('activity_notifications_anonymous'),
        isEmpty,
      );
    } finally {
      service.dispose();
    }
  });

  test('NotificationService scopes local cache by the shared token subject',
      () async {
    final service = NotificationService.forTesting(
      apiService: ApiService(
        baseUrl: 'http://test.local',
        client: MockClient((_) async => http.Response('[]', 200)),
      ),
      tokenStore: _MemoryTokenStore(accessToken: _jwtWithSubject('user-42')),
    );

    try {
      await service.addEmailSignInNotification('user@example.com');

      expect(
        (await SharedPreferences.getInstance())
            .getStringList('activity_notifications_user-42'),
        isNotEmpty,
      );
      expect(
        (await SharedPreferences.getInstance())
            .getStringList('activity_notifications_anonymous'),
        isNull,
      );
    } finally {
      service.dispose();
    }
  });
}

String _jwtWithSubject(String subject) {
  String encode(Map<String, String> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode({
        'sub': subject
      })}.signature';
}

class _MemoryTokenStore implements TokenStore {
  _MemoryTokenStore({this.accessToken});

  String? accessToken;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveAccessToken(String value) async => accessToken = value;

  @override
  Future<void> saveTokens(String value, {String? refreshToken}) async {
    accessToken = value;
  }

  @override
  Future<void> clearAccessToken() async => accessToken = null;

  @override
  Future<void> clearTokens() async => accessToken = null;
}
