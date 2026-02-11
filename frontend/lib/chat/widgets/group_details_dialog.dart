import 'package:flutter/material.dart';
import '../../auth/services/team_service.dart';
import '../../core/models/team_member.dart';
import '../models/chat_group.dart';
import '../services/chat_service.dart';
import 'add_members_dialog.dart';

class GroupDetailsDialog extends StatefulWidget {
  final ChatGroup group;
  final bool isOwner;
  final Function() onGroupUpdated;

  const GroupDetailsDialog({
    Key? key,
    required this.group,
    required this.isOwner,
    required this.onGroupUpdated,
  }) : super(key: key);

  @override
  _GroupDetailsDialogState createState() => _GroupDetailsDialogState();
}

class _GroupDetailsDialogState extends State<GroupDetailsDialog> {
  bool _isLoading = true;
  List<TeamMember> _members = [];

  @override
  void initState() {
    super.initState();
    _loadGroupMembers();
  }

  Future<void> _loadGroupMembers() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch fresh group data to get latest members list
      final freshGroup = await ChatService.getGroup(widget.group.id);

      // 2. Fetch all company members
      final memberStream = TeamService.getTeamMembers(widget.group.companyId);
      final allMembers = await memberStream.first;

      if (mounted) {
        setState(() {
          _members = allMembers
              .where((m) => freshGroup.members.contains(m.id))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load group members: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(String memberId) async {
    try {
      await ChatService.removeMember(widget.group.id, memberId);

      // Reload to refresh list
      await _loadGroupMembers();

      widget.onGroupUpdated();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove member: $e')));
      }
    }
  }

  void _showAddMembers() {
    showDialog(
      context: context,
      builder: (context) => AddMembersDialog(
        groupId: widget.group.id,
        companyId: widget.group.companyId,
        // Use currently loaded member IDs for exclusion
        existingMemberIds: _members.map((m) => m.id).toList(),
        onMembersAdded: () {
          _loadGroupMembers(); // Refresh list
          widget.onGroupUpdated();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group.name),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.group.description != null) ...[
              Text(
                widget.group.description!,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Members (${_members.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (widget.isOwner)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    onPressed: _showAddMembers,
                  ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _members.isEmpty
                  ? const Center(child: Text('No members in this group'))
                  : ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(
                              (member.displayName ?? member.email)[0]
                                  .toUpperCase(),
                            ),
                          ),
                          title: Text(member.displayName ?? member.email),
                          subtitle: member.displayName != null
                              ? Text(member.email)
                              : null,
                          trailing: widget.isOwner
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removeMember(member.id),
                                  tooltip: 'Remove',
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
