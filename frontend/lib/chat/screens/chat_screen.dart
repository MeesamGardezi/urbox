import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../auth/services/auth_service.dart';

import '../models/chat_group.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../widgets/create_group_dialog.dart';
import '../widgets/add_members_dialog.dart';
import '../widgets/group_details_dialog.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:go_router/go_router.dart';

class ChatScreen extends StatefulWidget {
  final String? initialGroupId;
  const ChatScreen({Key? key, this.initialGroupId}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Authentication & Role
  final User? currentUser = FirebaseAuth.instance.currentUser;
  bool isOwner = false;

  // State
  List<ChatGroup> groups = [];
  bool isLoadingGroups = true;
  String? selectedGroupId;
  ChatGroup? selectedGroup;

  List<ChatMessage> messages = [];
  bool isLoadingMessages = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Attachments
  List<ChatAttachment> _pendingAttachments = [];
  bool _isUploading = false;

  // Streams
  StreamSubscription? _msgSubscription;
  StreamSubscription? _reactionSubscription;

  @override
  void initState() {
    super.initState();
    ChatService.initSocket();
    _setupSocketListeners();
    _checkRole();
    _loadGroups();

    if (widget.initialGroupId != null) {
      selectedGroupId = widget.initialGroupId;
    }
  }

  void _setupSocketListeners() {
    _msgSubscription = ChatService.messageStream.listen((message) {
      if (mounted && selectedGroupId == message.groupId) {
        setState(() {
          final exists = messages.any((m) => m.id == message.id);
          if (!exists) {
            if (message.senderId != currentUser?.uid) {
              messages.insert(
                0,
                message,
              ); // Insert at beginning for reversed list
              _scrollToBottom();
            }
          }
        });
      }
    });

    _reactionSubscription = ChatService.reactionStream.listen((data) {
      if (mounted && selectedGroupId != null) {
        final messageId = data['messageId'];
        final reactionsData = data['reactions'] as List;

        setState(() {
          final index = messages.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            final oldMsg = messages[index];
            final updatedReactions = reactionsData
                .map((r) => ChatReaction.fromJson(r))
                .toList();

            messages[index] = ChatMessage(
              id: oldMsg.id,
              groupId: oldMsg.groupId,
              senderId: oldMsg.senderId,
              senderName: oldMsg.senderName,
              content: oldMsg.content,
              type: oldMsg.type,
              createdAt: oldMsg.createdAt,
              attachments: oldMsg.attachments,
              reactions: updatedReactions,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _reactionSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    if (selectedGroupId != null) {
      ChatService.leaveGroup(selectedGroupId!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialGroupId != oldWidget.initialGroupId &&
        widget.initialGroupId != null) {
      _selectGroupById(widget.initialGroupId!);
    }
  }

  Future<void> _checkRole() async {
    if (currentUser == null) return;
    try {
      final userResponse = await AuthService.getUserProfile(currentUser!.uid);
      if (userResponse['success'] == true) {
        final userData = userResponse['user'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            isOwner = userData['role'] == 'owner';
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking role: $e');
    }
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    setState(() => isLoadingGroups = true);
    try {
      final fetchedGroups = await ChatService.getGroups();
      if (!mounted) return;
      setState(() {
        groups = fetchedGroups;
        isLoadingGroups = false;

        if (selectedGroupId != null) {
          try {
            final group = groups.firstWhere((g) => g.id == selectedGroupId);
            _selectGroup(group, updateUrl: false);
          } catch (e) {
            selectedGroupId = null;
            if (groups.isNotEmpty) {
              _selectGroup(groups.first);
            }
          }
        } else if (groups.isNotEmpty) {
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

  void _selectGroupById(String groupId) {
    try {
      final group = groups.firstWhere((g) => g.id == groupId);
      _selectGroup(group, updateUrl: false);
    } catch (e) {
      setState(() => selectedGroupId = groupId);
    }
  }

  void _selectGroup(ChatGroup group, {bool updateUrl = true}) {
    if (selectedGroupId == group.id && !updateUrl) return;

    // Leave previous group room
    if (selectedGroupId != null) {
      ChatService.leaveGroup(selectedGroupId!);
    }

    setState(() {
      selectedGroupId = group.id;
      selectedGroup = group;
      messages = [];
      _pendingAttachments = [];
    });

    // Join new group room
    ChatService.joinGroup(group.id);

    if (updateUrl) {
      context.go('/chat/${group.id}');
    }

    _loadMessages(group.id);
  }

  Future<void> _loadMessages(String groupId) async {
    setState(() => isLoadingMessages = true);
    try {
      final fetchedMessages = await ChatService.getMessages(groupId);
      if (mounted && selectedGroupId == groupId) {
        setState(() {
          // Reverse the messages for reversed ListView
          messages = fetchedMessages.reversed.toList();
          isLoadingMessages = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingMessages = false);
      }
    }
  }

  Future<void> _pickFiles() async {
    if (selectedGroupId == null) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );

    if (result != null) {
      setState(() => _isUploading = true);

      for (var file in result.files) {
        try {
          final attachment = await ChatService.uploadAttachment(
            file,
            selectedGroupId!,
          );
          if (mounted) {
            setState(() {
              _pendingAttachments.add(attachment);
            });
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload ${file.name}: $e')),
            );
          }
        }
      }

      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _pendingAttachments.removeAt(index);
    });
  }

  Future<void> _sendMessage() async {
    if ((_messageController.text.trim().isEmpty &&
            _pendingAttachments.isEmpty) ||
        selectedGroupId == null) {
      return;
    }

    final content = _messageController.text.trim();
    final attachmentsToSend = List<ChatAttachment>.from(_pendingAttachments);

    _messageController.clear();
    setState(() {
      _pendingAttachments.clear();
    });
    _focusNode.requestFocus();

    // 1. Optimistic Update: Create a temporary message
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = ChatMessage(
      id: tempId,
      groupId: selectedGroupId!,
      senderId: currentUser!.uid,
      senderName: currentUser!.displayName ?? 'Me',
      content: content,
      type: 'text',
      createdAt: DateTime.now(),
      attachments: attachmentsToSend,
      reactions: [],
    );

    // 2. Add to beginning of list for reversed ListView
    if (mounted) {
      setState(() {
        messages.insert(0, optimisticMessage);
      });
      _scrollToBottom();
    }

    try {
      // 3. Send to backend
      final sentMessage = await ChatService.sendMessage(
        selectedGroupId!,
        content,
        attachments: attachmentsToSend,
      );

      // 4. Update the optimistic message with real ID and data from server
      if (mounted) {
        setState(() {
          final index = messages.indexWhere((m) => m.id == tempId);
          if (index != -1) {
            messages[index] = sentMessage;
          }
        });
      }
    } catch (e) {
      // 5. Revert optimistic update on failure
      if (mounted) {
        setState(() {
          messages.removeWhere((m) => m.id == tempId);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _sendReaction(String messageId, String reaction) async {
    try {
      await ChatService.sendReaction(messageId, reaction);
      // Reaction update will come via socket
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send reaction: $e')));
      }
    }
  }

  void _showReactionPicker(ChatMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(10),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['👍', '❤️', '😂', '😮', '😢', '🔥'].map((emoji) {
            return IconButton(
              icon: Text(emoji, style: const TextStyle(fontSize: 24)),
              onPressed: () {
                _sendReaction(message.id, emoji);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // In reversed list, position 0 is the bottom (newest messages)
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          CreateGroupDialog(onGroupCreated: () => _loadGroups()),
    );
  }

  void _showAddMembersDialog() {
    if (selectedGroup == null) return;
    showDialog(
      context: context,
      builder: (context) => AddMembersDialog(
        groupId: selectedGroup!.id,
        companyId: selectedGroup!.companyId,
        existingMemberIds: selectedGroup!.members,
        onMembersAdded: () => _loadGroups(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: isDesktop ? 300 : 80,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(2, 0),
                ),
              ],
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
                      if (isDesktop)
                        const Text(
                          'Groups',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      if (isOwner)
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
                              title: isDesktop
                                  ? Text(
                                      group.name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    )
                                  : null,
                              subtitle: isDesktop && group.lastMessage != null
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
                              selectedGroup!.name,
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
                            const Spacer(),
                            if (isOwner)
                              IconButton(
                                icon: const Icon(Icons.person_add_outlined),
                                tooltip: 'Add Members',
                                onPressed: _showAddMembersDialog,
                              ),
                            IconButton(
                              icon: const Icon(Icons.info_outline),
                              tooltip: 'Group Info',
                              onPressed: () {
                                if (selectedGroup != null) {
                                  showDialog(
                                    context: context,
                                    builder: (context) => GroupDetailsDialog(
                                      group: selectedGroup!,
                                      isOwner: isOwner,
                                      onGroupUpdated: () => _loadGroups(),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // Messages List (REVERSED)
                      Expanded(
                        child: isLoadingMessages
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                reverse: true, // Enable reversed ListView
                                controller: _scrollController,
                                padding: const EdgeInsets.all(20),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final msg = messages[index];
                                  final isMe = msg.senderId == currentUser?.uid;

                                  // For reversed list, check NEXT item (index + 1) for avatar logic
                                  final showAvatar =
                                      index == messages.length - 1 ||
                                      messages[index + 1].senderId !=
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
                                          child: GestureDetector(
                                            onLongPress: () =>
                                                _showReactionPicker(msg),
                                            onSecondaryTap: () =>
                                                _showReactionPicker(msg),
                                            child: Column(
                                              crossAxisAlignment: isMe
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    gradient: isMe
                                                        ? AppTheme
                                                              .primaryGradient
                                                        : null,
                                                    color: isMe
                                                        ? null
                                                        : Colors.grey.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
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
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors
                                                                  .grey
                                                                  .shade700,
                                                            ),
                                                          ),
                                                        ),

                                                      // Attachments
                                                      if (msg
                                                          .attachments
                                                          .isNotEmpty)
                                                        ...msg.attachments.map((
                                                          att,
                                                        ) {
                                                          return Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  bottom: 8.0,
                                                                ),
                                                            child: InkWell(
                                                              onTap: () async {
                                                                if (await canLaunchUrl(
                                                                  Uri.parse(
                                                                    att.url,
                                                                  ),
                                                                )) {
                                                                  await launchUrl(
                                                                    Uri.parse(
                                                                      att.url,
                                                                    ),
                                                                  );
                                                                }
                                                              },
                                                              child:
                                                                  att.type
                                                                      .startsWith(
                                                                        'image/',
                                                                      )
                                                                  ? ClipRRect(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            8,
                                                                          ),
                                                                      child: Image.network(
                                                                        att.url,
                                                                        height:
                                                                            150,
                                                                        width:
                                                                            200,
                                                                        fit: BoxFit
                                                                            .cover,
                                                                        errorBuilder:
                                                                            (
                                                                              c,
                                                                              e,
                                                                              s,
                                                                            ) => const Icon(
                                                                              Icons.broken_image,
                                                                            ),
                                                                      ),
                                                                    )
                                                                  : Container(
                                                                      padding:
                                                                          const EdgeInsets.all(
                                                                            8,
                                                                          ),
                                                                      decoration: BoxDecoration(
                                                                        color: Colors
                                                                            .black12,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              8,
                                                                            ),
                                                                      ),
                                                                      child: Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.min,
                                                                        children: [
                                                                          const Icon(
                                                                            Icons.description,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Flexible(
                                                                            child: Text(
                                                                              att.name,
                                                                              maxLines: 1,
                                                                              overflow: TextOverflow.ellipsis,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                            ),
                                                          );
                                                        }).toList(),

                                                      if (msg
                                                          .content
                                                          .isNotEmpty)
                                                        Text(
                                                          msg.content,
                                                          style: TextStyle(
                                                            color: isMe
                                                                ? Colors.white
                                                                : Colors
                                                                      .black87,
                                                          ),
                                                        ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        timeago.format(
                                                          msg.createdAt,
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: isMe
                                                              ? Colors.white
                                                                    .withOpacity(
                                                                      0.7,
                                                                    )
                                                              : Colors
                                                                    .grey
                                                                    .shade500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Reactions
                                                if (msg.reactions.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Wrap(
                                                      spacing: 4,
                                                      children: msg.reactions.map((
                                                        r,
                                                      ) {
                                                        return Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey
                                                                .shade200,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            border: Border.all(
                                                              color: Colors
                                                                  .grey
                                                                  .shade300,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            r.reaction,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                ),
                                                          ),
                                                        );
                                                      }).toList(),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pending Attachments
                            if (_pendingAttachments.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: SizedBox(
                                  height: 60,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _pendingAttachments.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final att = _pendingAttachments[index];
                                      return Stack(
                                        children: [
                                          Container(
                                            width: 60,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: att.type.startsWith('image/')
                                                ? ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: Image.network(
                                                      att.url,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.description,
                                                    color: Colors.grey,
                                                  ),
                                          ),
                                          Positioned(
                                            top: -5,
                                            right: -5,
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                size: 16,
                                                color: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  _removeAttachment(index),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            if (_isUploading) const LinearProgressIndicator(),

                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.attach_file),
                                  onPressed: _pickFiles,
                                  color: Colors.grey.shade600,
                                ),
                                Expanded(
                                  child: TextField(
                                    focusNode: _focusNode,
                                    controller: _messageController,
                                    decoration: InputDecoration(
                                      hintText: 'Type a message...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppTheme.primaryGradient,
                                  ),
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
