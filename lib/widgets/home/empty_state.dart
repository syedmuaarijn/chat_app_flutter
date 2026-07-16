import 'package:flutter/material.dart';

class EmptyConversations extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyConversations({
    super.key,
    this.icon = Icons.chat_bubble_outline_rounded,
    this.message = 'No Conversations Yet',
  });

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: muted),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: muted),
          ),
        ],
      ),
    );
  }
}
