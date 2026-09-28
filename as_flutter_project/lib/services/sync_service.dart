import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'config_service.dart';

class SyncService {
  final String baseUrl;
  final http.Client _client;
  
  // Offline queue management
  final List<Map<String, dynamic>> _offlineQueue = [];
  bool _isOnline = true;
  Timer? _retryTimer;
  
  // Callbacks for status updates
  Function(bool)? onConnectivityChange;
  Function(int)? onQueueSizeChange;

  // baseUrl is optional; if not provided, use ConfigService().backendUrl (production)
  SyncService({String? baseUrl, http.Client? client}) : baseUrl = baseUrl ?? ConfigService().backendUrl, _client = client ?? http.Client() {
    _startRetryTimer();
  }

  bool get isOnline => _isOnline;
  int get queueSize => _offlineQueue.length;

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_offlineQueue.isNotEmpty) {
        _processOfflineQueue();
      }
    });
  }

  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;
    
    debugPrint('🔄 Processing offline queue: ${_offlineQueue.length} items');
    
    final itemsToRetry = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();
    
    for (final item in itemsToRetry) {
      final success = await pushAppliances(item['data'] as List<Map<String, dynamic>>);
      if (!success) {
        _offlineQueue.add(item);
      }
    }
    
    onQueueSizeChange?.call(_offlineQueue.length);
    debugPrint('✅ Queue processed. Remaining: ${_offlineQueue.length}');
  }

  void _addToOfflineQueue(List<Map<String, dynamic>> appliances) {
    _offlineQueue.add({
      'timestamp': DateTime.now().toIso8601String(),
      'data': appliances,
    });
    onQueueSizeChange?.call(_offlineQueue.length);
    debugPrint('📦 Added to offline queue. Total: ${_offlineQueue.length}');
  }

  // Push full appliances snapshot to backend
  Future<bool> pushAppliances(List<Map<String, dynamic>> appliances) async {
    try {
      final uri = Uri.parse('$baseUrl/api/appliances');
      final resp = await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'items': appliances}),
      ).timeout(const Duration(seconds: 10));
      
      final success = resp.statusCode >= 200 && resp.statusCode < 300;
      
      if (success && !_isOnline) {
        _isOnline = true;
        onConnectivityChange?.call(true);
        debugPrint('✅ Back online!');
        _processOfflineQueue();
      }
      
      return success;
    } catch (e) {
      debugPrint('❌ Push failed: $e');
      
      if (_isOnline) {
        _isOnline = false;
        onConnectivityChange?.call(false);
        debugPrint('📡 Went offline');
      }
      
      _addToOfflineQueue(appliances);
      return false;
    }
  }

  // ✅ NEW: Pull devices from backend (using real backend API)
  Future<List<Map<String, dynamic>>?> pullDevices({required String authToken}) async {
    try {
      final uri = Uri.parse('$baseUrl/devices/list');
      debugPrint('📡 Pulling devices from: $uri');
      debugPrint('🔑 Auth token length: ${authToken.length}');
      
      final resp = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('📊 Response status: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        debugPrint('📄 Response body: ${resp.body}');
      }
      
      if (resp.statusCode == 200) {
        if (!_isOnline) {
          _isOnline = true;
          onConnectivityChange?.call(true);
          debugPrint('✅ Back online!');
        }
        
        final data = json.decode(resp.body);
        final List deviceList = data['devices'] ?? [];
        
        debugPrint('✅ Got ${deviceList.length} devices from backend');
        
        // Convert to appliance format
        return deviceList.map((device) {
          final mqttId = device['mqtt_client_id'] ?? device['device_id'] ?? '';
          return {
            'device_id': mqttId,  // Use mqtt_client_id as device_id for MQTT control
            'backend_device_id': device['device_id'] ?? '',  // Keep Firebase ID for backend calls
            'name': device['device_name'] ?? 'Unknown Device',
            'isOn': false,
            'mqtt_client_id': mqttId,
            'topic': 'home/device/$mqttId',  // ✅ FIXED: Use correct topic format
            'pin': device['pin'] ?? 23, // Default pin
            'location': device['location'] ?? '',
            'is_online': device['is_online'] ?? false,
            'last_seen': device['last_seen'],
          };
        }).toList();
      }
      
      debugPrint('❌ Pull devices failed: HTTP ${resp.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ Pull devices error: $e');
      debugPrint('💭 This might be a CORS issue or network problem');
      
      if (_isOnline) {
        _isOnline = false;
        onConnectivityChange?.call(false);
        debugPrint('📡 Went offline');
      }
      
      return null;
    }
  }

  // Pull appliances from backend (authoritative) - OLD METHOD (DEPRECATED)
  Future<List<Map<String, dynamic>>?> pullAppliances() async {
    try {
      final uri = Uri.parse('$baseUrl/api/appliances');
      final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
      
      if (resp.statusCode == 200) {
        if (!_isOnline) {
          _isOnline = true;
          onConnectivityChange?.call(true);
          debugPrint('✅ Back online!');
          _processOfflineQueue();
        }
        
        final data = jsonDecode(resp.body);
        final List items = (data is Map && data['items'] is List) ? data['items'] as List : (data as List);
        return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return null;
    } catch (e) {
      debugPrint('❌ Pull failed: $e');
      
      if (_isOnline) {
        _isOnline = false;
        onConnectivityChange?.call(false);
        debugPrint('📡 Went offline');
      }
      
      return null;
    }
  }
  
  void dispose() {
    _retryTimer?.cancel();
  }
}
