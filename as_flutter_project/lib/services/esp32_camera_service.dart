import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Motion event model
class MotionEvent {
  final String id;
  final DateTime timestamp;
  final String imageUrl;
  final bool personDetected;
  final String? thumbnailUrl;
  final String? videoUrl;
  final String? clipPath;
  final int? frameCount;

  MotionEvent({
    required this.id,
    required this.timestamp,
    required this.imageUrl,
    required this.personDetected,
    this.thumbnailUrl,
    this.videoUrl,
    this.clipPath,
    this.frameCount,
  });

  factory MotionEvent.fromJson(Map<String, dynamic> json) {
    return MotionEvent(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      imageUrl: json['imageUrl'] ?? json['image_url'] ?? '',
      personDetected: json['personDetected'] ?? json['person_detected'] ?? false,
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail_url'],
      videoUrl: json['videoUrl'] ?? json['video_url'],
      clipPath: json['clipPath'] ?? json['clip_path'],
      frameCount: json['frameCount'] ?? json['frame_count'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'imageUrl': imageUrl,
    'personDetected': personDetected,
    'thumbnailUrl': thumbnailUrl,
    'videoUrl': videoUrl,
    'clipPath': clipPath,
    'frameCount': frameCount,
  };

  bool get hasVideoClip => (videoUrl != null && videoUrl!.isNotEmpty) ||
                           (clipPath != null && clipPath!.isNotEmpty);
}

/// Timelapse snapshot model
class TimelapseSnapshot {
  final String id;
  final DateTime timestamp;
  final String imageUrl;
  final String hour;

  TimelapseSnapshot({
    required this.id,
    required this.timestamp,
    required this.imageUrl,
    required this.hour,
  });

  factory TimelapseSnapshot.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'] != null
        ? DateTime.parse(json['timestamp'])
        : DateTime.now();
    return TimelapseSnapshot(
      id: json['id'] ?? '',
      timestamp: ts,
      imageUrl: json['imageUrl'] ?? json['image_url'] ?? '',
      hour: '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
    );
  }
}

/// Camera status model
class CameraStatus {
  final bool isConnected;
  final String? ip;
  final DateTime? lastSeen;
  final bool? isRecording;
  final int? dailyClips;
  final bool? sdCardReady;

  CameraStatus({
    required this.isConnected,
    this.ip,
    this.lastSeen,
    this.isRecording,
    this.dailyClips,
    this.sdCardReady,
  });
}

/// ESP32 Camera Service - Handles camera connection, streaming, and storage
class ESP32CameraService {
  static final ESP32CameraService _instance = ESP32CameraService._internal();
  factory ESP32CameraService() => _instance;
  ESP32CameraService._internal();

  // Stream controllers
  final _frameStreamController = StreamController<Uint8List>.broadcast();
  final _statusStreamController = StreamController<CameraStatus>.broadcast();
  final _motionStreamController = StreamController<bool>.broadcast();

  Stream<Uint8List> get frameStream => _frameStreamController.stream;
  Stream<CameraStatus> get statusStream => _statusStreamController.stream;
  Stream<bool> get motionStream => _motionStreamController.stream;

  // State
  String? _esp32Ip;
  bool _isConnected = false;
  bool _isStreaming = false;
  bool _motionDetected = false;
  Timer? _streamTimer;
  Timer? _timelapseTimer;
  Timer? _statusCheckTimer;
  StreamSubscription<DatabaseEvent>? _ipSubscription;

  // Getters
  String? get esp32Ip => _esp32Ip;
  bool get isConnected => _isConnected;
  bool get isStreaming => _isStreaming;
  bool get motionDetected => _motionDetected;

  /// Initialize the camera service
  Future<void> initialize() async {
    debugPrint('📷 Initializing ESP32 Camera Service...');
    _listenToIpChanges();
    await _fetchCurrentIp();
    _startStatusCheck();
    debugPrint('✅ ESP32 Camera Service initialized');
  }

  /// Listen to IP changes from Firebase
  void _listenToIpChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ No user logged in, skipping Firebase ESP32 listener');
      return;
    }

    final userRef = FirebaseDatabase.instance.ref().child('users/${user.uid}/esp32cam');

    _ipSubscription?.cancel();
    _ipSubscription = userRef.onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final newIp = data['ip'] as String?;
          final status = data['status'] as String?;

          if (newIp != null && newIp != _esp32Ip) {
            debugPrint('📡 ESP32-CAM IP updated: $newIp');
            _esp32Ip = newIp;
            _checkConnection();
          }

          _isConnected = status == 'online';
          _statusStreamController.add(CameraStatus(
            isConnected: _isConnected,
            ip: _esp32Ip,
            lastSeen: data['last_seen'] != null
                ? DateTime.tryParse(data['last_seen'])
                : null,
          ));
        } catch (e) {
          debugPrint('❌ Error parsing ESP32 data: $e');
        }
      }
    }, onError: (error) {
      if (error.toString().contains('permission-denied')) {
        debugPrint('⚠️ ESP32 Firebase path not set up yet');
      } else {
        debugPrint('❌ Firebase ESP32 listener error: $error');
      }
    });
  }

  /// Fetch current IP from Firebase
  Future<void> _fetchCurrentIp() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ No user logged in, skipping ESP32 IP fetch');
        return;
      }

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users/${user.uid}/esp32cam')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        _esp32Ip = data['ip'] as String?;
        _isConnected = data['status'] == 'online';

        if (_esp32Ip != null) {
          debugPrint('📡 ESP32-CAM IP from Firebase: $_esp32Ip');
          await _checkConnection();
        }
      } else {
        debugPrint('ℹ️ No ESP32-CAM configured yet');
      }
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        debugPrint('ℹ️ ESP32-CAM not configured for this user yet');
      } else {
        debugPrint('❌ Error fetching ESP32 IP: $e');
      }
    }
  }

  /// Check if ESP32-CAM is reachable
  Future<bool> _checkConnection() async {
    if (_esp32Ip == null) return false;

    try {
      final response = await http.get(
        Uri.parse('http://$_esp32Ip/status'),
      ).timeout(const Duration(seconds: 5));

      _isConnected = response.statusCode == 200;

      _statusStreamController.add(CameraStatus(
        isConnected: _isConnected,
        ip: _esp32Ip,
        lastSeen: DateTime.now(),
      ));

      return _isConnected;
    } catch (e) {
      debugPrint('⚠️ ESP32-CAM not reachable at $_esp32Ip: $e');
      _isConnected = false;
      _statusStreamController.add(CameraStatus(
        isConnected: false,
        ip: _esp32Ip,
        lastSeen: null,
      ));
      return false;
    }
  }

  /// Start periodic status check
  void _startStatusCheck() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkConnection();
    });
  }

  /// Start live streaming (3 fps)
  Future<void> startStreaming() async {
    if (_esp32Ip == null || _isStreaming) return;

    _isStreaming = true;
    debugPrint('▶️ Starting live stream from $_esp32Ip');

    _streamTimer = Timer.periodic(const Duration(milliseconds: 333), (_) async {
      await _captureFrame();
    });
  }

  /// Stop live streaming
  void stopStreaming() {
    _isStreaming = false;
    _streamTimer?.cancel();
    _streamTimer = null;
    debugPrint('⏹️ Live stream stopped');
  }

  /// Capture a single frame
  Future<Uint8List?> _captureFrame() async {
    if (_esp32Ip == null) return null;

    try {
      final response = await http.get(
        Uri.parse('http://$_esp32Ip/capture'),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final frame = response.bodyBytes;
        _frameStreamController.add(frame);

        final motionHeader = response.headers['x-motion-detected'];
        final personHeader = response.headers['x-person-detected'];

        final hasMotion = motionHeader == 'true' || personHeader == 'true';
        if (hasMotion != _motionDetected) {
          _motionDetected = hasMotion;
          _motionStreamController.add(hasMotion);

          if (hasMotion) {
            await _saveMotionEvent(frame, personHeader == 'true');
          }
        }

        return frame;
      }
    } catch (e) {
      debugPrint('⚠️ Frame capture error: $e');
    }
    return null;
  }

  /// Get single snapshot (for manual capture)
  Future<Uint8List?> captureSnapshot() async {
    if (_esp32Ip == null) return null;

    try {
      final response = await http.get(
        Uri.parse('http://$_esp32Ip/capture'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('❌ Snapshot capture error: $e');
    }
    return null;
  }

  /// Save motion event to Firebase
  Future<void> _saveMotionEvent(Uint8List imageData, bool personDetected) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final id = now.millisecondsSinceEpoch.toString();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('camera_snapshots')
          .child(user.uid)
          .child(dateStr)
          .child('motion')
          .child('$id.jpg');

      await storageRef.putData(imageData, SettableMetadata(contentType: 'image/jpeg'));
      final imageUrl = await storageRef.getDownloadURL();

      final dbRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('camera_events')
          .child(dateStr)
          .child('motion')
          .child(id);

      await dbRef.set({
        'id': id,
        'timestamp': now.toIso8601String(),
        'imageUrl': imageUrl,
        'personDetected': personDetected,
        'type': 'motion',
      });

      debugPrint('📸 Motion event saved: $id (person: $personDetected)');
    } catch (e) {
      debugPrint('❌ Error saving motion event: $e');
    }
  }

  /// Start timelapse capture (1 shot per minute)
  Future<void> startTimelapse() async {
    if (_esp32Ip == null) return;

    debugPrint('🕐 Starting timelapse capture (1/min)');

    _timelapseTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _captureTimelapseSnapshot();
    });

    await _captureTimelapseSnapshot();
  }

  /// Stop timelapse
  void stopTimelapse() {
    _timelapseTimer?.cancel();
    _timelapseTimer = null;
    debugPrint('🕐 Timelapse stopped');
  }

  /// Capture timelapse snapshot
  Future<void> _captureTimelapseSnapshot() async {
    try {
      final frame = await captureSnapshot();
      if (frame == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final id = now.millisecondsSinceEpoch.toString();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('camera_snapshots')
          .child(user.uid)
          .child(dateStr)
          .child('timelapse')
          .child('$id.jpg');

      await storageRef.putData(frame, SettableMetadata(contentType: 'image/jpeg'));
      final imageUrl = await storageRef.getDownloadURL();

      final dbRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('camera_events')
          .child(dateStr)
          .child('timelapse')
          .child(id);

      await dbRef.set({
        'id': id,
        'timestamp': now.toIso8601String(),
        'imageUrl': imageUrl,
        'type': 'timelapse',
      });

      debugPrint('📸 Timelapse snapshot saved: $id');
    } catch (e) {
      debugPrint('❌ Error saving timelapse: $e');
    }
  }

  /// Get available dates with camera events
  Future<List<DateTime>> getAvailableDates() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('camera_events')
          .get();

      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final dates = <DateTime>[];

      for (final dateStr in data.keys) {
        try {
          final parts = dateStr.split('-');
          if (parts.length == 3) {
            dates.add(DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            ));
          }
        } catch (e) {
          debugPrint('Error parsing date: $dateStr');
        }
      }

      dates.sort((a, b) => b.compareTo(a));
      return dates;
    } catch (e) {
      debugPrint('❌ Error getting available dates: $e');
      return [];
    }
  }

  /// Get motion events for a specific date
  Future<List<MotionEvent>> getMotionEvents(DateTime date) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('camera_events')
          .child(dateStr)
          .child('motion')
          .get();

      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final events = <MotionEvent>[];

      for (final entry in data.entries) {
        try {
          events.add(MotionEvent.fromJson(Map<String, dynamic>.from(entry.value)));
        } catch (e) {
          debugPrint('Error parsing motion event: $e');
        }
      }

      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return events;
    } catch (e) {
      debugPrint('❌ Error getting motion events: $e');
      return [];
    }
  }

  /// Get timelapse snapshots for a specific date
  Future<List<TimelapseSnapshot>> getTimelapseSnapshots(DateTime date) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid)
          .child('camera_events')
          .child(dateStr)
          .child('timelapse')
          .get();

      if (!snapshot.exists) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final snapshots = <TimelapseSnapshot>[];

      for (final entry in data.entries) {
        try {
          snapshots.add(TimelapseSnapshot.fromJson(Map<String, dynamic>.from(entry.value)));
        } catch (e) {
          debugPrint('Error parsing timelapse snapshot: $e');
        }
      }

      snapshots.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return snapshots;
    } catch (e) {
      debugPrint('❌ Error getting timelapse snapshots: $e');
      return [];
    }
  }

  /// Manually set ESP32-CAM IP
  Future<void> setManualIp(String ip) async {
    _esp32Ip = ip;
    debugPrint('📡 Setting manual IP: $ip');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseDatabase.instance
            .ref()
            .child('users/${user.uid}/esp32cam')
            .update({
          'ip': ip,
          'status': 'online',
          'last_seen': DateTime.now().toIso8601String(),
          'manual_set': true,
        });
        debugPrint('✅ IP saved to Firebase: users/${user.uid}/esp32cam');
      }
    } catch (e) {
      debugPrint('❌ Error saving manual IP to Firebase: $e');
    }

    await _checkConnection();
  }

  /// Cleanup old recordings (older than 7 days)
  Future<void> cleanupOldRecordings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
      final dates = await getAvailableDates();

      for (final date in dates) {
        if (date.isBefore(cutoffDate)) {
          final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

          await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child(user.uid)
              .child('camera_events')
              .child(dateStr)
              .remove();

          debugPrint('🗑️ Cleaned up recordings for $dateStr');
        }
      }
    } catch (e) {
      debugPrint('❌ Error cleaning up old recordings: $e');
    }
  }

  /// Run diagnostics
  Future<Map<String, dynamic>> runDiagnostics() async {
    final results = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'configured_ip': _esp32Ip,
      'tests': <String, dynamic>{},
    };

    if (_esp32Ip == null || _esp32Ip!.isEmpty) {
      results['error'] = 'No IP address configured';
      results['suggestion'] = 'Set the ESP32-CAM IP address first';
      return results;
    }

    debugPrint('🔍 Running camera diagnostics for $_esp32Ip...');

    // Test 1: Status endpoint
    try {
      final statusResponse = await http.get(
        Uri.parse('http://$_esp32Ip/status'),
      ).timeout(const Duration(seconds: 10));

      results['tests']['status_endpoint'] = {
        'success': statusResponse.statusCode == 200,
        'status_code': statusResponse.statusCode,
      };
    } catch (e) {
      results['tests']['status_endpoint'] = {
        'success': false,
        'error': e.toString(),
      };
    }

    // Test 2: Capture endpoint
    try {
      final captureResponse = await http.get(
        Uri.parse('http://$_esp32Ip/capture'),
      ).timeout(const Duration(seconds: 10));

      results['tests']['capture_endpoint'] = {
        'success': captureResponse.statusCode == 200,
        'status_code': captureResponse.statusCode,
        'size_bytes': captureResponse.bodyBytes.length,
      };
    } catch (e) {
      results['tests']['capture_endpoint'] = {
        'success': false,
        'error': e.toString(),
      };
    }

    // Overall assessment
    final allTests = results['tests'] as Map<String, dynamic>;
    final passedTests = allTests.values.where((t) => t['success'] == true).length;
    final totalTests = allTests.length;

    results['summary'] = {
      'passed': passedTests,
      'total': totalTests,
      'all_passed': passedTests == totalTests,
    };

    if (passedTests == 0) {
      results['diagnosis'] = 'UNREACHABLE';
      results['suggestions'] = [
        'Make sure phone is on same WiFi as ESP32-CAM',
        'Check if ESP32-CAM IP is correct: $_esp32Ip',
        'Try accessing http://$_esp32Ip in phone browser',
        'Check if router has AP Isolation enabled - disable it',
      ];
    } else if (passedTests < totalTests) {
      results['diagnosis'] = 'PARTIAL';
      results['suggestions'] = ['Some endpoints working. Try restarting camera.'];
    } else {
      results['diagnosis'] = 'OK';
      results['suggestions'] = ['Camera is reachable and responding.'];
    }

    return results;
  }

  /// Download full clip frames
  Future<List<Uint8List>> downloadFullClip(String clipPath, int frameCount) async {
    final frames = <Uint8List>[];
    if (_esp32Ip == null) return frames;

    for (int i = 0; i < frameCount; i++) {
      try {
        final frameName = 'frame_${i.toString().padLeft(3, '0')}.jpg';
        final path = '$clipPath/$frameName';

        final response = await http.get(
          Uri.parse('http://$_esp32Ip/clip?path=$path'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          frames.add(response.bodyBytes);
        }

        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        debugPrint('❌ Error downloading frame $i: $e');
      }
    }

    return frames;
  }

  /// Dispose resources
  void dispose() {
    stopStreaming();
    stopTimelapse();
    _statusCheckTimer?.cancel();
    _ipSubscription?.cancel();
    _frameStreamController.close();
    _statusStreamController.close();
    _motionStreamController.close();
  }
}

