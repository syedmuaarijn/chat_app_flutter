import 'package:chat_app_flutter/models/ai_message_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({super.key, required this.message});

  final AiMessageModel message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMe = message.isMe;
    final bubbleColor = isMe
        ? colorScheme.primary
        : colorScheme.surfaceContainerHigh;
    final textColor = isMe ? colorScheme.onPrimary : colorScheme.onSurface;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: message.content));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Copied')));
          }
        },
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 64 : 12,
            right: isMe ? 12 : 64,
            top: 4,
            bottom: 4,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.content,
                style: TextStyle(color: textColor, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
