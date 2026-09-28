// filepath: c:\Users\Ivy\OneDrive\Desktop\New folder\brix\as_flutter_project\lib\screens\monitor_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/esp32_camera_service.dart';
import '../main.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep this page alive when switching tabs

  final ESP32CameraService _cameraService = ESP32CameraService();

  // State
  Uint8List? _currentFrame;
  bool _isConnected = false;
  bool _isStreaming = false;
  bool _motionDetected = false;
  String? _cameraIp;
  DateTime? _lastSeen;
  List<MotionEvent> _motionEvents = [];
  List<TimelapseSnapshot> _timelapseSnapshots = [];
  List<DateTime> _availableDates = [];
  DateTime _selectedDate = DateTime.now();
  bool _isLoadingEvents = false;

  // Motion auto-reset timer
  Timer? _motionResetTimer;

  // Video playback
  bool _isPlayingVideo = false;
  String? _currentVideoUrl;
  MotionEvent? _selectedClip;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _borderController;
  late Animation<Color?> _borderColorAnimation;

  // Subscriptions
  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<CameraStatus>? _statusSub;
  StreamSubscription<bool>? _motionSub;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();
  }

  void _initAnimations() {
    // Pulse animation for live indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Border color animation for motion detection - FAST response (200ms)
    _borderController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _borderColorAnimation = ColorTween(
      begin: AppColors.electricGreen,
      end: AppColors.error,
    ).animate(CurvedAnimation(parent: _borderController, curve: Curves.easeInOut));
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();

    // Listen to frame updates
    _frameSub = _cameraService.frameStream.listen((frame) {
      if (mounted) {
        setState(() => _currentFrame = frame);
      }
    });

    // Listen to status updates
    _statusSub = _cameraService.statusStream.listen((status) {
      if (mounted) {
        final wasConnected = _isConnected;
        setState(() {
          _isConnected = status.isConnected;
          _cameraIp = status.ip;
          _lastSeen = status.lastSeen;
        });

        // Auto-start streaming when camera becomes connected
        if (!wasConnected && status.isConnected && !_isStreaming) {
          debugPrint('📹 Camera connected! Auto-starting stream...');
          _startStreaming();
        }
      }
    });

    // Listen to motion detection with auto-reset
    _motionSub = _cameraService.motionStream.listen((hasMotion) {
      if (mounted) {
        // Cancel any existing reset timer
        _motionResetTimer?.cancel();

        setState(() => _motionDetected = hasMotion);

        if (hasMotion) {
          // Motion detected - turn RED immediately
          _borderController.forward();

          // Auto-reset to GREEN after 3 seconds if no new motion
          _motionResetTimer = Timer(const Duration(seconds: 3), () {
            if (mounted && _motionDetected) {
              setState(() => _motionDetected = false);
              _borderController.reverse();
            }
          });
        } else {
          // No motion - turn GREEN immediately
          _borderController.reverse();
        }
      }
    });

    // Load initial data
    await _loadAvailableDates();
    await _loadEventsForDate(_selectedDate);

    // Start streaming if connected
    if (_cameraService.isConnected) {
      _startStreaming();
    }
  }

  Future<void> _loadAvailableDates() async {
    final dates = await _cameraService.getAvailableDates();
    if (mounted) {
      setState(() => _availableDates = dates);
    }
  }

  Future<void> _loadEventsForDate(DateTime date) async {
    setState(() => _isLoadingEvents = true);

    final motionEvents = await _cameraService.getMotionEvents(date);
    final timelapseSnapshots = await _cameraService.getTimelapseSnapshots(date);

    if (mounted) {
      setState(() {
        _motionEvents = motionEvents;
        _timelapseSnapshots = timelapseSnapshots;
        _isLoadingEvents = false;
      });
    }
  }

  void _startStreaming() {
    _cameraService.startStreaming();
    _cameraService.startTimelapse();
    setState(() => _isStreaming = true);
  }

  void _stopStreaming() {
    _cameraService.stopStreaming();
    setState(() => _isStreaming = false);
  }

  @override
  void dispose() {
    _motionResetTimer?.cancel();
    _pulseController.dispose();
    _borderController.dispose();
    _frameSub?.cancel();
    _statusSub?.cancel();
    _motionSub?.cancel();
    _cameraService.stopStreaming();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
            ? [AppColors.darkBg, AppColors.darkBgSecondary]
            : [AppColors.lightBg, Colors.white],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadAvailableDates();
          await _loadEventsForDate(_selectedDate);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Camera View
              _buildLiveCameraView(isDark),

              // Camera Status & Controls
              _buildCameraControls(isDark),

              // Date Selector
              _buildDateSelector(isDark),

              // Timeline Section
              _buildTimelineSection(isDark),

              // Motion Events
              _buildMotionEventsSection(isDark),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveCameraView(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (_motionDetected ? AppColors.error : AppColors.electricGreen)
                .withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _borderColorAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _borderColorAnimation.value ?? AppColors.electricGreen,
                width: 4,
              ),
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera Feed or Placeholder
                _currentFrame != null
                    ? Image.memory(
                        _currentFrame!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        color: isDark ? AppColors.darkBgCard : Colors.grey.shade200,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isConnected ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                              size: 60,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isConnected ? 'Connecting to camera...' : 'Camera Offline',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 16,
                              ),
                            ),
                            if (_cameraIp != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'IP: $_cameraIp',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                // Live Indicator
                Positioned(
                  top: 12,
                  left: 12,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isStreaming ? _pulseAnimation.value : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isStreaming
                                ? AppColors.error.withOpacity(0.9)
                                : Colors.grey.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _isStreaming ? Colors.white : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isStreaming ? 'LIVE' : 'OFFLINE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Motion Detection Badge
                if (_motionDetected)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'PERSON DETECTED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Timestamp
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      DateFormat('HH:mm:ss').format(DateTime.now()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraControls(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBgCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Connection Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_isConnected ? AppColors.electricGreen : AppColors.error)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: _isConnected ? AppColors.electricGreen : AppColors.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isConnected ? 'Camera Connected' : 'Camera Disconnected',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppColors.darkBg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _cameraIp != null ? 'IP: $_cameraIp' : 'No camera found',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Stream Toggle Button
                ElevatedButton.icon(
                  onPressed: _isConnected
                      ? () {
                          if (_isStreaming) {
                            _stopStreaming();
                          } else {
                            _startStreaming();
                          }
                        }
                      : null,
                  icon: Icon(_isStreaming ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(_isStreaming ? 'Stop' : 'Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStreaming ? AppColors.error : AppColors.electricGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Snapshot',
                    onTap: () async {
                      final frame = await _cameraService.captureSnapshot();
                      if (frame != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('📸 Snapshot captured!'),
                            backgroundColor: AppColors.electricGreen,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    },
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.settings_rounded,
                    label: 'Set IP',
                    onTap: () => _showSetIpDialog(isDark),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Cleanup',
                    onTap: () async {
                      await _cameraService.cleanupOldRecordings();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('🗑️ Old recordings cleaned up'),
                            backgroundColor: AppColors.primaryBlue,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    },
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: isDark ? AppColors.darkBg : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recordings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.darkBg,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: _availableDates.isEmpty
                ? Center(
                    child: Text(
                      'No recordings yet',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableDates.length,
                    itemBuilder: (context, index) {
                      final date = _availableDates[index];
                      final isSelected = _isSameDay(date, _selectedDate);
                      final isToday = _isSameDay(date, DateTime.now());

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedDate = date);
                          _loadEventsForDate(date);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [AppColors.primaryBlue, AppColors.electricPurple],
                                  )
                                : null,
                            color: isSelected ? null : (isDark ? AppColors.darkBgCard : Colors.white),
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? null
                                : Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isToday ? 'Today' : DateFormat('EEE').format(date),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? Colors.white70 : Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                DateFormat('d MMM').format(date),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? Colors.white : AppColors.darkBg),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '24h Timelapse',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.darkBg,
                ),
              ),
              if (_timelapseSnapshots.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showTimelapsePlayer(isDark),
                  icon: const Icon(Icons.play_circle_rounded, size: 20),
                  label: const Text('Play All'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBgCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: _isLoadingEvents
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _timelapseSnapshots.isEmpty
                    ? Center(
                        child: Text(
                          'No timelapse for this day',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        ),
                      )
                    : _buildTimelineBar(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineBar(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Stack(
          children: [
            // Hour markers
            ...List.generate(24, (hour) {
              final x = (hour / 24) * width;
              return Positioned(
                left: x,
                bottom: 0,
                child: Container(
                  width: 1,
                  height: hour % 6 == 0 ? 12 : 6,
                  color: Colors.grey.withOpacity(0.3),
                ),
              );
            }),

            // Motion events markers (red dots)
            ..._motionEvents.map((event) {
              final hour = event.timestamp.hour + (event.timestamp.minute / 60);
              final x = (hour / 24) * width;
              return Positioned(
                left: x - 4,
                top: 20,
                child: GestureDetector(
                  onTap: () => _showEventImage(event, isDark),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: event.personDetected ? AppColors.error : AppColors.warning,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (event.personDetected ? AppColors.error : AppColors.warning)
                              .withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            // Time labels
            Positioned(
              left: 8,
              bottom: 4,
              child: Text('00:00', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ),
            Positioned(
              left: width / 2 - 12,
              bottom: 4,
              child: Text('12:00', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ),
            Positioned(
              right: 8,
              bottom: 4,
              child: Text('24:00', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ),

            // Legend
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Person', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Motion', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMotionEventsSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Motion Events (${_motionEvents.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.darkBg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _isLoadingEvents
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _motionEvents.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBgCard : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.motion_photos_off_rounded,
                                size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'No motion events for this day',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: _motionEvents.length > 9 ? 9 : _motionEvents.length,
                      itemBuilder: (context, index) {
                        final event = _motionEvents[index];
                        return _buildMotionEventTile(event, isDark);
                      },
                    ),

          if (_motionEvents.length > 9)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () => _showAllMotionEvents(isDark),
                  child: Text('View all ${_motionEvents.length} events'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMotionEventTile(MotionEvent event, bool isDark) {
    return GestureDetector(
      onTap: () => _showEventImage(event, isDark),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: event.personDetected
                ? AppColors.error.withOpacity(0.5)
                : Colors.grey.withOpacity(0.3),
            width: event.personDetected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              Image.network(
                event.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image_rounded),
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: isDark ? AppColors.darkBgCard : Colors.grey.shade200,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),

              // Time badge
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    DateFormat('HH:mm').format(event.timestamp),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // Person detected badge
              if (event.personDetected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSetIpDialog(bool isDark) {
    final controller = TextEditingController(text: _cameraIp ?? '');
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set Camera IP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter ESP32-CAM IP address manually if auto-detection fails.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'IP Address',
                  hintText: '192.168.1.100',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                keyboardType: TextInputType.number,
                enabled: !isLoading,
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure your phone is on the same WiFi network as the ESP32-CAM.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                final ip = controller.text.trim();
                if (ip.isNotEmpty) {
                  setDialogState(() => isLoading = true);

                  debugPrint('🔧 Setting camera IP to: $ip');
                  await _cameraService.setManualIp(ip);

                  // Wait a bit for connection check
                  await Future.delayed(const Duration(milliseconds: 500));

                  if (mounted) {
                    Navigator.pop(context);

                    final connected = _cameraService.isConnected;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(connected
                          ? '✅ Camera connected at $ip'
                          : '⚠️ IP set to $ip but camera not reachable'),
                        backgroundColor: connected ? AppColors.electricGreen : AppColors.warning,
                        duration: const Duration(seconds: 3),
                      ),
                    );

                    // Auto-start streaming if connected
                    if (connected && !_isStreaming) {
                      _startStreaming();
                    }
                  }
                }
              },
              child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                  )
                : const Text('Set IP'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEventImage(MotionEvent event, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image/Video Container
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Image
                    Image.network(
                      event.imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 300,
                          height: 225,
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        width: 300,
                        height: 225,
                        color: Colors.grey.shade800,
                        child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.white54, size: 50),
                        ),
                      ),
                    ),

                    // Play button overlay (if video clip exists)
                    if (event.videoUrl != null && event.videoUrl!.isNotEmpty)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              _playMotionClip(event);
                            },
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Close button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Info bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBgCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Event type icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (event.personDetected ? AppColors.error : AppColors.warning).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      event.personDetected ? Icons.person_rounded : Icons.motion_photos_on_rounded,
                      color: event.personDetected ? AppColors.error : AppColors.warning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Event info
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.personDetected ? 'Person Detected' : 'Motion Detected',
                        style: TextStyle(
                          color: isDark ? Colors.white : AppColors.darkBg,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM d, yyyy • HH:mm:ss').format(event.timestamp),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  // Video indicator
                  if (event.videoUrl != null && event.videoUrl!.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_rounded, color: AppColors.primaryBlue, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Clip',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Action buttons row
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Download button
                _buildEventActionButton(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  color: AppColors.electricGreen,
                  onTap: () {
                    Navigator.pop(context);
                    _downloadEventImage(event);
                  },
                ),
                const SizedBox(width: 8),
                // Play clip button (if available)
                if (event.hasVideoClip)
                  _buildEventActionButton(
                    icon: Icons.play_circle_rounded,
                    label: 'Play Clip',
                    color: AppColors.primaryBlue,
                    onTap: () {
                      Navigator.pop(context);
                      _playMotionClip(event);
                    },
                  ),
                if (event.hasVideoClip)
                  const SizedBox(width: 8),
                // Delete button
                _buildEventActionButton(
                  icon: Icons.delete_rounded,
                  label: 'Delete',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteEvent(event);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Download event image to device
  Future<void> _downloadEventImage(MotionEvent event) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Downloading...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Download image
      final response = await http.get(Uri.parse(event.imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image');
      }

      // Get downloads directory
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'motion_${DateFormat('yyyyMMdd_HHmmss').format(event.timestamp)}.jpg';
      final filePath = '${directory.path}/$fileName';

      // Save file
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: $fileName'),
            backgroundColor: AppColors.electricGreen,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error downloading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Confirm and delete event
  void _confirmDeleteEvent(MotionEvent event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event?'),
        content: const Text('This will permanently delete this motion event.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: Implement actual deletion from Firebase/ESP32
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Event deleted'),
                  backgroundColor: AppColors.electricGreen,
                ),
              );
              // Refresh the events list
              await _loadEventsForDate(_selectedDate);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Play motion clip video or frame sequence
  void _playMotionClip(MotionEvent event) {
    // Check if it's a video URL
    if (event.videoUrl != null && event.videoUrl!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _VideoPlayerPage(
            videoUrl: event.videoUrl!,
            event: event,
          ),
        ),
      );
      return;
    }

    // Check if it's an ESP32 SD card clip (frame sequence)
    if (event.clipPath != null && event.clipPath!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _ClipPlayerPage(
            event: event,
            cameraService: _cameraService,
          ),
        ),
      );
      return;
    }

    // No clip available
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No video clip available for this event'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showTimelapsePlayer(bool isDark) {
    if (_timelapseSnapshots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No timelapse snapshots available'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TimelapsePlayerPage(
          snapshots: _timelapseSnapshots,
          date: _selectedDate,
        ),
      ),
    );
  }

  void _showAllMotionEvents(bool isDark) {
    // TODO: Implement full motion events view
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('📋 Full event list coming soon!'),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ============================================================================
// VIDEO PLAYER PAGE - For playing motion clips
// ============================================================================

class _VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final MotionEvent event;

  const _VideoPlayerPage({
    required this.videoUrl,
    required this.event,
  });

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));

    try {
      await _controller.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller.play();
        setState(() => _isPlaying = true);
        _startHideControlsTimer();
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    _controller.addListener(() {
      if (mounted) {
        setState(() => _isPlaying = _controller.value.isPlaying);
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
      _startHideControlsTimer();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.personDetected ? 'Person Detected' : 'Motion Detected',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              DateFormat('MMM d, yyyy • HH:mm:ss').format(widget.event.timestamp),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video Player
            if (_isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Play/Pause Overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                ),
                child: Center(
                  child: IconButton(
                    iconSize: 80,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      color: Colors.white,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                ),
              ),
            ),

            // Progress Bar
            if (_isInitialized)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    children: [
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: AppColors.primaryBlue,
                          bufferedColor: Colors.white30,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_controller.value.position),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            _formatDuration(_controller.value.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

// ============================================================================
// TIMELAPSE PLAYER PAGE - For playing timelapse snapshots as slideshow
// ============================================================================

class _TimelapsePlayerPage extends StatefulWidget {
  final List<TimelapseSnapshot> snapshots;
  final DateTime date;

  const _TimelapsePlayerPage({
    required this.snapshots,
    required this.date,
  });

  @override
  State<_TimelapsePlayerPage> createState() => _TimelapsePlayerPageState();
}

class _TimelapsePlayerPageState extends State<_TimelapsePlayerPage> {
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _playTimer;
  double _playbackSpeed = 1.0; // Frames per second

  @override
  void initState() {
    super.initState();
    // Auto-start playback
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _startPlayback();
    });
  }

  void _startPlayback() {
    setState(() => _isPlaying = true);
    _playTimer?.cancel();
    _playTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _playbackSpeed).round()),
      (timer) {
        if (_currentIndex < widget.snapshots.length - 1) {
          setState(() => _currentIndex++);
        } else {
          // Loop back to start
          setState(() => _currentIndex = 0);
        }
      },
    );
  }

  void _pausePlayback() {
    setState(() => _isPlaying = false);
    _playTimer?.cancel();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    if (_isPlaying) {
      _pausePlayback();
      _startPlayback();
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSnapshot = widget.snapshots[_currentIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '24h Timelapse',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              DateFormat('EEEE, MMM d, yyyy').format(widget.date),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Speed selector
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed_rounded),
            tooltip: 'Playback Speed',
            onSelected: _setSpeed,
            itemBuilder: (context) => [
              PopupMenuItem(value: 0.5, child: Text('0.5x ${_playbackSpeed == 0.5 ? "✓" : ""}')),
              PopupMenuItem(value: 1.0, child: Text('1x ${_playbackSpeed == 1.0 ? "✓" : ""}')),
              PopupMenuItem(value: 2.0, child: Text('2x ${_playbackSpeed == 2.0 ? "✓" : ""}')),
              PopupMenuItem(value: 5.0, child: Text('5x ${_playbackSpeed == 5.0 ? "✓" : ""}')),
              PopupMenuItem(value: 10.0, child: Text('10x ${_playbackSpeed == 10.0 ? "✓" : ""}')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Image display
          Expanded(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Snapshot image
                  Image.network(
                    currentSnapshot.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 60),
                    ),
                  ),

                  // Play/Pause overlay
                  if (!_isPlaying)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),

                  // Timestamp overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        DateFormat('HH:mm:ss').format(currentSnapshot.timestamp),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Frame counter
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.snapshots.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Progress slider
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: Column(
              children: [
                // Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primaryBlue,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppColors.primaryBlue,
                    overlayColor: AppColors.primaryBlue.withOpacity(0.2),
                  ),
                  child: Slider(
                    value: _currentIndex.toDouble(),
                    min: 0,
                    max: (widget.snapshots.length - 1).toDouble(),
                    onChanged: (value) {
                      _pausePlayback();
                      setState(() => _currentIndex = value.round());
                    },
                  ),
                ),

                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Skip to start
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                      onPressed: () {
                        _pausePlayback();
                        setState(() => _currentIndex = 0);
                      },
                    ),

                    // Previous frame
                    IconButton(
                      icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white),
                      onPressed: () {
                        _pausePlayback();
                        if (_currentIndex > 0) {
                          setState(() => _currentIndex--);
                        }
                      },
                    ),

                    // Play/Pause
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        iconSize: 40,
                        icon: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),

                    // Next frame
                    IconButton(
                      icon: const Icon(Icons.fast_forward_rounded, color: Colors.white),
                      onPressed: () {
                        _pausePlayback();
                        if (_currentIndex < widget.snapshots.length - 1) {
                          setState(() => _currentIndex++);
                        }
                      },
                    ),

                    // Skip to end
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                      onPressed: () {
                        _pausePlayback();
                        setState(() => _currentIndex = widget.snapshots.length - 1);
                      },
                    ),
                  ],
                ),

                // Speed indicator
                Text(
                  'Speed: ${_playbackSpeed}x',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CLIP PLAYER PAGE - For playing ESP32 SD card motion clips (frame sequences)
// ============================================================================

class _ClipPlayerPage extends StatefulWidget {
  final MotionEvent event;
  final ESP32CameraService cameraService;

  const _ClipPlayerPage({
    required this.event,
    required this.cameraService,
  });

  @override
  State<_ClipPlayerPage> createState() => _ClipPlayerPageState();
}

class _ClipPlayerPageState extends State<_ClipPlayerPage> {
  List<Uint8List> _frames = [];
  int _currentFrameIndex = 0;
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _loadError = false;
  Timer? _playTimer;
  double _playbackSpeed = 3.0; // 3 fps (same as recording speed)

  @override
  void initState() {
    super.initState();
    _loadClipFrames();
  }

  Future<void> _loadClipFrames() async {
    try {
      final clipPath = widget.event.clipPath ?? '';
      final frameCount = widget.event.frameCount ?? 45; // Default 15 seconds at 3fps

      if (clipPath.isEmpty) {
        setState(() {
          _isLoading = false;
          _loadError = true;
        });
        return;
      }

      // Load all frames
      final frames = await widget.cameraService.downloadFullClip(clipPath, frameCount);

      if (mounted) {
        setState(() {
          _frames = frames;
          _isLoading = false;
          _loadError = frames.isEmpty;
        });

        // Auto-play if loaded successfully
        if (frames.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _startPlayback();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading clip frames: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = true;
        });
      }
    }
  }

  void _startPlayback() {
    if (_frames.isEmpty) return;

    setState(() => _isPlaying = true);
    _playTimer?.cancel();
    _playTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _playbackSpeed).round()),
      (timer) {
        if (_currentFrameIndex < _frames.length - 1) {
          setState(() => _currentFrameIndex++);
        } else {
          // Loop back to start
          setState(() => _currentFrameIndex = 0);
        }
      },
    );
  }

  void _pausePlayback() {
    setState(() => _isPlaying = false);
    _playTimer?.cancel();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.personDetected ? 'Person Detected' : 'Motion Detected',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              DateFormat('MMM d, yyyy • HH:mm:ss').format(widget.event.timestamp),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isLoading && _frames.isNotEmpty)
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed_rounded),
              tooltip: 'Playback Speed',
              onSelected: (speed) {
                setState(() => _playbackSpeed = speed);
                if (_isPlaying) {
                  _pausePlayback();
                  _startPlayback();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 1.0, child: Text('1x (Slow) ${_playbackSpeed == 1.0 ? "✓" : ""}')),
                PopupMenuItem(value: 3.0, child: Text('3x (Normal) ${_playbackSpeed == 3.0 ? "✓" : ""}')),
                PopupMenuItem(value: 6.0, child: Text('6x (Fast) ${_playbackSpeed == 6.0 ? "✓" : ""}')),
                PopupMenuItem(value: 10.0, child: Text('10x (Very Fast) ${_playbackSpeed == 10.0 ? "✓" : ""}')),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading clip frames...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : _loadError || _frames.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_rounded, color: Colors.red, size: 60),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to load clip',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _loadError = false;
                          });
                          _loadClipFrames();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Frame display
                    Expanded(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Current frame
                            Image.memory(
                              _frames[_currentFrameIndex],
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),

                            // Play/Pause overlay
                            if (!_isPlaying)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 60,
                                ),
                              ),

                            // Frame counter
                            Positioned(
                              bottom: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_currentFrameIndex + 1} / ${_frames.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Controls
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.black,
                      child: Column(
                        children: [
                          // Progress slider
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.primaryBlue,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: AppColors.primaryBlue,
                              overlayColor: AppColors.primaryBlue.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: _currentFrameIndex.toDouble(),
                              min: 0,
                              max: (_frames.length - 1).toDouble(),
                              onChanged: (value) {
                                _pausePlayback();
                                setState(() => _currentFrameIndex = value.round());
                              },
                            ),
                          ),

                          // Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                                onPressed: () {
                                  _pausePlayback();
                                  setState(() => _currentFrameIndex = 0);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white),
                                onPressed: () {
                                  _pausePlayback();
                                  if (_currentFrameIndex > 0) {
                                    setState(() => _currentFrameIndex--);
                                  }
                                },
                              ),
                              Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  iconSize: 40,
                                  icon: Icon(
                                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: _togglePlayPause,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.fast_forward_rounded, color: Colors.white),
                                onPressed: () {
                                  _pausePlayback();
                                  if (_currentFrameIndex < _frames.length - 1) {
                                    setState(() => _currentFrameIndex++);
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                                onPressed: () {
                                  _pausePlayback();
                                  setState(() => _currentFrameIndex = _frames.length - 1);
                                },
                              ),
                            ],
                          ),

                          // Speed indicator
                          Text(
                            'Speed: ${_playbackSpeed}x (${_frames.length} frames)',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

