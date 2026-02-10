import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/services/auth_service.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../../custom_inboxes/services/custom_inbox_service.dart';
import '../../core/models/custom_inbox.dart';

/// Simplified application shell for team members.
/// Clean, minimalist design with light sidebar.
class TeamMemberShell extends StatefulWidget {
  final Widget child;

  const TeamMemberShell({super.key, required this.child});

  @override
  State<TeamMemberShell> createState() => _TeamMemberShellState();
}

class _TeamMemberShellState extends State<TeamMemberShell> {
  UserProfile? _userProfile;
  bool _isLoading = true;
  bool _isCollapsed = false;
  List<CustomInbox> _assignedInboxes = [];

  @override
  void initState() {
    super.initState();
    _fetchMemberInfo();
  }

  Future<void> _fetchMemberInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userResponse = await AuthService.getUserProfile(user.uid);

      if (userResponse['success'] == true) {
        final userData = userResponse['user'] as Map<String, dynamic>;

        // Parse dates manually if needed, similar to DashboardScreen
        // For simple profile display we might just need strings

        if (mounted) {
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
              createdAt: DateTime.now(), // Placeholder
              updatedAt: DateTime.now(), // Placeholder
            );
            _isLoading = false;
          });

          // Fetch assigned inboxes
          if (_userProfile!.companyId.isNotEmpty &&
              _userProfile!.assignedInboxIds.isNotEmpty) {
            try {
              final allInboxes = await CustomInboxService.getInboxes(
                _userProfile!.companyId,
              );
              if (mounted) {
                setState(() {
                  _assignedInboxes = allInboxes
                      .where(
                        (inbox) =>
                            _userProfile!.assignedInboxIds.contains(inbox.id),
                      )
                      .toList();
                });
              }
            } catch (e) {
              debugPrint('Error loading assigned inboxes: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching member info: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onLogout() {
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
    final sidebarWidth = _isCollapsed ? 72.0 : 260.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      );
    }

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
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildSidebar(String currentLocation) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Team Member Badge
          if (!_isCollapsed) _buildMemberBadge(),

          // Navigation
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacing4,
                horizontal: AppTheme.spacing3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Assigned Custom Inboxes
                  if (_assignedInboxes.isNotEmpty) ...[
                    if (!_isCollapsed) ...[
                      _buildSectionHeader('INBOXES'),
                      const SizedBox(height: AppTheme.spacing1),
                    ],
                    ..._assignedInboxes.map((inbox) {
                      final route = '/custom-inbox/${inbox.id}';
                      final isSelected = currentLocation == route;
                      return _buildNavItem(
                        icon: Icons.folder,
                        activeIcon: Icons.folder_open,
                        label: inbox.name,
                        route: route,
                        isSelected: isSelected,
                        color: Color(inbox.color),
                      );
                    }),
                    const SizedBox(height: AppTheme.spacing6),
                  ],

                  if (!_isCollapsed) ...[
                    _buildSectionHeader('TOOLS'),
                    const SizedBox(height: AppTheme.spacing2),
                  ],

                  _buildNavItem(
                    icon: Icons.chat_bubble_outline,
                    activeIcon: Icons.chat_bubble,
                    label: 'Team Chat',
                    route: '/chat',
                    isSelected: currentLocation == '/chat',
                  ),

                  _buildNavItem(
                    icon: Icons.assignment_outlined,
                    activeIcon: Icons.assignment,
                    label: 'Assignments',
                    route: '/assignments',
                    isSelected: currentLocation == '/assignments',
                  ),

                  _buildNavItem(
                    icon: Icons.cloud_outlined,
                    activeIcon: Icons.cloud,
                    label: 'Storage',
                    route: '/storage',
                    isSelected: currentLocation == '/storage',
                  ),

                  _buildNavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Settings',
                    route: '/settings',
                    isSelected: currentLocation == '/settings',
                  ),
                ],
              ),
            ),
          ),

          // Logout
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(
        horizontal: _isCollapsed ? AppTheme.spacing3 : AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Logo
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

          if (!_isCollapsed) ...[
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

          // Collapse button
          IconButton(
            onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
            icon: Icon(
              _isCollapsed ? Icons.chevron_right : Icons.chevron_left,
              color: AppTheme.textMuted,
              size: 20,
            ),
            tooltip: _isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildMemberBadge() {
    final displayName = _userProfile?.displayName.isNotEmpty == true
        ? _userProfile!.displayName
        : _userProfile?.email.split('@').first ?? 'User';

    final initial = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';

    return Container(
      margin: const EdgeInsets.all(AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: AppTheme.gray50,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Center(
              child: Text(
                initial,
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
                  displayName,
                  style: AppTheme.labelMd.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    'Team Member',
                    style: AppTheme.labelSm.copyWith(
                      color: AppTheme.secondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
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
    Color? color,
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
          splashColor: (color ?? AppTheme.primary).withOpacity(0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: _isCollapsed ? AppTheme.spacing3 : AppTheme.spacing3,
              vertical: AppTheme.spacing3,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? (color ?? AppTheme.primary).withOpacity(0.08)
                  : null,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color:
                      color ??
                      (isSelected ? AppTheme.primary : AppTheme.textSecondary),
                  size: 20,
                ),
                if (!_isCollapsed) ...[
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTheme.bodyMd.copyWith(
                        color: isSelected
                            ? (color ?? AppTheme.primary)
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

  Widget _buildLogoutButton() {
    return Container(
      padding: EdgeInsets.all(
        _isCollapsed ? AppTheme.spacing3 : AppTheme.spacing4,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: _onLogout,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: AppTheme.spacing3,
              horizontal: _isCollapsed
                  ? AppTheme.spacing3
                  : AppTheme.spacing2 + 4,
            ),
            child: Row(
              mainAxisAlignment: _isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
                if (!_isCollapsed) ...[
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
    );
  }
}
