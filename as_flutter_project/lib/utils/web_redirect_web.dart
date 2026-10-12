// Web implementation: uses the web platform API to perform a redirect.
import 'package:web/web.dart' as web;

String? redirectTo(String url) {
  web.window.location.href = url;
  return url;
}
