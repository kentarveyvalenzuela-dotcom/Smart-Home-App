// filepath: c:\Users\Ivy\OneDrive\Desktop\New folder\brix\as_flutter_project\lib\screens\home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'device_page.dart';
import 'notification_page.dart';
import 'settings_page.dart';
import 'logs_page.dart';
import '../services/energy_monitor_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../services/config_service.dart';
import '../services/auth_service.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final EnergyMonitorService _energyService = EnergyMonitorService();
  int _selectedIndex = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Energy data
  EnergyReading? _currentReading;
  EnergyBill? _currentBill;
  StreamSubscription<EnergyReading>? _readingSub;
  StreamSubscription<EnergyBill>? _billSub;

  // ESP32 online detection
  DateTime? _lastReadingTime;
  Timer? _offlineCheckTimer;
  bool _isEsp32Online = false;
  static const int _offlineTimeoutSeconds = 10; // Consider offline if no reading for 10 seconds

  // Stats
  int _deviceCount = 1;
  int _activeDevices = 0;
  int _alertCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initAnimations();
    _startOfflineCheck();
  }

  void _startOfflineCheck() {
    // Check every 2 seconds if ESP32 is still online
    _offlineCheckTimer?.cancel();
    _offlineCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_lastReadingTime != null) {
        final secondsSinceLastReading = DateTime.now().difference(_lastReadingTime!).inSeconds;
        final wasOnline = _isEsp32Online;
        _isEsp32Online = secondsSinceLastReading < _offlineTimeoutSeconds;

        // If status changed, update UI
        if (wasOnline != _isEsp32Online && mounted) {
          setState(() {
            if (!_isEsp32Online) {
              debugPrint('⚠️ ESP32 went OFFLINE (no data for ${secondsSinceLastReading}s)');
            } else {
              debugPrint('✅ ESP32 is ONLINE');
            }
          });
        }
      }
    });
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

  }

  Future<void> _initializeServices() async {
    await _energyService.initialize();

    _readingSub = _energyService.readingStream.listen((reading) {
      if (mounted) {
        setState(() {
          _currentReading = reading;
          _lastReadingTime = DateTime.now();
          _isEsp32Online = true;
        });
      }
    });

    _billSub = _energyService.billStream.listen((bill) {
      if (mounted) setState(() => _currentBill = bill);
    });

    // Load device stats from cache
    await _loadDeviceStats();

    // Load alert count from notification service
    _loadAlertCount();

    // Periodically refresh stats
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _loadDeviceStats();
        _loadAlertCount();
      }
    });
  }

  Future<void> _loadDeviceStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? cached = prefs.getStringList('appliances');

      if (cached != null && cached.isNotEmpty) {
        int total = cached.length;
        int active = 0;

        // Count active devices (isOn=true)
        for (final item in cached) {
          if (item.contains('isOn=true')) {
            active++;
          }
        }

        if (mounted) {
          setState(() {
            _deviceCount = total;
            _activeDevices = active;
          });
        }
      } else {
        // Try to get from backend
        try {
          final sync = SyncService(baseUrl: ConfigService().backendUrl);
          final token = await AuthService().getAccessToken();
          if (token != null) {
            final devices = await sync.pullDevices(authToken: token);
            if (devices != null && mounted) {
              setState(() {
                _deviceCount = devices.length;
                _activeDevices = devices.where((d) => d['isOn'] == true).length;
              });
            }
          }
        } catch (e) {
          debugPrint('Error loading device stats from backend: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading device stats: $e');
    }
  }

  void _loadAlertCount() {
    try {
      final notifications = NotificationService().notifications;
      // Count unread/recent alerts (within last 24 hours)
      final now = DateTime.now();
      final recentAlerts = notifications.where((n) {
        // ActivityNotification has a timestamp property (DateTime)
        return now.difference(n.timestamp).inHours < 24;
      }).length;

      if (mounted) {
        setState(() {
          _alertCount = recentAlerts;
        });
      }
    } catch (e) {
      debugPrint('Error loading alert count: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _readingSub?.cancel();
    _billSub?.cancel();
    _offlineCheckTimer?.cancel();
    super.dispose();
  }

  // Keep page instances alive to preserve state
  // These are created once and reused (not recreated on every build)
  final List<Widget> _pages = const [
    DevicePage(),
    LogsPage(),
    NotificationsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(isDark),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Dashboard needs to rebuild for energy data updates
          _buildDashboardPage(),
          // These pages keep their state via AutomaticKeepAliveClientMixin
          _pages[0], // DevicePage
          _pages[1], // LogsPage
          _pages[2], // NotificationsPage
          _pages[3], // SettingsPage
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(isDark),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
              ? [AppColors.darkBgSecondary, AppColors.darkBg]
              : [AppColors.primaryBlueDark, AppColors.darkBg],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryBlue.withOpacity(_pulseAnimation.value),
                      AppColors.electricGreen.withOpacity(_pulseAnimation.value * 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withOpacity(0.4 * _pulseAnimation.value),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt, color: Colors.white, size: 18),
              );
            },
          ),
          const SizedBox(width: 10),
          Text(_getAppBarTitle(), style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.refresh, size: 20),
          ),
          onPressed: () {
            setState(() {});
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomNavBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
            ? [AppColors.darkBgSecondary, AppColors.darkBg]
            : [const Color(0xFF1a1f3a), AppColors.darkBg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded, 'Home'),
              _buildNavItem(1, Icons.devices_rounded, 'Devices'),
              _buildNavItem(2, Icons.history_rounded, 'Logs'),
              _buildNavItem(3, Icons.notifications_rounded, 'Alerts'),
              _buildNavItem(4, Icons.settings_rounded, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        if (_selectedIndex != index) {
          setState(() => _selectedIndex = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 12 : 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
            ? LinearGradient(colors: [
                AppColors.primaryBlue.withOpacity(0.3),
                AppColors.electricPurple.withOpacity(0.2),
              ])
            : null,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: AppColors.primaryBlue.withOpacity(0.5)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? AppColors.primaryBlue : Colors.grey, size: isSelected ? 24 : 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? AppColors.primaryBlue : Colors.grey, fontSize: 9, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    const titles = ['Dashboard', 'Device Control', 'Activity Logs', 'Notifications', 'Settings'];
    return titles[_selectedIndex];
  }

  Widget _buildDashboardPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        return RefreshIndicator(
          onRefresh: () async => await _energyService.initialize(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(isDark),
                const SizedBox(height: 20),
                isWide ? _buildWideStats(isDark) : _buildNarrowStats(isDark),
                const SizedBox(height: 20),
                isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildVoltageCard(isDark)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildCurrentCard(isDark)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildVoltageCard(isDark),
                          const SizedBox(height: 16),
                          _buildCurrentCard(isDark),
                        ],
                      ),
                const SizedBox(height: 16),
                _buildPowerBillCard(isDark),
                const SizedBox(height: 16),
                _buildBillingSummaryCard(isDark),
                const SizedBox(height: 100),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideStats(bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Devices', '$_deviceCount', Icons.devices_rounded, AppColors.primaryBlue, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Active', '$_activeDevices', Icons.power_rounded, AppColors.electricGreen, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Alerts', '$_alertCount', Icons.warning_rounded, AppColors.warning, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('ESP32', _isEsp32Online ? 'Online' : 'Offline', Icons.wifi_rounded, _isEsp32Online ? AppColors.electricGreen : AppColors.error, isDark)),
      ],
    );
  }

  Widget _buildNarrowStats(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('Devices', '$_deviceCount', Icons.devices_rounded, AppColors.primaryBlue, isDark)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Active', '$_activeDevices', Icons.power_rounded, AppColors.electricGreen, isDark)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('Alerts', '$_alertCount', Icons.warning_rounded, AppColors.warning, isDark)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('ESP32', _isEsp32Online ? 'Online' : 'Offline', Icons.wifi_rounded, _isEsp32Online ? AppColors.electricGreen : AppColors.error, isDark)),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue.withOpacity(0.8), AppColors.electricPurple.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primaryBlue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Smart Home', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Energy Monitoring System', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_isEsp32Online ? AppColors.electricGreen : AppColors.error).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: (_isEsp32Online ? AppColors.electricGreen : AppColors.error).withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isEsp32Online ? Icons.check_circle : Icons.wifi_off, color: _isEsp32Online ? AppColors.electricGreen : AppColors.error, size: 16),
                      const SizedBox(width: 6),
                      Text(_isEsp32Online ? 'ESP32 Connected' : 'ESP32 Offline', style: TextStyle(color: _isEsp32Online ? AppColors.electricGreen : AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withOpacity(0.2 * _pulseAnimation.value), Colors.transparent]),
                ),
                child: Icon(
                  _isEsp32Online ? Icons.bolt_rounded : Icons.bolt_outlined,
                  size: 50,
                  color: Colors.white.withOpacity(_isEsp32Online ? 0.9 : 0.5)
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.darkBg)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildVoltageCard(bool isDark) {
    // Show 0 when ESP32 is offline
    final voltage = _isEsp32Online ? (_currentReading?.voltage ?? 0.0) : 0.0;
    final isOnline = _isEsp32Online;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (isOnline ? AppColors.electricYellow : AppColors.error).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: (isOnline ? AppColors.electricYellow : AppColors.error).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: (isOnline ? AppColors.electricYellow : AppColors.error).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(isOnline ? Icons.electrical_services_rounded : Icons.power_off_rounded, color: isOnline ? AppColors.electricYellow : AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Voltage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.darkBg)),
                    Text(isOnline ? 'ZMPT101B • GPIO13' : 'ESP32 Disconnected', style: TextStyle(fontSize: 11, color: isOnline ? Colors.grey.shade500 : AppColors.error)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: (isOnline ? AppColors.electricGreen : AppColors.error).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isOnline ? Icons.wifi : Icons.wifi_off, size: 12, color: isOnline ? AppColors.electricGreen : AppColors.error),
                    const SizedBox(width: 4),
                    Text(isOnline ? 'LIVE' : 'OFFLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOnline ? AppColors.electricGreen : AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  voltage.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: isOnline ? AppColors.electricYellow : Colors.grey,
                    height: 1
                  ),
                ),
                Text('Volts', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (voltage / 250).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation(
                !isOnline ? Colors.grey :
                voltage < 200 ? AppColors.error :
                voltage > 240 ? AppColors.warning :
                AppColors.electricGreen
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0V', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              Text(isOnline ? 'Normal: 220V' : 'No Signal', style: TextStyle(fontSize: 10, color: isOnline ? Colors.grey.shade500 : AppColors.error)),
              Text('250V', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCard(bool isDark) {
    // Show 0 when ESP32 is offline
    final current = _isEsp32Online ? (_currentReading?.current ?? 0.0) : 0.0;
    final channels = _isEsp32Online ? (_currentReading?.currentPerChannel ?? {}) : <String, double>{};
    final isOnline = _isEsp32Online;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (isOnline ? AppColors.electricPurple : AppColors.error).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: (isOnline ? AppColors.electricPurple : AppColors.error).withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: (isOnline ? AppColors.electricPurple : AppColors.error).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(isOnline ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: isOnline ? AppColors.electricPurple : AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.darkBg)),
                    Text(isOnline ? 'SCT-013-030 × 4' : 'ESP32 Disconnected', style: TextStyle(fontSize: 11, color: isOnline ? Colors.grey.shade500 : AppColors.error)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: (isOnline ? AppColors.electricGreen : AppColors.error).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isOnline ? Icons.wifi : Icons.wifi_off, size: 12, color: isOnline ? AppColors.electricGreen : AppColors.error),
                    const SizedBox(width: 4),
                    Text(isOnline ? 'LIVE' : 'OFFLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOnline ? AppColors.electricGreen : AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  current.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: isOnline ? AppColors.electricPurple : Colors.grey,
                    height: 1
                  ),
                ),
                Text('Amperes (Total)', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isOnline ? 'Channels (GPIO 35, 34, 33, 32):' : 'No sensor data available',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade700)
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(4, (i) {
              final channelCurrent = isOnline ? (channels['ch${i + 1}'] ?? 0.0) : 0.0;
              final pins = [35, 34, 33, 32];
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: isDark ? AppColors.darkBg : Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      Text('CH${i + 1}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      Text('GPIO${pins[i]}', style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
                      const SizedBox(height: 4),
                      Text('${channelCurrent.toStringAsFixed(1)}A', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.electricPurple)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerBillCard(bool isDark) {
    // Show 0 when ESP32 is offline
    final voltage = _isEsp32Online ? (_currentReading?.voltage ?? 0.0) : 0.0;
    final current = _isEsp32Online ? (_currentReading?.current ?? 0.0) : 0.0;
    final power = _isEsp32Online ? (_currentReading?.power ?? (voltage * current)) : 0.0;
    final energy = _currentBill?.totalKwh ?? 0.0;
    final isOnline = _isEsp32Online;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline
            ? [AppColors.electricOrange.withOpacity(0.1), AppColors.electricYellow.withOpacity(0.05)]
            : [AppColors.error.withOpacity(0.1), Colors.grey.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (isOnline ? AppColors.electricOrange : AppColors.error).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: (isOnline ? AppColors.electricOrange : AppColors.error).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(isOnline ? Icons.power_rounded : Icons.power_off_rounded, color: isOnline ? AppColors.electricOrange : AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Power Consumption', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.darkBg)),
              ),
              if (!isOnline)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Text('OFFLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.error)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildPowerStat('Power', isOnline ? '${power.toStringAsFixed(0)} W' : '0 W', isOnline ? AppColors.electricOrange : Colors.grey, isDark)),
              const SizedBox(width: 12),
              Expanded(child: _buildPowerStat('Energy', '${energy.toStringAsFixed(2)} kWh', AppColors.electricGreen, isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPowerStat(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: isDark ? AppColors.darkBgCard : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildBillingSummaryCard(bool isDark) {
    final bill = _currentBill;
    final totalCost = bill?.totalCost ?? 0.0;
    final projectedCost = bill?.projectedMonthlyCost ?? 0.0;
    final rate = bill?.ratePerKwh ?? 11.85;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.electricGreen.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: AppColors.electricGreen.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.electricGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_rounded, color: AppColors.electricGreen, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Electricity Bill', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.darkBg)),
                    Text('Rate: ₱${rate.toStringAsFixed(2)}/kWh', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.edit_rounded, size: 20), color: AppColors.primaryBlue, onPressed: () => _showRateDialog(isDark)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryBlue.withOpacity(0.1), AppColors.electricPurple.withOpacity(0.05)]), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('Current Bill', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('₱${totalCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.warning.withOpacity(0.1), AppColors.electricOrange.withOpacity(0.05)]), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('Projected/Month', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('₱${projectedCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.warning)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (bill != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Period: ${bill.daysInPeriod} days', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                Text('Avg: ${bill.averageDailyKwh.toStringAsFixed(2)} kWh/day', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _energyService.resetBillingPeriod();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Billing period reset'), backgroundColor: AppColors.electricGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  );
                }
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset Billing Period'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryBlue, side: BorderSide(color: AppColors.primaryBlue.withOpacity(0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ],
      ),
    );
  }

  void _showRateDialog(bool isDark) {
    final controller = TextEditingController(text: _energyService.ratePerKwh.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Electricity Rate'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Rate per kWh (₱)', hintText: '11.85', border: OutlineInputBorder(), prefixText: '₱ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final rate = double.tryParse(controller.text) ?? 11.85;
              _energyService.setRate(rate);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

