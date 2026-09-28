import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_page.dart';
import 'screens/monitor_page.dart';
import 'screens/home_screen.dart';
import 'services/mqtt_service.dart';
import 'services/firebase_database_service.dart';
import 'services/config_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Electric IoT Theme Colors
class AppColors {
  // Primary Electric Blue
  static const Color primaryBlue = Color(0xFF00D4FF);
  static const Color primaryBlueDark = Color(0xFF0099CC);

  // Electric Accent Colors
  static const Color electricYellow = Color(0xFFFFE500);
  static const Color electricOrange = Color(0xFFFF8C00);
  static const Color electricGreen = Color(0xFF00FF88);
  static const Color electricPurple = Color(0xFF8B5CF6);

  // Background Gradients
  static const Color darkBg = Color(0xFF0A0E27);
  static const Color darkBgSecondary = Color(0xFF1A1F3A);
  static const Color darkBgCard = Color(0xFF1E2545);

  // Light Theme
  static const Color lightBg = Color(0xFFF0F4F8);
  static const Color lightBgCard = Color(0xFFFFFFFF);

  // Status Colors
  static const Color success = Color(0xFF00FF88);
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFFF4757);
  static const Color info = Color(0xFF00D4FF);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optimize system UI for smooth experience
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.darkBg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load runtime config (backend URL, etc.)
  await ConfigService().initialize();
  
  // Initialize connectivity monitoring
  await ConnectivityService().initialize();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Firebase initialization error: $e');
  }
  
  // Initialize Firebase Realtime Database
  debugPrint('🔥 Initializing Firebase Realtime Database...');
  await FirebaseDbService().initialize();
  
  // Initialize Notification Service
  debugPrint('📢 Initializing Notification Service...');
  await NotificationService().initialize();

  // Initialize MQTT in background (don't block app startup)
  debugPrint('🚀 Starting global MQTT service in background...');
  MqttService().initialize().catchError((e) {
    debugPrint('⚠️ MQTT initialization error (non-blocking): $e');
  });

  // If web and an OAuth token exists in the URL (callback), store it and auto-login
  String initialRoute = '/';
  if (kIsWeb) {
    try {
      final params = Uri.base.queryParameters;
      final token = params['token'];
      if (token != null && token.isNotEmpty) {
        debugPrint('🔑 OAuth token found in URL, storing token...');
        final ok = await AuthService().storeAccessToken(token);
        if (ok) {
          debugPrint('✅ Token stored and user loaded, routing to /home');
          initialRoute = '/home';
        } else {
          debugPrint('⚠️ Token store failed or user load failed');
        }
      }
    } catch (e) {
      debugPrint('Error checking URL token: $e');
    }
  }

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, this.initialRoute = '/'});

   @override
   Widget build(BuildContext context) {
     return ValueListenableBuilder<ThemeMode>(
       valueListenable: themeNotifier,
       builder: (_, ThemeMode currentMode, __) {
         return MaterialApp(
           debugShowCheckedModeBanner: false,
           title: 'Smart Home IoT',
           theme: ThemeData(
             useMaterial3: true,
             brightness: Brightness.light,
             colorScheme: ColorScheme.light(
               primary: AppColors.primaryBlueDark,
               secondary: AppColors.electricOrange,
               surface: AppColors.lightBgCard,
               onPrimary: Colors.white,
               onSecondary: Colors.white,
             ),
             scaffoldBackgroundColor: AppColors.lightBg,
             appBarTheme: AppBarTheme(
               elevation: 0,
               centerTitle: true,
               backgroundColor: AppColors.darkBg,
               foregroundColor: Colors.white,
               titleTextStyle: const TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.w600,
                 letterSpacing: 0.5,
               ),
             ),
             cardTheme: CardThemeData(
               elevation: 4,
               shadowColor: AppColors.primaryBlue.withOpacity(0.2),
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(16),
               ),
             ),
             bottomNavigationBarTheme: BottomNavigationBarThemeData(
               backgroundColor: AppColors.darkBg,
               selectedItemColor: AppColors.primaryBlue,
               unselectedItemColor: Colors.grey.shade500,
               type: BottomNavigationBarType.fixed,
               elevation: 8,
             ),
             floatingActionButtonTheme: FloatingActionButtonThemeData(
               backgroundColor: AppColors.primaryBlue,
               foregroundColor: Colors.white,
               elevation: 6,
             ),
             inputDecorationTheme: InputDecorationTheme(
               filled: true,
               fillColor: Colors.grey.shade100,
               border: OutlineInputBorder(
                 borderRadius: BorderRadius.circular(12),
                 borderSide: BorderSide.none,
               ),
               focusedBorder: OutlineInputBorder(
                 borderRadius: BorderRadius.circular(12),
                 borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
               ),
             ),
             elevatedButtonTheme: ElevatedButtonThemeData(
               style: ElevatedButton.styleFrom(
                 backgroundColor: AppColors.primaryBlue,
                 foregroundColor: Colors.white,
                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(12),
                 ),
                 elevation: 4,
               ),
             ),
           ),
           darkTheme: ThemeData(
             useMaterial3: true,
             brightness: Brightness.dark,
             colorScheme: ColorScheme.dark(
               primary: AppColors.primaryBlue,
               secondary: AppColors.electricOrange,
               surface: AppColors.darkBgCard,
               onPrimary: Colors.white,
               onSecondary: Colors.white,
             ),
             scaffoldBackgroundColor: AppColors.darkBg,
             appBarTheme: const AppBarTheme(
               elevation: 0,
               centerTitle: true,
               backgroundColor: AppColors.darkBgSecondary,
               foregroundColor: Colors.white,
               titleTextStyle: TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.w600,
                 letterSpacing: 0.5,
               ),
             ),
             cardTheme: CardThemeData(
               elevation: 4,
               color: AppColors.darkBgCard,
               shadowColor: AppColors.primaryBlue.withOpacity(0.3),
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(16),
               ),
             ),
             bottomNavigationBarTheme: const BottomNavigationBarThemeData(
               backgroundColor: AppColors.darkBgSecondary,
               selectedItemColor: AppColors.primaryBlue,
               unselectedItemColor: Colors.grey,
               type: BottomNavigationBarType.fixed,
               elevation: 8,
             ),
             floatingActionButtonTheme: const FloatingActionButtonThemeData(
               backgroundColor: AppColors.primaryBlue,
               foregroundColor: Colors.white,
               elevation: 6,
             ),
             inputDecorationTheme: InputDecorationTheme(
               filled: true,
               fillColor: AppColors.darkBgSecondary,
               border: OutlineInputBorder(
                 borderRadius: BorderRadius.circular(12),
                 borderSide: BorderSide.none,
               ),
               focusedBorder: OutlineInputBorder(
                 borderRadius: BorderRadius.circular(12),
                 borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
               ),
             ),
             elevatedButtonTheme: ElevatedButtonThemeData(
               style: ElevatedButton.styleFrom(
                 backgroundColor: AppColors.primaryBlue,
                 foregroundColor: Colors.white,
                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                 shape: RoundedRectangleBorder(
                   borderRadius: BorderRadius.circular(12),
                 ),
                 elevation: 4,
               ),
             ),
           ),
           themeMode: currentMode,
           initialRoute: initialRoute == '/home' ? '/home' : '/',
           routes: {
             '/': (context) => const AuthPage(),
             '/home': (context) => const HomeScreen(),
             '/monitor': (context) => const MonitorPage(),
           },
         );
       },
     );
   }
 }
