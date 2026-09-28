// Conditional export: use dart:html implementation on web, IO stub elsewhere
export 'web_redirect_io.dart' if (dart.library.html) 'web_redirect_web.dart';

