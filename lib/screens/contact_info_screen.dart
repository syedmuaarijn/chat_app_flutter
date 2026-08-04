import 'dart:ui';

import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/widgets/common/avatar_helper.dart';
import 'package:chat_app_flutter/widgets/common/abstract_background.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ContactInfoScreen extends StatefulWidget {
  final ConversationModel conversation;

  const ContactInfoScreen({super.key, required this.conversation});

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  bool _isBlockedByMe = false;
  bool _isLoadingBlockStatus = true;
  bool _isActionInProgress = false;

  void _showAvatar(String avatarUrl) {
    if (avatarUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image(
                  image: AvatarHelper.getAvatarProvider(avatarUrl),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        content: const Text(
          'Are you sure you want to clear this chat for you?',
        ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat cleared')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final otherUser = widget.conversation.otherUser;

    if (otherUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact Info')),
        body: const Center(child: Text('User info not available.')),
      );
    }

    final displayName = widget.conversation.displayName;
    final username = otherUser.username.isNotEmpty
        ? '@${otherUser.username}'
        : '';
    final avatarUrl = widget.conversation.displayAvatar;
    final initial = widget.conversation.displayInitial;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: _GlassAppBar(title: 'Contact Info'),
      body: Stack(
        children: [
          const AbstractBackground(),
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: kToolbarHeight + 48),

                // ── Header ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      // Avatar with glow ring
                      GestureDetector(
                        onTap: () => _showAvatar(avatarUrl),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2.5),
                          ),
                          child: CircleAvatar(
                            radius: 54,
                            backgroundColor: accent.withValues(alpha: 0.15),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? AvatarHelper.getAvatarProvider(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    initial,
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: accent,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          username,
                          style: TextStyle(
                            fontSize: 15,
                            color: accent.withValues(alpha: 0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Bio Section ──────────────────────────────────────
                if (otherUser.bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bio',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.8,
                                  color: accent.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                otherUser.bio,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Action Buttons ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Clear Chat
                      _ActionButton(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Clear Chat',
                        onPressed: _isActionInProgress ? null : _clearChat,
                        isDark: isDark,
                        accent: accent,
                      ),
                      const SizedBox(height: 12),

                      // Block / Unblock
                      _ActionButton(
                        icon: _isLoadingBlockStatus
                            ? null
                            : (_isBlockedByMe ? Icons.lock_open : Icons.block),
                        label: _isLoadingBlockStatus
                            ? 'Loading...'
                            : (_isBlockedByMe ? 'Unblock User' : 'Block User'),
                        isLoading: _isLoadingBlockStatus,
                        onPressed: _isLoadingBlockStatus || _isActionInProgress
                            ? null
                            : _toggleBlock,
                        isDark: isDark,
                        accent: Colors.red,
                        isDestructive: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),
              ],
            ),
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

// ── Action Button ─────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDark;
  final Color accent;
  final bool isDestructive;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.isDark,
    required this.accent,
    this.isDestructive = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              backgroundColor: accent.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  )
                : Icon(icon),
            label: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
