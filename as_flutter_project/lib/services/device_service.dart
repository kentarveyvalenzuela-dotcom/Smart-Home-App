import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Device model from backend
class Device {
  final String id;
  final String name;
  final String type;
  final String status;
  final bool isOnline;
  final int? pin;
  final String? topic;
  final DateTime createdAt;
  final DateTime? lastSeen;

  Device({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.isOnline,
    this.pin,
    this.topic,
    required this.createdAt,
    this.lastSeen,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Device',
      type: json['type'] ?? 'light',
      status: json['status'] ?? 'off',
      isOnline: json['is_online'] ?? false,
      pin: json['pin'],
      topic: json['topic'],
      createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : DateTime.now(),
      lastSeen: json['last_seen'] != null
        ? DateTime.parse(json['last_seen'])
        : null,
    );
  }

  @override
  String toString() => 'Device(id: $id, name: $name, isOnline: $isOnline, status: $status)';
}

/// Device control response
class DeviceControlResponse {
  final bool success;
  final String message;
  final String? newStatus;

  DeviceControlResponse({
    required this.success,
    required this.message,
    this.newStatus,
  });

  factory DeviceControlResponse.fromJson(Map<String, dynamic> json) {
    return DeviceControlResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? 'No message',
      newStatus: json['new_status'],
    );
  }
}

/// Device Service - Manages all device-related API calls
class DeviceService extends ApiService {
  static final DeviceService _instance = DeviceService._internal();

  factory DeviceService() {
    return _instance;
  }

  DeviceService._internal();

  /// List all user's devices
  Future<ApiResponse<List<Device>>> listDevices() async {
    return getRequest(
      '/devices/list',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => Device.fromJson(item as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Get specific device details
  Future<ApiResponse<Device>> getDevice(String deviceId) async {
    return getRequest(
      '/devices/$deviceId',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid device data');
        }
        return Device.fromJson(data as Map<String, dynamic>);
      },
    );
  }

  /// Register a new device
  Future<ApiResponse<Device>> registerDevice({
    required String name,
    required String type,
    int? pin,
    String? topic,
  }) async {
    return postRequest(
      '/devices/register',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return Device.fromJson(data as Map<String, dynamic>);
      },
      body: {
        'name': name,
        'type': type,
        if (pin != null) 'pin': pin,
        if (topic != null) 'topic': topic,
      },
    );
  }

  /// Control device (turn on/off, etc.)
  Future<ApiResponse<DeviceControlResponse>> controlDevice({
    required String deviceId,
    required String command,
    Map<String, dynamic>? parameters,
  }) async {
    return postRequest(
      '/devices/$deviceId/control',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return DeviceControlResponse.fromJson(data as Map<String, dynamic>);
      },
      body: {
        'command': command,
        if (parameters != null) ...parameters,
      },
    );
  }

  /// Update device settings
  Future<ApiResponse<Device>> updateDevice({
    required String deviceId,
    String? name,
    String? type,
    int? pin,
    String? topic,
  }) async {
    return patchRequest(
      '/devices/$deviceId',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return Device.fromJson(data as Map<String, dynamic>);
      },
      body: {
        if (name != null) 'name': name,
        if (type != null) 'type': type,
        if (pin != null) 'pin': pin,
        if (topic != null) 'topic': topic,
      },
    );
  }

  /// Delete device
  Future<ApiResponse<Map<String, dynamic>>> deleteDevice(String deviceId) async {
    return deleteRequest(
      '/devices/$deviceId',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }

  /// Get device status
  Future<ApiResponse<String>> getDeviceStatus(String deviceId) async {
    return getRequest(
      '/devices/$deviceId/status',
      parser: (data) {
        if (data is Map) {
          return data['status'] ?? 'unknown';
        }
        return 'unknown';
      },
    );
  }

  /// Sync device state from backend (useful after device changes)
  Future<ApiResponse<Device>> syncDevice(String deviceId) async {
    return getDevice(deviceId);
  }

  /// Get device activity logs
  Future<ApiResponse<List<Map<String, dynamic>>>> getDeviceLogs(String deviceId) async {
    return getRequest(
      '/logs/device/$deviceId',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List).map((item) => item as Map<String, dynamic>).toList();
      },
    );
  }
}

