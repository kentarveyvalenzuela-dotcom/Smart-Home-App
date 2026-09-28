// filepath: c:\Users\Ivy\OneDrive\Desktop\New folder\brix\as_flutter_project\lib\services\connectivity_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service to monitor network connectivity status
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final _statusController = StreamController<ConnectivityStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityStatus _currentStatus = ConnectivityStatus.unknown;

  /// Stream of connectivity status changes
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  /// Current connectivity status
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Check if currently online
  bool get isOnline => _currentStatus == ConnectivityStatus.online;

  /// Initialize the service
  Future<void> initialize() async {
    debugPrint('📡 Initializing Connectivity Service...');

    // Check initial status
    await checkConnectivity();

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });

    debugPrint('✅ Connectivity Service initialized: $_currentStatus');
  }

  /// Check current connectivity
  Future<ConnectivityStatus> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _updateStatus(results);
    } catch (e) {
      debugPrint('❌ Error checking connectivity: $e');
      return ConnectivityStatus.unknown;
    }
  }

  ConnectivityStatus _updateStatus(List<ConnectivityResult> results) {
    ConnectivityStatus newStatus;

    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      newStatus = ConnectivityStatus.offline;
    } else if (results.contains(ConnectivityResult.wifi)) {
      newStatus = ConnectivityStatus.online;
    } else if (results.contains(ConnectivityResult.mobile)) {
      newStatus = ConnectivityStatus.online;
    } else if (results.contains(ConnectivityResult.ethernet)) {
      newStatus = ConnectivityStatus.online;
    } else {
      newStatus = ConnectivityStatus.unknown;
    }

    if (newStatus != _currentStatus) {
      _currentStatus = newStatus;
      _statusController.add(newStatus);
      debugPrint('📡 Connectivity changed: $newStatus');
    }

    return newStatus;
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}

enum ConnectivityStatus {
  online,
  offline,
  unknown,
}

/// Mixin for widgets that need connectivity awareness
mixin ConnectivityAware<T extends StatefulWidget> on State<T> {
  late final ConnectivityService _connectivityService;
  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  ConnectivityStatus _connectivityStatus = ConnectivityStatus.unknown;

  ConnectivityStatus get connectivityStatus => _connectivityStatus;
  bool get isOnline => _connectivityStatus == ConnectivityStatus.online;

  @override
  void initState() {
    super.initState();
    _connectivityService = ConnectivityService();
    _connectivityStatus = _connectivityService.currentStatus;

    _connectivitySub = _connectivityService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _connectivityStatus = status);
        onConnectivityChanged(status);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Override this to handle connectivity changes
  void onConnectivityChanged(ConnectivityStatus status) {}
}
