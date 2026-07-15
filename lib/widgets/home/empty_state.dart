import 'package:flutter/material.dart';

class EmptyConversations extends StatelessWidget {
  const EmptyConversations({super.key});

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
