import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/config/app_config.dart';
import '../../core/models/team_member.dart';
import '../services/team_member_service.dart';

/// Team management screen for company owners
/// Allows inviting team members and managing them
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _companyId;
  bool _isLoading = true;
  List<TeamMember> _members = [];
  List<TeamMember> _pendingInvites = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchCompanyIdAndLoad();
    // Auto-refresh every 5 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadData(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCompanyIdAndLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Get company ID from backend user endpoint
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/api/auth/user/${user.uid}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['user'] != null) {
          if (mounted) {
            setState(() {
              _companyId = data['user']['companyId'];
            });
            await _loadData();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching company ID: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadData() async {
    if (_companyId == null) return;

    try {
      final members = await TeamMemberService.getTeamMembers(_companyId!);
      final invites = await TeamMemberService.getPendingInvites(_companyId!);

      if (mounted) {
        setState(() {
          _members = members;
          _pendingInvites = invites;
        });
      }
    } catch (e) {
      debugPrint('Error loading team data: $e');
    }
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          _InviteMemberDialog(companyId: _companyId!, onInvite: _inviteMember),
    );
  }

  Future<void> _inviteMember(String email) async {
    if (_companyId == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final result = await TeamMemberService.inviteMember(
        email: email,
        companyId: _companyId!,
        invitedBy: user!.uid,
        assignedInboxIds: [],
      );

      if (mounted) {
        if (result['emailSent'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Invitation email sent to $email')),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          _showInviteLinkDialog(email, result['token'] as String?);
        }
        // Refresh the list
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to invite: ${e.toString().replaceAll('Exception:', '').trim()}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showInviteLinkDialog(String email, String? token) {
    if (token == null) return;

    final inviteLink = '${Uri.base.origin}/accept-invite/$token';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.link, color: Colors.amber.shade700, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Share Invite Link'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.amber.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Email could not be sent. Please share this link with $email manually.',
                      style: TextStyle(
                        color: Colors.amber.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Invitation Link',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      inviteLink,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inviteLink));
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Link copied to clipboard!'),
                      ],
                    ),
                    backgroundColor: Colors.green.shade600,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_companyId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Unable to load team',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team Management',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Invite members and manage team access',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showInviteDialog,
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Invite Member'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo,
              tabs: const [
                Tab(text: 'Active Members'),
                Tab(text: 'Pending Invites'),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMembersList(), _buildPendingInvitesList()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList() {
    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No team members yet',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite your first team member to get started',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _members.length,
      itemBuilder: (context, index) => _buildMemberCard(_members[index]),
    );
  }

  Widget _buildMemberCard(TeamMember member) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isCurrentUser = member.id == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: member.isOwner
                      ? [Colors.amber.shade400, Colors.orange.shade500]
                      : [Colors.indigo.shade400, Colors.purple.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  (member.displayName ?? member.email)
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        member.displayName ?? member.email.split('@').first,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.email,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  _buildRoleBadge(member),
                ],
              ),
            ),

            // Actions
            if (!member.isOwner && !isCurrentUser)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                onSelected: (value) async {
                  switch (value) {
                    case 'disable':
                      await TeamMemberService.disableMember(member.id);
                      await _loadData();
                      break;
                    case 'enable':
                      await TeamMemberService.enableMember(member.id);
                      await _loadData();
                      break;
                    case 'remove':
                      _confirmRemoveMember(member);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (member.isActive)
                    const PopupMenuItem(
                      value: 'disable',
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 18),
                          SizedBox(width: 8),
                          Text('Disable Access'),
                        ],
                      ),
                    )
                  else
                    const PopupMenuItem(
                      value: 'enable',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Enable Access'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Remove', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(TeamMember member) {
    final isOwner = member.isOwner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOwner ? Colors.amber.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOwner ? Colors.amber.shade200 : Colors.indigo.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOwner ? Icons.star : Icons.person,
            size: 12,
            color: isOwner ? Colors.amber.shade700 : Colors.indigo.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            isOwner ? 'Owner' : 'Member',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOwner ? Colors.amber.shade700 : Colors.indigo.shade700,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveMember(TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Team Member'),
        content: Text(
          'Are you sure you want to remove ${member.email} from your team? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await TeamMemberService.removeMember(member.id);
                await _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${member.email} has been removed'),
                      backgroundColor: Colors.green.shade600,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to remove: $e'),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingInvitesList() {
    if (_pendingInvites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No pending invitations',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingInvites.length,
      itemBuilder: (context, index) => _buildInviteCard(_pendingInvites[index]),
    );
  }

  Widget _buildInviteCard(TeamMember invite) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade300, Colors.amber.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.mail_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.email,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 12,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Pending',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Copy link button
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _copyInviteLink(invite),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Copy Link'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 24, color: Colors.grey.shade300),
                  // Resend button
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _resendInvite(invite),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Resend'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green.shade600,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 24, color: Colors.grey.shade300),
                  // Cancel button
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _cancelInvite(invite),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade400,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyInviteLink(TeamMember invite) async {
    try {
      final data = await TeamMemberService.getInviteToken(invite.id);

      if (data['success'] == true && data['inviteLink'] != null) {
        await Clipboard.setData(ClipboardData(text: data['inviteLink']));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Invite link copied!'),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy link: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _resendInvite(TeamMember invite) async {
    try {
      final data = await TeamMemberService.resendInvite(invite.id);

      if (mounted) {
        if (data['success'] == true && data['emailSent'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Invitation resent to ${invite.email}'),
                ],
              ),
              backgroundColor: Colors.green.shade600,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.info, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data['message'] ??
                          'Invite renewed, use Copy Link to share',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.amber.shade600,
            ),
          );
        }
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _cancelInvite(TeamMember invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Invitation?'),
        content: Text(
          'Are you sure you want to cancel the invitation to ${invite.email}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Invite'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await TeamMemberService.cancelInvite(invite.id);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invitation to ${invite.email} cancelled')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel invite: $e'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    }
  }
}

/// Dialog for inviting a new team member
class _InviteMemberDialog extends StatefulWidget {
  final String companyId;
  final Future<void> Function(String email) onInvite;

  const _InviteMemberDialog({required this.companyId, required this.onInvite});

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    Navigator.pop(context);
    await widget.onInvite(_emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade400, Colors.purple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_add, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Invite Team Member'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invite a new member to collaborate on your team.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Email field
              Text(
                'Email Address',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'colleague@company.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.indigo.shade400,
                      width: 2,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Email is required';
                  if (!RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  ).hasMatch(value)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send, size: 18),
          label: Text(_isLoading ? 'Sending...' : 'Send Invite'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}
