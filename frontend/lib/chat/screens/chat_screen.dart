import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_theme.dart';

import '../models/chat_group.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../widgets/create_group_dialog.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Authentication & Role
  final User? currentUser = FirebaseAuth.instance.currentUser;
  bool isOwner = false; // Will check role properly

  // State
  List<ChatGroup> groups = [];
  bool isLoadingGroups = true;
  String? selectedGroupId;
  ChatGroup? selectedGroup;

  List<ChatMessage> messages = [];
  bool isLoadingMessages = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkRole();
    _loadGroups();
  }

  Future<void> _checkRole() async {
    // In a real app, you might store this in a provider or GetIt
    // For now, we'll fetch the token claim or user profile if needed
    // But typically the Shell already knows.
    // Let's assume for now we can get it from the token logic or fail safe.
    // simpler: The create button visibility.
    // We can fetch the user profile if we want to be 100% sure of 'role'
    // But let's just use the current user ID for sending messages.
    // For the "Create Group" button, we might need to know if they are admin.
    // Let's defer strict role check or fetch it.

    // OPTIONAL: Fetch user profile to confirm role 'owner'
  }

  Future<void> _loadGroups() async {
    setState(() => isLoadingGroups = true);
    try {
      final fetchedGroups = await ChatService.getGroups();
      setState(() {
        groups = fetchedGroups;
        isLoadingGroups = false;

        // Auto-select first group if none selected and groups exist
        if (selectedGroupId == null && groups.isNotEmpty) {
          _selectGroup(groups.first);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingGroups = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load groups: $e')));
      }
    }
  }

  void _selectGroup(ChatGroup group) {
    setState(() {
      selectedGroupId = group.id;
      selectedGroup = group;
      messages = []; // Clear previous messages
    });
    _loadMessages(group.id);
  }

  Future<void> _loadMessages(String groupId) async {
    setState(() => isLoadingMessages = true);
    try {
      final fetchedMessages = await ChatService.getMessages(groupId);
      if (mounted && selectedGroupId == groupId) {
        setState(() {
          messages = fetchedMessages;
          isLoadingMessages = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingMessages = false);
        // Error handling
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || selectedGroupId == null)
      return;

    final content = _messageController.text.trim();
    _messageController.clear();

    // Optimistic UI update (optional, but good for UX)
    // For now, we'll just wait for server response to keep it simple and consistent

    try {
      final newMessage = await ChatService.sendMessage(
        selectedGroupId!,
        content,
      );
      if (mounted && selectedGroupId == newMessage.groupId) {
        setState(() {
          messages.add(newMessage);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateGroupDialog(
        onGroupCreated: () {
          _loadGroups(); // Refresh list
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Basic responsive layout
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar (Groups List)
          Container(
            width: isDesktop
                ? 300
                : 80, // Collapsed on mobile/tablet or drawer?
            // For simplicity, let's just make it fixed width for now or adaptable.
            // If width < 600, maybe show only list or only chat?
            // Let's stick to a standard dashboard layout.
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
              color: Colors.white,
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Groups',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      // Only show add button if we assume admin for now, or check role
                      // Let's show it, and backend will reject if not allowed,
                      // or better: checking role. For now, showing it.
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _showCreateGroupDialog,
                        tooltip: 'Create Group',
                      ),
                    ],
                  ),
                ),
                // Groups List
                Expanded(
                  child: isLoadingGroups
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            final isSelected = group.id == selectedGroupId;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isSelected
                                    ? AppTheme.primary
                                    : Colors.grey.shade200,
                                child: Text(
                                  group.name.isNotEmpty
                                      ? group.name[0].toUpperCase()
                                      : '#',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              title: Text(
                                group.name,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: group.lastMessage != null
                                  ? Text(
                                      group.lastMessage!['content'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    )
                                  : null,
                              selected: isSelected,
                              selectedTileColor: AppTheme.primary.withOpacity(
                                0.05,
                              ),
                              onTap: () => _selectGroup(group),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Chat Area
          Expanded(
            child: selectedGroup == null
                ? const Center(child: Text('Select a group to start chatting'))
                : Column(
                    children: [
                      // Chat Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Text(
                              selectedGroup!
                                  .name, // Handle private/direct messages later
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            if (selectedGroup!.description != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                  selectedGroup!.description!,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Messages List
                      Expanded(
                        child: isLoadingMessages
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(20),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final msg = messages[index];
                                  final isMe = msg.senderId == currentUser?.uid;

                                  // Check if we should show avatar (if previous msg was from same user)
                                  final bool showAvatar =
                                      index == 0 ||
                                      messages[index - 1].senderId !=
                                          msg.senderId;

                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: 8,
                                      top: showAvatar ? 8 : 0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: isMe
                                          ? MainAxisAlignment.end
                                          : MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe && showAvatar)
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                Colors.grey.shade300,
                                            child: Text(
                                              msg.senderName.isNotEmpty
                                                  ? msg.senderName[0]
                                                        .toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          )
                                        else if (!isMe)
                                          const SizedBox(width: 32),

                                        const SizedBox(width: 8),

                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? AppTheme.primary
                                                  : Colors.grey.shade100,
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(
                                                  12,
                                                ),
                                                topRight: const Radius.circular(
                                                  12,
                                                ),
                                                bottomLeft: Radius.circular(
                                                  isMe ? 12 : 0,
                                                ),
                                                bottomRight: Radius.circular(
                                                  isMe ? 0 : 12,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (!isMe && showAvatar)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 4,
                                                        ),
                                                    child: Text(
                                                      msg.senderName,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .grey
                                                            .shade700,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  msg.content,
                                                  style: TextStyle(
                                                    color: isMe
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  timeago.format(msg.createdAt),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isMe
                                                        ? Colors.white
                                                              .withOpacity(0.7)
                                                        : Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Input Area
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: _sendMessage,
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
    );
  }
}
