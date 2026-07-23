import 'dart:async';

import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'New Group',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Create',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Group name input ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.group,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Group name',
                      border: InputBorder.none,
                      filled: false,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ],
            ),
          ),

          // ── Selected count ─────────────────────────────────────────
          if (_selectedIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Text(
                '${_selectedIds.length} selected',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),

          // ── Search bar ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
              onChanged: (query) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted)
                    context.read<ChatProvider>().searchUsers(query.trim());
                });
              },
            ),
          ),

          // ── Users list ─────────────────────────────────────────────
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isUsersLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (chatProvider.users.isEmpty) {
                  return Center(
                    child: Text(
                      'No users found',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: chatProvider.users.length,
                  itemBuilder: (context, index) {
                    final user = chatProvider.users[index];
                    final isSelected = _selectedIds.contains(user.id);

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: user.avatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(user.avatarUrl)
                            : null,
                        child: user.avatarUrl.isEmpty
                            ? Text(
                                user.fullName.isNotEmpty
                                    ? user.fullName[0].toUpperCase()
                                    : user.username[0].toUpperCase(),
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        user.fullName.isNotEmpty
                            ? user.fullName
                            : user.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '@${user.username}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: colorScheme.primary)
                          : Icon(
                              Icons.circle_outlined,
                              color: colorScheme.outline,
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
    );
  }
}
