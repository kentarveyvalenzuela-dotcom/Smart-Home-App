import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the local backend URL for local development', () async {
    SharedPreferences.setMockInitialValues({});
    await ConfigService().initialize();

    final backendUrl = ConfigService().backendUrl;

    expect(
      backendUrl,
      matches(RegExp(r'^http://(localhost|127\.0\.0\.1|10\.0\.2\.2):8000$')),
    );
  });
}
