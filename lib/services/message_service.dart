import 'dart:io';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class MessageService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  String? get currentUserId => _supabaseClient.auth.currentUser?.id;

  RealtimeChannel? _messageChannel;

  Future<MessageModel> sendMessage(
    String conversationId,
    String content,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final data = await _supabaseClient
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUser,
            'content': content,
            'type': 'text',
          })
          .select()
          .single();

      return MessageModel.fromJson(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<MessageModel> sendMediaMessage({
    required String conversationId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String type,
    String? caption,
    int? audioDuration,
  }) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception(
          'The selected file is no longer available on this device.',
        );
      }

      final fileExt = fileName.contains('.') ? fileName.split('.').last : '';
      final storagePath =
          '$conversationId/${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}.$fileExt';

      await _supabaseClient.storage
          .from('chat-attachments')
          .upload(storagePath, file);

      final publicUrl = _supabaseClient.storage
          .from('chat-attachments')
          .getPublicUrl(storagePath);

      final data = await _supabaseClient
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUser,
            'content': caption != null && caption.isNotEmpty
                ? caption
                : fileName,
            'type': type,
            'media_url': publicUrl,
            'file_name': fileName,
            'file_size': fileSize,
            'audio_duration': audioDuration,
          })
          .select()
          .single();

      return MessageModel.fromJson(data);
    } on StorageException catch (e) {
      if (e.message.contains('Bucket not found') || e.statusCode == 404) {
        throw Exception(
          'Storage bucket "chat-attachments" not found. Please create this bucket in your Supabase dashboard at: https://supabase.com/dashboard/project/nfjlgqylmggppsxabtbd/storage',
        );
      }
      throw Exception('Could not upload the attachment: ${e.message}');
    } on PostgrestException catch (e) {
      throw Exception(
        'The attachment uploaded, but the message could not be saved: ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to send media message: $e');
    }
  }

  Future<MessageModel> forwardMessage({
    required String conversationId,
    required MessageModel source,
  }) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final data = await _supabaseClient
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUser,
            'content': source.content,
            'type': source.type,
            'media_url': source.mediaUrl,
            'file_name': source.fileName,
            'file_size': source.fileSize,
            'is_forwarded': true,
          })
          .select()
          .single();

      return MessageModel.fromJson(data);
    } catch (e) {
      throw Exception('Failed to forward message: $e');
    }
  }

  Future<void> deleteMessageForMe(String messageId) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await _supabaseClient.from('deleted_messages').upsert({
        'user_id': userId,
        'message_id': messageId,
      }, onConflict: 'user_id, message_id');
    } catch (e) {
      debugPrint('Error saving deleted message: $e');
    }
  }

  Future<Set<String>> getDeletedMessages() async {
    final userId = currentUserId;
    if (userId == null) return {};
    try {
      final data = await _supabaseClient
          .from('deleted_messages')
          .select('message_id')
          .eq('user_id', userId);
      return (data as List).map((row) => row['message_id'] as String).toSet();
    } catch (e) {
      debugPrint('Error reading deleted messages: $e');
      return {};
    }
  }

  Future<void> deleteMessageForEveryone(String messageId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient
          .from('messages')
          .update({'content': '[This message was deleted]'})
          .eq('id', messageId)
          .eq('sender_id', currentUser);
    } catch (e) {
      throw Exception('Failed to delete message for everyone: $e');
    }
  }

  Future<void> clearChat(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      final msgs = await _supabaseClient
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId);

      final List<Map<String, dynamic>> deletedEntries = (msgs as List)
          .map((m) => {'user_id': userId, 'message_id': m['id']})
          .toList();

      if (deletedEntries.isNotEmpty) {
        await _supabaseClient
            .from('deleted_messages')
            .upsert(deletedEntries, onConflict: 'user_id, message_id');
      }
    } catch (e) {
      debugPrint('Error clearing chat: $e');
    }
  }

  Future<List<MessageModel>> getMessages(
    String conversationId,
    Set<String> deletedMsgs,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final data = await _supabaseClient
          .from('messages')
          .select('*, profiles:sender_id(username, avatar_url)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      return (data as List)
          .map((json) {
            final message = MessageModel.fromJson(json);
            if (json['profiles'] != null) {
              message.senderUsername = json['profiles']['username'] as String?;
              message.senderAvatarUrl =
                  json['profiles']['avatar_url'] as String?;
            }
            return message;
          })
          .where((message) {
            return !deletedMsgs.contains(message.id);
          })
          .toList();
    } catch (e) {
      throw Exception('Failed to get messages: $e');
    }
  }

  void subscribeToMessages(
    String conversationId, {
    required void Function(List<MessageModel> messages) onData,
    required void Function(Object error) onError,
    required Set<String> deletedMsgs,
  }) {
    unsubscribeFromMessages();

    _messageChannel = _supabaseClient.channel('chat-messages-$conversationId');
    _messageChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (PostgresChangePayload payload) {
        getMessages(
          conversationId,
          deletedMsgs,
        ).then(onData).catchError(onError);
      },
    );
    _messageChannel!.subscribe((status, error) {
      debugPrint('📡 Message channel ($conversationId): $status');
      if (error != null) debugPrint('❌ Message channel error: $error');
    });
  }

  void unsubscribeFromMessages() {
    if (_messageChannel != null) {
      _supabaseClient.removeChannel(_messageChannel!);
      _messageChannel = null;
    }
  }
}
