import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final UserModel otherUser;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
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
    // Start real-time listener first — it will deliver the full snapshot
    // including any messages that arrive during the initial load.
    chatProvider.listenToMessages(widget.conversationId);
    // Also do a one-shot load so we have data immediately without waiting
    // for the first stream event (which may have a small delay).
    await chatProvider.loadMessages(widget.conversationId);
    _scrollToBottom();
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
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

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
        // Restore text if failed
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = widget.otherUser.fullName.isNotEmpty
        ? widget.otherUser.fullName
        : widget.otherUser.username;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: widget.otherUser.avatarUrl.isNotEmpty
                  ? NetworkImage(widget.otherUser.avatarUrl)
                  : null,
              child: widget.otherUser.avatarUrl.isEmpty
                  ? Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayName,
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
      body: Column(
        children: [
          // Message list
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isMessagesLoading && chatProvider.messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (chatProvider.messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nSay hello!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  );
                }

                // Auto-scroll when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom(animated: true);
                });

                final messages = chatProvider.messages;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == _currentUserId;

                    // Show date separator if day changes
                    final showDate = index == 0 ||
                        !_isSameDay(
                          messages[index - 1].createdAt,
                          message.createdAt,
                        );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDate) _DateSeparator(date: message.createdAt),
                        _MessageBubble(
                          message: message,
                          isMe: isMe,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Input bar
          _MessageInputBar(
            controller: _messageController,
            isSending: _isSending,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }
}

// ── Date separator ───────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: muted, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(date),
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Expanded(child: Divider(color: muted, thickness: 0.5)),
        ],
      ),
    );
  }

  String _label(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${local.day}/${local.month}/${local.year}';
  }
}

// ── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bubbleColor =
        isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor =
        isMe ? colorScheme.onPrimary : colorScheme.onSurface;
    final timeColor = isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.7)
        : colorScheme.onSurface.withValues(alpha: 0.5);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.content,
              style: TextStyle(color: textColor, fontSize: 15),
            ),
            const SizedBox(height: 3),
            Text(
              _timeAgo(message.createdAt),
              style: TextStyle(fontSize: 10, color: timeColor),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${local.day}/${local.month}';
  }
}

// ── Message input bar ────────────────────────────────────────────────────────

class _MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _MessageInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                onPressed: isSending ? null : onSend,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 0,
                child: isSending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
