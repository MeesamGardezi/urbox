import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/company.dart';
import '../models/user_profile.dart';
import '../../auth/services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/theme_service.dart';

/// Settings Screen - Fortune 500 Design
///
/// Features:
/// - Clean sectioned layout
/// - Profile management
/// - Company information
/// - Appearance settings
/// - Notifications preferences
/// - Security settings
/// - Professional corporate aesthetic
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final user = FirebaseAuth.instance.currentUser;
  UserProfile? _userProfile;
  Company? _company;
  bool _isLoading = true;

  // Settings toggles
  bool _emailNotifications = true;
  bool _desktopNotifications = false;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _darkMode = ThemeService().isDarkMode;
    _loadData();
  }

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'] ?? 0;
      final nanoseconds = value['_nanoseconds'] ?? value['nanoseconds'] ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000) + (nanoseconds ~/ 1000000),
      );
    }
    return DateTime.now();
  }

  Future<void> _loadData() async {
    if (user == null) return;

    try {
      debugPrint('[Settings] Loading user data for: ${user!.uid}');

      // Make both API calls in parallel for faster loading
      final results = await Future.wait([
        AuthService.getUserProfile(user!.uid),
        // We'll get company data after we have the user profile
        Future.value({'success': false}), // Placeholder
      ]);

      final userResponse = results[0];

      if (userResponse['success'] == true) {
        final userData = userResponse['user'] as Map<String, dynamic>;

        _userProfile = UserProfile(
          id: userData['id']?.toString() ?? user!.uid,
          email: userData['email']?.toString() ?? '',
          displayName: userData['displayName']?.toString() ?? '',
          companyId: userData['companyId']?.toString() ?? '',
          role: userData['role']?.toString() ?? 'member',
          assignedInboxIds: List<String>.from(
            userData['assignedInboxIds'] ?? [],
          ),
          status: userData['status']?.toString() ?? 'active',
          mfaEnabled: userData['mfaEnabled'] == true,
          phoneNumber: userData['phoneNumber']?.toString(),
          timezone: userData['timezone']?.toString(),
          language: userData['language']?.toString(),
          createdAt: _parseDateTime(userData['createdAt']),
          lastLoginAt: _parseDateTime(userData['lastLoginAt']),
          updatedAt: _parseDateTime(userData['updatedAt']),
          emailNotifications: userData['emailNotifications'] == true,
          pushNotifications: userData['pushNotifications'] == true,
          preferences: Map<String, dynamic>.from(userData['preferences'] ?? {}),
        );

        debugPrint(
          '[Settings] User profile loaded. CompanyId: ${_userProfile!.companyId}',
        );

        if (mounted) {
          setState(() {
            _emailNotifications = _userProfile!.emailNotifications;
            _desktopNotifications = _userProfile!.pushNotifications;
            // Sync local state with already-initialized ThemeService
            _darkMode = ThemeService().isDarkMode;
            // Show UI immediately with user data
            _isLoading = false;
          });
        }

        // Load company data in the background (non-blocking)
        if (_userProfile!.companyId.isNotEmpty) {
          debugPrint(
            '[Settings] Triggering company data load for: ${_userProfile!.companyId}',
          );
          _loadCompanyData(_userProfile!.companyId);
        } else {
          debugPrint(
            '[Settings] No company ID found, skipping company data load',
          );
        }
      } else {
        debugPrint(
          '[Settings] User profile load failed: ${userResponse['error']}',
        );
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('[Settings] Error loading settings data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCompanyData(String companyId) async {
    debugPrint('[Settings] Loading company data for: $companyId');
    try {
      final companyResponse = await SubscriptionService.getCompanyPlan(
        companyId,
      );

      debugPrint('[Settings] Company response: ${companyResponse['success']}');
      debugPrint('[Settings] Full response: $companyResponse');

      if (companyResponse['success'] == true) {
        // The data is returned directly in the response, not nested under 'company'
        debugPrint(
          '[Settings] Company data received: ${companyResponse['companyName']}',
        );

        if (mounted) {
          setState(() {
            _company = Company(
              id: companyId,
              name:
                  companyResponse['companyName']?.toString() ?? 'Your Company',
              ownerId: '',
              plan: companyResponse['plan']?.toString() ?? 'free',
              isFree: companyResponse['isFree'] == true,
              isProFree: companyResponse['isProFree'] == true,
              subscriptionStatus:
                  companyResponse['subscriptionStatus']?.toString() ?? 'none',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              memberCount: companyResponse['memberCount'] is int
                  ? companyResponse['memberCount']
                  : 1,
            );
          });
          debugPrint('[Settings] Company state updated successfully');
        } else {
          debugPrint('[Settings] Widget not mounted, skipping state update');
        }
      } else {
        debugPrint(
          '[Settings] Company response failed: ${companyResponse['error']}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[Settings] Error loading company data: $e');
      debugPrint('[Settings] Stack trace: $stackTrace');
      // Don't show error to user, company section will just show loading state
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _iconBgColor => _isDark ? AppTheme.gray800 : AppTheme.gray50;
  Color get _textColor =>
      Theme.of(context).textTheme.bodyMedium?.color ?? AppTheme.textPrimary;
  Color get _subtitleColor =>
      Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacing8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: AppTheme.spacing8),
              _buildProfileSection(),
              const SizedBox(height: AppTheme.spacing6),
              _buildCompanySection(),
              const SizedBox(height: AppTheme.spacing6),
              _buildPreferencesSection(),
              const SizedBox(height: AppTheme.spacing6),
              _buildNotificationsSection(),
              const SizedBox(height: AppTheme.spacing6),
              _buildSecuritySection(),
              const SizedBox(height: AppTheme.spacing6),
              _buildDangerZone(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: AppTheme.headingXl.copyWith(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: _textColor,
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        Text(
          'Manage your account settings and preferences',
          style: AppTheme.bodyLg.copyWith(color: _subtitleColor, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildProfileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: AppTheme.primary, size: 24),
                const SizedBox(width: AppTheme.spacing3),
                Text(
                  'Profile Information',
                  style: AppTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing6),

            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: Center(
                    child: Text(
                      (_userProfile?.displayName ?? 'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userProfile?.displayName ?? 'User',
                        style: AppTheme.headingSm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                      Text(
                        user?.email ?? '',
                        style: AppTheme.bodyMd.copyWith(color: _subtitleColor),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _handleEditProfile(),
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: _isDark ? Colors.white : AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacing6),
            const Divider(),
            const SizedBox(height: AppTheme.spacing6),

            _buildInfoRow(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: _userProfile?.role.toUpperCase() ?? 'MEMBER',
            ),
            const SizedBox(height: AppTheme.spacing4),
            _buildInfoRow(
              icon: Icons.access_time_outlined,
              label: 'Member Since',
              value: _formatDate(_userProfile?.createdAt),
            ),
            const SizedBox(height: AppTheme.spacing4),
            _buildInfoRow(
              icon: Icons.schedule_outlined,
              label: 'Last Login',
              value: _formatDate(_userProfile?.lastLoginAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.business_outlined,
                  color: AppTheme.primary,
                  size: 24,
                ),
                const SizedBox(width: AppTheme.spacing3),
                Text(
                  'Company Information',
                  style: AppTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing6),

            if (_company != null) ...[
              _buildInfoRow(
                icon: Icons.corporate_fare_outlined,
                label: 'Company Name',
                value: _company!.name,
              ),
              const SizedBox(height: AppTheme.spacing4),
              _buildInfoRow(
                icon: Icons.workspace_premium_outlined,
                label: 'Plan',
                value: _company!.isProFree
                    ? 'Pro (Forever Free)'
                    : _company!.hasProAccess
                    ? 'Pro'
                    : 'Free',
              ),
              const SizedBox(height: AppTheme.spacing4),
              _buildInfoRow(
                icon: Icons.people_outline,
                label: 'Team Size',
                value:
                    '${_company!.memberCount} member${_company!.memberCount != 1 ? 's' : ''}',
              ),
            ] else ...[
              // Loading skeleton
              _buildLoadingSkeleton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      children: [
        _buildSkeletonRow(),
        const SizedBox(height: AppTheme.spacing4),
        _buildSkeletonRow(),
        const SizedBox(height: AppTheme.spacing4),
        _buildSkeletonRow(),
      ],
    );
  }

  Widget _buildSkeletonRow() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _iconBgColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
        ),
        const SizedBox(width: AppTheme.spacing3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: _iconBgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 16,
                width: 120,
                decoration: BoxDecoration(
                  color: _iconBgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_outlined, color: AppTheme.primary, size: 24),
                const SizedBox(width: AppTheme.spacing3),
                Text(
                  'Preferences',
                  style: AppTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing6),

            _buildToggleRow(
              icon: Icons.dark_mode_outlined,
              title: 'Dark Mode',
              subtitle: 'Switch to dark theme',
              value: _darkMode,
              onChanged: (value) async {
                setState(() => _darkMode = value);
                ThemeService().toggleTheme(value);
                await _updatePreferences();
              },
            ),
            const Divider(height: AppTheme.spacing6),
            _buildSelectRow(
              icon: Icons.language_outlined,
              title: 'Language',
              subtitle: 'Choose your preferred language',
              value: _userProfile?.language ?? 'English',
              onTap: () => _handleLanguage(),
            ),
            const Divider(height: AppTheme.spacing6),
            _buildSelectRow(
              icon: Icons.access_time_outlined,
              title: 'Timezone',
              subtitle: 'Set your local timezone',
              value: _userProfile?.timezone ?? 'UTC',
              onTap: () => _handleTimezone(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.primary,
                  size: 24,
                ),
                const SizedBox(width: AppTheme.spacing3),
                Text(
                  'Notifications',
                  style: AppTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing6),

            _buildToggleRow(
              icon: Icons.email_outlined,
              title: 'Email Notifications',
              subtitle: 'Receive updates via email',
              value: _emailNotifications,
              onChanged: (value) {
                setState(() => _emailNotifications = value);
                _updatePreferences();
              },
            ),
            const Divider(height: AppTheme.spacing6),
            _buildToggleRow(
              icon: Icons.desktop_windows_outlined,
              title: 'Desktop Notifications',
              subtitle: 'Show desktop push notifications',
              value: _desktopNotifications,
              onChanged: (value) {
                setState(() => _desktopNotifications = value);
                _updatePreferences();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.security_outlined,
                  color: AppTheme.primary,
                  size: 24,
                ),
                const SizedBox(width: AppTheme.spacing3),
                Text(
                  'Security',
                  style: AppTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing6),

            _buildActionRow(
              icon: Icons.lock_outline,
              title: 'Change Password',
              subtitle: 'Update your password',
              onTap: () => _handleChangePassword(),
            ),
            const Divider(height: AppTheme.spacing6),
            _buildActionRow(
              icon: Icons.phonelink_lock_outlined,
              title: 'Two-Factor Authentication',
              subtitle: _userProfile?.mfaEnabled == true
                  ? 'Enabled'
                  : 'Not enabled',
              onTap: () => _showComingSoon(),
            ),
            const Divider(height: AppTheme.spacing6),
            _buildActionRow(
              icon: Icons.devices_outlined,
              title: 'Active Sessions',
              subtitle: 'Manage your logged-in devices',
              onTap: () => _showComingSoon(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    return Card(
      color: AppTheme.error.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        side: BorderSide(color: AppTheme.error.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_outlined, color: AppTheme.error, size: 24),
                const SizedBox(width: AppTheme.spacing3),
                Text(
                  'Danger Zone',
                  style: AppTheme.headingMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing6),

            _buildActionRow(
              icon: Icons.delete_outline,
              title: 'Delete Account',
              subtitle: 'Permanently delete your account and all data',
              textColor: AppTheme.error,
              onTap: () => _handleDeleteAccount(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing2),
          decoration: BoxDecoration(
            color: _iconBgColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(icon, size: 18, color: _subtitleColor),
        ),
        const SizedBox(width: AppTheme.spacing3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.labelSm.copyWith(
                  color: _subtitleColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTheme.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing2),
          decoration: BoxDecoration(
            color: _iconBgColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(icon, size: 18, color: _subtitleColor),
        ),
        const SizedBox(width: AppTheme.spacing3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.labelMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTheme.bodySm.copyWith(color: _subtitleColor),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primary,
        ),
      ],
    );
  }

  Widget _buildSelectRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing2),
              decoration: BoxDecoration(
                color: _iconBgColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(icon, size: 18, color: _subtitleColor),
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.labelMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bodySm.copyWith(color: _subtitleColor),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: AppTheme.bodyMd.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Icon(Icons.chevron_right, size: 20, color: _subtitleColor),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing2),
              decoration: BoxDecoration(
                color: textColor?.withOpacity(0.1) ?? _iconBgColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(icon, size: 18, color: textColor ?? _subtitleColor),
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.labelMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textColor ?? _textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bodySm.copyWith(
                      color: textColor?.withOpacity(0.7) ?? _subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: textColor ?? _subtitleColor,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    if (difference.inDays < 30)
      return '${(difference.inDays / 7).floor()} weeks ago';
    if (difference.inDays < 365)
      return '${(difference.inDays / 30).floor()} months ago';
    return '${(difference.inDays / 365).floor()} years ago';
  }

  void _handleDeleteAccount() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_outlined, color: AppTheme.error),
            const SizedBox(width: AppTheme.spacing3),
            const Text('Delete Account?'),
          ],
        ),
        content: const Text(
          'This action cannot be undone. All your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              if (user == null) return;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              );

              final result = await AuthService.deleteAccount(user!.uid);

              if (!mounted) return;
              Navigator.pop(context); // Pop loading

              if (result['success'] == true) {
                await FirebaseAuth.instance.signOut();
                // Router will handle redirect to login
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['error'] ?? 'Failed to delete account',
                    ),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePreferences() async {
    if (user == null) return;

    final preferences = {
      'darkMode': _darkMode,
      'language': 'en', // TODO: Make dynamic
      'timezone': 'UTC', // TODO: Make dynamic
    };

    await AuthService.updatePreferences(
      userId: user!.uid,
      preferences: preferences,
      emailNotifications: _emailNotifications,
      pushNotifications: _desktopNotifications,
    );
  }

  void _handleChangePassword() {
    final passwordController = TextEditingController();
    bool obscureText = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Password'),
          content: TextField(
            controller: passwordController,
            obscureText: obscureText,
            decoration: InputDecoration(
              labelText: 'New Password',
              suffixIcon: IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => obscureText = !obscureText),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (passwordController.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password must be at least 6 characters'),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) =>
                      const Center(child: CircularProgressIndicator()),
                );

                final result = await AuthService.changePassword(
                  userId: user!.uid,
                  newPassword: passwordController.text,
                );

                if (!mounted) return;
                Navigator.pop(context); // Pop loading

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['success'] == true
                          ? 'Password updated successfully'
                          : (result['error'] ?? 'Failed to update password'),
                    ),
                    backgroundColor: result['success'] == true
                        ? Colors.green
                        : AppTheme.error,
                  ),
                );
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleEditProfile() {
    if (_userProfile == null) return;

    final nameController = TextEditingController(
      text: _userProfile!.displayName,
    );
    final phoneController = TextEditingController(
      text: _userProfile!.phoneNumber,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
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
            onPressed: () async {
              Navigator.pop(context);

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              );

              final result = await AuthService.updateProfile(
                userId: user!.uid,
                displayName: nameController.text,
                phoneNumber: phoneController.text,
              );

              if (!mounted) return;
              Navigator.pop(context); // Pop loading

              if (result['success'] == true) {
                // Reload data
                await _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile updated successfully'),
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['error'] ?? 'Failed to update profile',
                    ),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature is coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleLanguage() async {
    final languages = ['English', 'Spanish', 'French', 'German'];

    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Language'),
        children: languages
            .map(
              (lang) => SimpleDialogOption(
                onPressed: () async {
                  Navigator.pop(context);

                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  await AuthService.updateProfile(
                    userId: user!.uid,
                    language: lang,
                  );

                  if (!mounted) return;
                  Navigator.pop(context); // Pop loading
                  await _loadData();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(lang),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _handleTimezone() async {
    final timezones = [
      'UTC',
      'America/New_York',
      'America/Los_Angeles',
      'Europe/London',
      'Europe/Paris',
      'Asia/Tokyo',
      'Australia/Sydney',
    ];

    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Timezone'),
        children: timezones
            .map(
              (tz) => SimpleDialogOption(
                onPressed: () async {
                  Navigator.pop(context);

                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  await AuthService.updateProfile(
                    userId: user!.uid,
                    timezone: tz,
                  );

                  if (!mounted) return;
                  Navigator.pop(context); // Pop loading
                  await _loadData();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(tz),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
