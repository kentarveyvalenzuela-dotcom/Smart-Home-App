import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Firebase Realtime Database Service for storing sensor and device data
class FirebaseDbService {
  static final FirebaseDbService _instance = FirebaseDbService._internal();
  factory FirebaseDbService() => _instance;
  FirebaseDbService._internal();

  // Lazily initialized instance to avoid late-init errors even if initialize() wasn't awaited.
  late final FirebaseDatabase _database = FirebaseDatabase.instance;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await initialize();
  }

  /// Initialize Firebase Database
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (!kIsWeb) {
        _database.setPersistenceEnabled(true);
      }
      _initialized = true;
      debugPrint('✅ Firebase Realtime Database initialized');
    } catch (e) {
      debugPrint('❌ Firebase Database init error: $e');
      rethrow;
    }
  }

  /// Get reference to sensors data for current user
  DatabaseReference getUserSensorsRef(String userId) {
    return _database.ref().child('users').child(userId).child('sensors');
  }

  /// Get reference to devices data for current user
  DatabaseReference getUserDevicesRef(String userId) {
    return _database.ref().child('users').child(userId).child('devices');
  }

  /// Get reference to alerts data for current user
  DatabaseReference getUserAlertsRef(String userId) {
    return _database.ref().child('users').child(userId).child('alerts');
  }

  /// Save sensor reading to Firebase
  Future<void> saveSensorReading({
    required String userId,
    required String sensorId,
    required double value,
    required String unit,
    required DateTime timestamp,
  }) async {
    try {
      await _ensureInitialized();
      final ref = getUserSensorsRef(userId).child(sensorId);
      
      await ref.set({
        'sensorId': sensorId,
        'value': value,
        'unit': unit,
        'timestamp': timestamp.toIso8601String(),
      });
      
      debugPrint('📊 Sensor reading saved: $sensorId = $value $unit');
    } catch (e) {
      debugPrint('❌ Error saving sensor reading: $e');
      rethrow;
    }
  }

  /// Get latest sensor reading
  Future<Map<String, dynamic>?> getLatestSensorReading({
    required String userId,
    required String sensorId,
  }) async {
    try {
      await _ensureInitialized();
      final snapshot = await getUserSensorsRef(userId).child(sensorId).get();
      
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting sensor reading: $e');
      return null;
    }
  }

  /// Listen to sensor readings in real-time
  Stream<Map<String, dynamic>> listenToSensorReadings({
    required String userId,
    required String sensorId,
  }) {
    // Fire-and-forget init to keep stream signature sync
    _ensureInitialized();
    return getUserSensorsRef(userId)
        .child(sensorId)
        .onValue
        .map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return {};
    });
  }

  /// Save device state
  Future<void> saveDeviceState({
    required String userId,
    required String deviceId,
    required String name,
    required bool isOn,
    required String gpioPin,
  }) async {
    try {
      await _ensureInitialized();
      final ref = getUserDevicesRef(userId).child(deviceId);
      
      await ref.set({
        'deviceId': deviceId,
        'name': name,
        'isOn': isOn,
        'gpioPin': gpioPin,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      debugPrint('💡 Device state saved: $name = ${isOn ? 'ON' : 'OFF'}');
    } catch (e) {
      debugPrint('❌ Error saving device state: $e');
      rethrow;
    }
  }

  /// Get all devices for user
  Future<List<Map<String, dynamic>>> getAllDevices(String userId) async {
    try {
      await _ensureInitialized();
      final snapshot = await getUserDevicesRef(userId).get();
      
      if (snapshot.exists) {
        final devices = <Map<String, dynamic>>[];
        for (var child in snapshot.children) {
          devices.add(Map<String, dynamic>.from(child.value as Map));
        }
        return devices;
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error getting devices: $e');
      return [];
    }
  }

  /// Listen to all devices in real-time
  Stream<List<Map<String, dynamic>>> listenToAllDevices(String userId) {
    _ensureInitialized();
    return getUserDevicesRef(userId).onValue.map((event) {
      if (event.snapshot.exists) {
        final devices = <Map<String, dynamic>>[];
        for (var child in event.snapshot.children) {
          devices.add(Map<String, dynamic>.from(child.value as Map));
        }
        return devices;
      }
      return [];
    });
  }

  /// Save sensor history for analytics
  Future<void> saveSensorHistory({
    required String userId,
    required String sensorId,
    required double value,
    required String unit,
    required DateTime timestamp,
  }) async {
    try {
      await _ensureInitialized();
      final ref = _database
          .ref()
          .child('users')
          .child(userId)
          .child('sensor_history')
          .child(sensorId)
          .push();
      
      await ref.set({
        'value': value,
        'unit': unit,
        'timestamp': timestamp.toIso8601String(),
      });
      
      debugPrint('📈 Sensor history recorded');
    } catch (e) {
      debugPrint('❌ Error saving sensor history: $e');
      rethrow;
    }
  }

  /// Get sensor history for date range
  Future<List<Map<String, dynamic>>> getSensorHistory({
    required String userId,
    required String sensorId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      await _ensureInitialized();
      final snapshot = await _database
          .ref()
          .child('users')
          .child(userId)
          .child('sensor_history')
          .child(sensorId)
          .get();
      
      if (snapshot.exists) {
        final history = <Map<String, dynamic>>[];
        for (var child in snapshot.children) {
          final data = Map<String, dynamic>.from(child.value as Map);
          final timestamp = DateTime.parse(data['timestamp'] as String);
          
          if (timestamp.isAfter(startDate) && timestamp.isBefore(endDate)) {
            history.add(data);
          }
        }
        return history;
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error getting sensor history: $e');
      return [];
    }
  }

  /// Save an alert event for the user
  Future<String?> saveAlertEvent({
    required String userId,
    required String type,
    required String message,
    required double value,
    required DateTime timestamp,
    Map<String, dynamic>? metadata,
    bool resolved = false,
  }) async {
    try {
      await _ensureInitialized();
      final ref = getUserAlertsRef(userId).push();

      await ref.set({
        'id': ref.key,
        'type': type,
        'message': message,
        'value': value,
        'resolved': resolved,
        'timestamp': timestamp.toIso8601String(),
        if (metadata != null) 'metadata': metadata,
      });

      debugPrint('🚨 Alert saved: $type -> $message');
      return ref.key;
    } catch (e) {
      debugPrint('❌ Error saving alert: $e');
      return null;
    }
  }
}
