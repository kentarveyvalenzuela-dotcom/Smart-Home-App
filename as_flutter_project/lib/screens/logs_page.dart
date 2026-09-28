import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../main.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  List<dynamic> _logs = [];
  bool _isLoading = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  int _totalCount = 0;
  String _filterType = 'all';
  int _selectedHours = 24;
  String? _error;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _loadLogs();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);

    try {
      Map<String, dynamic>? data;

      if (_filterType == 'device_control') {
        data = await _authService.getDeviceControlLogs(
          skip: _currentPage * _pageSize,
          limit: _pageSize,
          hours: _selectedHours,
        );
      } else if (_filterType == 'sensor_readings') {
        data = await _authService.getSensorReadings(
          skip: _currentPage * _pageSize,
          limit: _pageSize,
          hours: _selectedHours,
        );
      } else {
        // All logs - no type filter
        data = await _authService.getLogs(
          skip: _currentPage * _pageSize,
          limit: _pageSize,
          hours: _selectedHours,
        );
      }

      if (data != null && mounted) {
        setState(() {
          _logs = List<dynamic>.from(data?['logs'] ?? []);
          _totalCount = data?['total_count'] ?? 0;
          _error = null;
          _isLoading = false;
        });
        _animController.forward(from: 0);
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Failed to load logs. Try again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Connection error. Check your network.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          // Filter bar
          _buildFilterBar(isDark),

          // Error banner
          if (_error != null) _buildErrorBanner(isDark),

          // Logs list
          Expanded(
            child: _isLoading
                ? _buildLoadingState(isDark)
                : _logs.isEmpty
                    ? _buildEmptyState(isDark)
                    : _buildLogsList(isDark),
          ),

          // Pagination
          if (_totalCount > _pageSize) _buildPagination(isDark),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModernFilterChip('All', 'all', Icons.list_rounded, isDark),
                  const SizedBox(width: 8),
                  _buildModernFilterChip('Devices', 'device_control', Icons.devices_rounded, isDark),
                  const SizedBox(width: 8),
                  _buildModernFilterChip('Sensors', 'sensor_readings', Icons.sensors_rounded, isDark),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildTimeSelector(isDark),
        ],
      ),
    );
  }

  Widget _buildModernFilterChip(String label, String type, IconData icon, bool isDark) {
    final isSelected = _filterType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _filterType = type;
          _currentPage = 0;
        });
        _loadLogs();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
            ? LinearGradient(
                colors: [AppColors.primaryBlue, AppColors.electricPurple.withOpacity(0.8)],
              )
            : null,
          color: isSelected ? null : (isDark ? AppColors.darkBgCard : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
            ? null
            : Border.all(color: Colors.grey.withOpacity(0.3)),
          boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
      ),
      child: PopupMenuButton<int>(
        initialValue: _selectedHours,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          setState(() {
            _selectedHours = value;
            _currentPage = 0;
          });
          _loadLogs();
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 1, child: Text('Last 1 hour')),
          const PopupMenuItem(value: 6, child: Text('Last 6 hours')),
          const PopupMenuItem(value: 24, child: Text('Last 24 hours')),
          const PopupMenuItem(value: 168, child: Text('Last 7 days')),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_rounded, size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 6),
            Text(
              '${_selectedHours}h',
              style: const TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.primaryBlue, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
          TextButton(
            onPressed: _loadLogs,
            child: const Text('Retry', style: TextStyle(color: AppColors.primaryBlue)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBgCard : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withOpacity(0.2),
                  blurRadius: 15,
                ),
              ],
            ),
            child: const CircularProgressIndicator(
              color: AppColors.primaryBlue,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading logs...',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBgCard : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              size: 50,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No logs found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.darkBg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Activity logs will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadLogs,
      color: AppColors.primaryBlue,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _logs.length,
        itemBuilder: (context, index) => _buildModernLogItem(_logs[index], isDark, index),
      ),
    );
  }

  Widget _buildModernLogItem(dynamic log, bool isDark, int index) {
    String title = '';
    String subtitle = '';
    IconData icon = Icons.history_rounded;
    Color iconColor = AppColors.primaryBlue;

    if (log is Map<String, dynamic>) {
      if (log.containsKey('device_name') && log.containsKey('action')) {
        title = log['device_name'] ?? 'Device';
        subtitle = log['action'] ?? '';
        final isOn = log['action'] == 'ON';
        icon = isOn ? Icons.power_rounded : Icons.power_off_rounded;
        iconColor = isOn ? AppColors.electricGreen : AppColors.warning;
      } else if (log.containsKey('sensor_type') && log.containsKey('value')) {
        String sensorType = log['sensor_type'] ?? 'unknown';
        String value = log['value'].toString();
        String unit = log['unit'] ?? '';
        title = log['device_name'] ?? 'Sensor';
        subtitle = '$sensorType: $value $unit';
        icon = sensorType == 'voltage' ? Icons.bolt_rounded : Icons.electric_meter_rounded;
        iconColor = AppColors.electricYellow;
      }

      DateTime? timestamp;
      if (log['timestamp'] != null) {
        try {
          timestamp = DateTime.parse(log['timestamp']);
        } catch (e) {
          timestamp = null;
        }
      }

      String timeStr = timestamp != null
          ? DateFormat('MMM dd, HH:mm').format(timestamp)
          : 'Unknown time';

      return TweenAnimationBuilder<double>(
        duration: Duration(milliseconds: 200 + (index * 30)),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.easeOut,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 15 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBgCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: iconColor.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: iconColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.darkBg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: iconColor),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox();
  }

  Widget _buildPagination(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgSecondary : Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPaginationButton(
            icon: Icons.chevron_left_rounded,
            enabled: _currentPage > 0,
            onPressed: () {
              setState(() => _currentPage--);
              _loadLogs();
            },
            isDark: isDark,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Page ${_currentPage + 1}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.darkBg,
              ),
            ),
          ),
          _buildPaginationButton(
            icon: Icons.chevron_right_rounded,
            enabled: (_currentPage + 1) * _pageSize < _totalCount,
            onPressed: () {
              setState(() => _currentPage++);
              _loadLogs();
            },
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: enabled
            ? AppColors.primaryBlue.withOpacity(0.15)
            : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: enabled ? AppColors.primaryBlue : Colors.grey.shade400,
          size: 24,
        ),
      ),
    );
  }
}
