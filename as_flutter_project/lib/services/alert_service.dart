import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Alert severity levels
enum AlertSeverity { low, medium, high, critical }

/// Alert model from backend
class Alert {
  final String id;
  final String title;
  final String message;
  final AlertSeverity severity;
  final String source; // 'device', 'sensor', 'system'
  final String? deviceId;
  final bool isRead;
  final bool isDismissed;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;

  Alert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.source,
    this.deviceId,
    required this.isRead,
    required this.isDismissed,
    required this.createdAt,
    this.acknowledgedAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Alert',
      message: json['message'] ?? '',
      severity: _parseSeverity(json['severity']),
      source: json['source'] ?? 'system',
      deviceId: json['device_id'],
      isRead: json['is_read'] ?? false,
      isDismissed: json['is_dismissed'] ?? false,
      createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : DateTime.now(),
      acknowledgedAt: json['acknowledged_at'] != null
        ? DateTime.parse(json['acknowledged_at'])
        : null,
    );
  }

  static AlertSeverity _parseSeverity(dynamic value) {
    if (value == null) return AlertSeverity.low;
    final str = value.toString().toLowerCase();
    switch (str) {
      case 'critical':
        return AlertSeverity.critical;
      case 'high':
        return AlertSeverity.high;
      case 'medium':
        return AlertSeverity.medium;
      default:
        return AlertSeverity.low;
    }
  }

  @override
  String toString() => 'Alert(id: $id, title: $title, severity: $severity)';
}

/// Alert statistics
class AlertStats {
  final int total;
  final int unread;
  final int critical;
  final int high;
  final int medium;
  final int low;

  AlertStats({
    required this.total,
    required this.unread,
    required this.critical,
    required this.high,
    required this.medium,
    required this.low,
  });

  factory AlertStats.fromJson(Map<String, dynamic> json) {
    return AlertStats(
      total: json['total'] ?? 0,
      unread: json['unread'] ?? 0,
      critical: json['critical'] ?? 0,
      high: json['high'] ?? 0,
      medium: json['medium'] ?? 0,
      low: json['low'] ?? 0,
    );
  }
}

/// Alert Service - Manages all alert-related API calls
class AlertService extends ApiService {
  static final AlertService _instance = AlertService._internal();

  factory AlertService() {
    return _instance;
  }

  AlertService._internal();

  /// Create a new alert
  Future<ApiResponse<Alert>> createAlert({
    required String title,
    required String message,
    required String severity,
    required String source,
    String? deviceId,
  }) async {
    return postRequest(
      '/alerts/create',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return Alert.fromJson(data as Map<String, dynamic>);
      },
      body: {
        'title': title,
        'message': message,
        'severity': severity,
        'source': source,
        if (deviceId != null) 'device_id': deviceId,
      },
    );
  }

  /// Get all user alerts
  Future<ApiResponse<List<Alert>>> listAlerts({
    int limit = 50,
    int offset = 0,
    String? severity,
    bool onlyUnread = false,
  }) async {
    return getRequest(
      '/alerts/list',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => Alert.fromJson(item as Map<String, dynamic>))
            .toList();
      },
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (severity != null) 'severity': severity,
        if (onlyUnread) 'unread_only': 'true',
      },
    );
  }

  /// Get unread alerts count
  Future<ApiResponse<List<Alert>>> getUnreadAlerts() async {
    return getRequest(
      '/alerts/unread',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => Alert.fromJson(item as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Mark alert as read
  Future<ApiResponse<Alert>> markAlertAsRead(String alertId) async {
    return patchRequest(
      '/alerts/$alertId/read',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return Alert.fromJson(data as Map<String, dynamic>);
      },
    );
  }

  /// Dismiss alert
  Future<ApiResponse<Alert>> dismissAlert(String alertId) async {
    return patchRequest(
      '/alerts/$alertId/dismiss',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return Alert.fromJson(data as Map<String, dynamic>);
      },
    );
  }

  /// Mark all alerts as read
  Future<ApiResponse<Map<String, dynamic>>> markAllAlertsRead() async {
    return postRequest(
      '/alerts/mark-all-read',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }

  /// Get alert statistics
  Future<ApiResponse<AlertStats>> getAlertStatistics({
    int? daysBack,
  }) async {
    return getRequest(
      '/alerts/statistics',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid response');
        }
        return AlertStats.fromJson(data as Map<String, dynamic>);
      },
      queryParams: {
        if (daysBack != null) 'days_back': daysBack.toString(),
      },
    );
  }

  /// Clear old alerts
  Future<ApiResponse<Map<String, dynamic>>> clearOldAlerts({
    int daysOld = 30,
  }) async {
    return deleteRequest(
      '/alerts/clear-old',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }

  /// Resolve alert (mark as read and dismissed)
  Future<ApiResponse<Alert>> resolveAlert(String alertId) async {
    await markAlertAsRead(alertId);
    return dismissAlert(alertId);
  }
}

