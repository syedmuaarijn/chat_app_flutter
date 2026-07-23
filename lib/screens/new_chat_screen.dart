import 'dart:async';

import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchController = TextEditingController();
  bool _hasSearched = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadAllUsers();
      setState(() => _hasSearched = true);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) context.read<ChatProvider>().searchUsers(query.trim());
    });
  }

  Future<void> _openChat(UserModel user) async {
    final chatProvider = context.read<ChatProvider>();

    final conversationId = await chatProvider.getOrCreateConversation(user.id);

    if (!mounted) return;

    if (conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chatProvider.error ?? 'Could not open chat'),
          backgroundColor: Colors.red,
        ),
      );
      chatProvider.clearError();
      return;
    }

    final conversation = chatProvider.conversations.firstWhere(
      (c) => c.id == conversationId,
      orElse: () => ConversationModel(
        id: conversationId,
        createdAt: DateTime.now(),
        otherUser: user,
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          conversationId: conversationId,
          conversation: conversation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'New Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Results
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!_hasSearched) {
                  return const SizedBox.shrink();
                }

                if (chatProvider.users.isEmpty) {
                  return _EmptyUsers(
                    message: _searchController.text.isEmpty
                        ? 'No users found'
                        : 'No results for "${_searchController.text}"',
                  );
                }

                return ListView.builder(
                  itemCount: chatProvider.users.length,
                  itemBuilder: (context, index) {
                    final user = chatProvider.users[index];
                    return _UserTile(user: user, onTap: () => _openChat(user));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyUsers extends StatelessWidget {
  final String message;
  const _EmptyUsers({required this.message});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_rounded, size: 72, color: muted),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(fontSize: 16, color: muted)),
        ],
      ),
    );
  }
}

// ── User tile ────────────────────────────────────────────────────────────────

class _UserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = user.fullName.isNotEmpty
        ? user.fullName
        : user.username;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: user.avatarUrl.isNotEmpty
            ? CachedNetworkImageProvider(user.avatarUrl)
            : null,
        child: user.avatarUrl.isEmpty
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
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: user.fullName.isNotEmpty
          ? Text(
              '@${user.username}',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
