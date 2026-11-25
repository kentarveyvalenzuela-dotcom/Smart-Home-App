import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pushAppliances preserves the PUT endpoint and does not add auth', () async {
    late http.Request captured;
    final sync = SyncService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      }),
    );

    final result = await sync.pushAppliances([
      {'id': 'lamp-1', 'name': 'Lamp'},
    ]);

    expect(result, isTrue);
    expect(captured.method, 'PUT');
    expect(captured.url.toString(), 'http://test.local/api/appliances');
    expect(captured.headers.containsKey('authorization'), isFalse);
    expect(jsonDecode(captured.body), {
      'items': [
        {'id': 'lamp-1', 'name': 'Lamp'},
      ],
    });
    sync.dispose();
  });

  test('pullDevices preserves the explicit token and MQTT topic mapping', () async {
    late http.Request captured;
    final sync = SyncService(
      baseUrl: 'http://test.local',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              'id': 7,
              'mqtt_client_id': 'esp32-7',
              'device_name': 'Living Room Lamp',
              'pin': 23,
            },
          ]),
          200,
        );
      }),
    );

    final devices = await sync.pullDevices(authToken: 'session-token');

    expect(captured.method, 'GET');
    expect(captured.url.toString(), 'http://test.local/devices/list');
    expect(captured.headers['authorization'], 'Bearer session-token');
    expect(devices, hasLength(1));
    expect(devices!.single['backend_device_id'], '7');
    expect(devices.single['topic'], 'home/device/esp32-7');
    sync.dispose();
  });
}
