// Web implementation: uses dart:html to perform a redirect
import 'dart:html' as html;

String? redirectTo(String url) {
  try {
    html.window.location.href = url;
    return url;
  } catch (e) {
    return null;
  }
}

