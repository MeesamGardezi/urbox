import 'package:flutter/material.dart';
import '../../auth/services/team_service.dart';
import '../../core/models/team_member.dart';
import '../services/chat_service.dart';

class AddMembersDialog extends StatefulWidget {
  final String groupId;
  final String companyId;
  final List<String> existingMemberIds;
  final Function() onMembersAdded;

  const AddMembersDialog({
    Key? key,
    required this.groupId,
    required this.companyId,
    required this.existingMemberIds,
    required this.onMembersAdded,
  }) : super(key: key);

  @override
  _AddMembersDialogState createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<AddMembersDialog> {
  bool _isLoading = true;
  List<TeamMember> _availableMembers = [];
  final Set<String> _selectedMemberIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      // Need to convert stream to list
      final memberStream = TeamService.getTeamMembers(widget.companyId);
      final members = await memberStream.first; // Get first emission

      if (mounted) {
        setState(() {
          // Filter out members who are already in the group
          _availableMembers = members
              .where((m) => !widget.existingMemberIds.contains(m.id))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load members: $e')));
      }
    }
  }

  Future<void> _addSelectedMembers() async {
    if (_selectedMemberIds.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      await ChatService.addMembers(widget.groupId, _selectedMemberIds.toList());

      if (mounted) {
        Navigator.of(context).pop();
        widget.onMembersAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Members added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add members: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Members'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _availableMembers.isEmpty
            ? const Center(child: Text('No new members to add'))
            : ListView.builder(
                itemCount: _availableMembers.length,
                itemBuilder: (context, index) {
                  final member = _availableMembers[index];
                  final isSelected = _selectedMemberIds.contains(member.id);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedMemberIds.add(member.id);
                        } else {
                          _selectedMemberIds.remove(member.id);
                        }
                      });
                    },
                    title: Text(member.displayName ?? member.email),
                    subtitle: member.displayName != null
                        ? Text(member.email)
                        : null,
                    secondary: CircleAvatar(
                      child: Text(
                        (member.displayName ?? member.email)[0].toUpperCase(),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving || _selectedMemberIds.isEmpty
              ? null
              : _addSelectedMembers,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Add (${_selectedMemberIds.length})'),
        ),
      ],
    );
  }
}
