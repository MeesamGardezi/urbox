import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Models
import '../models/inbox_item.dart';
import '../models/email_model.dart';
import '../../whatsapp/models/whatsapp_model.dart';
import '../../slack/models/slack_message.dart';

// Services
import '../../email/services/email_service.dart';
import '../../whatsapp/services/whatsapp_service.dart';
import '../../slack/services/slack_service.dart';
import '../../custom_inboxes/services/custom_inbox_service.dart';
import '../../core/models/custom_inbox.dart';
import '../../auth/services/auth_service.dart';

// UI
import '../../core/ui/resizable_shell.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/email_renderer.dart';

class InboxScreen extends StatefulWidget {
  final String? customInboxId;

  const InboxScreen({super.key, this.customInboxId});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  // Services
  final EmailService _emailService = EmailService();
  final WhatsAppService _whatsAppService = WhatsAppService();
  final SlackService _slackService = SlackService();

  // State
  List<InboxItem> _items = [];
  List<InboxItem> _allItems = []; // Store unfiltered items
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = [];
  InboxItem? _selectedItem;
  bool _isLoadingMore = false;

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  // UI State
  bool _isSidebarVisible = true;

  @override
  void initState() {
    super.initState();
    _fetchInboxItems();
  }

  @override
  void didUpdateWidget(InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customInboxId != oldWidget.customInboxId) {
      if (mounted) {
        setState(() {
          _items = [];
          _allItems = [];
          _isLoading = true;
          _error = null;
        });
      }
      _fetchInboxItems();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = query;
        _filterItems();
      });
    });
  }

  void _filterItems() {
    var filtered = _allItems;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((item) {
        return item.title.toLowerCase().contains(query) ||
            item.subtitle.toLowerCase().contains(query) ||
            item.snippet.toLowerCase().contains(query);
      }).toList();
    }

    setState(() {
      _items = filtered;
    });
  }

  // Pagination State
  final Map<String, dynamic> _cursors = {}; // Store cursors/offsets per source
  bool _hasMoreEmails = true;
  bool _hasMoreWhatsApp = true;
  bool _hasMoreSlack = true;
  bool _isFetching = false; // Mutex for fetching

  // Context Data
  String? _companyId;
  Set<String> _assignedAccountIds = {};
  Set<String> _assignedWhatsAppGroupIds = {};
  Set<String> _assignedSlackChannelIds = {};
  CustomInbox? _currentCustomInbox;

  Future<void> _fetchInboxItems({bool isLoadMore = false}) async {
    debugPrint('START _fetchInboxItems (isLoadMore: $isLoadMore)');
    if (_isFetching) {
      debugPrint('Already fetching, skipping.');
      return;
    }
    _isFetching = true;

    if (!isLoadMore) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isLoadingMore = true);
    }

    if (!isLoadMore) {
      setState(() {
        _error = null;
        _items = [];
        _allItems = [];
        _cursors.clear();
        _hasMoreEmails = true;
        _hasMoreWhatsApp = true;
        _hasMoreSlack = true;
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      if (!isLoadMore) {
        debugPrint('Loading context data...');
        await _loadContextData(user);
        debugPrint(
          'Context loaded. Accounts: ${_accounts.length}, CompanyId: $_companyId',
        );
      }

      List<Future<List<InboxItem>>> tasks = [];

      // Email Task
      if (_hasMoreEmails && _accounts.isNotEmpty) {
        debugPrint('Fetching emails...');
        tasks.add(_fetchEmails(isLoadMore));
      } else {
        debugPrint(
          'Skipping emails (hasMore: $_hasMoreEmails, accounts: ${_accounts.length})',
        );
        tasks.add(Future.value([]));
      }

      // WhatsApp Task (use companyId if available, fallback to userId)
      if (_hasMoreWhatsApp) {
        final idToUse = _companyId ?? user.uid;
        debugPrint(
          'Fetching WhatsApp (using ${_companyId != null ? "companyId" : "userId"}: $idToUse)...',
        );
        tasks.add(_fetchWhatsApp(idToUse, isLoadMore));
      } else {
        debugPrint('Skipping WhatsApp (hasMore: $_hasMoreWhatsApp)');
        tasks.add(Future.value([]));
      }

      // Slack Task
      if (_hasMoreSlack && _companyId != null) {
        debugPrint('Fetching Slack (CompanyId: $_companyId)...');
        tasks.add(_fetchSlack(_companyId!, isLoadMore));
      } else {
        debugPrint(
          'Skipping Slack (hasMore: $_hasMoreSlack, CompanyId: $_companyId)',
        );
        tasks.add(Future.value([]));
      }

      final results = await Future.wait(tasks);
      final newEmails = results[0];
      final newWhatsApp = results[1];
      final newSlack = results[2];

      debugPrint(
        'Fetched: ${newEmails.length} emails, ${newWhatsApp.length} WA, ${newSlack.length} Slack',
      );

      final allNewItems = [...newEmails, ...newWhatsApp, ...newSlack];

      if (isLoadMore && allNewItems.isEmpty) {
        debugPrint('No new items fetched in loadMore.');
      }

      setState(() {
        if (!isLoadMore) {
          _allItems = allNewItems;
        } else {
          _allItems.addAll(allNewItems);
        }

        final uniqueItems = {for (var i in _allItems) i.id: i}.values.toList();
        _allItems = uniqueItems;

        _allItems.sort((a, b) => b.date.compareTo(a.date));

        _filterItems();
        debugPrint('Total items after filter: ${_items.length}');
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e, stack) {
      debugPrint('Error fetching inbox: $e\n$stack');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } finally {
      _isFetching = false;
      if (mounted) {
        // double check loading states
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadContextData(User user) async {
    // 1. Get User Profile
    final profileResponse = await AuthService.getUserProfile(user.uid);
    if (profileResponse['success'] != true)
      throw Exception('Failed to load user profile');

    final userData = profileResponse['user'];
    _companyId = userData['companyId']?.toString();

    // 3. Load Custom Inboxes
    List<CustomInbox> allInboxes = [];
    if (_companyId != null && _companyId!.isNotEmpty) {
      try {
        allInboxes = await CustomInboxService.getInboxes(_companyId!);
      } catch (e) {
        debugPrint('Warning: Failed to load custom inboxes: $e');
      }
    }

    // 3. Determine Filters
    _assignedAccountIds.clear();
    _assignedWhatsAppGroupIds.clear();
    _assignedSlackChannelIds.clear();
    _currentCustomInbox = null;

    if (widget.customInboxId != null) {
      try {
        _currentCustomInbox = allInboxes.firstWhere(
          (i) => i.id == widget.customInboxId,
        );
      } catch (_) {
        throw Exception('Custom inbox not found');
      }
    } else {
      for (var inbox in allInboxes) {
        _assignedAccountIds.addAll(inbox.accountIds);
        _assignedWhatsAppGroupIds.addAll(inbox.whatsappGroupIds);
        _assignedSlackChannelIds.addAll(inbox.slackChannelIds);
      }
    }

    // 4. Load & Filter Accounts
    await _loadAccounts(user.uid);
    if (_currentCustomInbox != null) {
      _accounts = _accounts
          .where((a) => _currentCustomInbox!.accountIds.contains(a['id']))
          .toList();
    } else {
      _accounts = _accounts
          .where((a) => !_assignedAccountIds.contains(a['id']))
          .toList();
    }
  }

  Future<void> _loadAccounts(String userId) async {
    try {
      final accountsList = await _emailService.getEmailAccounts(userId: userId);
      _accounts = accountsList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error loading accounts: $e');
      _accounts = [];
    }
  }

  Future<List<InboxItem>> _fetchEmails(bool isLoadMore) async {
    try {
      Map<String, dynamic> offsets = {};
      if (isLoadMore) {
        offsets = Map<String, dynamic>.from(_cursors['emails'] ?? {});
      }

      final result = await _emailService.fetchEmails(
        _accounts,
        offsets: offsets,
      );

      final emails =
          (result['emails'] as List?)?.map((e) => Email.fromJson(e)).toList() ??
          [];
      final pagination = result['pagination'] as Map<String, dynamic>?;

      if (pagination != null) {
        Map<String, dynamic> newOffsets = {};
        bool anyHasMore = false;

        pagination.forEach((key, value) {
          if (value['nextPageToken'] != null) {
            newOffsets[key] = value['nextPageToken'];
            if (value['hasMore'] != false) anyHasMore = true;
          } else if (value['nextOffset'] != null) {
            newOffsets[key] = value['nextOffset'];
            if (value['hasMore'] != false) anyHasMore = true;
          }
        });

        _cursors['emails'] = newOffsets;
        _hasMoreEmails = anyHasMore;
      } else {
        _hasMoreEmails = false;
      }

      return emails.map((e) => EmailInboxItem(e)).toList();
    } catch (e) {
      debugPrint('Error fetching emails: $e');
      return [];
    }
  }

  Future<List<InboxItem>> _fetchWhatsApp(
    String idToUse,
    bool isLoadMore,
  ) async {
    try {
      String? startAfter;
      if (isLoadMore) {
        if (_cursors.containsKey('whatsapp')) {
          startAfter = _cursors['whatsapp'];
        } else {
          // Fallback: find oldest WhatsApp message timestamp
          final whatsappItems = _allItems
              .whereType<WhatsAppInboxItem>()
              .toList();
          if (whatsappItems.isNotEmpty) {
            whatsappItems.sort((a, b) => a.date.compareTo(b.date));
            // Use the message ID as cursor
            startAfter = whatsappItems.first.whatsappMessage!.id;
          }
        }
      }

      // Use companyId if available, otherwise userId for backward compatibility
      final whatsappMessages = _companyId != null
          ? await _whatsAppService.getMessages(
              companyId: idToUse,
              limit: 50,
              startAfter: startAfter,
            )
          : await _whatsAppService.getMessages(
              userId: idToUse,
              limit: 50,
              startAfter: startAfter,
            );

      if (whatsappMessages['messages'] != null) {
        final messagesList = (whatsappMessages['messages'] as List)
            .cast<WhatsAppMessage>();

        debugPrint(
          'WhatsApp: Fetched ${messagesList.length} messages. Filtering...',
        );

        // Update cursor and hasMore flag
        if (messagesList.isNotEmpty) {
          final lastMsg = messagesList.last;
          _cursors['whatsapp'] = lastMsg.id;
          _hasMoreWhatsApp = messagesList.length >= 50;
        } else {
          _hasMoreWhatsApp = false;
        }

        var filteredMsgs = messagesList;
        if (_currentCustomInbox != null) {
          // Custom Inbox: Only show assigned
          filteredMsgs = messagesList
              .where(
                (m) =>
                    _currentCustomInbox!.whatsappGroupIds.contains(m.groupId),
              )
              .toList();
        } else {
          // Main Inbox: Show ALL (No exclusion)
          // filteredMsgs = messagesList;
        }

        debugPrint('WhatsApp: Returning ${filteredMsgs.length} messages.');
        return filteredMsgs.map((m) => WhatsAppInboxItem(m)).toList();
      }
    } catch (e) {
      debugPrint('Error whatsapp: $e');
    }
    return [];
  }

  Future<List<InboxItem>> _fetchSlack(String companyId, bool isLoadMore) async {
    try {
      String? beforeTimestamp;
      if (isLoadMore) {
        // use cursor if available
        if (_cursors.containsKey('slack')) {
          beforeTimestamp = _cursors['slack'];
        } else {
          // Fallback: find oldest slack message in current items
          final slackItems = _allItems.whereType<SlackInboxItem>().toList();
          if (slackItems.isNotEmpty) {
            // Sort by date ascending to find oldest
            slackItems.sort((a, b) => a.date.compareTo(b.date));
            // Slack timestamp is usually seconds.micro, but our model parses to DateTime.
            // We need to convert back to string format if possible or store originalId.
            // SlackService expects string timestamp.
            // Best to use originalId from SlackMessage if available.
            // Casting to SlackInboxItem to access underlying message is tricky unless we expose it.
            // SlackInboxItem definition: class SlackInboxItem extends InboxItem { final SlackMessage _message; ... SlackMessage? get slackMessage => _message; }
            // We can access .slackMessage
            beforeTimestamp = slackItems.first.slackMessage!.originalId;
          }
        }
      }

      final slackMessages = await _slackService.getMessages(
        companyId: companyId,
        limit: 50,
        before: beforeTimestamp,
      );

      final messagesList = slackMessages
          .map((m) => SlackMessage.fromJson(m))
          .toList();

      if (messagesList.isNotEmpty) {
        // Update cursor to the *last* message's timestamp (oldest in this batch)
        final lastMsg = messagesList.last;
        _cursors['slack'] = lastMsg.originalId;
        _hasMoreSlack = messagesList.length >= 50;
      } else {
        _hasMoreSlack = false;
      }

      debugPrint(
        'Slack: Fetched ${messagesList.length} messages. Filtering...',
      );

      var filteredMsgs = messagesList;
      if (_currentCustomInbox != null) {
        filteredMsgs = messagesList
            .where(
              (m) => _currentCustomInbox!.slackChannelIds.contains(m.channelId),
            )
            .toList();
      } else {
        // Main Inbox: Show ALL (No exclusion)
        // filteredMsgs = messagesList;
      }

      debugPrint('Slack: Returning ${filteredMsgs.length} messages.');

      return filteredMsgs.map((m) => SlackInboxItem(m)).toList();
    } catch (e) {
      debugPrint('Error slack: $e');
      return [];
    }
  }

  Future<void> _loadMoreItems() async {
    await _fetchInboxItems(isLoadMore: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading inbox: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchInboxItems,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ResizableShell(
      isSidebarVisible: _isSidebarVisible,
      initialSidebarWidth: 360,
      minSidebarWidth: 300,
      maxSidebarWidth: 480,
      sidebar: _buildEmailList(),
      body: _buildMainContent(),
    );
  }

  Widget _buildEmailList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Text(
              _currentCustomInbox?.name ?? "All Messages",
              style: AppTheme.headingMd,
            ),
          ),

          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search messages...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppTheme.gray50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // List
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('No messages found'))
                : NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      if (scrollInfo.metrics.pixels >=
                          scrollInfo.metrics.maxScrollExtent - 200) {
                        _loadMoreItems();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _buildInboxItem(_items[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInboxItem(InboxItem item) {
    final isSelected = _selectedItem?.id == item.id;
    final isRead = item.isRead;

    return Material(
      color: isSelected
          ? AppTheme.primary.withOpacity(0.05)
          : (isRead ? Colors.white : AppTheme.gray50),
      child: InkWell(
        onTap: () {
          setState(() => _selectedItem = item);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.border, width: 0.5),
              left: isSelected
                  ? BorderSide(color: AppTheme.primary, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              _buildAvatar(item),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: (isRead ? AppTheme.bodyMd : AppTheme.labelLg)
                                .copyWith(
                                  fontWeight: isRead
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatDate(item.date),
                          style: AppTheme.bodyXs.copyWith(
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: AppTheme.bodySm.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.snippet,
                      style: AppTheme.bodyXs.copyWith(
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(InboxItem item) {
    if (item.type == InboxItemType.whatsapp) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.chat, color: Colors.green, size: 20),
      );
    }

    if (item.type == InboxItemType.slack) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.tag, color: Colors.purple, size: 20),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          item.title.isNotEmpty ? item.title[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Simple date formatting
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat.jm().format(date);
    }
    return DateFormat.MMMd().format(date);
  }

  Widget _buildMainContent() {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          // Toolbar
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isSidebarVisible
                        ? Icons.fullscreen
                        : Icons.fullscreen_exit,
                  ),
                  onPressed: () =>
                      setState(() => _isSidebarVisible = !_isSidebarVisible),
                  tooltip: 'Toggle Sidebar',
                ),
                const Spacer(),
                if (_selectedItem != null) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined),
                    onPressed: () {},
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: _selectedItem == null
                ? _buildEmptyState()
                : _buildItemDetail(_selectedItem!),
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
          Icon(
            Icons.mark_email_unread_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Select a message to read',
            style: AppTheme.headingSm.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetail(InboxItem item) {
    // Logic for different types
    if (item.type == InboxItemType.email && item.email != null) {
      final email = item.email!;
      return SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject
                Text(email.subject, style: AppTheme.headingLg),
                const SizedBox(height: 24),

                // Sender Info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _getAvatarColor(email.from),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          email.from.isNotEmpty
                              ? email.from[0].toUpperCase()
                              : '?',
                          style: AppTheme.labelLg.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  email.from,
                                  style: AppTheme.labelLg,
                                ),
                              ),
                              Text(
                                _formatDateTime(email.date),
                                style: AppTheme.bodySm,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('to me', style: AppTheme.bodySm),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Email Body
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: EmailRenderer(
                    htmlContent: email.html.isNotEmpty
                        ? email.html
                        : '<p>${email.text.replaceAll('\n', '<br>')}</p>',
                  ),
                ),

                const SizedBox(height: 32),

                // Action Buttons
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.reply_outlined, size: 18),
                      label: const Text('Reply'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.forward_outlined, size: 18),
                      label: const Text('Forward'),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      );
    } else if (item.type == InboxItemType.whatsapp &&
        item.whatsappMessage != null) {
      final msg = item.whatsappMessage!;
      return SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chat_rounded,
                        color: Colors.green,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(msg.groupName, style: AppTheme.headingMd),
                          const SizedBox(height: 4),
                          Text(
                            'From ${msg.senderName} • ${_formatDateTime(msg.timestamp)}',
                            style: AppTheme.bodySm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Message Content
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.hasMedia && msg.downloadUrl != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.attach_file,
                              size: 18,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Media attachment',
                              style: AppTheme.labelMd.copyWith(
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: Image.network(msg.downloadUrl!),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        msg.body,
                        style: AppTheme.bodyLg.copyWith(
                          color: AppTheme.textPrimary,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      );
    } else if (item.type == InboxItemType.slack && item.slackMessage != null) {
      final msg = item.slackMessage!;
      return SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.tag,
                        color: Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${msg.channelName}',
                            style: AppTheme.headingMd,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'From ${msg.senderName} • ${_formatDateTime(msg.timestamp)}',
                            style: AppTheme.bodySm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Message Content
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.hasMedia && msg.mediaUrl != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.attach_file,
                              size: 18,
                              color: Colors.purple,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Media attachment',
                              style: AppTheme.labelMd.copyWith(
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: Image.network(
                              msg.mediaUrl!,
                              errorBuilder: (c, e, s) =>
                                  const Text('Unable to load media'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        msg.body,
                        style: AppTheme.bodyLg.copyWith(
                          color: AppTheme.textPrimary,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      );
    }

    return const Center(child: Text('Unknown item type'));
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF2563EB), // Blue
      const Color(0xFF7C3AED), // Violet
      const Color(0xFF059669), // Emerald
      const Color(0xFFD97706), // Amber
      const Color(0xFFDC2626), // Red
      const Color(0xFF0891B2), // Cyan
    ];
    return colors[name.hashCode % colors.length];
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays < 1 && now.day == date.day) {
      return DateFormat.jm().format(date);
    } else if (diff.inDays < 7) {
      return '${DateFormat.E().format(date)}, ${DateFormat.jm().format(date)}';
    } else {
      return DateFormat('MMM d, yyyy, h:mm a').format(date);
    }
  }
}
