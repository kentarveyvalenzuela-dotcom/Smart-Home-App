// filepath: c:\Users\Ivy\OneDrive\Desktop\New folder\brix\as_flutter_project\lib\screens\notification_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../main.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();

  // Alerts state
  Map<String, dynamic> _summary = {};
  List<dynamic> _alerts = [];
  bool _isLoadingAlerts = true;
  bool _showUnresolvedOnly = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  String? _alertError;

  // Activity Notifications state
  List<ActivityNotification> _activityNotifications = [];
  StreamSubscription<List<ActivityNotification>>? _notificationSub;

  late TabController _tabController;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _initNotificationService();
    _loadAlerts();
  }

  Future<void> _initNotificationService() async {
    await _notificationService.initialize();
    _activityNotifications = _notificationService.notifications;

    _notificationSub = _notificationService.notificationStream.listen((notifications) {
      if (mounted) {
        setState(() {
          _activityNotifications = notifications;
        });
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animController.dispose();
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    if (!mounted) return;

    setState(() => _isLoadingAlerts = true);

    try {
      final summaryData = await _authService.getAlertsSummary();
      final listData = await _authService.getAlertsList(
        skip: _currentPage * _pageSize,
        limit: _pageSize,
        resolved: _showUnresolvedOnly ? false : null,
      );

      if (mounted) {
        setState(() {
          _alertError = null;
          if (summaryData != null) {
            _summary = summaryData;
          }
          if (listData != null) {
            _alerts = listData['alerts'] ?? [];
          }
          _isLoadingAlerts = false;
        });
        _animController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAlerts = false;
          _alertError = 'Could not load alerts. Check connection.';
        });
      }
    }
  }

  Future<void> _resolveAlert(String alertId, int index) async {
    final result = await _authService.resolveAlert(alertId);

    if (result != null && result['success'] == true && mounted) {
      setState(() {
        _alerts.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Alert resolved'),
          backgroundColor: AppColors.electricGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      _loadAlerts();
    }
  }

  Future<void> _clearAllAlerts() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Alerts?'),
        content: const Text('Mark all alerts as resolved?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _authService.clearAllAlerts();

              if (result != null && result['success'] == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cleared ${result['cleared_count']} alerts'),
                    backgroundColor: AppColors.electricGreen,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
                _loadAlerts();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllNotifications() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications?'),
        content: const Text('Delete all activity notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _notificationService.clearAll();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('All notifications cleared'),
                  backgroundColor: AppColors.electricGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
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
          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBgCard : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryBlue, AppColors.electricPurple],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade500,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_active_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Activity'),
                      if (_notificationService.unreadCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_notificationService.unreadCount}',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Alerts'),
                      if ((_summary['unresolved_alerts'] ?? 0) > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_summary['unresolved_alerts'] ?? 0}',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActivityTab(isDark),
                _buildAlertsTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ACTIVITY TAB ====================
  Widget _buildActivityTab(bool isDark) {
    return Column(
      children: [
        // Action row
        if (_activityNotifications.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.done_all_rounded, color: AppColors.primaryBlue, size: 20),
                  label: const Text('Mark all read', style: TextStyle(color: AppColors.primaryBlue, fontSize: 12)),
                  onPressed: () => _notificationService.markAllAsRead(),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                  label: const Text('Clear all', style: TextStyle(color: AppColors.error, fontSize: 12)),
                  onPressed: _clearAllNotifications,
                ),
              ],
            ),
          ),

        Expanded(
          child: _activityNotifications.isEmpty
            ? _buildEmptyActivityState(isDark)
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _activityNotifications.length,
                itemBuilder: (context, index) => _buildActivityItem(_activityNotifications[index], index, isDark),
              ),
        ),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildEmptyActivityState(bool isDark) {
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
              Icons.notifications_none_rounded,
              size: 50,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.darkBg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your activity history will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(ActivityNotification notification, int index, bool isDark) {
    final timeStr = DateFormat('MMM dd, HH:mm').format(notification.timestamp);

    IconData icon;
    Color iconColor;

    switch (notification.type) {
      case NotificationType.googleSignIn:
        icon = Icons.login_rounded;
        iconColor = AppColors.electricGreen;
        break;
      case NotificationType.emailSignIn:
        icon = Icons.mail_outline_rounded;
        iconColor = AppColors.primaryBlue;
        break;
      case NotificationType.passwordChange:
        icon = Icons.lock_reset_rounded;
        iconColor = AppColors.warning;
        break;
      case NotificationType.deviceToggle:
        icon = Icons.power_settings_new_rounded;
        iconColor = AppColors.electricOrange;
        break;
      case NotificationType.deviceAdd:
        icon = Icons.add_circle_outline_rounded;
        iconColor = AppColors.electricGreen;
        break;
      case NotificationType.deviceDelete:
        icon = Icons.remove_circle_outline_rounded;
        iconColor = AppColors.error;
        break;
      case NotificationType.profileUpdate:
        icon = Icons.person_outline_rounded;
        iconColor = AppColors.electricPurple;
        break;
      case NotificationType.logout:
        icon = Icons.logout_rounded;
        iconColor = Colors.grey;
        break;
    }

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
      child: Dismissible(
        key: Key(notification.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        onDismissed: (_) => _notificationService.deleteNotification(notification.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark
              ? (notification.isRead ? AppColors.darkBg.withOpacity(0.5) : AppColors.darkBgCard)
              : (notification.isRead ? Colors.grey.shade100 : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: notification.isRead
                ? Colors.grey.withOpacity(0.2)
                : iconColor.withOpacity(0.3),
            ),
            boxShadow: notification.isRead
              ? null
              : [
                  BoxShadow(
                    color: iconColor.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (!notification.isRead) {
                  _notificationService.markAsRead(notification.id);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(notification.isRead ? 0.1 : 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: notification.isRead ? Colors.grey : iconColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : AppColors.darkBg,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notification.message,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                        if (!notification.isRead) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== ALERTS TAB ====================
  Widget _buildAlertsTab(bool isDark) {
    return Column(
      children: [
        // Action row for "Clear all" button
        if (_alerts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.done_all_rounded, color: AppColors.primaryBlue, size: 20),
                  label: const Text('Clear all', style: TextStyle(color: AppColors.primaryBlue)),
                  onPressed: _clearAllAlerts,
                ),
              ],
            ),
          ),
        Expanded(
          child: _isLoadingAlerts
            ? _buildLoadingState(isDark)
            : RefreshIndicator(
                onRefresh: _loadAlerts,
                color: AppColors.primaryBlue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      if (_alertError != null) _buildErrorBanner(isDark),

                      // Summary cards
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _buildModernSummaryCard(
                              'Total',
                              _summary['total_alerts']?.toString() ?? '0',
                              AppColors.primaryBlue,
                              Icons.notifications_rounded,
                              isDark,
                            ),
                            const SizedBox(width: 10),
                            _buildModernSummaryCard(
                              'Active',
                              _summary['unresolved_alerts']?.toString() ?? '0',
                              AppColors.error,
                              Icons.warning_rounded,
                              isDark,
                            ),
                            const SizedBox(width: 10),
                            _buildModernSummaryCard(
                              '24h',
                              _summary['alerts_24h']?.toString() ?? '0',
                              AppColors.warning,
                              Icons.access_time_rounded,
                              isDark,
                            ),
                          ],
                        ),
                      ),

                      // Info about 24-hour alerts
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.info.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Alerts are triggered when devices are ON for more than 24 hours continuously.',
                                  style: TextStyle(fontSize: 12, color: AppColors.info),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Filter toggle
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildFilterToggle(isDark),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Alerts list
                      _alerts.isEmpty
                          ? _buildEmptyAlertState(isDark)
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _alerts.length,
                              itemBuilder: (context, index) =>
                                  _buildModernAlertItem(_alerts[index], index, isDark),
                            ),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
        ),
      ],
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
            'Loading alerts...',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
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
            child: Text(_alertError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
          TextButton(
            onPressed: _loadAlerts,
            child: const Text('Retry', style: TextStyle(color: AppColors.primaryBlue)),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSummaryCard(String label, String value, Color color, IconData icon, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBgCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToggle(bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showUnresolvedOnly = !_showUnresolvedOnly;
          _currentPage = 0;
        });
        _loadAlerts();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: _showUnresolvedOnly
            ? LinearGradient(
                colors: [AppColors.primaryBlue, AppColors.electricPurple.withOpacity(0.8)],
              )
            : null,
          color: _showUnresolvedOnly ? null : (isDark ? AppColors.darkBgCard : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: _showUnresolvedOnly
            ? null
            : Border.all(color: Colors.grey.withOpacity(0.3)),
          boxShadow: _showUnresolvedOnly
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
              _showUnresolvedOnly ? Icons.filter_list_rounded : Icons.filter_list_off_rounded,
              size: 16,
              color: _showUnresolvedOnly ? Colors.white : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Text(
              'Unresolved Only',
              style: TextStyle(
                fontSize: 13,
                fontWeight: _showUnresolvedOnly ? FontWeight.w600 : FontWeight.normal,
                color: _showUnresolvedOnly ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAlertState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBgCard : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_rounded,
              size: 50,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No alerts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.darkBg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All systems running normally',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildModernAlertItem(dynamic alert, int index, bool isDark) {
    if (alert is! Map<String, dynamic>) return const SizedBox();

    String alertType = alert['alert_type'] ?? 'unknown';
    String message = alert['message'] ?? 'Unknown alert';
    bool isResolved = alert['is_resolved'] ?? false;

    DateTime? timestamp;
    if (alert['timestamp'] != null) {
      try {
        timestamp = DateTime.parse(alert['timestamp']);
      } catch (e) {
        timestamp = null;
      }
    }

    String timeStr = timestamp != null
        ? DateFormat('MMM dd, HH:mm').format(timestamp)
        : 'Unknown time';

    IconData icon;
    Color iconColor;

    if (alertType.contains('voltage')) {
      icon = Icons.electrical_services_rounded;
      iconColor = AppColors.electricYellow;
    } else if (alertType.contains('current')) {
      icon = Icons.bolt_rounded;
      iconColor = AppColors.electricPurple;
    } else if (alertType.contains('24_hours') || alertType.contains('long_running')) {
      icon = Icons.timer_off_rounded;
      iconColor = AppColors.warning;
    } else {
      icon = Icons.warning_rounded;
      iconColor = AppColors.error;
    }

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
        decoration: BoxDecoration(
          color: isDark
            ? (isResolved ? AppColors.darkBg.withOpacity(0.5) : AppColors.darkBgCard)
            : (isResolved ? Colors.grey.shade100 : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isResolved
              ? Colors.grey.withOpacity(0.2)
              : iconColor.withOpacity(0.3),
          ),
          boxShadow: isResolved
            ? null
            : [
                BoxShadow(
                  color: iconColor.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: isResolved ? null : () => _resolveAlert(alert['id'], index),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isResolved ? Colors.grey : iconColor).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: isResolved ? Colors.grey : iconColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : AppColors.darkBg,
                            decoration: isResolved ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${alert['device_name'] ?? 'Unknown'} • Pin ${alert['pin_number'] ?? '-'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        if (alert['value'] != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${alert['value']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isResolved ? Colors.grey : iconColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (alert['threshold'] != null) ...[
                                Text(
                                  ' / Threshold: ${alert['threshold']}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      if (isResolved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.electricGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Resolved',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.electricGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: AppColors.primaryBlue,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

