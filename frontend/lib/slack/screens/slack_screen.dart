import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../auth/services/auth_service.dart';
import '../services/slack_service.dart';
import '../models/slack_message.dart';
import '../widgets/add_slack_dialog.dart';

class SlackScreen extends StatefulWidget {
  const SlackScreen({Key? key}) : super(key: key);

  @override
  State<SlackScreen> createState() => _SlackScreenState();
}

class _SlackScreenState extends State<SlackScreen>
    with SingleTickerProviderStateMixin {
  final _slackService = SlackService();

  // User & Company
  String? _userId;
  String? _companyId;

  // Data
  List<dynamic> _accounts = [];
  List<SlackMessage> _messages = [];
  List<Map<String, dynamic>> _allTrackedChannels = [];

  // UI State
  bool _isLoading = true;
  bool _isLoadingMessages = false;
  String? _error;

  // Tabs
  late TabController _tabController;
  int _selectedTab = 0;

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _searchQuery;
  String? _selectedChannelId;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
        if (_selectedTab == 1 && _messages.isEmpty) {
          _loadMessages();
        }
      }
    });

    _fetchUserAndData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchUserAndData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;

        // Fetch Company ID
        final userProfile = await AuthService.getUserProfile(_userId!);
        if (userProfile['success'] == true) {
          final userData = userProfile['user'] as Map<String, dynamic>;
          _companyId = userData['companyId'];
        }

        await _fetchAccounts();

        // If we have accounts and companyId, we can load messages if on that tab
        if (_selectedTab == 1) {
          _loadMessages();
        }
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

      // Aggregate tracked channels for the filter
      final List<Map<String, dynamic>> channels = [];
      for (var account in accounts) {
        final tracked = (account['trackedChannels'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList();
        if (tracked != null) {
          channels.addAll(tracked);
        }
      }

      if (mounted) {
        setState(() {
          _accounts = accounts;
          _allTrackedChannels = channels;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_companyId == null) return;

    setState(() => _isLoadingMessages = true);

    try {
      final rawMessages = await _slackService.getMessages(
        companyId: _companyId!,
        limit: 50,
      );

      // Convert to models
      var messages = rawMessages.map((m) => SlackMessage.fromJson(m)).toList();

      // Client-side filtering
      if (_selectedChannelId != null) {
        messages = messages
            .where((m) => m.channelId == _selectedChannelId)
            .toList();
      }
      if (_searchQuery != null && _searchQuery!.isNotEmpty) {
        final query = _searchQuery!.toLowerCase();
        messages = messages.where((m) {
          return m.body.toLowerCase().contains(query) ||
              m.senderName.toLowerCase().contains(query);
        }).toList();
      }

      // Sort by timestamp desc
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoadingMessages = false;
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
        setState(() => _isLoadingMessages = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = value.trim().isEmpty ? null : value.trim();
      });
      _loadMessages();
    });
  }

  void _onChannelFilterChanged(String? channelId) {
    setState(() {
      _selectedChannelId = channelId;
    });
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Custom Tab Selector
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCustomTab(
                      index: 0,
                      title: 'Connections',
                      icon: Icons.link,
                      isDark: isDark,
                    ),
                  ),
                  Expanded(
                    child: _buildCustomTab(
                      index: 1,
                      title: 'Messages',
                      icon: Icons.message_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildConnectionsTab(isDark),
                _buildMessagesTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTab({
    required int index,
    required String title,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedTab == index;
    final primaryColor = const Color(0xFF4A154B); // Slack Purple

    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() => _selectedTab = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: primaryColor.withOpacity(0.3), width: 1)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? primaryColor
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? primaryColor
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONNECTIONS TAB
  // ---------------------------------------------------------------------------

  Widget _buildConnectionsTab(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4A154B)),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          if (_accounts.isEmpty)
            _buildEmptyState()
          else
            ..._accounts.map((account) => _buildAccountCard(account)).toList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
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
            label: const Text('Connect'),
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
            child: const Icon(Icons.tag, size: 64, color: Color(0xFF4A154B)),
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
                label: const Text('Manage'),
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
                  'No channels tracked',
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

  // ---------------------------------------------------------------------------
  // MESSAGES TAB
  // ---------------------------------------------------------------------------

  Widget _buildMessagesTab(bool isDark) {
    if (_companyId == null && !_isLoading) {
      return Center(
        child: Text(
          'Please connect a Slack account first.',
          style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade700),
        ),
      );
    }

    return Column(
      children: [
        // Search & Filter Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          child: Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Channel Filter
              Expanded(
                flex: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return DropdownMenu<String?>(
                      width: constraints.maxWidth,
                      initialSelection: _selectedChannelId,
                      onSelected: _onChannelFilterChanged,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(
                          value: null,
                          label: 'All Channels',
                        ),
                        ..._allTrackedChannels.map((channel) {
                          return DropdownMenuEntry<String?>(
                            value: channel['id'],
                            label: channel['name'] ?? 'Unknown',
                          );
                        }),
                      ],
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      menuStyle: MenuStyle(
                        backgroundColor: MaterialStateProperty.all(
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                        ),
                      ),
                      trailingIcon: Icon(
                        Icons.filter_list,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      selectedTrailingIcon: Icon(
                        Icons.filter_list,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Messages List
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _loadMessages();
            },
            color: const Color(0xFF4A154B),
            child: _isLoadingMessages
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF4A154B)),
                  )
                : _messages.isEmpty
                ? _buildNoMessagesState(isDark)
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _messages.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _buildMessageCard(_messages[index], isDark);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoMessagesState(bool isDark) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: 400,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery != null ? 'No matches found' : 'No messages yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Messages from tracked channels will appear here',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(SlackMessage message, bool isDark) {
    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Channel and Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.numbers,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          message.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (message.accountName != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A154B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            message.accountName!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF4A154B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Sender
            Text(
              message.senderName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A154B),
              ),
            ),
            const SizedBox(height: 4),

            // Media Indicator
            if (message.hasMedia)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Media Attached',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

            // Body
            if (message.body.isNotEmpty)
              Text(
                message.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? Colors.grey.shade200 : Colors.black87,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // DIALOGS & HELPER CLASSES
  // ---------------------------------------------------------------------------

  void _showManageChannelsDialog(
    String accountId,
    List<Map<String, dynamic>> currentTracked,
  ) {
    showDialog(
      context: context,
      builder: (context) => _ManageChannelsDialog(
        accountId: accountId,
        currentlyTracked: currentTracked,
        onSave: _fetchAccounts,
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
