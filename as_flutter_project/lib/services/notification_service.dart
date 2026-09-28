// filepath: c:\Users\Ivy\OneDrive\Desktop\New folder\brix\as_flutter_project\lib\services\notification_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Types of activity notifications
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

/// Activity Notification Model
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

  factory ActivityNotification.fromJson(Map<String, dynamic> json) {
    return ActivityNotification(
      id: json['id'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.deviceToggle,
      ),
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      isRead: json['isRead'] ?? false,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
    'metadata': metadata,
  };

  ActivityNotification copyWith({bool? isRead}) {
    return ActivityNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      metadata: metadata,
    );
  }
}

/// Notification Service - Manages local activity notifications with Firebase sync
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<ActivityNotification> _notifications = [];
  final _notificationStreamController = StreamController<List<ActivityNotification>>.broadcast();

  StreamSubscription<DatabaseEvent>? _firebaseSubscription;
  bool _initialized = false;
  String? _currentUserId;

  Stream<List<ActivityNotification>> get notificationStream => _notificationStreamController.stream;
  List<ActivityNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Get Firebase reference for user notifications
  DatabaseReference? _getUserNotificationsRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseDatabase.instance.ref().child('users').child(user.uid).child('notifications');
  }

  /// Initialize and load notifications from storage/Firebase
  Future<void> initialize() async {
    if (_initialized) return;

    // Listen to auth state changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && user.uid != _currentUserId) {
        _currentUserId = user.uid;
        _setupFirebaseListener();
      } else if (user == null) {
        _currentUserId = null;
        _firebaseSubscription?.cancel();
        _notifications.clear();
        _notificationStreamController.add(_notifications);
      }
    });

    // Load from local storage first (for offline support)
    await _loadFromLocalStorage();

    // Then sync with Firebase if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      await _syncFromFirebase();
      _setupFirebaseListener();
    }

    _initialized = true;
    debugPrint('✅ NotificationService initialized with ${_notifications.length} notifications');
  }

  /// Setup real-time Firebase listener
  void _setupFirebaseListener() {
    _firebaseSubscription?.cancel();

    final ref = _getUserNotificationsRef();
    if (ref == null) return;

    _firebaseSubscription = ref.orderByChild('timestamp').onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          _notifications.clear();

          data.forEach((key, value) {
            try {
              final notifData = Map<String, dynamic>.from(value as Map);
              notifData['id'] = key;
              _notifications.add(ActivityNotification.fromJson(notifData));
            } catch (e) {
              debugPrint('⚠️ Error parsing notification $key: $e');
            }
          });

          // Sort by timestamp descending (newest first)
          _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Also save to local storage for offline access
          _saveToLocalStorage();

          _notificationStreamController.add(_notifications);
          debugPrint('🔄 Firebase notifications synced: ${_notifications.length} items');
        } catch (e) {
          debugPrint('❌ Error processing Firebase notifications: $e');
        }
      }
    }, onError: (error) {
      debugPrint('❌ Firebase notification listener error: $error');
    });
  }

  /// Sync notifications from Firebase
  Future<void> _syncFromFirebase() async {
    try {
      final ref = _getUserNotificationsRef();
      if (ref == null) return;

      final snapshot = await ref.orderByChild('timestamp').limitToLast(100).get();

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        _notifications.clear();

        data.forEach((key, value) {
          try {
            final notifData = Map<String, dynamic>.from(value as Map);
            notifData['id'] = key;
            _notifications.add(ActivityNotification.fromJson(notifData));
          } catch (e) {
            debugPrint('⚠️ Error parsing notification $key: $e');
          }
        });

        // Sort by timestamp descending
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        // Save to local storage
        await _saveToLocalStorage();

        _notificationStreamController.add(_notifications);
        debugPrint('✅ Synced ${_notifications.length} notifications from Firebase');
      }
    } catch (e) {
      debugPrint('❌ Error syncing from Firebase: $e');
    }
  }

  /// Add a Google Sign-In notification
  Future<void> addGoogleSignInNotification(String email) async {
    await _addNotification(
      type: NotificationType.googleSignIn,
      title: 'Google Sign-In',
      message: 'Successfully signed in with Google account: $email',
      metadata: {'email': email},
    );
  }

  /// Add an Email Sign-In notification
  Future<void> addEmailSignInNotification(String email) async {
    await _addNotification(
      type: NotificationType.emailSignIn,
      title: 'Email Sign-In',
      message: 'Successfully signed in with email: $email',
      metadata: {'email': email},
    );
  }

  /// Add a Password Change notification
  Future<void> addPasswordChangeNotification() async {
    await _addNotification(
      type: NotificationType.passwordChange,
      title: 'Password Changed',
      message: 'Your password has been successfully changed',
    );
  }

  /// Add a Device Toggle notification
  Future<void> addDeviceToggleNotification({
    required String deviceName,
    required String action,
    String? location,
  }) async {
    final actionText = action.toUpperCase() == 'ON' ? 'turned ON' : 'turned OFF';
    final locationText = location?.isNotEmpty == true ? ' in $location' : '';

    await _addNotification(
      type: NotificationType.deviceToggle,
      title: 'Device Control',
      message: 'Your $deviceName$locationText has been $actionText',
      metadata: {
        'deviceName': deviceName,
        'action': action,
        'location': location,
      },
    );
  }

  /// Add a Device Add notification
  Future<void> addDeviceAddNotification(String deviceName) async {
    await _addNotification(
      type: NotificationType.deviceAdd,
      title: 'Device Added',
      message: 'New device "$deviceName" has been added to your smart home',
      metadata: {'deviceName': deviceName},
    );
  }

  /// Add a Device Delete notification
  Future<void> addDeviceDeleteNotification(String deviceName) async {
    await _addNotification(
      type: NotificationType.deviceDelete,
      title: 'Device Removed',
      message: 'Device "$deviceName" has been removed from your smart home',
      metadata: {'deviceName': deviceName},
    );
  }

  /// Add a Profile Update notification
  Future<void> addProfileUpdateNotification() async {
    await _addNotification(
      type: NotificationType.profileUpdate,
      title: 'Profile Updated',
      message: 'Your profile information has been updated',
    );
  }

  /// Add a Logout notification
  Future<void> addLogoutNotification() async {
    await _addNotification(
      type: NotificationType.logout,
      title: 'Signed Out',
      message: 'You have been signed out of your account',
    );
  }

  /// Internal method to add notification
  Future<void> _addNotification({
    required NotificationType type,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final notification = ActivityNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    // Add to local list
    _notifications.insert(0, notification);

    // Keep only last 100 notifications locally
    if (_notifications.length > 100) {
      _notifications.removeRange(100, _notifications.length);
    }

    // Save to Firebase if user is logged in
    await _saveToFirebase(notification);

    // Save to local storage
    await _saveToLocalStorage();

    _notificationStreamController.add(_notifications);

    debugPrint('📢 Notification added: $title - $message');
  }

  /// Save notification to Firebase
  Future<void> _saveToFirebase(ActivityNotification notification) async {
    try {
      final ref = _getUserNotificationsRef();
      if (ref == null) {
        debugPrint('⚠️ User not logged in, notification saved locally only');
        return;
      }

      await ref.child(notification.id).set(notification.toJson());
      debugPrint('☁️ Notification saved to Firebase: ${notification.id}');

      // Clean up old notifications in Firebase (keep last 100)
      await _cleanupOldFirebaseNotifications();
    } catch (e) {
      debugPrint('❌ Error saving notification to Firebase: $e');
    }
  }

  /// Clean up old notifications in Firebase
  Future<void> _cleanupOldFirebaseNotifications() async {
    try {
      final ref = _getUserNotificationsRef();
      if (ref == null) return;

      final snapshot = await ref.orderByChild('timestamp').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        if (data.length > 100) {
          // Sort by timestamp and get oldest ones to delete
          final entries = data.entries.toList();
          entries.sort((a, b) {
            final aTime = DateTime.tryParse(a.value['timestamp'] ?? '') ?? DateTime.now();
            final bTime = DateTime.tryParse(b.value['timestamp'] ?? '') ?? DateTime.now();
            return aTime.compareTo(bTime);
          });

          // Delete oldest entries beyond 100
          final toDelete = entries.take(data.length - 100);
          for (final entry in toDelete) {
            await ref.child(entry.key).remove();
          }
          debugPrint('🗑️ Cleaned up ${toDelete.length} old notifications from Firebase');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error cleaning up Firebase notifications: $e');
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);

      // Update in Firebase
      try {
        final ref = _getUserNotificationsRef();
        if (ref != null) {
          await ref.child(notificationId).update({'isRead': true});
        }
      } catch (e) {
        debugPrint('⚠️ Error updating read status in Firebase: $e');
      }

      await _saveToLocalStorage();
      _notificationStreamController.add(_notifications);
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }

    // Update in Firebase
    try {
      final ref = _getUserNotificationsRef();
      if (ref != null) {
        final updates = <String, dynamic>{};
        for (final n in _notifications) {
          updates['${n.id}/isRead'] = true;
        }
        await ref.update(updates);
      }
    } catch (e) {
      debugPrint('⚠️ Error marking all as read in Firebase: $e');
    }

    await _saveToLocalStorage();
    _notificationStreamController.add(_notifications);
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    _notifications.removeWhere((n) => n.id == notificationId);

    // Delete from Firebase
    try {
      final ref = _getUserNotificationsRef();
      if (ref != null) {
        await ref.child(notificationId).remove();
      }
    } catch (e) {
      debugPrint('⚠️ Error deleting from Firebase: $e');
    }

    await _saveToLocalStorage();
    _notificationStreamController.add(_notifications);
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    _notifications.clear();

    // Clear from Firebase
    try {
      final ref = _getUserNotificationsRef();
      if (ref != null) {
        await ref.remove();
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing Firebase notifications: $e');
    }

    await _saveToLocalStorage();
    _notificationStreamController.add(_notifications);
  }

  /// Save notifications to local storage (for offline support)
  Future<void> _saveToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _notifications.map((n) => jsonEncode(n.toJson())).toList();
      await prefs.setStringList('activity_notifications', jsonList);
    } catch (e) {
      debugPrint('❌ Error saving notifications locally: $e');
    }
  }

  /// Load notifications from local storage
  Future<void> _loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('activity_notifications') ?? [];

      _notifications.clear();
      for (final jsonStr in jsonList) {
        try {
          final json = jsonDecode(jsonStr);
          _notifications.add(ActivityNotification.fromJson(json));
        } catch (e) {
          debugPrint('⚠️ Error parsing local notification: $e');
        }
      }

      // Sort by timestamp descending
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _notificationStreamController.add(_notifications);
      debugPrint('📱 Loaded ${_notifications.length} notifications from local storage');
    } catch (e) {
      debugPrint('❌ Error loading local notifications: $e');
    }
  }

  void dispose() {
    _firebaseSubscription?.cancel();
    _notificationStreamController.close();
  }
}

