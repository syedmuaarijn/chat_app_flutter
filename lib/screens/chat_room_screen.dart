import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/group_info_screen.dart';
import 'package:chat_app_flutter/screens/contact_info_screen.dart';
import 'package:chat_app_flutter/widgets/chat/message_bubble.dart';
import 'package:chat_app_flutter/widgets/chat/message_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final ConversationModel conversation;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.conversation,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final String _currentUserId =
      Supabase.instance.client.auth.currentUser?.id ?? '';

  bool _isSending = false;
  bool _isBlockedByMe = false;
  bool _roleLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initChat();
    });
  }

  void _initChat() {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.clearMessages();
    chatProvider.clearGroupParticipants();
    chatProvider.setActiveConversation(widget.conversationId);
    
    // Set scroll callback for auto-scroll after cache loads
    chatProvider.setScrollToBottomCallback(_scrollToBottom);
    
    // Begin listening to real-time message stream
    chatProvider.listenToMessages(widget.conversationId);

    // Load messages immediately (cache loads instantly, network refreshes in background)
    chatProvider.loadMessages(widget.conversationId);

    // Load block status and group role in background without blocking UI
    if (!widget.conversation.isGroup && widget.conversation.otherUser != null) {
      chatProvider.isCurrentUserBlocking(widget.conversation.otherUser!.id).then((isBlocked) {
        if (mounted) {
          setState(() => _isBlockedByMe = isBlocked);
        }
      });
    }

    if (widget.conversation.isGroup) {
      chatProvider.loadCurrentUserRole(widget.conversationId).then((_) {
        if (mounted) {
          setState(() => _roleLoaded = true);
        }
      });
    }
  }

  @override
  void dispose() {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.setActiveConversation(null);
    chatProvider.stopListeningToMessages();
    chatProvider.setScrollToBottomCallback(null); // Clear callback to prevent memory leak
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final chatProvider = context.read<ChatProvider>();
    final conv = widget.conversation;

    // Check sending permission
    if (conv.isGroup) {
      final role = chatProvider.currentUserRole;
      if (role.isEmpty || (conv.onlyAdminsCanMessage && role == 'member')) {
        return;
      }
    }

    setState(() => _isSending = true);
    _messageController.clear();

    final success = await chatProvider.sendMessage(widget.conversationId, text);

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        _scrollToBottom(animated: true);
      } else {
        _messageController.text = text;
        _showSendErrorDialog(chatProvider.error ?? 'Failed to send message.');
      }
    }
  }

  Future<void> _sendMediaMessage({
    required String filePath,
    required String fileName,
    required int fileSize,
    required String type,
    String? caption,
    int? audioDuration,
  }) async {
    if (_isSending) return;

    final chatProvider = context.read<ChatProvider>();
    setState(() => _isSending = true);

    final success = await chatProvider.sendMediaMessage(
      conversationId: widget.conversationId,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      type: type,
      caption: caption,
      audioDuration: audioDuration,
    );

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        _scrollToBottom(animated: true);
      } else {
        _showSendErrorDialog(
          chatProvider.error ?? 'Failed to send media message.',
        );
      }
    }
  }

  Future<void> _sendVoiceMessage({
    required String filePath,
    required String fileName,
    required int fileSize,
    required int durationSeconds,
  }) async {
    try {
      await _sendMediaMessage(
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        type: 'voice',
        caption: '',
        audioDuration: durationSeconds,
      );
    } finally {
      final recording = File(filePath);
      if (await recording.exists()) await recording.delete();
    }
  }

  Future<void> _forwardMessage(MessageModel message) async {
    final chatProvider = context.read<ChatProvider>();
    final targets = chatProvider.conversations
        .where((conversation) => conversation.id != widget.conversationId)
        .toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start another chat or group before forwarding.'),
        ),
      );
      return;
    }

    final target = await showModalBottomSheet<ConversationModel>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.6,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Forward to',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: targets.length,
                  itemBuilder: (_, index) {
                    final conversation = targets[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(conversation.displayInitial),
                      ),
                      title: Text(conversation.displayName),
                      subtitle: Text(conversation.isGroup ? 'Group' : 'Chat'),
                      onTap: () => Navigator.pop(sheetContext, conversation),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || target == null) return;
    final success = await chatProvider.forwardMessage(
      conversationId: target.id,
      message: message,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Message forwarded to ${target.displayName}'
              : (chatProvider.error ?? 'Could not forward message'),
        ),
        backgroundColor: success ? null : Colors.red,
      ),
    );
  }

  Future<void> _showSendErrorDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Message not sent'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openGroupInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
          conversationId: widget.conversationId,
          conversation: widget.conversation,
        ),
      ),
    );
  }

  Future<void> _openContactInfo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactInfoScreen(conversation: widget.conversation),
      ),
    );
    if (mounted) {
      final chatProvider = context.read<ChatProvider>();
      final otherUser = widget.conversation.otherUser;
      if (otherUser != null) {
        final isBlocked = await chatProvider.isCurrentUserBlocking(
          otherUser.id,
        );
        if (mounted) {
          setState(() {
            _isBlockedByMe = isBlocked;
          });
        }
      }
    }
  }

  Future<void> _toggleBlock() async {
    final otherUser = widget.conversation.otherUser;
    if (otherUser == null) return;

    if (!_isBlockedByMe) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block user?'),
          content: Text(
            '${widget.conversation.displayName} will no longer be able to find you in search or send you direct messages.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final success = _isBlockedByMe
        ? await context.read<ChatProvider>().unblockUser(otherUser.id)
        : await context.read<ChatProvider>().blockUser(otherUser.id);
    if (!mounted) return;

    if (success) {
      setState(() => _isBlockedByMe = !_isBlockedByMe);
      await context.read<ChatProvider>().loadMessages(widget.conversationId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<ChatProvider>().error ?? 'Could not update block',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final conv = widget.conversation;
    final chatProvider = context.watch<ChatProvider>();

    bool canSend = true;
    bool leftGroup = false;

    if (conv.isGroup) {
      final role = chatProvider.currentUserRole;
      // Only restrict sending if role has loaded and indicates user can't send
      // If role is empty (still loading), assume user can send (optimistic UI)
      if (_roleLoaded && role.isEmpty) {
        canSend = false;
        leftGroup = true;
      } else if (_roleLoaded && conv.onlyAdminsCanMessage && role == 'member') {
        canSend = false;
        leftGroup = false;
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: conv.isGroup ? _openGroupInfo : _openContactInfo,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: conv.displayAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(conv.displayAvatar)
                    : null,
                child: conv.displayAvatar.isEmpty
                    ? Text(conv.displayInitial)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  conv.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'block') {
                await _toggleBlock();
              } else if (value == 'clear') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Clear Chat?'),
                    content: const Text(
                      'Are you sure you want to clear this chat for you?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await chatProvider.clearChat(widget.conversationId);
                }
              }
            },
            itemBuilder: (context) => [
              if (!conv.isGroup)
                PopupMenuItem(
                  value: 'block',
                  child: Text(_isBlockedByMe ? 'Unblock user' : 'Block user'),
                ),
              const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatProvider.messages.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: chatProvider.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatProvider.messages[index];
                      return MessageBubble(
                        message: message,
                        isMe: message.senderId == _currentUserId,
                        isGroup: conv.isGroup,
                        onForward: _forwardMessage,
                      );
                    },
                  ),
          ),
          if (_isBlockedByMe)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'You blocked this user. Unblock them to send messages.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            )
          else if (canSend)
            MessageInputBar(
              controller: _messageController,
              isSending: _isSending,
              onSend: _sendMessage,
              onSendMedia: _sendMediaMessage,
              onSendVoice: _sendVoiceMessage,
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                leftGroup
                    ? 'You left this group'
                    : 'Only admins can send messages',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
