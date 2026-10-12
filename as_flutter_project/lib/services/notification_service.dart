import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'config_service.dart';

enum NotificationType {
  googleSignIn,
  emailSignIn,
  passwordChange,
  deviceToggle,
  deviceAdd,
  deviceDelete,
  profileUpdate,
  logout,
}

class ActivityNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? metadata;

  ActivityNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.metadata,
  });

  factory ActivityNotification.fromJson(Map<String, dynamic> json) => ActivityNotification(
        id: json['id']?.toString() ?? '',
        type: NotificationType.values.firstWhere((e) => e.name == json['type'], orElse: () => NotificationType.deviceToggle),
        title: json['title']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        timestamp: DateTime.tryParse((json['timestamp'] ?? json['created_at'] ?? '').toString()) ?? DateTime.now(),
        isRead: json['isRead'] == true || json['is_read'] == true,
        metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'metadata': metadata,
      };

  ActivityNotification copyWith({bool? isRead}) => ActivityNotification(
        id: id, type: type, title: title, message: message, timestamp: timestamp,
        isRead: isRead ?? this.isRead, metadata: metadata,
      );
}

/// Notifications are stored by the PostgreSQL API and cached locally for offline use.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<ActivityNotification> _notifications = [];
  final _notificationStreamController = StreamController<List<ActivityNotification>>.broadcast();
  Timer? _pollTimer;
  StreamSubscription<String>? _pushTokenSubscription;
  String? _registeredPushToken;
  bool _initialized = false;

  Stream<List<ActivityNotification>> get notificationStream => _notificationStreamController.stream;
  List<ActivityNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<Map<String, String>> _headers() async {
    final headers = await AuthService().getAuthHeaders();
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  Future<void> initialize() async {
    if (_initialized) {
      _startPolling();
      return;
    }
    await _loadFromLocalStorage();
    await _syncFromBackend();
    _startPolling();
    if (!kIsWeb) {
      try {
        _pushTokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
          _registerPushToken(token);
        });
      } catch (e) {
        debugPrint('Firebase Messaging is not initialized: $e');
      }
    }
    _initialized = true;
  }

  void _startPolling() {
    _pollTimer ??=
        Timer.periodic(const Duration(seconds: 20), (_) => _syncFromBackend());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _syncFromBackend() async {
    try {
      final headers = await _headers();
      if (!headers.containsKey('Authorization')) return;
      await _registerPushToken();
      final response = await http.get(Uri.parse('${ConfigService().backendUrl}/notifications?limit=100'), headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final items = jsonDecode(response.body) as List;
      _notifications
        ..clear()
        ..addAll(items.map((item) => ActivityNotification.fromJson(Map<String, dynamic>.from(item as Map))));
      await _saveToLocalStorage();
      _notificationStreamController.add(List.unmodifiable(_notifications));
    } catch (e) {
      debugPrint('Notification sync error: $e');
    }
  }

  Future<void> _registerPushToken([String? refreshedToken]) async {
    if (kIsWeb) return;
    try {
      final headers = await _headers();
      if (!headers.containsKey('Authorization')) return;
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = refreshedToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty || token == _registeredPushToken) return;
      final response = await http.post(
        Uri.parse('${ConfigService().backendUrl}/notifications/device-token'),
        headers: headers,
        body: jsonEncode({'token': token, 'platform': defaultTargetPlatform.name}),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) _registeredPushToken = token;
    } catch (e) {
      // Firebase can be unconfigured for a build target; in-app notifications still work.
      debugPrint('Push token registration unavailable: $e');
    }
  }

  Future<void> addGoogleSignInNotification(String email) => _addNotification(type: NotificationType.googleSignIn, title: 'Google Sign-In', message: 'Successfully signed in with Google account: $email', metadata: {'email': email});
  Future<void> addEmailSignInNotification(String email) => _addNotification(type: NotificationType.emailSignIn, title: 'Email Sign-In', message: 'Successfully signed in with email: $email', metadata: {'email': email});
  Future<void> addPasswordChangeNotification() => _addNotification(type: NotificationType.passwordChange, title: 'Password Changed', message: 'Your password has been successfully changed');
  Future<void> addDeviceAddNotification(String deviceName) => _addNotification(type: NotificationType.deviceAdd, title: 'Device Added', message: 'New device "$deviceName" has been added to your smart home', metadata: {'deviceName': deviceName});
  Future<void> addDeviceDeleteNotification(String deviceName) => _addNotification(type: NotificationType.deviceDelete, title: 'Device Removed', message: 'Device "$deviceName" has been removed from your smart home', metadata: {'deviceName': deviceName});
  Future<void> addProfileUpdateNotification() => _addNotification(type: NotificationType.profileUpdate, title: 'Profile Updated', message: 'Your profile information has been updated');
  Future<void> addLogoutNotification() => _addNotification(type: NotificationType.logout, title: 'Signed Out', message: 'You have been signed out of your account');

  Future<void> addDeviceToggleNotification({required String deviceName, required String action, String? location}) {
    final locationText = location?.isNotEmpty == true ? ' in $location' : '';
    final actionText = action.toUpperCase() == 'ON' ? 'turned ON' : 'turned OFF';
    return _addNotification(type: NotificationType.deviceToggle, title: 'Device Control', message: 'Your $deviceName$locationText has been $actionText', metadata: {'deviceName': deviceName, 'action': action, 'location': location});
  }

  Future<void> _addNotification({required NotificationType type, required String title, required String message, Map<String, dynamic>? metadata}) async {
    final notification = ActivityNotification(id: DateTime.now().millisecondsSinceEpoch.toString(), type: type, title: title, message: message, timestamp: DateTime.now(), metadata: metadata);
    _notifications.insert(0, notification);
    if (_notifications.length > 100) _notifications.removeRange(100, _notifications.length);
    await _saveToLocalStorage();
    _notificationStreamController.add(List.unmodifiable(_notifications));
    try {
      final headers = await _headers();
      if (headers.containsKey('Authorization')) {
        final response = await http.post(Uri.parse('${ConfigService().backendUrl}/notifications'), headers: headers, body: jsonEncode({'type': type.name, 'title': title, 'message': message, 'metadata': metadata ?? {}})).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final saved = ActivityNotification.fromJson(Map<String, dynamic>.from(jsonDecode(response.body)));
          final index = _notifications.indexWhere((n) => n.id == notification.id);
          if (index >= 0) _notifications[index] = saved;
          await _saveToLocalStorage();
          _notificationStreamController.add(List.unmodifiable(_notifications));
        }
      }
    } catch (e) { debugPrint('Notification save error: $e'); }
  }

  Future<void> markAsRead(String id) async {
    final i = _notifications.indexWhere((n) => n.id == id);
    if (i < 0) return;
    _notifications[i] = _notifications[i].copyWith(isRead: true);
    await _request('PATCH', '/notifications/$id/read');
    await _publishLocal();
  }

  Future<void> markAllAsRead() async {
    for (var i = 0; i < _notifications.length; i++) { _notifications[i] = _notifications[i].copyWith(isRead: true); }
    await _request('POST', '/notifications/read-all');
    await _publishLocal();
  }

  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    await _request('DELETE', '/notifications/$id');
    await _publishLocal();
  }

  Future<void> clearAll() async {
    _notifications.clear();
    await _request('DELETE', '/notifications');
    await _publishLocal();
  }

  Future<void> _request(String method, String path) async {
    try {
      final headers = await _headers();
      if (!headers.containsKey('Authorization')) return;
      final uri = Uri.parse('${ConfigService().backendUrl}$path');
      if (method == 'PATCH') await http.patch(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (method == 'POST') await http.post(uri, headers: headers).timeout(const Duration(seconds: 8));
      if (method == 'DELETE') await http.delete(uri, headers: headers).timeout(const Duration(seconds: 8));
    } catch (e) { debugPrint('Notification update error: $e'); }
  }

  Future<void> _publishLocal() async {
    await _saveToLocalStorage();
    _notificationStreamController.add(List.unmodifiable(_notifications));
  }

  Future<void> _saveToLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(await _cacheKey(), _notifications.map((n) => jsonEncode(n.toJson())).toList());
  }

  Future<void> _loadFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(await _cacheKey()) ?? [];
    _notifications
      ..clear()
      ..addAll(rows.map((row) => ActivityNotification.fromJson(Map<String, dynamic>.from(jsonDecode(row)))));
    _notificationStreamController.add(List.unmodifiable(_notifications));
  }

  Future<String> _cacheKey() async {
    final auth = AuthService();
    var userId = auth.currentUserId;
    if (userId == null) {
      try {
        final token = await auth.getAccessToken();
        final parts = token?.split('.') ?? const <String>[];
        if (parts.length == 3) {
          final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
          userId = payload['sub']?.toString();
        }
      } catch (_) {}
    }
    return 'activity_notifications_${userId ?? 'anonymous'}';
  }

  void dispose() {
    stopPolling();
    _pushTokenSubscription?.cancel();
    _notificationStreamController.close();
  }
}
