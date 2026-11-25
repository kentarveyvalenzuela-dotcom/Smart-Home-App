# Graph Report - as_flutter_project  (2026-11-24)

## Corpus Check
- 106 files · ~64,510 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 57 file(s) not represented in the graph (top: (none) 8, .xcconfig 8, .xml 7)
- WARNING: 57 of 201 files seen (28%) have no supported extractor and are missing from this graph entirely. It may look complete while representing only part of the codebase.

## Summary
- 1717 nodes · 2521 edges · 90 communities (63 shown, 27 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 42 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- auth_service.dart
- smooth_ui.dart
- notification_service.dart
- Any
- home_screen.dart
- main.py
- device_page.dart
- settings_page.dart
- mqtt_service.dart
- energy_monitor_service.dart
- GeneratedPluginRegistrant.swift
- config_service.dart
- 📱 BRIX SMART HOME IoT - COMPREHENSIVE STATUS REPORT
- simulate_device.py
- notification_page.dart
- dependencies
- main.dart
- alert_service.dart
- BRIX Smart Home IoT System
- log_service.dart
- 📊 SMART HOME IoT PROJECT - COMPLETE STATUS REPORT
- my_application.cc
- auth_page.dart
- post
- logs_page.dart
- sensor_service.dart
- device_service.dart
- forgot_password_page.dart
- State
- api_service.dart
- google_signin_2fa_service.dart
- connectivity_service.dart
- monitor_page.dart
- google_signin_2fa_page.dart
- sync_service.dart
- win32_window.cpp
- BRIX - Smart Home IoT System
- FlutterWindow
- backend_sync_service.dart
- Any
- StatelessWidget
- package:shared_preferences/shared_preferences.dart
- utils.cpp
- package:flutter/material.dart
- preferences_token_store.dart
- Win32Window
- _execute_device_command
- manifest.json
- .MessageHandler
- auth_repository.dart
- token_store.dart
- web_redirect_web.dart
- analysis_options.yaml
- windows/flutter/generated_plugin_registrant.cc
- ApiService
- MaterialPageRoute
- google_signin_button_web.dart
- Point
- settings_repository.dart
- as_flutter_project/MainActivity.kt
- astralminds/MainActivity.kt
- test_device_registration.py
- LaunchImage.imageset/README.md
- post
- auth_controller.dart
- domain_service_contract_test.dart
- dart:convert
- package:flutter/foundation.dart
- os
- generate_keystore.py
- migrate_sqlite_to_postgres.py
- token_store_test.dart
- _LogsPageState
- google_signin_button_stub.dart
- _SmoothButtonState
- _SmoothFadeInState

## God Nodes (most connected - your core abstractions)
1. `_create_db_connection()` - 69 edges
2. `UserOut` - 62 edges
3. `Win32Window` - 21 edges
4. `dependencies` - 18 edges
5. `📱 BRIX SMART HOME IoT - COMPREHENSIVE STATUS REPORT` - 15 edges
6. `ApiService` - 14 edges
7. `login()` - 13 edges
8. `_evaluate_sensor_thresholds()` - 12 edges
9. `📊 SMART HOME IoT PROJECT - COMPLETE STATUS REPORT` - 12 edges
10. `create_alert()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `_TestApiService` --inherits--> `ApiService`  [EXTRACTED]
  test/storage/token_store_test.dart → lib/services/api_service.dart
- `_MemoryTokenStore` --implements--> `TokenStore`  [EXTRACTED]
  test/services/domain_service_contract_test.dart → lib/storage/token_store.dart
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `FlutterWindow` --inherits--> `Win32Window`  [EXTRACTED]
  windows/runner/flutter_window.h → windows/runner/win32_window.h
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc

## Import Cycles
- None detected.

## Communities (90 total, 27 thin omitted)

### Community 0 - "auth_service.dart"
Cohesion: 0.03
Nodes (69): _apiService, _authRepository, AuthService, autoLogin, _baseUrl, changePassword, clearAllAlerts, _clearToken (+61 more)

### Community 1 - "smooth_ui.dart"
Cohesion: 0.03
Nodes (45): actionLabel, activeColor, borderRadius, build, child, children, color, _controller (+37 more)

### Community 2 - "notification_service.dart"
Cohesion: 0.04
Nodes (49): ActivityNotification, addDeviceAddNotification, addDeviceDeleteNotification, addDeviceToggleNotification, addEmailSignInNotification, addGoogleSignInNotification, addLogoutNotification, _addNotification (+41 more)

### Community 3 - "Any"
Cohesion: 0.13
Nodes (38): clear_old_alerts(), clear_old_logs(), _create_db_connection(), create_sensor_reading(), delete_account(), delete_all_notifications(), delete_device(), delete_notification() (+30 more)

### Community 4 - "home_screen.dart"
Cohesion: 0.04
Nodes (44): _activeDevices, _alertCount, _billSub, build, _buildAppBar, _buildBillingSummaryCard, _buildBottomNavBar, _buildCurrentCard (+36 more)

### Community 5 - "main.py"
Cohesion: 0.07
Nodes (19): create_log(), _create_token(), _decode_base64(), _encode_base64(), get_current_user(), _get_user_by_id(), google_signin(), GoogleSignInRequest (+11 more)

### Community 6 - "device_page.dart"
Cohesion: 0.04
Nodes (46): _addAppliance, appliances, _authRepository, _backendStatus, build, _buildConnectionStatusCard, _buildEmptyState, _buildErrorCard (+38 more)

### Community 7 - "settings_page.dart"
Cohesion: 0.04
Nodes (43): _backendUrl, build, _buildInfoTile, _buildLoadingState, _buildSectionTitle, _buildSettingsCard, _buildSettingsTile, _buildSwitchTile (+35 more)

### Community 8 - "mqtt_service.dart"
Cohesion: 0.04
Nodes (35): _brokerOptions, _client, connect, _connectionCompleter, _connectionState, _connectionStateController, currentConnectionState, currentError (+27 more)

### Community 9 - "energy_monitor_service.dart"
Cohesion: 0.05
Nodes (36): _apiService, _billCalculationTimer, billStream, _billStreamController, _calculateBill, current, _currentBill, currentPerChannel (+28 more)

### Community 10 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.06
Nodes (19): Cocoa, connectivity_plus, firebase_core, firebase_messaging, Flutter, FlutterMacOS, Foundation, google_sign_in_ios (+11 more)

### Community 11 - "config_service.dart"
Cohesion: 0.05
Nodes (33): _amperageMax, _amperageMaxKey, _backendKey, _backendUrl, ConfigService, getConfigInfo, _getDefaultBackendUrl, getGoogleOAuthUrl (+25 more)

### Community 12 - "📱 BRIX SMART HOME IoT - COMPREHENSIVE STATUS REPORT"
Cohesion: 0.05
Nodes (36): API Endpoints, 🔐 AUTHENTICATION FEATURES, ⚡ BACKEND (FastAPI/Python), Backend Files (backend/app/), Backend (Heroku), Billing Calculation, 📱 BRIX SMART HOME IoT - COMPREHENSIVE STATUS REPORT, Broker Configuration (+28 more)

### Community 13 - "simulate_device.py"
Cohesion: 0.26
Nodes (4): _energy_payload(), main(), _post_json(), _sensor_payload()

### Community 14 - "notification_page.dart"
Cohesion: 0.05
Nodes (34): _activityNotifications, _alertError, _alerts, _alertService, _animController, build, _buildActivityItem, _buildActivityTab (+26 more)

### Community 15 - "dependencies"
Cohesion: 0.06
Nodes (34): dependencies, cached_network_image, connectivity_plus, cupertino_icons, firebase_core, firebase_messaging, fl_chart, flutter (+26 more)

### Community 16 - "main.dart"
Cohesion: 0.06
Nodes (22): AppColors, build, darkBg, darkBgCard, darkBgSecondary, electricGreen, electricOrange, electricPurple (+14 more)

### Community 17 - "alert_service.dart"
Cohesion: 0.05
Nodes (36): acknowledgedAt, Alert, AlertSeverity, AlertStats, clearOldAlerts, clearScreenAlerts, createAlert, createdAt (+28 more)

### Community 18 - "BRIX Smart Home IoT System"
Cohesion: 0.06
Nodes (33): Abstract, Appendices to Prepare, Background of the Study, BRIX Smart Home IoT System, Capstone Paper Draft, Chapter 1. The Problem and Its Background, Chapter 2. Review of Related Concepts and System Design, Chapter 3. Methodology (+25 more)

### Community 19 - "log_service.dart"
Cohesion: 0.06
Nodes (30): action, ActivityLog, clearOldLogs, command, createdAt, createLog, details, DeviceControlLog (+22 more)

### Community 20 - "📊 SMART HOME IoT PROJECT - COMPLETE STATUS REPORT"
Cohesion: 0.06
Nodes (30): 📋 10. CONFIGURATION REQUIRED, 🔧 1. BACKEND (Python FastAPI + Heroku), 📱 2. FLUTTER FRONTEND, 📡 4. MQTT CONFIGURATION, 🔌 5. ESP32 FIRMWARE, 📦 6. DEPENDENCIES, 🐛 7. ERRORS FIXED, ⚠️ 8. WARNINGS (Non-blocking) (+22 more)

### Community 21 - "my_application.cc"
Cohesion: 0.09
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 22 - "auth_page.dart"
Cohesion: 0.07
Nodes (20): _authController, _buildTextField, _confirmPassController, createState, dispose, _emailController, _formKey, _googleAccountSubscription (+12 more)

### Community 23 - "post"
Cohesion: 0.12
Nodes (25): AuthTokenResponse, begin_enable_two_factor(), change_password(), ChangePasswordRequest, confirm_password_reset(), DeviceSensorItem, DeviceUpdateRequest, EmailRequest (+17 more)

### Community 24 - "logs_page.dart"
Cohesion: 0.07
Nodes (25): _animController, build, _buildEmptyState, _buildErrorBanner, _buildFilterBar, _buildLoadingState, _buildLogsList, _buildModernFilterChip (+17 more)

### Community 25 - "sensor_service.dart"
Cohesion: 0.07
Nodes (25): average, createReading, deviceId, endTime, fromJson, getAllReadings, getDashboardSummary, getDeviceReadings (+17 more)

### Community 26 - "device_service.dart"
Cohesion: 0.06
Nodes (30): controlDevice, createdAt, deleteDevice, deleteScreenDevice, Device, DeviceControlResponse, ensureEnergyDeviceRegistered, fromJson (+22 more)

### Community 27 - "forgot_password_page.dart"
Cohesion: 0.09
Nodes (19): _authController, build, _buildFormView, _buildNewPasswordView, _buildSuccessView, _confirmPasswordController, createState, dispose (+11 more)

### Community 28 - "State"
Cohesion: 0.19
Nodes (12): AuthPage, _AuthPageState, DevicePage, _DevicePageState, ForgotPasswordPage, _ForgotPasswordPageState, HomeScreen, _HomeScreenState (+4 more)

### Community 29 - "api_service.dart"
Cohesion: 0.07
Nodes (25): _accessToken, ApiResponse, baseUrl, _buildHeaders, clearTokens, _client, close, data (+17 more)

### Community 30 - "google_signin_2fa_service.dart"
Cohesion: 0.08
Nodes (20): _apiService, _authRepository, backendUrl, _compatibilityResult, disable2FA, enable2FA, getUserProfile, _googleClientId (+12 more)

### Community 31 - "connectivity_service.dart"
Cohesion: 0.08
Nodes (17): checkConnectivity, _connectivity, ConnectivityAware, ConnectivityService, ConnectivityStatus, _connectivitySub, _currentStatus, dispose (+9 more)

### Community 32 - "monitor_page.dart"
Cohesion: 0.09
Nodes (18): build, createState, _deviceService, dispose, _energyService, _history, initState, _loadHistory (+10 more)

### Community 33 - "google_signin_2fa_page.dart"
Cohesion: 0.10
Nodes (19): _auth, build, _build2FAInput, _buildGoogleSignInButton, _codeController, createState, dispose, email (+11 more)

### Community 34 - "sync_service.dart"
Cohesion: 0.09
Nodes (16): _addToOfflineQueue, _apiService, baseUrl, _client, dispose, _isOnline, _offlineQueue, _ownsClient (+8 more)

### Community 35 - "win32_window.cpp"
Cohesion: 0.14
Nodes (8): EnableNonClientDpiScaling, Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, WindowClassRegistrar::GetWindowClass(), instance_, WindowClassRegistrar::UnregisterWindowClass()

### Community 36 - "BRIX - Smart Home IoT System"
Cohesion: 0.11
Nodes (18): 👤 Author, Backend Setup, BRIX - Smart Home IoT System, Building for Production, 🔧 Configuration, 🛠️ Development, Environment Variables (project `.env` or `backend/.env`), 🔌 ESP32 Hardware (+10 more)

### Community 37 - "FlutterWindow"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 38 - "backend_sync_service.dart"
Cohesion: 0.15
Nodes (10): addDevice, _apiService, BackendSyncService, controlDevice, deleteDevice, _instance, loadDevices, setUserId (+2 more)

### Community 39 - "Any"
Cohesion: 0.15
Nodes (25): _alert_filters(), _alert_json(), AlertCreateRequest, create_alert(), create_energy_reading(), create_notification(), _device_owner(), DeviceSensorBatch (+17 more)

### Community 40 - "StatelessWidget"
Cohesion: 0.14
Nodes (13): MyApp, ShimmerCard, ShimmerDeviceGrid, ShimmerList, SmoothEmptyState, SmoothLoader, SmoothLoaderCircle, SmoothLoaderDots (+5 more)

### Community 42 - "utils.cpp"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 43 - "package:flutter/material.dart"
Cohesion: 0.20
Nodes (6): clear, clearAppData, main, prefs, buildPageRoute, PageTransitions

### Community 44 - "preferences_token_store.dart"
Cohesion: 0.15
Nodes (9): accessTokenKey, clearAccessToken, clearTokens, _instance, readAccessToken, readRefreshToken, refreshTokenKey, saveAccessToken (+1 more)

### Community 45 - "Win32Window"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 46 - "_execute_device_command"
Cohesion: 0.25
Nodes (6): _publish_mqtt_message(), on_connect(), _record_mqtt_state(), start_mqtt_event_listener(), on_message(), stop_mqtt_event_listener()

### Community 48 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 50 - "auth_repository.dart"
Cohesion: 0.08
Nodes (21): _apiService, _baseUrl, _decode, _error, exchangeGoogleAccount, getCurrentUser, getCurrentUserProfile, logout (+13 more)

### Community 51 - "token_store.dart"
Cohesion: 0.20
Nodes (9): PreferencesTokenStore, clearAccessToken, clearTokens, readAccessToken, readRefreshToken, saveAccessToken, saveTokens, TokenStore (+1 more)

### Community 53 - "web_redirect_web.dart"
Cohesion: 0.25
Nodes (4): redirectTo, url, redirectTo, url

### Community 54 - "analysis_options.yaml"
Cohesion: 0.33
Nodes (5): analyzer, exclude, include, linter, rules

### Community 56 - "ApiService"
Cohesion: 0.40
Nodes (5): AlertService, ApiService, DeviceService, LogService, SensorService

### Community 57 - "MaterialPageRoute"
Cohesion: 0.50
Nodes (3): build, _handleEmailAuth, _handleGoogleWebAccount

### Community 59 - "Point"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 60 - "settings_repository.dart"
Cohesion: 0.09
Nodes (18): _apiService, _baseUrl, changePassword, _decode, deleteAccount, disable2FA, enable2FA, get2FAStatus (+10 more)

### Community 66 - "test_device_registration.py"
Cohesion: 0.08
Nodes (9): DeviceCreateRequest, _Connection, DeviceControlMqttTests, DeviceRegistrationTests, _Result, _configured_preferences(), _FakeConnection, _FakeResult (+1 more)

### Community 75 - "post"
Cohesion: 0.12
Nodes (19): clear_all_alerts(), _code_hash(), _consume_email_code(), control_device(), control_device_legacy(), disable_two_factor(), EmailVerificationRequest, _execute_device_command() (+11 more)

### Community 76 - "auth_controller.dart"
Cohesion: 0.11
Nodes (14): AuthController, dispose, logout, register, _repository, requestPasswordReset, resetPassword, restoreSession (+6 more)

### Community 77 - "domain_service_contract_test.dart"
Cohesion: 0.12
Nodes (10): accessToken, clearAccessToken, clearTokens, encode, _jwtWithSubject, main, readAccessToken, readRefreshToken (+2 more)

### Community 78 - "dart:convert"
Cohesion: 0.21
Nodes (4): main, main, main, main

### Community 79 - "package:flutter/foundation.dart"
Cohesion: 0.20
Nodes (6): AuthState, AuthStatus, copyWith, message, status, user

### Community 80 - "os"
Cohesion: 0.28
Nodes (3): create_smart_home_icon(), main(), generate_android_icons()

### Community 83 - "token_store_test.dart"
Cohesion: 0.33
Nodes (3): main, _TestApiService, tokenStore

## Knowledge Gaps
- **876 isolated node(s):** `_repository`, `state`, `register`, `signIn`, `verifyEmail` (+871 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1209 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **27 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `Win32Window` to `win32_window.cpp`, `FlutterWindow`, `flutter_window.h`, `.MessageHandler`, `Point`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **What connects `_repository`, `state`, `register` to the rest of the system?**
  _876 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `auth_service.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.027777777777777776 - nodes in this community are weakly interconnected._
- **Why does `ApiService` connect `ApiService` to `auth_service.dart`, `notification_service.dart`, `sync_service.dart`, `backend_sync_service.dart`, `energy_monitor_service.dart`, `auth_repository.dart`, `token_store_test.dart`, `settings_repository.dart`, `api_service.dart`, `google_signin_2fa_service.dart`?**
  _High betweenness centrality (0.022) - this node is a cross-community bridge._
- **Should `smooth_ui.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.034482758620689655 - nodes in this community are weakly interconnected._
- **Why does `TokenStore` connect `token_store.dart` to `auth_service.dart`, `notification_service.dart`, `device_page.dart`, `auth_repository.dart`, `settings_repository.dart`, `api_service.dart`, `google_signin_2fa_service.dart`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **Should `notification_service.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.038461538461538464 - nodes in this community are weakly interconnected._