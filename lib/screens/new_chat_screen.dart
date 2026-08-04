import 'dart:async';
import 'dart:ui';

import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:chat_app_flutter/widgets/common/avatar_helper.dart';
import 'package:chat_app_flutter/widgets/common/abstract_background.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _GlassAppBar(title: 'New Chat'),
      body: Stack(
        children: [
          const AbstractBackground(),
          Column(
            children: [
              // Spacer for appbar height
              SizedBox(
                height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: _onSearchChanged,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search users...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.black.withValues(alpha: 0.35),
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: accent.withValues(alpha: 0.7),
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Results
              Expanded(
                child: Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    if (chatProvider.isLoading) {
                      return Center(
                        child: CircularProgressIndicator(color: accent),
                      );
                    }
                    if (!_hasSearched) return const SizedBox.shrink();
                    if (chatProvider.users.isEmpty) {
                      return _EmptyUsers(
                        message: _searchController.text.isEmpty
                            ? 'No users found'
                            : 'No results for "${_searchController.text}"',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8),
                      itemCount: chatProvider.users.length,
                      itemBuilder: (context, index) {
                        final user = chatProvider.users[index];
                        return _UserTile(
                          user: user,
                          onTap: () => _openChat(user),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Glass AppBar ──────────────────────────────────────────────────────────────
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _GlassAppBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.3),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            iconTheme: IconThemeData(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ── Empty state ──────────────────────────────────────────────────────────────
class _EmptyUsers extends StatelessWidget {
  final String message;
  const _EmptyUsers({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.3);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_rounded, size: 72, color: muted),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── User tile ─────────────────────────────────────────────────────────────────
class _UserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayName = user.fullName.isNotEmpty
        ? user.fullName
        : user.username;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.4,
        ),
        backgroundImage: user.avatarUrl.isNotEmpty
            ? AvatarHelper.getAvatarProvider(user.avatarUrl)
            : null,
        child: user.avatarUrl.isEmpty
            ? Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              )
            : null,
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: user.fullName.isNotEmpty
          ? Text(
              '@${user.username}',
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.45),
                fontSize: 13,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
