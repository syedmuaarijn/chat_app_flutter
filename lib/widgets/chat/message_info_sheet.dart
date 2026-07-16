import 'package:flutter/material.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:provider/provider.dart';

class MessageInfoSheet extends StatelessWidget {
  final String messageId;

  const MessageInfoSheet({super.key, required this.messageId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: context.read<ChatProvider>().getMessageInfo(messageId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        }
        final info = snapshot.data!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("Message Info", style: TextStyle(fontWeight: FontWeight.bold))),
            if (info['read']!.isNotEmpty) ...[
              const ListTile(title: Text("Read by", style: TextStyle(fontWeight: FontWeight.bold))),
              ...info['read']!.map((user) => ListTile(title: Text(user['fullName'] ?? user['username']))),
            ],
            if (info['delivered']!.isNotEmpty) ...[
              const ListTile(title: Text("Delivered to", style: TextStyle(fontWeight: FontWeight.bold))),
              ...info['delivered']!.map((user) => ListTile(title: Text(user['fullName'] ?? user['username']))),
            ],
          ],
        );
      },
    );
  }
}
