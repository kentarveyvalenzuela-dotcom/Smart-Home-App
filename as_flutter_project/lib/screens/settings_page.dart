import 'package:flutter/material.dart';
import 'auth_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/config_service.dart';
import '../services/notification_service.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = AuthService();
  Map<String, dynamic> _profile = {};
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  bool _emailAlertsEnabled = true;
  bool _isOAuthUser = false;
  String _backendUrl = '';
  bool _isSavingBackend = false;
  bool _isSavingProfile = false;
  bool _isChangingPassword = false;
  bool _isSavingThresholds = false;
  bool _isSavingPreferences = false;

  @override
  void initState() {
    super.initState();
    _loadProfileAndPreferences();
  }

  Future<void> _loadProfileAndPreferences() async {
    try {
      // Get profile from backend or Firebase Auth
      final profile = await _authService.getUserProfile();
      final prefs = await _authService.getUserPreferences();
      final backendUrl = ConfigService().backendUrl;

      // Also try to get from Firebase Auth directly
      final firebaseUser = await _authService.getCurrentFirebaseUser();

      if (mounted) {
        setState(() {
          // Prefer Firebase Auth data, fallback to profile from backend
          if (firebaseUser != null) {
            _profile = {
              'name': firebaseUser['displayName'] ?? profile?['name'] ?? 'User',
              'email': firebaseUser['email'] ?? profile?['email'] ?? '',
              'provider': firebaseUser['provider'] ?? 'email',
            };
            _isOAuthUser = firebaseUser['provider'] == 'google.com' ||
                firebaseUser['provider'] == 'google';
          } else if (profile != null) {
            _profile = profile;
            _isOAuthUser = profile['provider'] == 'google' ||
                profile['is_oauth_user'] == true;
          }

          if (prefs != null) {
            _notificationsEnabled = prefs['notifications_enabled'] ?? true;
            _emailAlertsEnabled = prefs['email_alerts'] ?? true;
          }
          _backendUrl = backendUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showProfileDialog() {
    final nameController = TextEditingController(text: _profile['name'] ?? '');
    final emailController =
        TextEditingController(text: _profile['email'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _updateProfile(nameController.text, emailController.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProfile(String name, String email) async {
    setState(() => _isSavingProfile = true);
    final result = await _authService.updateUserProfile(name, email);

    if (result != null && mounted) {
      // Add notification for profile update
      NotificationService().addProfileUpdateNotification();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Profile updated'), backgroundColor: Colors.green),
      );
      _loadProfileAndPreferences();
    }
  }

  void _showPasswordDialog() {
    final currentPwdController = TextEditingController();
    final newPwdController = TextEditingController();
    final confirmPwdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPwdController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPwdController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPwdController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _changePassword(
                currentPwdController.text,
                newPwdController.text,
                confirmPwdController.text,
              );
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _showBackendDialog() {
    final controller = TextEditingController(text: _backendUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            hintText: 'http://192.168.1.100:8000',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isEmpty) return;
              setState(() => _isSavingBackend = true);
              await ConfigService().setBackendUrl(newUrl);
              setState(() {
                _backendUrl = newUrl;
                _isSavingBackend = false;
              });
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backend URL updated')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showVoltageThresholdDialog() async {
    final minController =
        TextEditingController(text: ConfigService().voltageMin.toString());
    final maxController =
        TextEditingController(text: ConfigService().voltageMax.toString());
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voltage Thresholds'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Minimum Voltage (V)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: maxController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Maximum Voltage (V)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final min = double.tryParse(minController.text.trim()) ??
                  ConfigService().voltageMin;
              final max = double.tryParse(maxController.text.trim()) ??
                  ConfigService().voltageMax;
              Navigator.pop(context, {'min': min, 'max': max});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await ConfigService().setVoltageMin(result['min']!);
      await ConfigService().setVoltageMax(result['max']!);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voltage thresholds updated')),
        );
      }
    }
  }

  void _showAmperageThresholdDialog() async {
    final controller =
        TextEditingController(text: ConfigService().amperageMax.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Amperage Threshold'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Maximum Amperage (A)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final max = double.tryParse(controller.text.trim()) ??
                  ConfigService().amperageMax;
              Navigator.pop(context, max);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (mounted) setState(() => _isSavingThresholds = true);
      await ConfigService().setAmperageMax(result);
      if (mounted) {
        setState(() => _isSavingThresholds = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amperage threshold updated')),
        );
      }
    }
  }

  Future<void> _changePassword(
      String currentPwd, String newPwd, String confirmPwd) async {
    if (newPwd != confirmPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Passwords do not match'),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (newPwd.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password must be at least 6 characters'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isChangingPassword = true);
    final result =
        await _authService.changePassword(currentPwd, newPwd, confirmPwd);

    if (mounted) {
      setState(() => _isChangingPassword = false);
      if (result != null && result['success'] == true) {
        // Add notification for password change
        NotificationService().addPasswordChangeNotification();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password changed'), backgroundColor: Colors.green),
        );
      } else if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result['detail'] ?? 'Error'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _confirmClearData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear App Data'),
        content: const Text(
            'This will clear all cached devices and settings. You will need to re-add your devices. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear device/appliance cache
      await prefs.remove('appliances');
      await prefs.remove('devices');
      await prefs.remove('cached_devices');

      // Clear other cached data
      await prefs.remove('notifications');
      await prefs.remove('energy_history');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App data cleared! Please restart the app.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      debugPrint('[OK] All app data cleared');
    } catch (e) {
      debugPrint('[ERROR] Failed to clear data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Only clear auth tokens, NOT appliances/devices cache
    // Devices will sync from backend when user logs back in
    await prefs.remove('access_token');
    await prefs.remove('user');
    // Note: We keep 'appliances' and 'deleted_device_ids' so they persist across login/logout

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthPage()),
        (route) => false,
      );
    }
  }

  Future<void> _toggleNotifications(bool enable) async {
    setState(() {
      _notificationsEnabled = enable;
      _isSavingPreferences = true;
    });

    await _authService.updateUserPreferences({
      'notifications_enabled': enable,
      'email_alerts': _emailAlertsEnabled,
    });

    if (mounted) {
      setState(() => _isSavingPreferences = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enable
              ? '🔔 Notifications enabled'
              : '🔕 Notifications disabled'),
          backgroundColor: AppColors.electricGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleEmailAlerts(bool enable) async {
    setState(() {
      _emailAlertsEnabled = enable;
      _isSavingPreferences = true;
    });

    await _authService.updateUserPreferences({
      'notifications_enabled': _notificationsEnabled,
      'email_alerts': enable,
    });

    if (mounted) {
      setState(() => _isSavingPreferences = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              enable ? '📧 Email alerts enabled' : '📧 Email alerts disabled'),
          backgroundColor: AppColors.electricGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Delete Account"),
          content: const Text(
              "⚠️ This action cannot be undone! All your data will be permanently deleted."),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text("Delete"),
              onPressed: () {
                _performDeleteAccount();
              },
            ),
          ],
        );
      },
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
      child: _isLoading
          ? _buildLoadingState(isDark)
          : RefreshIndicator(
              onRefresh: _loadProfileAndPreferences,
              color: AppColors.primaryBlue,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // User Profile Header
                  _buildUserProfileHeader(isDark),

                  const SizedBox(height: 24),

                  // Account Section
                  _buildSectionTitle('Account', isDark),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      icon: Icons.person_rounded,
                      iconColor: AppColors.primaryBlue,
                      title: 'Edit Profile',
                      subtitle: 'Update your name and email',
                      trailing: _isSavingProfile
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primaryBlue))
                          : Icon(Icons.chevron_right_rounded,
                              color: Colors.grey.shade400),
                      onTap: _isSavingProfile ? null : _showProfileDialog,
                      isDark: isDark,
                    ),
                    if (!_isOAuthUser)
                      _buildSettingsTile(
                        icon: Icons.lock_rounded,
                        iconColor: AppColors.electricPurple,
                        title: 'Change Password',
                        subtitle: 'Update your password',
                        trailing: _isChangingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryBlue))
                            : Icon(Icons.chevron_right_rounded,
                                color: Colors.grey.shade400),
                        onTap: _isChangingPassword ? null : _showPasswordDialog,
                        isDark: isDark,
                      ),
                    if (_isOAuthUser)
                      _buildInfoTile(
                        icon: Icons.security_rounded,
                        iconColor: AppColors.info,
                        title: 'Google Account',
                        subtitle: 'Password managed by Google',
                        isDark: isDark,
                      ),
                  ], isDark),

                  const SizedBox(height: 24),

                  // Preferences Section
                  _buildSectionTitle('Preferences', isDark),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSwitchTile(
                      icon: Icons.notifications_rounded,
                      iconColor: AppColors.primaryBlue,
                      title: 'Notifications',
                      subtitle: _notificationsEnabled
                          ? 'Alerts enabled'
                          : 'Alerts disabled',
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                      isLoading: _isSavingPreferences,
                      isDark: isDark,
                    ),
                    _buildSwitchTile(
                      icon: Icons.email_rounded,
                      iconColor: AppColors.electricOrange,
                      title: 'Email Alerts',
                      subtitle: _emailAlertsEnabled
                          ? 'Email notifications on'
                          : 'Email notifications off',
                      value: _emailAlertsEnabled,
                      onChanged: _toggleEmailAlerts,
                      isLoading: _isSavingPreferences,
                      isDark: isDark,
                    ),
                  ], isDark),

                  const SizedBox(height: 24),

                  // System Settings Section
                  _buildSectionTitle('System', isDark),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      icon: Icons.link_rounded,
                      iconColor: AppColors.primaryBlue,
                      title: 'Backend URL',
                      subtitle: _backendUrl.isEmpty ? 'Not set' : _backendUrl,
                      trailing: _isSavingBackend
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primaryBlue))
                          : Icon(Icons.chevron_right_rounded,
                              color: Colors.grey.shade400),
                      onTap: _showBackendDialog,
                      isDark: isDark,
                    ),
                    _buildSettingsTile(
                      icon: Icons.electric_bolt_rounded,
                      iconColor: AppColors.electricYellow,
                      title: 'Voltage Thresholds',
                      subtitle:
                          'Min: ${ConfigService().voltageMin}V, Max: ${ConfigService().voltageMax}V',
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      onTap: _showVoltageThresholdDialog,
                      isDark: isDark,
                    ),
                    _buildSettingsTile(
                      icon: Icons.flash_on_rounded,
                      iconColor: AppColors.warning,
                      title: 'Amperage Threshold',
                      subtitle: 'Max: ${ConfigService().amperageMax}A',
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      onTap: _showAmperageThresholdDialog,
                      isDark: isDark,
                    ),
                  ], isDark),

                  const SizedBox(height: 24),

                  // About Section
                  _buildSectionTitle('About', isDark),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      icon: Icons.info_rounded,
                      iconColor: AppColors.info,
                      title: 'About',
                      subtitle: 'App version and details',
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: "Smart Home IoT",
                          applicationVersion: "1.0.0",
                          applicationIcon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primaryBlue,
                                  AppColors.electricPurple
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.home_rounded,
                                color: Colors.white, size: 32),
                          ),
                          applicationLegalese: "© 2025 Smart Home IoT",
                        );
                      },
                      isDark: isDark,
                    ),
                  ], isDark),

                  const SizedBox(height: 24),

                  // Actions Section
                  _buildSectionTitle('Actions', isDark),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      icon: Icons.cleaning_services_rounded,
                      iconColor: Colors.orange,
                      title: 'Clear App Data',
                      subtitle: 'Clear cached devices and settings',
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      onTap: _confirmClearData,
                      isDark: isDark,
                    ),
                    _buildSettingsTile(
                      icon: Icons.logout_rounded,
                      iconColor: AppColors.warning,
                      title: 'Logout',
                      subtitle: 'Sign out of your account',
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      onTap: _confirmLogout,
                      isDark: isDark,
                    ),
                    _buildSettingsTile(
                      icon: Icons.delete_forever_rounded,
                      iconColor: AppColors.error,
                      title: 'Delete Account',
                      subtitle: 'Permanently remove your account',
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: AppColors.error.withValues(alpha: 0.5)),
                      onTap: _confirmDeleteAccount,
                      isDark: isDark,
                      isDestructive: true,
                    ),
                  ], isDark),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildUserProfileHeader(bool isDark) {
    final userName = _profile['name'] ?? 'User';
    final userEmail = _profile['email'] ?? 'Not logged in';
    final initials = userName.isNotEmpty
        ? userName
            .split(' ')
            .map((n) => n.isNotEmpty ? n[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : 'U';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            AppColors.electricPurple,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userEmail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isOAuthUser
                            ? Icons.g_mobiledata_rounded
                            : Icons.email_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isOAuthUser ? 'Google Account' : 'Email Account',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Refresh button
          IconButton(
            onPressed: _loadProfileAndPreferences,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh profile',
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
                  color: AppColors.primaryBlue.withValues(alpha: 0.2),
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
            'Loading settings...',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBgCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.1 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                  height: 1,
                  indent: 60,
                  color: Colors.grey.withValues(alpha: 0.15)),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback? onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDestructive
                            ? AppColors.error
                            : (isDark ? Colors.white : AppColors.darkBg),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required bool isDark,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: iconColor))
                : Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.darkBg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.electricGreen,
              activeTrackColor: AppColors.electricGreen.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.darkBg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteAccount() async {
    Navigator.of(context).pop();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return const AlertDialog(
          content: SizedBox(
            height: 80,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );

    try {
      final result = await _authService.deleteAccount();

      if (mounted) {
        Navigator.of(context).pop();

        if (result != null && result['success'] == true) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.clear();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your account has been deleted.'),
                backgroundColor: Colors.red,
              ),
            );

            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const AuthPage()),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
