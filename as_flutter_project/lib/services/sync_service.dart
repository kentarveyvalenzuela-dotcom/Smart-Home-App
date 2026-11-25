import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'config_service.dart';

class SyncService {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  late final ApiService _apiService;

  final List<Map<String, dynamic>> _offlineQueue = [];
  bool _isOnline = true;
  Timer? _retryTimer;

  Function(bool)? onConnectivityChange;
  Function(int)? onQueueSizeChange;

  SyncService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? ConfigService().backendUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    _apiService = ApiService(client: _client, baseUrl: this.baseUrl);
    _startRetryTimer();
  }

  bool get isOnline => _isOnline;
  int get queueSize => _offlineQueue.length;

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_offlineQueue.isNotEmpty) _processOfflineQueue();
    });
  }

  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    final itemsToRetry = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final item in itemsToRetry) {
      final success = await pushAppliances(
        item['data'] as List<Map<String, dynamic>>,
      );
      if (!success) _offlineQueue.add(item);
    }

    onQueueSizeChange?.call(_offlineQueue.length);
  }

  void _addToOfflineQueue(List<Map<String, dynamic>> appliances) {
    _offlineQueue.add({
      'timestamp': DateTime.now().toIso8601String(),
      'data': appliances,
    });
    onQueueSizeChange?.call(_offlineQueue.length);
  }

  Future<bool> pushAppliances(List<Map<String, dynamic>> appliances) async {
    try {
      final response = await _apiService.putRequest<dynamic>(
        '/api/appliances',
        includeAuth: false,
        body: {'items': appliances},
        parser: (data) => data,
      );
      final success = response.success;

      if (success && !_isOnline) {
        _isOnline = true;
        onConnectivityChange?.call(true);
        _processOfflineQueue();
      }
      return success;
    } catch (e) {
      debugPrint('Push failed: $e');
      if (_isOnline) {
        _isOnline = false;
        onConnectivityChange?.call(false);
      }
      _addToOfflineQueue(appliances);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> pullDevices({
    required String authToken,
  }) async {
    try {
      debugPrint('Pulling devices from $baseUrl/devices/list');
      debugPrint('Auth token length: ${authToken.length}');

      final response = await _apiService.getRequest<dynamic>(
        '/devices/list',
        authorizationToken: authToken,
        parser: (data) => data,
      );

      if (response.statusCode == 200) {
        if (!_isOnline) {
          _isOnline = true;
          onConnectivityChange?.call(true);
        }

        final data = response.data;
        final List deviceList = data is List ? data : (data['devices'] ?? []);

        return deviceList.map((device) {
          final mqttId = device['mqtt_client_id'] ?? device['device_id'] ?? '';
          return {
            'device_id': mqttId,
            'backend_device_id':
                device['id']?.toString() ?? device['backend_device_id'] ?? '',
            'name': device['device_name'] ?? device['name'] ?? 'Unknown Device',
            'isOn': false,
            'mqtt_client_id': mqttId,
            'topic': 'home/device/$mqttId',
            'pin': device['pin'] ?? 23,
            'location': device['location'] ?? '',
            'is_online': device['is_online'] ?? false,
            'last_seen': device['last_seen'],
          };
        }).toList();
      }

      return null;
    } catch (e) {
      debugPrint('Pull devices error: $e');
      if (_isOnline) {
        _isOnline = false;
        onConnectivityChange?.call(false);
      }
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> pullAppliances() async {
    try {
      final response = await _apiService.getRequest<dynamic>(
        '/api/appliances',
        includeAuth: false,
        parser: (data) => data,
      );

      if (response.statusCode == 200) {
        if (!_isOnline) {
          _isOnline = true;
          onConnectivityChange?.call(true);
          _processOfflineQueue();
        }

        final data = response.data;
        final List items = (data is Map && data['items'] is List)
            ? data['items'] as List
            : (data as List);
        return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return null;
    } catch (e) {
      debugPrint('Pull failed: $e');
      if (_isOnline) {
        _isOnline = false;
        onConnectivityChange?.call(false);
      }
      return null;
    }
  }

  void dispose() {
    _retryTimer?.cancel();
    if (_ownsClient) _apiService.close();
  }
}
