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
  final String accessRole;

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
    this.accessRole = 'owner',
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown Device',
      type: json['type'] ?? 'light',
      status: json['status'] ?? 'off',
      isOnline: json['is_online'] ?? false,
      pin: json['pin'],
      topic: json['topic'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      lastSeen:
          json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      accessRole: json['access_role']?.toString() ?? 'owner',
    );
  }

  @override
  String toString() =>
      'Device(id: $id, name: $name, isOnline: $isOnline, status: $status)';
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

class DeviceShare {
  final int userId;
  final String email;
  final String name;
  final String role;
  final DateTime? createdAt;

  DeviceShare({required this.userId, required this.email, required this.name, required this.role, this.createdAt});

  factory DeviceShare.fromJson(Map<String, dynamic> json) => DeviceShare(
        userId: int.tryParse(json['user_id'].toString()) ?? 0,
        email: json['email']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        role: json['role']?.toString() ?? 'viewer',
        createdAt: json['created_at'] == null ? null : DateTime.tryParse(json['created_at'].toString()),
      );
}

/// Device Service - Manages all device-related API calls
class DeviceService extends ApiService {
  static final DeviceService _instance = DeviceService._internal();

  factory DeviceService() {
    return _instance;
  }

  DeviceService._internal();

  /// Test-only constructor; production callers continue using the singleton.
  DeviceService.forTesting({super.client, super.baseUrl});

  /// Compatibility methods preserve the legacy device screen contracts while
  /// routing requests through the domain service.
  Future<Map<String, dynamic>> registerScreenDevice({
    required String deviceName,
    required String mqttClientId,
    required int pinNumber,
    String? location,
    String deviceType = 'esp32',
  }) async {
    final response = await postRequest<Map<String, dynamic>>(
      '/devices/register',
      body: {
        'name': deviceName,
        'type': deviceType,
        'pin': pinNumber,
        'topic': 'home/device/$mqttClientId',
        'mqtt_client_id': mqttClientId,
        'location': location ?? '',
      },
      parser: (data) => data is Map ? Map<String, dynamic>.from(data) : {},
    );
    if (!response.success) {
      return {'success': false, 'error': response.error};
    }

    final data = response.data ?? <String, dynamic>{};
    final backendDeviceId =
        data['id']?.toString() ?? data['device_id']?.toString();
    if (backendDeviceId == null || backendDeviceId.isEmpty) {
      return {
        'success': false,
        'error': 'Backend registration returned no device ID',
      };
    }

    return {
      ...data,
      'success': true,
      'id': backendDeviceId,
      'device_id': backendDeviceId,
      'backend_device_id': backendDeviceId,
      'mqtt_client_id': data['mqtt_client_id']?.toString() ?? mqttClientId,
    };
  }

  /// Ensures the authenticated user has an Energy Monitor device.
  /// The response shape remains compatible with the legacy AuthService method.
  Future<Map<String, dynamic>> ensureEnergyDeviceRegistered() async {
    final response = await postRequest<Map<String, dynamic>>(
      '/devices/register-energy',
      parser: (data) => data is Map ? Map<String, dynamic>.from(data) : {},
    );
    if (response.success) {
      return {
        'success': true,
        'device': response.data?['device'],
      };
    }
    return {'success': false, 'error': response.error};
  }

  Future<Map<String, dynamic>> sendScreenControl({
    required String deviceId,
    required int pinNumber,
    required String action,
  }) async {
    final response = await postRequest<Map<String, dynamic>>(
      '/devices/control',
      body: {
        'device_id': deviceId,
        'pin_number': pinNumber,
        'action': action,
      },
      parser: (data) => data is Map ? Map<String, dynamic>.from(data) : {},
    );
    return response.success
        ? {
            'success': true,
            ...?response.data,
            'mqtt_published': response.data?['mqtt_published'] ?? false,
          }
        : {'success': false, 'error': response.error};
  }

  Future<Map<String, dynamic>> deleteScreenDevice(String deviceId) async {
    final response = await deleteRequest<Map<String, dynamic>>(
      '/devices/$deviceId',
      parser: (data) => data is Map ? Map<String, dynamic>.from(data) : {},
    );
    if (response.success || response.statusCode == 404) {
      return {
        'success': true,
        'message': response.statusCode == 404
            ? 'Device already deleted or not found'
            : response.data?['message'] ?? 'Device deleted',
      };
    }
    return {'success': false, 'error': response.error};
  }

  /// List all user's devices
  Future<ApiResponse<List<Device>>> listDevices() async {
    return getRequest(
      '/devices/list',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data)
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
  Future<ApiResponse<Map<String, dynamic>>> deleteDevice(
      String deviceId) async {
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

  Future<ApiResponse<DeviceShare>> shareDevice({required String deviceId, required String email, String role = 'viewer'}) async {
    return postRequest('/devices/$deviceId/shares', body: {'email': email, 'role': role}, parser: (data) {
      final user = data is Map ? data['user'] : null;
      if (user is! Map) throw Exception('Invalid share response');
      return DeviceShare.fromJson({...Map<String, dynamic>.from(user), 'role': data['role']});
    });
  }

  Future<ApiResponse<List<DeviceShare>>> listDeviceShares(String deviceId) async {
    return getRequest('/devices/$deviceId/shares', parser: (data) {
      if (data is! List) return <DeviceShare>[];
      return data.map((item) => DeviceShare.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    });
  }

  Future<ApiResponse<Map<String, dynamic>>> revokeDeviceShare(String deviceId, int userId) async {
    return deleteRequest('/devices/$deviceId/shares/$userId', parser: (data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  /// Get device activity logs
  Future<ApiResponse<List<Map<String, dynamic>>>> getDeviceLogs(
      String deviceId) async {
    return getRequest(
      '/logs/device/$deviceId',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data).map((item) => item as Map<String, dynamic>).toList();
      },
    );
  }
}
