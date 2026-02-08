import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../services/slack_service.dart';
import '../widgets/add_slack_dialog.dart';

class SlackScreen extends StatefulWidget {
  const SlackScreen({Key? key}) : super(key: key);

  @override
  State<SlackScreen> createState() => _SlackScreenState();
}

class _SlackScreenState extends State<SlackScreen> {
  final _slackService = SlackService();
  String? _userId;
  List<dynamic> _accounts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUserAndAccounts();
  }

  Future<void> _fetchUserAndAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;
        _fetchAccounts();
      } else {
        setState(() {
          _error = 'User not authenticated';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAccounts() async {
    if (_userId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final accounts = await _slackService.getSlackAccounts(userId: _userId);

      if (mounted) {
        setState(() {
          _accounts = accounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // If 404/Empty and simply no accounts, we treat as empty
          // But API currently returns error message if something fails
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text('Error: $_error', style: AppTheme.bodyMd),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchAccounts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_accounts.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      itemCount: _accounts.length,
      itemBuilder: (context, index) {
        return _buildAccountCard(_accounts[index]);
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A154B), Color(0xFF611f69)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.tag, color: Colors.white, size: 24),
          ),
          const SizedBox(width: AppTheme.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Slack Connections', style: AppTheme.headingMd),
                const SizedBox(height: 2),
                Text(
                  'Manage your connected Slack workspaces',
                  style: AppTheme.bodyMd,
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Connect Workspace'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A154B),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing6),
            decoration: BoxDecoration(
              color: const Color(0xFF4A154B).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.tag, // Slack icon placeholder
              size: 64,
              color: Color(0xFF4A154B),
            ),
          ),
          const SizedBox(height: AppTheme.spacing6),
          Text('No Slack workspaces connected', style: AppTheme.headingSm),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            'Connect your Slack workspace to sync messages',
            style: AppTheme.bodyMd,
          ),
          const SizedBox(height: AppTheme.spacing6),
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Connect Workspace'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A154B),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(dynamic account) {
    final trackedChannels =
        (account['trackedChannels'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A154B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: const Icon(
                  Icons.tag,
                  color: Color(0xFF4A154B),
                  size: 28,
                ),
              ),
              const SizedBox(width: AppTheme.spacing4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account['teamName'] ?? 'Unknown Workspace',
                      style: AppTheme.labelLg,
                    ),
                    Text(
                      'Connected as ${account['name'] ?? 'User'}',
                      style: AppTheme.bodyMd,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _showManageChannelsDialog(account['id'], trackedChannels),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4A154B),
                  side: const BorderSide(color: Color(0xFF4A154B)),
                ),
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Manage Channels'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteAccount(account['id']),
                color: AppTheme.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Tracked Channels',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (trackedChannels.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Center(
                child: Text(
                  'No channels tracked. Click "Manage Channels" to select.',
                  style: AppTheme.bodySm.copyWith(color: AppTheme.textMuted),
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: trackedChannels.map((channel) {
                final name = channel['name'] ?? 'Unknown';
                return Chip(
                  label: Text('# $name'),
                  backgroundColor: const Color(0xFF4A154B).withOpacity(0.05),
                  labelStyle: const TextStyle(
                    color: Color(0xFF4A154B),
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _showManageChannelsDialog(
    String accountId,
    List<Map<String, dynamic>> currentTracked,
  ) {
    showDialog(
      context: context,
      builder: (context) => _ManageChannelsDialog(
        accountId: accountId,
        currentlyTracked: currentTracked,
        onSave: _fetchAccounts, // Refresh parent list after save
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => AddSlackDialog(
        onConnect: () {
          Navigator.of(context, rootNavigator: true).pop();
          _connectSlack();
        },
      ),
    );
  }

  void _connectSlack() {
    // We rely on backend resolving companyId via userId (LOOKUP)
    final url = AppConfig.slackAuthUrl('LOOKUP', _userId!);
    _openOAuthWebView(url);
  }

  void _deleteAccount(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Workspace'),
        content: const Text(
          'Are you sure you want to disconnect this workspace?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _slackService.deleteAccount(id);
      _fetchAccounts();
    }
  }

  void _openOAuthWebView(String url) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => OAuthWebView(url: url)));
  }
}

class OAuthWebView extends StatefulWidget {
  final String url;

  const OAuthWebView({Key? key, required this.url}) : super(key: key);

  @override
  State<OAuthWebView> createState() => _OAuthWebViewState();
}

class _OAuthWebViewState extends State<OAuthWebView> {
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    _launch();
  }

  Future<void> _launch() async {
    if (await canLaunchUrl(Uri.parse(widget.url))) {
      await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
      setState(() {
        _launched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Slack')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_launched) ...[
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppTheme.success,
              ),
              const SizedBox(height: 16),
              const Text('Browser opened for authentication.'),
              const SizedBox(height: 8),
              const Text(
                'Once completed, close this page and refresh your accounts.',
              ),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Opening browser...'),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return to App'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageChannelsDialog extends StatefulWidget {
  final String accountId;
  final List<Map<String, dynamic>> currentlyTracked;
  final VoidCallback onSave;

  const _ManageChannelsDialog({
    super.key,
    required this.accountId,
    required this.currentlyTracked,
    required this.onSave,
  });

  @override
  State<_ManageChannelsDialog> createState() => _ManageChannelsDialogState();
}

class _ManageChannelsDialogState extends State<_ManageChannelsDialog> {
  final _slackService = SlackService();
  Future<List<Map<String, dynamic>>>? _channelsFuture;
  final Set<String> _selectedIds = {};
  final List<Map<String, dynamic>> _selectedChannels = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    for (var c in widget.currentlyTracked) {
      if (c['id'] != null) {
        _selectedIds.add(c['id']);
        _selectedChannels.add(Map<String, dynamic>.from(c));
      }
    }
    _loadChannels();
  }

  void _loadChannels() {
    setState(() {
      _channelsFuture = _slackService.getChannels(widget.accountId);
    });
  }

  void _toggleChannel(Map<String, dynamic> channel) {
    final id = channel['id'];
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectedChannels.removeWhere((c) => c['id'] == id);
      } else {
        _selectedIds.add(id);
        _selectedChannels.add({
          'id': id,
          'name': channel['name'],
          'is_channel': channel['is_channel'],
          'is_group': channel['is_group'],
          'is_im': channel['is_im'],
        });
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _slackService.saveTrackedChannels(
        widget.accountId,
        _selectedChannels,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Monitored channels updated')),
        );
        widget.onSave();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Channels to Track'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _channelsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                    const SizedBox(height: 16),
                    Text('Failed to load channels: ${snapshot.error}'),
                    TextButton(
                      onPressed: _loadChannels,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final channels = snapshot.data ?? [];
            if (channels.isEmpty) {
              return const Center(child: Text('No channels found'));
            }

            return ListView.builder(
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final channel = channels[index];
                final isSelected = _selectedIds.contains(channel['id']);
                final isPrivate = channel['is_private'] == true;

                IconData icon = Icons.tag;
                if (isPrivate) icon = Icons.lock_outline;

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (val) => _toggleChannel(channel),
                  title: Text(channel['name'] ?? 'Unknown'),
                  secondary: Icon(icon, size: 18),
                  activeColor: const Color(0xFF4A154B),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A154B),
            foregroundColor: Colors.white,
          ),
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
