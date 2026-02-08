import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Models
import '../models/inbox_item.dart';
import '../models/email_model.dart';
import '../../whatsapp/models/whatsapp_model.dart';

// Services
import '../../email/services/email_service.dart';
import '../../whatsapp/services/whatsapp_service.dart';

// UI
import '../../core/ui/resizable_shell.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/email_renderer.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  // Services
  final EmailService _emailService = EmailService();
  final WhatsAppService _whatsAppService = WhatsAppService();

  // State
  List<InboxItem> _items = [];
  List<InboxItem> _allItems = []; // Store unfiltered items
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = [];
  InboxItem? _selectedItem;

  // Pagination
  Map<String, dynamic> _pagination = {};
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

  Future<void> _fetchInboxItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // 1. Load Accounts
      await _loadAccounts();

      List<Email> fetchedEmails = [];
      List<InboxItem> fetchedWhatsAppItems = [];

      // 2. Fetch Emails
      if (_accounts.isNotEmpty) {
        // Since fetches return Map<String, dynamic>, we need to parse it
        final result = await _emailService.fetchEmails(_accounts);

        // Parse emails
        if (result['emails'] != null) {
          fetchedEmails = (result['emails'] as List)
              .map((e) => Email.fromJson(e))
              .toList();
        }

        // Parse pagination
        if (result['pagination'] != null) {
          _pagination = result['pagination'];
        }
      }

      // 3. Fetch WhatsApp Messages (Unified Inbox) using backend
      final whatsappMessages = await _whatsAppService.getMessages(
        userId: user.uid,
        limit: 50,
      );

      // getMessages returns Map with 'messages' key
      if (whatsappMessages['messages'] != null) {
        final messagesList =
            whatsappMessages['messages'] as List<WhatsAppMessage>;
        fetchedWhatsAppItems = messagesList
            .map((m) => WhatsAppInboxItem(m))
            .toList();
      }

      // 4. Merge and Sort
      _allItems = [
        ...fetchedEmails.map((e) => EmailInboxItem(e)),
        ...fetchedWhatsAppItems,
      ];

      _allItems.sort((a, b) => b.date.compareTo(a.date));

      _filterItems(); // Apply current filters to new items
    } catch (e) {
      setState(() => _error = e.toString());
      print('Error fetching inbox: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAccounts() async {
    _accounts = [];
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use AuthService to get user profile, which should include companyId if needed,
    // but EmailService.getEmailAccounts takes userId directly.

    try {
      final accountsList = await _emailService.getEmailAccounts(
        userId: user.uid,
      );
      _accounts = accountsList.cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error loading accounts: $e');
    }
  }

  Future<void> _loadMoreItems() async {
    if (_isLoadingMore) return;

    // Check if we have more pages
    bool hasMore = _pagination.values.any(
      (p) => p['nextPageToken'] != null || p['hasMore'] == true,
    );
    if (!hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      // Prepare offsets
      final offsets = _pagination.map((key, value) {
        if (value['nextPageToken'] != null) {
          return MapEntry(key, value['nextPageToken']);
        } else if (value['nextOffset'] != null) {
          return MapEntry(key, value['nextOffset']);
        }
        return MapEntry(key, null);
      });
      offsets.removeWhere((key, value) => value == null);

      if (offsets.isNotEmpty) {
        final result = await _emailService.fetchEmails(
          _accounts,
          offsets: offsets,
        );

        List<Email> newEmails = [];
        if (result['emails'] != null) {
          newEmails = (result['emails'] as List)
              .map((e) => Email.fromJson(e))
              .toList();
        }

        if (result['pagination'] != null) {
          // Merge pagination
          final newPagination = result['pagination'] as Map<String, dynamic>;
          newPagination.forEach((key, value) {
            _pagination[key] = value;
          });
        }

        if (newEmails.isNotEmpty) {
          final newItems = newEmails.map((e) => EmailInboxItem(e)).toList();
          _allItems.addAll(newItems);
          _allItems.sort((a, b) => b.date.compareTo(a.date));
          _filterItems();
        }
      }
    } catch (e) {
      print('Error loading more items: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _markAsRead(InboxItem item) async {
    if (item.isRead) return;

    // Optimistic update
    setState(() {
      // We can't easily iterate and modify _allItems in place if types differ,
      // but modifying properties of object works if mutable.
      if (item is EmailInboxItem && item.email != null) {
        item.email!.isRead = true;
      }
      // For WhatsApp it's always read in model currently
    });

    if (item is EmailInboxItem && item.email != null) {
      final email = item.email!;
      // Find the account for this email
      final account = _accounts.firstWhere(
        (acc) => acc['name'] == email.accountName,
        orElse: () => {},
      );

      if (account.isNotEmpty) {
        String? uid;
        // Simple UID extraction logic
        final parts = email.id.split('_');
        if (parts.length >= 3) {
          uid = parts.last;
        }
        await _emailService.markAsRead(email.id, account, email.messageId, uid);
      }
    }
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
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
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
          if (!isRead) _markAsRead(item);
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
    if (item.type == InboxItemType.email && item.email != null) {
      final email = item.email!;
      return SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email.subject, style: AppTheme.headingLg),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      email.from.isNotEmpty ? email.from[0].toUpperCase() : '?',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email.from, style: AppTheme.labelMd),
                      Text('to ${email.to}', style: AppTheme.bodySm),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    DateFormat.yMMMd().add_jm().format(email.date),
                    style: AppTheme.bodySm,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 32),
              // Email content renderer
              EmailRenderer(
                htmlContent: email.html.isNotEmpty
                    ? email.html
                    : '<p>${email.text.replaceAll('\n', '<br>')}</p>',
              ),
            ],
          ),
        ),
      );
    } else if (item.type == InboxItemType.whatsapp &&
        item.whatsappMessage != null) {
      final msg = item.whatsappMessage!;
      return SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(msg.groupName, style: AppTheme.headingLg),
              const SizedBox(height: 16),
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.chat, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(msg.senderName, style: AppTheme.labelMd),
                      Text(msg.senderNumber, style: AppTheme.bodySm),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    DateFormat.yMMMd().add_jm().format(msg.timestamp),
                    style: AppTheme.bodySm,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 32),
              if (msg.hasMedia && msg.downloadUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Image.network(msg.downloadUrl!, height: 300),
                ),
              Text(msg.body, style: AppTheme.bodyLg),
            ],
          ),
        ),
      );
    }

    return const Center(child: Text('Unknown item type'));
  }
}
