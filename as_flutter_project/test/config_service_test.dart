import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_app/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the local backend URL for local development', () async {
    await ConfigService().initialize();

    final backendUrl = ConfigService().backendUrl;

    expect(
      backendUrl,
      matches(RegExp(r'^http://(localhost|127\.0\.0\.1):8000$')),
    );
  });
}
