import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/config/app_config.dart';
import '../../core/models/custom_inbox.dart';
import '../services/custom_inbox_service.dart';
import '../../email/services/email_service.dart';
import '../../whatsapp/services/whatsapp_service.dart';
import '../../slack/services/slack_service.dart';

class CustomInboxesScreen extends StatefulWidget {
  const CustomInboxesScreen({super.key});

  @override
  State<CustomInboxesScreen> createState() => _CustomInboxesScreenState();
}

class _CustomInboxesScreenState extends State<CustomInboxesScreen> {
  final _user = FirebaseAuth.instance.currentUser;
  String? _companyId;
  bool _isLoading = true;
  List<CustomInbox> _inboxes = [];

  @override
  void initState() {
    super.initState();
    _fetchCompanyIdAndData();
  }

  Future<void> _fetchCompanyIdAndData() async {
    if (_user == null) return;
    try {
      // Get user data to find companyId
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/api/auth/user/${_user.uid}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['user'] != null) {
          final userData = data['user'];
          if (mounted) {
            setState(() {
              _companyId = userData['companyId'];
            });
            await _loadInboxes();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching company ID: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadInboxes() async {
    if (_companyId == null) return;
    try {
      final inboxes = await CustomInboxService.getInboxes(_companyId!);
      if (mounted) {
        setState(() {
          _inboxes = inboxes;
        });
      }
    } catch (e) {
      debugPrint('Error loading inboxes: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load inboxes: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_companyId == null) {
      return const Center(child: Text('Error: No company found'));
    }

    return Column(
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
              const Icon(Icons.folder, color: Color(0xFF6366F1), size: 28),
              const SizedBox(width: 12),
              const Text(
                'Custom Inboxes',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showCreateInboxDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Inbox'),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _inboxes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 80,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No Custom Inboxes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create custom inboxes to group your email accounts',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showCreateInboxDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Your First Inbox'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: _inboxes.length,
                  itemBuilder: (context, index) {
                    return _buildInboxCard(_inboxes[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInboxCard(CustomInbox inbox) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditInboxDialog(context, inbox),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Color(inbox.color).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder,
                      color: Color(inbox.color),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inbox.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${inbox.accountIds.length} email account${inbox.accountIds.length == 1 ? '' : 's'}'
                          '${inbox.whatsappGroupIds.isNotEmpty ? ' • ${inbox.whatsappGroupIds.length} WA' : ''}'
                          '${inbox.slackChannelIds.isNotEmpty ? ' • ${inbox.slackChannelIds.length} Slack' : ''}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditInboxDialog(context, inbox);
                      } else if (value == 'delete') {
                        _showDeleteConfirmation(inbox);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (inbox.accountIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                FutureBuilder<List<dynamic>>(
                  future: EmailService().getEmailAccounts(
                    companyId: _companyId,
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final allAccounts = snapshot.data!;
                    final accounts = allAccounts
                        .where((a) => inbox.accountIds.contains(a['id']))
                        .toList();

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: accounts.map((data) {
                        final email = data['email'] ?? 'Unknown';
                        final isGmail = data['provider'] == 'gmail-oauth';
                        return Chip(
                          avatar: CircleAvatar(
                            backgroundColor: isGmail
                                ? Colors.red.shade100
                                : Colors.blue.shade100,
                            child: Icon(
                              isGmail ? Icons.g_mobiledata : Icons.mail,
                              size: 16,
                              color: isGmail ? Colors.red : Colors.blue,
                            ),
                          ),
                          label: Text(email),
                          backgroundColor: Colors.grey.shade50,
                          side: BorderSide(color: Colors.grey.shade200),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateInboxDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _InboxFormDialog(
        companyId: _companyId!,
        userId: _user!.uid,
        onSave:
            (
              name,
              accountIds,
              whatsappGroupIds,
              slackChannelIds,
              accountFilters,
              color,
            ) async {
              await CustomInboxService.createInbox(
                name: name,
                companyId: _companyId!,
                accountIds: accountIds,
                whatsappGroupIds: whatsappGroupIds,
                slackChannelIds: slackChannelIds,
                accountFilters: accountFilters,
                color: color,
              );
              _loadInboxes(); // Refresh list
            },
      ),
    );
  }

  void _showEditInboxDialog(BuildContext context, CustomInbox inbox) {
    showDialog(
      context: context,
      builder: (context) => _InboxFormDialog(
        companyId: _companyId!,
        userId: _user!.uid,
        inbox: inbox,
        onSave:
            (
              name,
              accountIds,
              whatsappGroupIds,
              slackChannelIds,
              accountFilters,
              color,
            ) async {
              await CustomInboxService.updateInbox(
                inbox.copyWith(
                  name: name,
                  accountIds: accountIds,
                  whatsappGroupIds: whatsappGroupIds,
                  slackChannelIds: slackChannelIds,
                  accountFilters: accountFilters,
                  color: color,
                ),
              );
              _loadInboxes(); // Refresh list
            },
      ),
    );
  }

  void _showDeleteConfirmation(CustomInbox inbox) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Inbox?'),
        content: Text(
          'Are you sure you want to delete "${inbox.name}"? This will not delete the email accounts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await CustomInboxService.deleteInbox(inbox.id);
              Navigator.pop(context);
              _loadInboxes();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _InboxFormDialog extends StatefulWidget {
  final String companyId;
  final String userId;
  final CustomInbox? inbox;
  final Future<void> Function(
    String name,
    List<String> accountIds,
    List<String> whatsappGroupIds,
    List<String> slackChannelIds,
    Map<String, List<String>> accountFilters,
    int color,
  )
  onSave;

  const _InboxFormDialog({
    required this.companyId,
    required this.userId,
    this.inbox,
    required this.onSave,
  });

  @override
  State<_InboxFormDialog> createState() => _InboxFormDialogState();
}

class _InboxFormDialogState extends State<_InboxFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  List<String> _selectedAccountIds = [];
  List<String> _selectedWhatsAppGroupIds = [];
  List<String> _selectedSlackChannelIds = [];
  Map<String, List<String>> _accountFilters = {};
  int _selectedColor = 0xFF6366F1;
  bool _isSaving = false;

  // Data
  List<dynamic> _availableAccounts = [];
  List<dynamic> _availableWhatsAppGroups = [];
  List<dynamic> _availableSlackChannels = [];
  bool _isLoadingData = true;

  final List<int> _colorOptions = [
    0xFF6366F1, // Indigo
    0xFFEF4444, // Red
    0xFFF59E0B, // Amber
    0xFF10B981, // Green
    0xFF3B82F6, // Blue
    0xFF8B5CF6, // Purple
    0xFFEC4899, // Pink
    0xFF06B6D4, // Cyan
  ];

  @override
  void initState() {
    super.initState();
    if (widget.inbox != null) {
      _nameController.text = widget.inbox!.name;
      _selectedAccountIds = List.from(widget.inbox!.accountIds);
      _selectedWhatsAppGroupIds = List.from(widget.inbox!.whatsappGroupIds);
      _selectedSlackChannelIds = List.from(widget.inbox!.slackChannelIds);
      _accountFilters = Map.from(widget.inbox!.accountFilters);
      _selectedColor = widget.inbox!.color;
    }
    _loadAvailableData();
  }

  Future<void> _loadAvailableData() async {
    try {
      // Parallel fetch
      final results = await Future.wait([
        EmailService().getEmailAccounts(companyId: widget.companyId),
        WhatsAppService().getMonitoredGroups(widget.userId),
        SlackService().getSlackAccounts(companyId: widget.companyId),
      ]);

      if (mounted) {
        setState(() {
          _availableAccounts = results[0];
          _availableWhatsAppGroups = results[1];

          // Process Slack Channels
          final slackAccounts = results[2];
          _availableSlackChannels = [];
          for (var account in slackAccounts) {
            final teamName = account['teamName'] ?? 'Slack';
            final tracked = account['trackedChannels'] as List<dynamic>? ?? [];
            for (var ch in tracked) {
              // Flatten for display
              _availableSlackChannels.add({
                'id': ch['id'],
                'name': ch['name'],
                'teamName': teamName,
              });
            }
          }

          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dialog data: $e');
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.inbox == null ? 'Create Custom Inbox' : 'Edit Inbox'),
      content: SizedBox(
        width: 500,
        child: _isLoadingData
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Inbox Name',
                          hintText: 'e.g., Work, Personal, Support',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Color picker
                      const Text(
                        'Color',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        children: _colorOptions.map((color) {
                          final isSelected = color == _selectedColor;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedColor = color),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(color),
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: Colors.black, width: 3)
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // Email accounts selector
                      const Text(
                        'Assign Email Accounts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _availableAccounts.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No email accounts found.'),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _availableAccounts.length,
                                itemBuilder: (context, index) {
                                  final data = _availableAccounts[index];
                                  final email = data['email'] ?? 'Unknown';
                                  final isGmail =
                                      data['provider'] == 'gmail-oauth';
                                  final accountId = data['id'];
                                  final isSelected = _selectedAccountIds
                                      .contains(accountId);

                                  return CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedAccountIds.add(accountId);
                                        } else {
                                          _selectedAccountIds.remove(accountId);
                                        }
                                      });
                                    },
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isGmail
                                          ? Colors.red.shade100
                                          : Colors.blue.shade100,
                                      child: Icon(
                                        isGmail
                                            ? Icons.g_mobiledata
                                            : Icons.mail,
                                        size: 18,
                                        color: isGmail
                                            ? Colors.red
                                            : Colors.blue,
                                      ),
                                    ),
                                    title: Text(email),
                                    dense: true,
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 24),

                      // WhatsApp Groups selector
                      const Text(
                        'Assign WhatsApp Groups',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _availableWhatsAppGroups.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No monitored WhatsApp groups found.',
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _availableWhatsAppGroups.length,
                                itemBuilder: (context, index) {
                                  final group = _availableWhatsAppGroups[index];
                                  final groupId = group.id;
                                  final groupName = group.name;
                                  final isSelected = _selectedWhatsAppGroupIds
                                      .contains(groupId);

                                  return CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedWhatsAppGroupIds.add(
                                            groupId,
                                          );
                                        } else {
                                          _selectedWhatsAppGroupIds.remove(
                                            groupId,
                                          );
                                        }
                                      });
                                    },
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.green.shade100,
                                      child: Icon(
                                        Icons.chat,
                                        size: 18,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    title: Text(groupName),
                                    dense: true,
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 24),

                      // Slack Channels selector
                      const Text(
                        'Assign Slack Channels',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _availableSlackChannels.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No monitored Slack channels found.',
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _availableSlackChannels.length,
                                itemBuilder: (context, index) {
                                  final channel =
                                      _availableSlackChannels[index];
                                  final channelId = channel['id'];
                                  final channelName = channel['name'];
                                  final teamName = channel['teamName'];
                                  final isSelected = _selectedSlackChannelIds
                                      .contains(channelId);

                                  return CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedSlackChannelIds.add(
                                            channelId,
                                          );
                                        } else {
                                          _selectedSlackChannelIds.remove(
                                            channelId,
                                          );
                                        }
                                      });
                                    },
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: const Color(
                                        0xFF4A154B,
                                      ).withOpacity(0.1),
                                      child: const Icon(
                                        Icons.tag,
                                        size: 18,
                                        color: Color(0xFF4A154B),
                                      ),
                                    ),
                                    title: Text('# $channelName'),
                                    subtitle: Text(
                                      teamName,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    dense: true,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving
              ? null
              : () async {
                  if (_formKey.currentState!.validate()) {
                    setState(() => _isSaving = true);
                    try {
                      await widget.onSave(
                        _nameController.text,
                        _selectedAccountIds,
                        _selectedWhatsAppGroupIds,
                        _selectedSlackChannelIds,
                        _accountFilters,
                        _selectedColor,
                      );
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      setState(() => _isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
