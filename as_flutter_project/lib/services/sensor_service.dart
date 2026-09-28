import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Sensor reading model
class SensorReading {
  final String id;
  final String deviceId;
  final String sensorType; // temperature, humidity, motion, light, etc.
  final double value;
  final String unit;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  SensorReading({
    required this.id,
    required this.deviceId,
    required this.sensorType,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.metadata,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      sensorType: json['sensor_type'] ?? 'unknown',
      value: (json['value'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      timestamp: json['timestamp'] != null
        ? DateTime.parse(json['timestamp'])
        : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'SensorReading($sensorType: $value$unit)';
}

/// Sensor statistics
class SensorStats {
  final double min;
  final double max;
  final double average;
  final int readingCount;
  final DateTime startTime;
  final DateTime endTime;

  SensorStats({
    required this.min,
    required this.max,
    required this.average,
    required this.readingCount,
    required this.startTime,
    required this.endTime,
  });

  factory SensorStats.fromJson(Map<String, dynamic> json) {
    return SensorStats(
      min: (json['min'] ?? 0).toDouble(),
      max: (json['max'] ?? 0).toDouble(),
      average: (json['average'] ?? 0).toDouble(),
      readingCount: json['reading_count'] ?? 0,
      startTime: json['start_time'] != null
        ? DateTime.parse(json['start_time'])
        : DateTime.now(),
      endTime: json['end_time'] != null
        ? DateTime.parse(json['end_time'])
        : DateTime.now(),
    );
  }
}

/// Sensor Service - Manages all sensor-related API calls
class SensorService extends ApiService {
  static final SensorService _instance = SensorService._internal();

  factory SensorService() {
    return _instance;
  }

  SensorService._internal();

  /// Get latest sensor reading for a device
  Future<ApiResponse<SensorReading>> getLatestReading(String deviceId) async {
    return getRequest(
      '/sensors/device/$deviceId/latest',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid sensor data');
        }
        return SensorReading.fromJson(data as Map<String, dynamic>);
      },
    );
  }

  /// Get historical sensor readings for a device
  Future<ApiResponse<List<SensorReading>>> getDeviceReadings(
    String deviceId, {
    String? sensorType,
    DateTime? startTime,
    DateTime? endTime,
    int limit = 100,
  }) async {
    return getRequest(
      '/sensors/device/$deviceId',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => SensorReading.fromJson(item as Map<String, dynamic>))
            .toList();
      },
      queryParams: {
        if (sensorType != null) 'sensor_type': sensorType,
        if (startTime != null) 'start_time': startTime.toIso8601String(),
        if (endTime != null) 'end_time': endTime.toIso8601String(),
        'limit': limit.toString(),
      },
    );
  }

  /// Get statistics for sensor readings
  Future<ApiResponse<SensorStats>> getSensorStatistics(
    String deviceId, {
    String? sensorType,
    int daysBack = 7,
  }) async {
    return getRequest(
      '/sensors/statistics/$deviceId',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid statistics data');
        }
        return SensorStats.fromJson(data as Map<String, dynamic>);
      },
      queryParams: {
        if (sensorType != null) 'sensor_type': sensorType,
        'days_back': daysBack.toString(),
      },
    );
  }

  /// Get all sensor readings across all devices
  Future<ApiResponse<List<SensorReading>>> getAllReadings({
    int limit = 50,
  }) async {
    return getRequest(
      '/sensors/all',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => SensorReading.fromJson(item as Map<String, dynamic>))
            .toList();
      },
      queryParams: {
        'limit': limit.toString(),
      },
    );
  }

  /// Create a new sensor reading (for testing)
  Future<ApiResponse<SensorReading>> createReading({
    required String deviceId,
    required String sensorType,
    required double value,
    required String unit,
  }) async {
    return postRequest(
      '/sensors/create',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return SensorReading.fromJson(data as Map<String, dynamic>);
      },
      body: {
        'device_id': deviceId,
        'sensor_type': sensorType,
        'value': value,
        'unit': unit,
      },
    );
  }

  /// Get sensor data summary for dashboard
  Future<ApiResponse<Map<String, dynamic>>> getDashboardSummary() async {
    return getRequest(
      '/sensors/summary',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }
}

