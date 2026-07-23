import 'package:flutter/material.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MessageInfoSheet extends StatelessWidget {
  final String messageId;

  const MessageInfoSheet({super.key, required this.messageId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: context.read<ChatProvider>().getMessageInfo(messageId),
      builder: (context, snapshot) {
        // ── Loading ───────────────────────────────────────────────────────
        if (!snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHandle(colorScheme: colorScheme),
                const SizedBox(height: 24),
                CircularProgressIndicator(color: colorScheme.primary),
                const SizedBox(height: 16),
                Text('Loading message info…',
                    style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 24),
              ],
            ),
          );
        }

        final info = snapshot.data!;
        final readList = info['read'] ?? [];
        final deliveredList = info['delivered'] ?? [];

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle bar ──────────────────────────────────────────────
              _SheetHandle(colorScheme: colorScheme),

              // ── Title (fixed, never scrolls) ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Message Info',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),

              // ── Scrollable content ───────────────────────────────────────
              LimitedBox(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
                child: (readList.isEmpty && deliveredList.isEmpty)
                    ? _EmptyState(colorScheme: colorScheme)
                    : ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewPadding.bottom + 8,
                        ),
                        physics: const ClampingScrollPhysics(),
                        children: [
                          // Read by section
                          if (readList.isNotEmpty) ...[
                            _SectionHeader(
                              icon: Icons.done_all,
                              iconColor: const Color(0xFF53BDEB),
                              label: 'Read by',
                              colorScheme: colorScheme,
                            ),
                            ...readList.map((user) => _UserRow(user: user, colorScheme: colorScheme)),
                          ],
                          // Delivered to section
                          if (deliveredList.isNotEmpty) ...[
                            if (readList.isNotEmpty)
                              Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                            _SectionHeader(
                              icon: Icons.done_all,
                              iconColor: colorScheme.onSurface.withValues(alpha: 0.55),
                              label: 'Delivered to',
                              colorScheme: colorScheme,
                            ),
                            ...deliveredList.map((user) => _UserRow(user: user, colorScheme: colorScheme)),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );

      },
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  final ColorScheme colorScheme;
  const _SheetHandle({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final ColorScheme colorScheme;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final ColorScheme colorScheme;

  const _UserRow({required this.user, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user['avatarUrl'] as String?;
    final fullName = (user['fullName'] as String?)?.trim();
    final username = (user['username'] as String?) ?? '';
    final displayName =
        (fullName != null && fullName.isNotEmpty) ? fullName : username;
    final initials = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage:
            (avatarUrl != null && avatarUrl.isNotEmpty)
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(initials,
                style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold))
            : null,
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: username.isNotEmpty && displayName != username
          ? Text('@$username',
              style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.5)))
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme colorScheme;
  const _EmptyState({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule,
              size: 48, color: colorScheme.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Text(
            'No receipts yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Recipients will appear here once they\nreceive or read this message.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}
