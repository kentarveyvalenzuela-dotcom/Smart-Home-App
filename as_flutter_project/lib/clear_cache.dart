import 'package:flutter/material.dart';

import 'main.dart';
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  print('✅ Cleared all SharedPreferences');
}
  debugPrint('✅ Cleared all SharedPreferences');
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await clearAppData();
  runApp(const MyApp());
}
