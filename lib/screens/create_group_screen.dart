import 'dart:async';
import 'dart:ui';

import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:chat_app_flutter/widgets/common/avatar_helper.dart';
import 'package:chat_app_flutter/widgets/common/abstract_background.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _isCreating = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadAllUsers();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        _selectedIds.remove(userId);
      } else {
        _selectedIds.add(userId);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Please enter a group name');
      return;
    }
    if (_selectedIds.isEmpty) {
      _showError('Please select at least one member');
      return;
    }

    setState(() => _isCreating = true);

    final chatProvider = context.read<ChatProvider>();
    final convId = await chatProvider.createGroup(
      name: name,
      memberIds: _selectedIds.toList(),
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (convId != null) {
      await chatProvider.loadConversations();
      if (!mounted) return;

      final conversation = chatProvider.conversations.firstWhere(
        (c) => c.id == convId,
        orElse: () => ConversationModel(
          id: convId,
          createdAt: DateTime.now(),
          isGroup: true,
          name: name,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversationId: convId,
            conversation: conversation,
          ),
        ),
      );
    } else {
      _showError(chatProvider.error ?? 'Failed to create group');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
      appBar: _GlassAppBar(
        title: 'New Group',
        action: TextButton(
          onPressed: _isCreating ? null : _createGroup,
          child: _isCreating
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              : Text(
                  'Create',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
        ),
      ),
      body: Stack(
        children: [
          const AbstractBackground(),
          Column(
            children: [
              SizedBox(
                height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),

              // ── Group name input ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.15),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.3)),
                            ),
                            child: Icon(Icons.group,
                                color: accent, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: TextStyle(
                                color:
                                    isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Group name',
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : Colors.black
                                          .withValues(alpha: 0.35),
                                ),
                                border: InputBorder.none,
                                filled: false,
                              ),
                              textCapitalization:
                                  TextCapitalization.sentences,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Selected count ─────────────────────────────────────
              if (_selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '${_selectedIds.length} member${_selectedIds.length == 1 ? '' : 's'} selected',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

              // ── Search bar ─────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.15),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
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
                          prefixIcon: Icon(Icons.search,
                              size: 20,
                              color: accent.withValues(alpha: 0.7)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                          border: InputBorder.none,
                        ),
                        onChanged: (query) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (mounted) {
                                context
                                    .read<ChatProvider>()
                                    .searchUsers(query.trim());
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              // ── Users list ─────────────────────────────────────────
              Expanded(
                child: Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    if (chatProvider.isUsersLoading) {
                      return Center(
                          child: CircularProgressIndicator(color: accent));
                    }
                    if (chatProvider.users.isEmpty) {
                      return Center(
                        child: Text(
                          'No users found',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.black.withValues(alpha: 0.35),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 120),
                      itemCount: chatProvider.users.length,
                      itemBuilder: (context, index) {
                        final user = chatProvider.users[index];
                        final isSelected =
                            _selectedIds.contains(user.id);
                        final avatarUrl = user.avatarUrl;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: accent.withValues(alpha: 0.15),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? AvatarHelper.getAvatarProvider(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    user.fullName.isNotEmpty
                                        ? user.fullName[0].toUpperCase()
                                        : user.username[0].toUpperCase(),
                                    style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(
                            user.fullName.isNotEmpty
                                ? user.fullName
                                : user.username,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.username}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.black.withValues(alpha: 0.45),
                              fontSize: 13,
                            ),
                          ),
                          trailing: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? accent
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? accent
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.3)
                                        : Colors.black
                                            .withValues(alpha: 0.25)),
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 16)
                                : null,
                          ),
                          onTap: () => _toggleSelection(user.id),
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
  final Widget? action;
  const _GlassAppBar({required this.title, this.action});

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
            iconTheme:
                IconThemeData(color: theme.colorScheme.primary),
            actions: [if (action != null) action!],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
