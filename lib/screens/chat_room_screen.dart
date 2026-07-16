import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/group_info_screen.dart';
import 'package:chat_app_flutter/widgets/chat/date_separator.dart';
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
  bool _canSend = true;
  bool _leftGroup = false;

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
    await chatProvider.loadMessages(widget.conversationId);

    if (widget.conversation.isGroup) {
      await chatProvider.loadCurrentUserRole(widget.conversationId);
      _checkCanSend(chatProvider);
    }
    _scrollToBottom();
  }

  void _checkCanSend(ChatProvider chatProvider) {
    if (chatProvider.currentUserRole.isEmpty) {
      setState(() {
        _canSend = false;
        _leftGroup = true;
      });
      return;
    }
    if (widget.conversation.onlyAdminsCanMessage &&
        chatProvider.currentUserRole == 'member') {
      setState(() {
        _canSend = false;
        _leftGroup = false;
      });
    } else {
      setState(() {
        _canSend = true;
        _leftGroup = false;
      });
    }
  }

  @override
  void dispose() {
    context.read<ChatProvider>().stopListeningToMessages();
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
    if (text.isEmpty || _isSending || !_canSend) return;

    final role = context.read<ChatProvider>().currentUserRole;
    if (role.isEmpty) {
      setState(() => _canSend = false);
      return;
    }

    setState(() => _isSending = true);
    _messageController.clear();

    final success = await context.read<ChatProvider>().sendMessage(
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
          SnackBar(content: Text(context.read<ChatProvider>().error ?? 'Failed to send'), backgroundColor: Colors.red),
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
                  await context.read<ChatProvider>().clearChat(widget.conversationId);
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
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isMessagesLoading) return const Center(child: CircularProgressIndicator());
                if (chatProvider.messages.isEmpty) return const Center(child: Text('No messages yet.'));

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: chatProvider.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatProvider.messages[index];
                    return MessageBubble(message: message, isMe: message.senderId == _currentUserId, isGroup: conv.isGroup);
                  },
                );
              },
            ),
          ),
          if (_canSend)
            MessageInputBar(controller: _messageController, isSending: _isSending, onSend: _sendMessage)
          else
            Container(padding: const EdgeInsets.all(16), child: Text(_leftGroup ? 'You left this group' : 'Only admins can send messages', style: const TextStyle(fontStyle: FontStyle.italic))),
        ],
      ),
    );
  }
}
