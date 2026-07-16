import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/widgets/chat/message_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isGroup = false,
  });

  void _showDeleteDialog(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('Choose how you want to delete this message.'),
        actions: [
            if (isMe)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Message Info'),
                onTap: () {
                  Navigator.pop(dialogCtx);
                  showModalBottomSheet(
                    context: context, 
                    builder: (_) => MessageInfoSheet(messageId: message.id)
                  );
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _confirmDelete(context, () async {
                final success = await chatProvider.deleteMessageForMe(message.id);
                if (!success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(chatProvider.error ?? 'Failed to delete message')),
                  );
                }
              }, 'Delete for me', 'Are you sure you want to delete this message for yourself?');
            },
            child: const Text('Delete for Me'),
          ),
          if (isMe)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _confirmDelete(context, () async {
                  final success = await chatProvider.deleteMessageForEveryone(message.id);
                  if (!success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(chatProvider.error ?? 'Failed to delete message')),
                    );
                  }
                }, 'Delete for everyone', 'Are you sure you want to delete this message for everyone?');
              },
              child: const Text('Delete for Everyone'),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, VoidCallback onConfirm, String title, String description) {
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(confirmCtx);
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  static Color _userNameColor(String userId) {
    final hash = userId.hashCode;
    final hue = (hash % 360).abs();
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.6, 0.5).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (message.isSystemMessage) {
      return _SystemBubble(message: message, colorScheme: colorScheme);
    }

    final isDeleted = message.content == '[This message was deleted]';

    final bubbleColor =
        isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor =
        isMe ? colorScheme.onPrimary : colorScheme.onSurface;
    final timeColor = isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.7)
        : colorScheme.onSurface.withValues(alpha: 0.5);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isDeleted ? null : () => _showDeleteDialog(context),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Sender name for incoming group messages
              if (isGroup && !isMe && message.senderUsername != null && !isDeleted)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 2),
                  child: Text(
                    message.senderUsername!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _userNameColor(message.senderId ?? ''),
                    ),
                  ),
                ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      isDeleted ? 'This message was deleted' : message.content,
                      style: TextStyle(
                        color: isDeleted ? textColor.withValues(alpha: 0.6) : textColor,
                        fontSize: 15,
                        fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timeAgo(message.createdAt),
                          style: TextStyle(fontSize: 10, color: timeColor),
                        ),
                        if (isMe && !isDeleted) ...[
                          const SizedBox(width: 4),
                          _StatusIcon(status: message.status),
                        ],
                      ],
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

class _SystemBubble extends StatelessWidget {
  final MessageModel message;
  final ColorScheme colorScheme;

  const _SystemBubble({required this.message, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == MessageStatus.read
        ? const Color(0xFF53BDEB)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: color,
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: color);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 14, color: color);
    }
  }
}
