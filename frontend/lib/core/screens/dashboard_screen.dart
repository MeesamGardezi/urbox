import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/company.dart';
import '../models/user_profile.dart';
import '../../auth/services/auth_service.dart';
import '../services/subscription_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final user = FirebaseAuth.instance.currentUser;
  UserProfile? _userProfile;
  Company? _company;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Helper to parse DateTime from various formats (Firestore Timestamp, ISO string, or Map)
  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();

    if (value is DateTime) return value;

    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }

    // Handle Firestore Timestamp returned as Map: {_seconds: xxx, _nanoseconds: xxx}
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
    if (user == null) {
      if (mounted) {
        context.go('/auth');
      }
      return;
    }

    try {
      debugPrint('Loading user profile for ${user!.uid} via API...');

      // Fetch user profile through backend API
      final userResponse = await AuthService.getUserProfile(user!.uid);

      if (userResponse['success'] != true) {
        throw Exception(userResponse['error'] ?? 'Failed to load user profile');
      }

      final userData = userResponse['user'] as Map<String, dynamic>;
      debugPrint('User profile loaded: ${userData['displayName']}');

      // Create UserProfile from API response with proper type handling
      _userProfile = UserProfile(
        id: userData['id']?.toString() ?? user!.uid,
        email: userData['email']?.toString() ?? '',
        displayName: userData['displayName']?.toString() ?? '',
        companyId: userData['companyId']?.toString() ?? '',
        role: userData['role']?.toString() ?? 'member',
        assignedInboxIds: List<String>.from(userData['assignedInboxIds'] ?? []),
        status: userData['status']?.toString() ?? 'active',
        createdAt: _parseDateTime(userData['createdAt']),
        updatedAt: _parseDateTime(userData['updatedAt']),
        mfaEnabled: userData['mfaEnabled'] == true,
        phoneNumber: userData['phoneNumber']?.toString(),
        timezone: userData['timezone']?.toString(),
        language: userData['language']?.toString(),
      );

      // Fetch company/subscription data through backend API
      if (_userProfile!.companyId.isNotEmpty) {
        debugPrint('Loading company ${_userProfile!.companyId} via API...');

        final companyResponse = await SubscriptionService.getCompanyPlan(
          _userProfile!.companyId,
        );

        if (companyResponse['success'] == true) {
          debugPrint('Company data loaded');

          // Create Company from API response
          _company = Company(
            id: _userProfile!.companyId,
            name: companyResponse['companyName']?.toString() ?? 'Your Company',
            ownerId: '',
            plan: companyResponse['plan']?.toString() ?? 'free',
            isFree: companyResponse['isFree'] == true,
            isProFree: companyResponse['isProFree'] == true,
            subscriptionStatus:
                companyResponse['subscriptionStatus']?.toString() ?? 'none',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        } else {
          debugPrint('Company not found - continuing without company data');
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _retryLoad() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _userProfile = null;
      _company = null;
    });
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard', style: AppTheme.headingMd),
        actions: [
          if (_company != null && _company!.canUpgrade)
            TextButton.icon(
              onPressed: () => context.push('/plans'),
              icon: const Icon(Icons.upgrade, size: 18),
              label: const Text('Upgrade to Pro'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your dashboard...'),
          ],
        ),
      );
    }

    if (_loadError != null || _userProfile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Unable to load dashboard',
                style: AppTheme.headingMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _loadError ?? 'Failed to load user data',
                style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) {
                    context.go('/auth');
                  }
                },
                child: const Text('Sign out and try again'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(),
              const SizedBox(height: AppTheme.spacing8),
              if (_company != null) _buildPlanStatusCard(),
              const SizedBox(height: AppTheme.spacing6),
              _buildQuickStats(),
              const SizedBox(height: AppTheme.spacing8),
              _buildGettingStarted(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Center(
                child: Text(
                  (_userProfile?.displayName ?? 'U')[0].toUpperCase(),
                  style: AppTheme.headingLg.copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, ${_userProfile?.displayName ?? "User"}!',
                    style: AppTheme.headingMd,
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  Text(
                    _company?.name ?? 'Your Company',
                    style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanStatusCard() {
    final isProFree = _company!.isProFree;
    final hasPro = _company!.hasProAccess;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: hasPro ? AppTheme.primaryGradient : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasPro ? Icons.workspace_premium : Icons.inbox,
                  color: hasPro ? Colors.white : AppTheme.primary,
                  size: 32,
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPro ? 'Pro Plan' : 'Free Plan',
                        style: AppTheme.headingSm.copyWith(
                          color: hasPro ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                      Text(
                        isProFree
                            ? 'Special Forever-Free Pro Access'
                            : hasPro
                            ? 'All features unlocked'
                            : 'Limited to 1 shared inbox',
                        style: AppTheme.bodySm.copyWith(
                          color: hasPro
                              ? Colors.white.withOpacity(0.9)
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasPro)
                  ElevatedButton(
                    onPressed: () => context.push('/plans'),
                    child: const Text('Upgrade'),
                  ),
              ],
            ),
            if (isProFree) ...[
              const SizedBox(height: AppTheme.spacing3),
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 16),
                    const SizedBox(width: AppTheme.spacing1),
                    Text(
                      'VIP Account',
                      style: AppTheme.labelSm.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.inbox,
            label: 'Shared Inboxes',
            value: _company?.hasUnlimitedInboxes == true ? 'Unlimited' : '1',
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: AppTheme.spacing4),
        Expanded(
          child: _buildStatCard(
            icon: Icons.people_outline,
            label: 'Team Members',
            value: '-',
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(width: AppTheme.spacing4),
        Expanded(
          child: _buildStatCard(
            icon: Icons.mail_outline,
            label: 'Messages',
            value: '-',
            color: AppTheme.success,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: AppTheme.spacing3),
            Text(value, style: AppTheme.headingLg.copyWith(color: color)),
            const SizedBox(height: AppTheme.spacing1),
            Text(
              label,
              style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGettingStarted() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Getting Started', style: AppTheme.headingMd),
            const SizedBox(height: AppTheme.spacing4),
            _buildGettingStartedItem(
              icon: Icons.add_circle_outline,
              title: 'Connect your first email account',
              description: 'Add Gmail, Outlook, or any IMAP account',
              completed: false,
            ),
            const Divider(height: AppTheme.spacing6),
            _buildGettingStartedItem(
              icon: Icons.people_outline,
              title: 'Invite team members',
              description: 'Collaborate with your team on shared inboxes',
              completed: false,
            ),
            const Divider(height: AppTheme.spacing6),
            _buildGettingStartedItem(
              icon: Icons.inbox,
              title: 'Create a shared inbox',
              description: 'Organize your emails with custom inboxes',
              completed: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGettingStartedItem({
    required IconData icon,
    required String title,
    required String description,
    required bool completed,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: completed
                ? AppTheme.success.withOpacity(0.1)
                : AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Icon(
            completed ? Icons.check_circle : icon,
            color: completed ? AppTheme.success : AppTheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: AppTheme.spacing3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.labelMd.copyWith(
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: AppTheme.spacing1),
              Text(
                description,
                style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
