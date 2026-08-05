import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/avatar_helper.dart';

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conv = conversation;
    final lastMsg = conv.lastMessage;
    final unread = conv.unreadCount;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isLastMsgMine =
        lastMsg != null &&
        lastMsg.senderId == currentUserId &&
        !lastMsg.isSystemMessage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
                  backgroundImage: conv.displayAvatar.isNotEmpty
                      ? AvatarHelper.getAvatarProvider(conv.displayAvatar)
                      : null,
                  child: conv.displayAvatar.isEmpty
                      ? Icon(
                          conv.isGroup ? Icons.group : Icons.person,
                          color: colorScheme.primary,
                          size: 26,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conv.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (isLastMsgMine) ...[
                            _TickIcon(
                              status: lastMsg.status,
                              colorScheme: colorScheme,
                            ),
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
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: unread > 0
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ] else if (lastMsg != null &&
                              lastMsg.isSystemMessage) ...[
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                lastMsg.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ] else
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildTrailing(colorScheme, lastMsg, unread),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(
    ColorScheme colorScheme,
    MessageModel? lastMsg,
    int unread,
  ) {
    return Column(
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
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        if (unread > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
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
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.white54,
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.white54);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white54);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 14, color: colorScheme.primary);
    }
  }
}
