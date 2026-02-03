import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/company.dart';
import '../models/user_profile.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (user == null) return;

    try {
      // Load user profile
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (userDoc.exists) {
        _userProfile = UserProfile.fromFirestore(userDoc);

        // Load company
        final companyDoc = await FirebaseFirestore.instance
            .collection('companies')
            .doc(_userProfile!.companyId)
            .get();

        if (companyDoc.exists) {
          _company = Company.fromFirestore(companyDoc);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard', style: AppTheme.headingMd),
        actions: [
          // Plans button
          if (_company != null && _company!.canUpgrade)
            TextButton.icon(
              onPressed: () => context.push('/plans'),
              icon: const Icon(Icons.upgrade, size: 18),
              label: const Text('Upgrade to Pro'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),

          // Settings button
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacing6),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome Section
                      _buildWelcomeSection(),

                      const SizedBox(height: AppTheme.spacing8),

                      // Plan Status Card
                      if (_company != null) _buildPlanStatusCard(),

                      const SizedBox(height: AppTheme.spacing6),

                      // Quick Stats
                      _buildQuickStats(),

                      const SizedBox(height: AppTheme.spacing8),

                      // Getting Started
                      _buildGettingStarted(),
                    ],
                  ),
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
                    _company?.name ?? 'Loading...',
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
