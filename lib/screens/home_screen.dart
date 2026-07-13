import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/auth_provider.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:chat_app_flutter/screens/new_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  void _load() {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.loadConversations();
    chatProvider.listenToConversations();
  }

  @override
  void dispose() {
    context.read<ChatProvider>().stopListeningToConversations();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _openConversation(ConversationModel conversation) {
    if (conversation.otherUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          conversationId: conversation.id,
          otherUser: conversation.otherUser!,
        ),
      ),
    ).then((_) {
      // Refresh list when returning from chat
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  void _openNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    ).then((_) {
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'New Chat',
            onPressed: _openNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (chatProvider.isConversationsLoading && chatProvider.conversations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (chatProvider.conversations.isEmpty) {
            return _EmptyConversations(onNewChat: _openNewChat);
          }

          return RefreshIndicator(
            onRefresh: () => chatProvider.loadConversations(),
            child: ListView.separated(
              itemCount: chatProvider.conversations.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 72,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                return _ConversationTile(
                  conversation: conversation,
                  onTap: () => _openConversation(conversation),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewChat,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.chat_bubble_outline_rounded),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyConversations extends StatelessWidget {
  final VoidCallback onNewChat;
  const _EmptyConversations({required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 72, color: muted),
          const SizedBox(height: 16),
          Text(
            'No Conversations Yet',
            style: TextStyle(fontSize: 16, color: muted),
          ),
        ],
      ),
    );
  }
}

// ── Conversation tile ────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final other = conversation.otherUser;
    final lastMsg = conversation.lastMessage;
    final unread = conversation.unreadCount;

    final displayName =
        (other?.fullName.isNotEmpty == true) ? other!.fullName : (other?.username ?? '');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: (other?.avatarUrl.isNotEmpty == true)
            ? NetworkImage(other!.avatarUrl)
            : null,
        child: (other?.avatarUrl.isEmpty ?? true)
            ? Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              )
            : null,
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: lastMsg != null
          ? Text(
              lastMsg.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: unread > 0
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.55),
                fontWeight:
                    unread > 0 ? FontWeight.w500 : FontWeight.normal,
                fontSize: 13,
              ),
            )
          : Text(
              'No messages yet',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
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
