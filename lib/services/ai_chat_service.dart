import 'dart:convert';
import 'package:chat_app_flutter/config/supabase_config.dart';
import 'package:chat_app_flutter/models/ai_message_model.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AiChatService {
  AiChatService._();
  static final instance = AiChatService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<AiMessageModel>> loadHistory() async {
    final data = await _client
        .from('ai_messages')
        .select()
        .order('created_at', ascending: true)
        .limit(100);
    return (data as List)
        .map((item) => AiMessageModel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> streamMessage({
    required String message,
    required void Function(String text) onText,
  }) async {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      throw Exception('Please sign in again to use Nova.');
    }

    final request =
        http.Request(
            'POST',
            Uri.parse(
              '${SupabaseConfig.supabaseUrl}/functions/v1/chat-with-nova',
            ),
          )
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'apikey': SupabaseConfig.supabasePublishableKey,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({'message': message});

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final data = jsonDecode(body);
        throw Exception(
          data is Map
              ? data['error'] ?? 'Nova is unavailable right now.'
              : 'Nova is unavailable right now.',
        );
      }

      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
        if (data['text'] is String) onText(data['text'] as String);
        if (data['error'] is String) throw Exception(data['error']);
      }
    } finally {
      client.close();
    }
  }

  Future<void> clearHistory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('ai_messages').delete().eq('user_id', userId);
  }
}
