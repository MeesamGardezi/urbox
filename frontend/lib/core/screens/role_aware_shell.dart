import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/services/auth_service.dart';
import 'dashboard_screen.dart';
import 'team_member_shell.dart';
import '../models/user_profile.dart';

/// Role-aware shell that shows different UI based on user role
/// Owners see full DashboardScreen, team members see simplified TeamMemberShell
class RoleAwareShell extends StatefulWidget {
  final Widget child;

  const RoleAwareShell({super.key, required this.child});

  @override
  State<RoleAwareShell> createState() => _RoleAwareShellState();
}

class _RoleAwareShellState extends State<RoleAwareShell> {
  UserProfile? _userProfile;
  bool _isLoading = true;

  // Owner-only routes that team members cannot access
  static const _ownerOnlyRoutes = [
    '/accounts',
    '/custom-inboxes',
    '/plans',
    '/team',
    '/whatsapp',
    '/slack',
  ];

  @override
  void initState() {
    super.initState();
    _fetchMemberInfo();
  }

  Future<void> _fetchMemberInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final userResponse = await AuthService.getUserProfile(user.uid);

      if (mounted) {
        if (userResponse['success'] == true) {
          final userData = userResponse['user'] as Map<String, dynamic>;
          setState(() {
            _userProfile = UserProfile(
              id: userData['id']?.toString() ?? user.uid,
              email: userData['email']?.toString() ?? '',
              displayName: userData['displayName']?.toString() ?? '',
              companyId: userData['companyId']?.toString() ?? '',
              role: userData['role']?.toString() ?? 'member',
              assignedInboxIds: List<String>.from(
                userData['assignedInboxIds'] ?? [],
              ),
              status: userData['status']?.toString() ?? 'active',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error fetching member info: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If user info not found, default to owner shell (safest fallback? or member?)
    // Defaulting to owner might expose UI, but data is protected by backend.
    // Let's default to member shell for safety if profile fails but user is logged in.
    // Actually, DashboardScreen handles its own loading, so maybe DashboardScreen is better fallback?
    // Let's use DashboardScreen as fallback.
    if (_userProfile == null) {
      return DashboardScreen(child: widget.child);
    }

    // Owner gets full DashboardScreen
    if (_userProfile!.isOwner) {
      return DashboardScreen(child: widget.child);
    }

    // --- Team Member Logic ---
    final currentLocation = GoRouterState.of(context).matchedLocation;

    // Check if team member is trying to access owner-only route
    // We check if current location STARTS with any of the restricted routes
    // to handle sub-routes like /custom-inbox/:id (though that is under /custom-inboxes usually?)
    // Actually /custom-inboxes is the list. /custom-inbox/:id is detail.
    // Let's check exact match or prefix if needed.
    bool iRestricted = _ownerOnlyRoutes.any(
      (route) => currentLocation.startsWith(route),
    );

    if (iRestricted) {
      return TeamMemberShell(child: _buildAccessDenied(context));
    }

    // Team member gets simplified TeamMemberShell for other valid routes
    return TeamMemberShell(child: widget.child);
  }

  Widget _buildAccessDenied(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 48,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Access Restricted',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This page is only available to workspace owners.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                context.go('/inbox');
              },
              icon: const Icon(Icons.inbox, size: 18),
              label: const Text('Go to My Inbox'),
            ),
          ],
        ),
      ),
    );
  }
}
