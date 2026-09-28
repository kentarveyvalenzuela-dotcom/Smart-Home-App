import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Activity log model
class ActivityLog {
  final String id;
  final String userId;
  final String action;
  final String resourceType; // 'device', 'sensor', 'alert', 'user'
  final String? resourceId;
  final String details;
  final String ipAddress;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  ActivityLog({
    required this.id,
    required this.userId,
    required this.action,
    required this.resourceType,
    this.resourceId,
    required this.details,
    required this.ipAddress,
    required this.createdAt,
    this.metadata,
  });

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      action: json['action'] ?? 'unknown',
      resourceType: json['resource_type'] ?? '',
      resourceId: json['resource_id'],
      details: json['details'] ?? '',
      ipAddress: json['ip_address'] ?? '',
      createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'ActivityLog(action: $action, resourceType: $resourceType)';
}

/// Device control log
class DeviceControlLog {
  final String id;
  final String deviceId;
  final String command;
  final String previousState;
  final String newState;
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;

  DeviceControlLog({
    required this.id,
    required this.deviceId,
    required this.command,
    required this.previousState,
    required this.newState,
    required this.success,
    this.errorMessage,
    required this.timestamp,
  });

  factory DeviceControlLog.fromJson(Map<String, dynamic> json) {
    return DeviceControlLog(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      command: json['command'] ?? '',
      previousState: json['previous_state'] ?? 'unknown',
      newState: json['new_state'] ?? 'unknown',
      success: json['success'] ?? false,
      errorMessage: json['error_message'],
      timestamp: json['timestamp'] != null
        ? DateTime.parse(json['timestamp'])
        : DateTime.now(),
    );
  }
}

/// Log Service - Manages all log-related API calls
class LogService extends ApiService {
  static final LogService _instance = LogService._internal();

  factory LogService() {
    return _instance;
  }

  LogService._internal();

  /// Get user activity logs
  Future<ApiResponse<List<ActivityLog>>> getUserLogs({
    int limit = 50,
    int offset = 0,
    String? action,
    String? resourceType,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    return getRequest(
      '/logs/user',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => ActivityLog.fromJson(item as Map<String, dynamic>))
            .toList();
      },
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (action != null) 'action': action,
        if (resourceType != null) 'resource_type': resourceType,
        if (startTime != null) 'start_time': startTime.toIso8601String(),
        if (endTime != null) 'end_time': endTime.toIso8601String(),
      },
    );
  }

  /// Get device control logs
  Future<ApiResponse<List<DeviceControlLog>>> getDeviceControlLogs(
    String deviceId, {
    int limit = 50,
    int offset = 0,
    bool onlyErrors = false,
  }) async {
    return getRequest(
      '/logs/device/$deviceId',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => DeviceControlLog.fromJson(item as Map<String, dynamic>))
            .toList();
      },
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (onlyErrors) 'errors_only': 'true',
      },
    );
  }

  /// Get authentication logs
  Future<ApiResponse<List<ActivityLog>>> getAuthenticationLogs({
    int limit = 30,
  }) async {
    return getUserLogs(
      limit: limit,
      action: 'login',
      resourceType: 'user',
    );
  }

  /// Get sensor data logs
  Future<ApiResponse<List<ActivityLog>>> getSensorDataLogs({
    String? deviceId,
    int limit = 50,
  }) async {
    return getUserLogs(
      limit: limit,
      resourceType: 'sensor',
    );
  }

  /// Create activity log (for manual logging)
  Future<ApiResponse<ActivityLog>> createLog({
    required String action,
    required String resourceType,
    String? resourceId,
    required String details,
    Map<String, dynamic>? metadata,
  }) async {
    return postRequest(
      '/logs/create',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return ActivityLog.fromJson(data as Map<String, dynamic>);
      },
      body: {
        'action': action,
        'resource_type': resourceType,
        if (resourceId != null) 'resource_id': resourceId,
        'details': details,
        if (metadata != null) 'metadata': metadata,
      },
    );
  }

  /// Export logs (CSV/JSON)
  Future<ApiResponse<String>> exportLogs({
    required String format, // 'csv' or 'json'
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    return getRequest(
      '/logs/export',
      parser: (data) {
        return data is String ? data : '';
      },
      queryParams: {
        'format': format,
        if (startTime != null) 'start_time': startTime.toIso8601String(),
        if (endTime != null) 'end_time': endTime.toIso8601String(),
      },
    );
  }

  /// Clear old logs
  Future<ApiResponse<Map<String, dynamic>>> clearOldLogs({
    int daysOld = 90,
  }) async {
    return deleteRequest(
      '/logs/clear-old',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }

  /// Get log statistics
  Future<ApiResponse<Map<String, dynamic>>> getLogStatistics({
    int daysBack = 30,
  }) async {
    return getRequest(
      '/logs/statistics',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
      queryParams: {
        'days_back': daysBack.toString(),
      },
    );
  }
}

