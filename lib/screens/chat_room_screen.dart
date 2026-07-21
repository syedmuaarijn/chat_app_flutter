import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/group_info_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initChat();
    });
  }

  Future<void> _initChat() async {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.clearMessages();
    chatProvider.clearGroupParticipants();
    chatProvider.setActiveConversation(widget.conversationId);
    
    // Begin listening to real-time message stream
    chatProvider.listenToMessages(widget.conversationId);
    
    // Load initial list of messages
    await chatProvider.loadMessages(widget.conversationId);

    if (widget.conversation.isGroup) {
      await chatProvider.loadCurrentUserRole(widget.conversationId);
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.setActiveConversation(null);
    chatProvider.stopListeningToMessages();
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

    final success = await chatProvider.sendMessage(
      widget.conversationId,
      text,
    );

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        _scrollToBottom(animated: true);
      } else {
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Failed to send'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final conv = widget.conversation;
    final chatProvider = context.watch<ChatProvider>();

    bool canSend = true;
    bool leftGroup = false;
    bool isLoadingRole = false;

    if (conv.isGroup) {
      if (chatProvider.isRoleLoading) {
        isLoadingRole = true;
        canSend = false;
      } else {
        final role = chatProvider.currentUserRole;
        if (role.isEmpty) {
          canSend = false;
          leftGroup = true;
        } else if (conv.onlyAdminsCanMessage && role == 'member') {
          canSend = false;
          leftGroup = false;
        }
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: conv.isGroup ? _openGroupInfo : null,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: conv.displayAvatar.isNotEmpty ? NetworkImage(conv.displayAvatar) : null,
                child: conv.displayAvatar.isEmpty ? Text(conv.displayInitial) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(conv.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Clear Chat?'),
                    content: const Text('Are you sure you want to clear this chat for you?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await chatProvider.clearChat(widget.conversationId);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatProvider.isMessagesLoading && chatProvider.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : chatProvider.messages.isEmpty
                    ? const Center(child: Text('No messages yet.'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: chatProvider.messages.length,
                        itemBuilder: (context, index) {
                          final message = chatProvider.messages[index];
                          return MessageBubble(message: message, isMe: message.senderId == _currentUserId, isGroup: conv.isGroup);
                        },
                      ),
          ),
          if (isLoadingRole)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (canSend)
            MessageInputBar(controller: _messageController, isSending: _isSending, onSend: _sendMessage)
          else
            Container(
              padding: const EdgeInsets.all(16),
              child: Text(
                leftGroup ? 'You left this group' : 'Only admins can send messages',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
