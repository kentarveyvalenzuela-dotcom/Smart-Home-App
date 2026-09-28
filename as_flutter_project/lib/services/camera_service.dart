import 'dart:async';
import 'api_service.dart';

/// Camera image model
/// Camera info model for live camera listing
class CameraInfo {
  final String id;
  final String name;
  final String ip;
  final String streamUrl;
  final String status; // 'online', 'offline'
  final DateTime? lastSeen;

  CameraInfo({
    required this.id,
    required this.name,
    required this.ip,
    required this.streamUrl,
    required this.status,
    this.lastSeen,
  });

  factory CameraInfo.fromJson(Map<String, dynamic> json) {
    return CameraInfo(
      id: json['id'] ?? json['device_id'] ?? '',
      name: json['name'] ?? json['device_name'] ?? 'Unknown Camera',
      ip: json['ip'] ?? json['ip_address'] ?? '',
      streamUrl: json['stream_url'] ?? json['streamUrl'] ?? '',
      status: json['status'] ?? (json['is_online'] == true ? 'online' : 'offline'),
      lastSeen: json['last_seen'] != null
        ? DateTime.tryParse(json['last_seen'].toString())
        : null,
    );
  }
}

        ? DateTime.parse(json['uploaded_at'])
        : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'CameraImage(deviceId: $deviceId, size: $fileSize bytes)';
}

/// Camera streaming info
class CameraStreamInfo {
  final String deviceId;
  final String streamUrl;
  final String streamType; // 'mjpeg', 'h264', 'webrtc'
  final bool isStreaming;
  final DateTime? lastFrameTime;
  final int? frameRate;

  CameraStreamInfo({
    required this.deviceId,
    required this.streamUrl,
    required this.streamType,
    required this.isStreaming,
    this.lastFrameTime,
    this.frameRate,
  });

  factory CameraStreamInfo.fromJson(Map<String, dynamic> json) {
    return CameraStreamInfo(
      deviceId: json['device_id'] ?? '',
      streamUrl: json['stream_url'] ?? '',
      streamType: json['stream_type'] ?? 'mjpeg',
      isStreaming: json['is_streaming'] ?? false,
      lastFrameTime: json['last_frame_time'] != null
        ? DateTime.parse(json['last_frame_time'])
        : null,
      frameRate: json['frame_rate'],
    );
  }
}

/// Camera Service - Manages ESP32-CAM image and stream operations
class CameraService extends ApiService {
  static final CameraService _instance = CameraService._internal();

  factory CameraService() {
    return _instance;
  }

  CameraService._internal();

  /// Get all camera images (gallery)
  Future<ApiResponse<List<CameraImage>>> getCameraImages({
    String? deviceId,
    int limit = 50,
    int offset = 0,
  }) async {
    return getRequest(
      '/camera/images/json',
      parser: (data) {
        if (data == null || data is! List) return [];
        return (data as List)
            .map((item) => CameraImage.fromJson(item as Map<String, dynamic>))
            .toList();
      },
      queryParams: {
        if (deviceId != null) 'device_id': deviceId,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
  }

  /// Get latest image from camera
  Future<ApiResponse<CameraImage>> getLatestImage(String deviceId) async {
    return getRequest(
      '/camera/device/$deviceId/latest',
      parser: (data) {
        if (data == null || data is! Map) {
          throw Exception('Invalid camera data');
        }
        return CameraImage.fromJson(data as Map<String, dynamic>);
      },
    );
  // Stream controller for cameras list
  final _camerasController = StreamController<List<CameraInfo>>.broadcast();
  List<CameraInfo> _cameras = [];
  Timer? _refreshTimer;

  /// Stream of cameras for UI listening
  Stream<List<CameraInfo>> get camerasStream => _camerasController.stream;

  /// Current list of cameras
  List<CameraInfo> get cameras => _cameras;

  /// Initialize camera service and start polling for cameras
  @override
  Future<void> initialize() async {
    await super.initialize();
    _startCameraPolling();
  }

  void _startCameraPolling() {
    // Fetch cameras immediately
    _fetchCameras();
    // Then poll every 10 seconds
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchCameras();
    });
  }

  Future<void> _fetchCameras() async {
    try {
      final response = await getRequest<List<CameraInfo>>(
        '/camera/devices',
        parser: (data) {
          if (data == null || data is! List) return <CameraInfo>[];
          return (data as List)
              .map((item) => CameraInfo.fromJson(item as Map<String, dynamic>))
              .toList();
        },
      );
      if (response.success && response.data != null) {
        _cameras = response.data!;
        _camerasController.add(_cameras);
      }
    } catch (e) {
      debugPrint('Error fetching cameras: $e');
    }
  }

  /// Refresh cameras list manually
  Future<void> refreshCameras() async {
    await _fetchCameras();
  }

  /// Dispose resources
  void dispose() {
    _refreshTimer?.cancel();
    _camerasController.close();
  }


  /// Delete camera image
  Future<ApiResponse<Map<String, dynamic>>> deleteImage(String imageId) async {
    return deleteRequest(
      '/camera/images/$imageId',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }

  /// Get camera statistics
  Future<ApiResponse<Map<String, dynamic>>> getCameraStats({
    String? deviceId,
    int daysBack = 7,
  }) async {
    return getRequest(
      '/camera/statistics',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
      queryParams: {
        if (deviceId != null) 'device_id': deviceId,
        'days_back': daysBack.toString(),
      },
    );
  }

  /// Get camera settings
  Future<ApiResponse<Map<String, dynamic>>> getCameraSettings(String deviceId) async {
    return getRequest(
      '/camera/device/$deviceId/settings',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }

  /// Update camera settings
  Future<ApiResponse<Map<String, dynamic>>> updateCameraSettings(
    String deviceId, {
    int? frameRate,
    String? resolution,
    int? quality,
    Map<String, dynamic>? otherSettings,
  }) async {
    return patchRequest(
      '/camera/device/$deviceId/settings',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
      body: {
        if (frameRate != null) 'frame_rate': frameRate,
        if (resolution != null) 'resolution': resolution,
        if (quality != null) 'quality': quality,
        if (otherSettings != null) ...otherSettings,
      },
    );
  }

  /// Clear all camera images
  Future<ApiResponse<Map<String, dynamic>>> clearCameraImages({
    String? deviceId,
    int? daysOld,
  }) async {
    return deleteRequest(
      '/camera/clear',
      parser: (data) {
        return data is Map ? data as Map<String, dynamic> : {};
      },
    );
  }
}

