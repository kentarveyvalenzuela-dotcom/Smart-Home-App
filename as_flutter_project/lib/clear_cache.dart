import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

Future<void> clearAppData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  debugPrint('✅ Cleared all SharedPreferences');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await clearAppData();
  runApp(const MyApp());
}
