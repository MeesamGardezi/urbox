import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/services/auth_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../models/company.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Helper to parse DateTime from various formats
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
      final userResponse = await AuthService.getUserProfile(user!.uid);

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
          createdAt: _parseDateTime(userData['createdAt']),
          updatedAt: _parseDateTime(userData['updatedAt']),
          mfaEnabled: userData['mfaEnabled'] == true,
          phoneNumber: userData['phoneNumber']?.toString(),
          timezone: userData['timezone']?.toString(),
          language: userData['language']?.toString(),
        );

        if (_userProfile!.companyId.isNotEmpty) {
          final companyResponse = await SubscriptionService.getCompanyPlan(
            _userProfile!.companyId,
          );

          if (companyResponse['success'] == true) {
            _company = Company(
              id: _userProfile!.companyId,
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
            );
          }
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: AppTheme.headingMd),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacing6),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Account Section
                      _buildSection(
                        title: 'Account',
                        children: [
                          _buildInfoTile(
                            icon: Icons.person_outline,
                            label: 'Name',
                            value: _userProfile?.displayName ?? '-',
                          ),
                          _buildInfoTile(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: user?.email ?? '-',
                          ),
                          _buildInfoTile(
                            icon: Icons.badge_outlined,
                            label: 'Role',
                            value: _userProfile?.isOwner == true
                                ? 'Owner'
                                : 'Member',
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing6),

                      // Company Section
                      _buildSection(
                        title: 'Company',
                        children: [
                          _buildInfoTile(
                            icon: Icons.business_outlined,
                            label: 'Company Name',
                            value: _company?.name ?? '-',
                          ),
                          _buildInfoTile(
                            icon: Icons.workspace_premium,
                            label: 'Plan',
                            value: _company?.hasProAccess == true
                                ? (_company?.isProFree == true
                                      ? 'Pro (VIP)'
                                      : 'Pro')
                                : 'Free',
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing6),

                      // Actions Section
                      _buildSection(
                        title: 'Actions',
                        children: [
                          if (_company?.canUpgrade == true)
                            ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMd,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.upgrade,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                              ),
                              title: const Text('Upgrade to Pro'),
                              subtitle: const Text('Unlock all features'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/plans'),
                            ),

                          ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                              ),
                              child: const Icon(
                                Icons.logout,
                                color: AppTheme.error,
                                size: 20,
                              ),
                            ),
                            title: const Text('Logout'),
                            subtitle: const Text('Sign out of your account'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _handleLogout,
                          ),
                        ],
                      ),

                      const SizedBox(height: AppTheme.spacing8),

                      // App Info
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Shared Mailbox',
                              style: AppTheme.labelMd.copyWith(
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing1),
                            Text(
                              'Version 1.0.0',
                              style: AppTheme.labelSm.copyWith(
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacing4,
            bottom: AppTheme.spacing3,
          ),
          child: Text(
            title,
            style: AppTheme.labelLg.copyWith(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(label, style: AppTheme.labelMd),
      subtitle: Text(
        value,
        style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
      ),
    );
  }
}
