import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Backend sync service for local device storage
/// No authentication required - perfect for demos!
class BackendSyncService {
  static final BackendSyncService _instance = BackendSyncService._internal();
  factory BackendSyncService() => _instance;
  BackendSyncService._internal();

  String _userId = 'default';
  final ApiService _apiService = ApiService();

  void setUserId(String userId) {
    _userId = userId;
  }

  /// Sync all devices to backend
  Future<bool> syncDevices(List<Map<String, dynamic>> devices) async {
    try {
      debugPrint('[SYNC] Syncing ${devices.length} devices to backend...');

      final response = await _apiService.postRequest<dynamic>(
        '/local-devices/sync',
        includeAuth: false,
        body: {
          'devices': devices
              .map((d) => {
                    'id': d['id']?.toString() ?? '',
                    'name': d['name']?.toString() ?? '',
                    'type': d['type']?.toString() ?? 'Light/Bulb',
                    'topic': d['topic']?.toString() ?? '',
                    'pin': d['pin'] ?? 23,
                    'isOn': d['isOn'] ?? false,
                    'esp32_id': d['esp32_id']?.toString(),
                  })
              .toList(),
          'user_id': _userId,
        },
        parser: (data) => data,
      );

      if (response.statusCode == 200) {
        debugPrint('[SYNC] ✅ Devices synced successfully');
        return true;
      } else {
        debugPrint('[SYNC] ❌ Sync failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[SYNC] ❌ Sync error: $e');
      return false;
    }
  }

  /// Load devices from backend
  Future<List<Map<String, dynamic>>?> loadDevices() async {
    try {
      debugPrint('[SYNC] Loading devices from backend...');

      final response = await _apiService.getRequest<dynamic>(
        '/local-devices/list',
        queryParams: {'user_id': _userId},
        includeAuth: false,
        parser: (data) => data,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final devices = (data['devices'] as List?)
            ?.map((d) => Map<String, dynamic>.from(d))
            .toList();
        debugPrint(
            '[SYNC] ✅ Loaded ${devices?.length ?? 0} devices from backend');
        return devices;
      } else {
        debugPrint('[SYNC] ❌ Load failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[SYNC] ❌ Load error: $e');
      return null;
    }
  }

  /// Add a single device
  Future<bool> addDevice(Map<String, dynamic> device) async {
    try {
      final response = await _apiService.postRequest<dynamic>(
        '/local-devices/add',
        queryParams: {'user_id': _userId},
        includeAuth: false,
        body: {
          'id': device['id']?.toString() ?? '',
          'name': device['name']?.toString() ?? '',
          'type': device['type']?.toString() ?? 'Light/Bulb',
          'topic': device['topic']?.toString() ?? '',
          'pin': device['pin'] ?? 23,
          'isOn': device['isOn'] ?? false,
          'esp32_id': device['esp32_id']?.toString(),
        },
        parser: (data) => data,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SYNC] ❌ Add device error: $e');
      return false;
    }
  }

  /// Delete a device
  Future<bool> deleteDevice(String deviceId) async {
    try {
      final response = await _apiService.deleteRequest<dynamic>(
        '/local-devices/$deviceId',
        queryParams: {'user_id': _userId},
        includeAuth: false,
        parser: (data) => data,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SYNC] ❌ Delete device error: $e');
      return false;
    }
  }

  /// Control device via backend (sends MQTT)
  Future<bool> controlDevice(String deviceId, String action,
      {int pin = 0}) async {
    try {
      final response = await _apiService.postRequest<dynamic>(
        '/local-devices/control',
        queryParams: {'user_id': _userId},
        includeAuth: false,
        body: {
          'device_id': deviceId,
          'action': action,
          'pin': pin,
        },
        parser: (data) => data,
      );

      if (response.statusCode == 200) {
        final data = response.data as Map? ?? const {};
        debugPrint(
            '[SYNC] ✅ Control sent: ${data['mqtt_sent'] == true ? 'MQTT' : 'Local only'}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SYNC] ❌ Control error: $e');
      return false;
    }
  }
}
