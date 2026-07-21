import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final conv = conversation;
    final lastMsg = conv.lastMessage;
    final unread = conv.unreadCount;

    // Determine if the last message was sent by the current user so we can
    // show WhatsApp-style tick icons (sent / delivered / read).
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isLastMsgMine =
        lastMsg != null && lastMsg.senderId == currentUserId && !lastMsg.isSystemMessage;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: conv.displayAvatar.isNotEmpty
            ? NetworkImage(conv.displayAvatar)
            : null,
        child: conv.displayAvatar.isEmpty
            ? Icon(
                conv.isGroup ? Icons.group : Icons.person,
                color: colorScheme.onPrimaryContainer,
                size: 26,
              )
            : null,
      ),
      title: Text(
        conv.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          // Tick icon prefix when the last message is from the current user
          if (isLastMsgMine) ...[
            _TickIcon(status: lastMsg.status, colorScheme: colorScheme),
            const SizedBox(width: 4),
          ],
          if (lastMsg != null && !lastMsg.isSystemMessage) ...[
            Flexible(
              child: Text(
                lastMsg.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unread > 0
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ] else if (lastMsg != null && lastMsg.isSystemMessage) ...[
            Icon(Icons.info_outline,
                size: 14, color: colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                lastMsg.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                ),
              ),
            ),
          ] else
            Text(
              'No messages yet',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMsg != null)
            Text(
              _formatTime(lastMsg.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: unread > 0
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          if (unread > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    }
    return '${local.day}/${local.month}/${local.year % 100}';
  }
}

// ── Tick icon widget ─────────────────────────────────────────────────────────

class _TickIcon extends StatelessWidget {
  final MessageStatus status;
  final ColorScheme colorScheme;

  const _TickIcon({required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        );
      case MessageStatus.sent:
        // Single grey tick — message is in the server but not yet delivered.
        return Icon(Icons.check, size: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.55));
      case MessageStatus.delivered:
        // Double grey tick — delivered to recipient's device.
        return Icon(Icons.done_all, size: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.55));
      case MessageStatus.read:
        // Double BLUE tick — recipient has read the message.
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB));
    }
  }
}
