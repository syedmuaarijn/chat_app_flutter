import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ContactInfoScreen extends StatefulWidget {
  final ConversationModel conversation;

  const ContactInfoScreen({
    super.key,
    required this.conversation,
  });

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  bool _isBlockedByMe = false;
  bool _isLoadingBlockStatus = true;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadBlockStatus();
  }

  Future<void> _loadBlockStatus() async {
    final otherUser = widget.conversation.otherUser;
    if (otherUser == null) {
      setState(() => _isLoadingBlockStatus = false);
      return;
    }
    final chatProvider = context.read<ChatProvider>();
    final isBlocked = await chatProvider.isCurrentUserBlocking(otherUser.id);
    if (mounted) {
      setState(() {
        _isBlockedByMe = isBlocked;
        _isLoadingBlockStatus = false;
      });
    }
  }

  Future<void> _toggleBlock() async {
    final otherUser = widget.conversation.otherUser;
    if (otherUser == null || _isActionInProgress) return;

    final chatProvider = context.read<ChatProvider>();

    if (!_isBlockedByMe) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block User?'),
          content: Text(
            '${widget.conversation.displayName} will no longer be able to find you in search or send you direct messages.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isActionInProgress = true);
    final success = _isBlockedByMe
        ? await chatProvider.unblockUser(otherUser.id)
        : await chatProvider.blockUser(otherUser.id);

    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        if (success) {
          _isBlockedByMe = !_isBlockedByMe;
        }
      });

      if (success) {
        await chatProvider.loadMessages(widget.conversation.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isBlockedByMe ? 'User blocked' : 'User unblocked'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Could not update block'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    if (_isActionInProgress) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: const Text('Are you sure you want to clear this chat for you?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isActionInProgress = true);
      final chatProvider = context.read<ChatProvider>();
      await chatProvider.clearChat(widget.conversation.id);
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final otherUser = widget.conversation.otherUser;

    if (otherUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact Info')),
        body: const Center(child: Text('User info not available.')),
      );
    }

    final displayName = widget.conversation.displayName;
    final username = otherUser.username.isNotEmpty ? '@${otherUser.username}' : '';
    final avatarUrl = widget.conversation.displayAvatar;
    final initial = widget.conversation.displayInitial;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Contact Info', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header (Avatar, Name, Username) ────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            initial,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  if (username.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      username,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // ── Bio Section ────────────────────────────────────────────
            if (otherUser.bio.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bio',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  otherUser.bio,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Action Buttons ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Clear Chat Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isActionInProgress ? null : _clearChat,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text(
                        'Clear Chat',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Block / Unblock Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoadingBlockStatus || _isActionInProgress ? null : _toggleBlock,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isLoadingBlockStatus
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                              ),
                            )
                          : Icon(_isBlockedByMe ? Icons.lock_open : Icons.block),
                      label: Text(
                        _isLoadingBlockStatus
                            ? 'Loading...'
                            : (_isBlockedByMe ? 'Unblock User' : 'Block User'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
