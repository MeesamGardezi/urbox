import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../models/company.dart';
import '../models/user_profile.dart';
import '../../auth/services/auth_service.dart';
import '../services/subscription_service.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';

/// URBox Dashboard - Main App Shell
///
/// This screen IS the app shell with persistent sidebar.
/// It renders different content in the main area based on the current route.
class DashboardScreen extends StatefulWidget {
  final Widget? child; // Optional child for nested routes

  const DashboardScreen({super.key, this.child});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final user = FirebaseAuth.instance.currentUser;
  UserProfile? _userProfile;
  Company? _company;
  bool _isLoading = true;
  String? _loadError;
  bool _isSidebarCollapsed = false;
  String? _companyId;
  String? _userName;

  @override
  void initState() {
    super.initState();
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
    if (user == null) {
      if (mounted) context.go('/auth');
      return;
    }

    try {
      debugPrint('Loading user profile for ${user!.uid}...');

      final userResponse = await AuthService.getUserProfile(user!.uid);

      if (userResponse['success'] != true) {
        throw Exception(userResponse['error'] ?? 'Failed to load user profile');
      }

      final userData = userResponse['user'] as Map<String, dynamic>;

      _userProfile = UserProfile(
        id: userData['id']?.toString() ?? user!.uid,
        email: userData['email']?.toString() ?? '',
        displayName: userData['displayName']?.toString() ?? '',
        companyId: userData['companyId']?.toString() ?? '',
        role: userData['role']?.toString() ?? 'member',
        assignedInboxIds: List<String>.from(userData['assignedInboxIds'] ?? []),
        status: userData['status']?.toString() ?? 'active',
        mfaEnabled: userData['mfaEnabled'] == true,
        phoneNumber: userData['phoneNumber']?.toString(),
        timezone: userData['timezone']?.toString(),
        language: userData['language']?.toString(),
        createdAt: _parseDateTime(userData['createdAt']),
        lastLoginAt: _parseDateTime(userData['lastLoginAt']),
        updatedAt: _parseDateTime(userData['updatedAt']),
      );

      _companyId = _userProfile!.companyId;
      _userName = _userProfile!.displayName.isNotEmpty
          ? _userProfile!.displayName
          : user!.email?.split('@').first;

      // Fetch company data
      if (_userProfile!.companyId.isNotEmpty) {
        final companyResponse = await SubscriptionService.getCompanyPlan(
          _userProfile!.companyId,
        );

        if (companyResponse['success'] == true &&
            companyResponse['company'] != null) {
          final companyData =
              companyResponse['company'] as Map<String, dynamic>;

          _company = Company(
            id: _userProfile!.companyId,
            name: companyData['companyName']?.toString() ?? 'Your Company',
            ownerId: '',
            plan: companyData['plan']?.toString() ?? 'free',
            isFree: companyData['isFree'] == true,
            isProFree: companyData['isProFree'] == true,
            subscriptionStatus:
                companyData['subscriptionStatus']?.toString() ?? 'none',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
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

  void _handleLogout() {
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
              FirebaseAuth.instance.signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    final sidebarWidth = _isSidebarCollapsed ? 72.0 : 260.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: sidebarWidth,
            child: _buildSidebar(currentLocation),
          ),

          // Divider
          Container(width: 1, color: AppTheme.border),

          // Main Content Area
          Expanded(child: widget.child ?? _buildDefaultDashboardContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar(String currentLocation) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildSidebarHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacing4,
                horizontal: AppTheme.spacing3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isSidebarCollapsed) _buildSectionHeader('MAIN'),
                  if (!_isSidebarCollapsed)
                    const SizedBox(height: AppTheme.spacing2),
                  _buildNavItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    route: '/dashboard',
                    isSelected: currentLocation == '/dashboard',
                  ),
                  _buildNavItem(
                    icon: Icons.inbox_outlined,
                    activeIcon: Icons.inbox,
                    label: 'Inbox',
                    route: '/inbox',
                    isSelected: currentLocation.startsWith('/inbox'),
                  ),
                  _buildNavItem(
                    icon: Icons.send_outlined,
                    activeIcon: Icons.send,
                    label: 'Sent',
                    route: '/sent',
                    isSelected: currentLocation == '/sent',
                  ),

                  const SizedBox(height: AppTheme.spacing6),

                  if (!_isSidebarCollapsed) _buildSectionHeader('SETTINGS'),
                  if (!_isSidebarCollapsed)
                    const SizedBox(height: AppTheme.spacing2),
                  _buildNavItem(
                    icon: Icons.email_outlined,
                    activeIcon: Icons.email,
                    label: 'Email Accounts',
                    route: '/accounts',
                    isSelected: currentLocation == '/accounts',
                  ),
                  _buildNavItem(
                    icon: Icons.folder_outlined,
                    activeIcon: Icons.folder,
                    label: 'Manage Inboxes',
                    route: '/custom-inboxes',
                    isSelected: currentLocation == '/custom-inboxes',
                  ),
                  _buildNavItem(
                    icon: Icons.credit_card_outlined,
                    activeIcon: Icons.credit_card,
                    label: 'Plans & Billing',
                    route: '/plans',
                    isSelected: currentLocation == '/plans',
                  ),
                  _buildNavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Settings',
                    route: '/settings',
                    isSelected: currentLocation == '/settings',
                  ),

                  const SizedBox(height: AppTheme.spacing6),

                  if (!_isSidebarCollapsed) _buildSectionHeader('INTEGRATIONS'),
                  if (!_isSidebarCollapsed)
                    const SizedBox(height: AppTheme.spacing2),
                  _buildNavItem(
                    icon: Icons.chat_outlined,
                    activeIcon: Icons.chat,
                    label: 'WhatsApp',
                    route: '/whatsapp',
                    isSelected: currentLocation == '/whatsapp',
                  ),
                  _buildNavItem(
                    icon: Icons.cloud_outlined,
                    activeIcon: Icons.cloud,
                    label: 'Storage',
                    route: '/storage',
                    isSelected: currentLocation == '/storage',
                  ),
                ],
              ),
            ),
          ),
          _buildUserSection(),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(
        horizontal: _isSidebarCollapsed ? AppTheme.spacing3 : AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: const Icon(
              Icons.all_inbox_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),

          if (!_isSidebarCollapsed) ...[
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Text(
                'URBox',
                style: AppTheme.headingSm.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],

          IconButton(
            onPressed: () =>
                setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            icon: Icon(
              _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
              color: AppTheme.textMuted,
              size: 20,
            ),
            tooltip: _isSidebarCollapsed
                ? 'Expand sidebar'
                : 'Collapse sidebar',
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.spacing2,
        bottom: AppTheme.spacing1,
      ),
      child: Text(
        label,
        style: AppTheme.labelSm.copyWith(
          color: AppTheme.textMuted,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String route,
    bool isSelected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: () => context.go(route),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          hoverColor: AppTheme.gray100,
          splashColor: AppTheme.primary.withOpacity(0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed
                  ? AppTheme.spacing3
                  : AppTheme.spacing3,
              vertical: AppTheme.spacing3,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primary.withOpacity(0.08) : null,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  size: 20,
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTheme.bodyMd.copyWith(
                        color: isSelected
                            ? AppTheme.primary
                            : Theme.of(context).textTheme.bodyMedium?.color,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserSection() {
    return Container(
      padding: EdgeInsets.all(
        _isSidebarCollapsed ? AppTheme.spacing3 : AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          if (!_isSidebarCollapsed)
            Container(
              padding: const EdgeInsets.all(AppTheme.spacing3),
              margin: const EdgeInsets.only(bottom: AppTheme.spacing3),
              decoration: BoxDecoration(
                color: AppTheme.gray50,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Center(
                      child: Text(
                        (_userName ?? 'U').substring(0, 1).toUpperCase(),
                        style: AppTheme.labelLg.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName ?? 'User',
                          style: AppTheme.labelMd.copyWith(
                            color: Theme.of(
                              context,
                            ).textTheme.titleSmall?.color,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? '',
                          style: AppTheme.labelSm.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: InkWell(
              onTap: _handleLogout,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: AppTheme.spacing3,
                  horizontal: _isSidebarCollapsed
                      ? AppTheme.spacing3
                      : AppTheme.spacing2 + 4,
                ),
                child: Row(
                  mainAxisAlignment: _isSidebarCollapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
                    if (!_isSidebarCollapsed) ...[
                      const SizedBox(width: AppTheme.spacing3),
                      Text(
                        'Sign out',
                        style: AppTheme.bodyMd.copyWith(
                          color: AppTheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Default dashboard content when on /dashboard route
  Widget _buildDefaultDashboardContent() {
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
                _loadError ?? 'Please check your internet connection',
                style: AppTheme.bodyMd.copyWith(color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacing8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeHeader(),
              const SizedBox(height: AppTheme.spacing6),
              if (_company != null) _buildPlanStatusCard(),
              const SizedBox(height: AppTheme.spacing6),
              _buildQuickStats(),
              const SizedBox(height: AppTheme.spacing6),
              _buildGettingStarted(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing6),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: const Icon(
                Icons.waving_hand,
                color: Colors.white,
                size: 28,
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
                    onPressed: () => context.go('/plans'),
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
              onTap: () => context.go('/accounts'),
            ),
            const Divider(height: AppTheme.spacing6),
            _buildGettingStartedItem(
              icon: Icons.people_outline,
              title: 'Invite team members',
              description: 'Collaborate with your team on shared inboxes',
              completed: false,
              onTap: () => context.go('/settings'),
            ),
            const Divider(height: AppTheme.spacing6),
            _buildGettingStartedItem(
              icon: Icons.inbox,
              title: 'Create a shared inbox',
              description: 'Organize your emails with custom inboxes',
              completed: false,
              onTap: () => context.go('/custom-inboxes'),
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
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
        child: Row(
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
            Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
