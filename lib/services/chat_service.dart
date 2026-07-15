import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class ChatService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;

  RealtimeChannel? _messageChannel;
  RealtimeChannel? _conversationChannel;

  String? get currentUserId => _supabaseClient.auth.currentUser?.id;

  // ── Helper Local Deletion Methods ────────────────────────────────────────

  Future<Map<String, String>> _getDeletedConversations() async {
    final userId = currentUserId;
    if (userId == null) return {};
    try {
      final data = await _supabaseClient
          .from('deleted_conversations')
          .select('conversation_id, deleted_at')
          .eq('user_id', userId);
      final Map<String, String> map = {};
      for (final row in data as List) {
        final convId = row['conversation_id'] as String;
        final deletedAt = row['deleted_at'] as String;
        map[convId] = deletedAt;
      }
      return map;
    } catch (e) {
      debugPrint('Error fetching deleted conversations: $e');
      return {};
    }
  }

  Future<void> _saveDeletedConversation(String conversationId, DateTime deletedAt) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await _supabaseClient.from('deleted_conversations').upsert({
        'user_id': userId,
        'conversation_id': conversationId,
        // Always store as UTC to avoid local/server clock skew
        'deleted_at': deletedAt.toUtc().toIso8601String(),
      }, onConflict: 'user_id, conversation_id');
    } catch (e) {
      debugPrint('Error saving deleted conversation: $e');
    }
  }

  Future<Set<String>> _getDeletedMessages() async {
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
    }
    return {};
  }

  Future<void> _saveDeletedMessage(String messageId) async {
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

  // ── User search ──────────────────────────────────────────────────────────

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');
      final data = await _supabaseClient
          .from('profiles')
          .select()
          .ilike('username', '%$query%')
          .neq('id', currentUser)
          .limit(20);
      return (data as List).map((json) => UserModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to search users: $e');
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');
      final data = await _supabaseClient
          .from('profiles')
          .select()
          .neq('id', currentUser)
          .order('username');
      return (data as List).map((json) => UserModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to get users: $e');
    }
  }

  // ── Conversations ────────────────────────────────────────────────────────

  Future<String> getOrCreateConversation(String otherUserId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      // Use a SECURITY DEFINER RPC to find or create the conversation.
      // This avoids triggering the recursive RLS policy on
      // conversation_participants while also handling the INSERT of both
      // participant rows atomically server-side.
      final convId = await _supabaseClient
          .rpc('get_or_create_conversation', params: {
            'other_user_id': otherUserId,
          });

      final existingConvId = convId as String;

      // Check if the current user has soft-deleted this conversation.
      // If so, create a brand-new conversation instead of reusing the old one.
      // This keeps old messages hidden and makes the new chat appear fresh on
      // the other user's home screen.
      final deletedConvs = await _getDeletedConversations();
      if (deletedConvs.containsKey(existingConvId)) {
        // The user deleted this conversation — create a genuinely new one.
        final newConvData = await _supabaseClient
            .rpc('create_fresh_conversation', params: {
              'other_user_id': otherUserId,
            });
        return newConvData as String;
      }

      return existingConvId;
    } catch (e) {
      throw Exception('Failed to get or create conversation: $e');
    }
  }

  Future<List<ConversationModel>> getConversations() async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final participantData = await _supabaseClient
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser);

      final List<ConversationModel> conversations = [];
      final deletedConvs = await _getDeletedConversations();

      for (var participant in participantData) {
        final conversationId = participant['conversation_id'] as String;
        final deletedAtStr = deletedConvs[conversationId];
        final deletedAt = deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

        final conversationData = await _supabaseClient
            .from('conversations')
            .select()
            .eq('id', conversationId)
            .single();

        final conversation = ConversationModel.fromJson(conversationData);

        final otherUserData = await _supabaseClient
            .from('conversation_participants')
            .select('user_id, profiles(*)')
            .eq('conversation_id', conversationId)
            .neq('user_id', currentUser)
            .single();

        conversation.otherUser =
            UserModel.fromJson(otherUserData['profiles'] as Map<String, dynamic>);

        final lastMessageData = await _supabaseClient
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(1);

        MessageModel? lastMsg;
        if ((lastMessageData as List).isNotEmpty) {
          lastMsg = MessageModel.fromJson(lastMessageData.first);
        }

        // Hide if deleted for the user and no new messages since deletion
        if (deletedAt != null) {
          if (lastMsg == null || lastMsg.createdAt.isBefore(deletedAt) || lastMsg.createdAt.isAtSameMomentAs(deletedAt)) {
            continue;
          }
        }

        conversation.lastMessage = lastMsg;

        var unreadQuery = _supabaseClient
            .from('messages')
            .select('id')
            .eq('conversation_id', conversationId)
            .eq('is_read', false)
            .neq('sender_id', currentUser);

        if (deletedAt != null) {
          unreadQuery = unreadQuery.gt('created_at', deletedAt.toIso8601String());
        }

        final unreadData = await unreadQuery.count(CountOption.exact);
        conversation.unreadCount = unreadData.count;

        conversations.add(conversation);
      }

      conversations.sort((a, b) {
        final bTime = b.lastMessage?.createdAt ?? b.updatedAt ?? b.createdAt;
        final aTime = a.lastMessage?.createdAt ?? a.updatedAt ?? a.createdAt;
        return bTime.compareTo(aTime);
      });
      return conversations;
    } catch (e) {
      throw Exception('Failed to get conversations: $e');
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<List<MessageModel>> getMessages(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final deletedConvs = await _getDeletedConversations();
      final deletedAtStr = deletedConvs[conversationId];
      final deletedAt = deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

      var query = _supabaseClient
          .from('messages')
          .select('*, profiles:sender_id(username, avatar_url)')
          .eq('conversation_id', conversationId);

      if (deletedAt != null) {
        query = query.gt('created_at', deletedAt.toIso8601String());
      }

      final data = await query.order('created_at', ascending: true);
      final deletedMsgs = await _getDeletedMessages();

      // Mark undelivered messages as delivered (recipient fetched them)
      await markMessagesAsDelivered(conversationId);

      return (data as List).map((json) {
        final message = MessageModel.fromJson(json);
        if (json['profiles'] != null) {
          message.senderUsername = json['profiles']['username'] as String?;
          message.senderAvatarUrl = json['profiles']['avatar_url'] as String?;
        }
        return message;
      }).where((message) {
        return !deletedMsgs.contains(message.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to get messages: $e');
    }
  }

  Future<MessageModel> sendMessage(
      String conversationId, String content) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final data = await _supabaseClient
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUser,
            'content': content,
          })
          .select()
          .single();

      return MessageModel.fromJson(data);
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');
      await _supabaseClient
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUser)
          .eq('is_read', false);
    } catch (e) {
      throw Exception('Failed to mark messages as read: $e');
    }
  }

  Future<void> markMessagesAsDelivered(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) return;
      await _supabaseClient
          .from('messages')
          .update({'is_delivered': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUser)
          .eq('is_delivered', false);
    } catch (e) {
      debugPrint('Failed to mark messages as delivered: $e');
    }
  }

  // ── Real-time subscriptions ──────────────────────────────────────────────

  void subscribeToMessages(
    String conversationId, {
    required void Function(List<MessageModel> messages) onData,
    required void Function(Object error) onError,
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
        getMessages(conversationId).then(onData).catchError(onError);
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

  void subscribeToConversations({
    required void Function() onRefresh,
  }) {
    unsubscribeFromConversations();

    final currentUser = currentUserId;
    if (currentUser == null) return;

    _conversationChannel =
        _supabaseClient.channel('chat-conversations-$currentUser');

    _conversationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (PostgresChangePayload payload) {
        final newRecord = payload.newRecord as Map<String, dynamic>?;
        if (newRecord != null) {
          final convId = newRecord['conversation_id'] as String?;
          if (convId != null) {
            markMessagesAsDelivered(convId);
          }
        }
        onRefresh();
      },
    );

    _conversationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'conversations',
      callback: (PostgresChangePayload payload) => onRefresh(),
    );

    _conversationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (PostgresChangePayload payload) => onRefresh(),
    );

    _conversationChannel!.subscribe((status, error) {
      debugPrint('📡 Conversation channel: $status');
      if (error != null) debugPrint('❌ Conversation channel error: $error');
    });
  }

  Future<void> deleteMessageForMe(String messageId) async {
    await _saveDeletedMessage(messageId);
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

  Future<void> deleteConversation(String conversationId) async {
    // Use UTC to avoid clock skew between local device and Supabase server
    await _saveDeletedConversation(conversationId, DateTime.now().toUtc());
  }

  void unsubscribeFromConversations() {
    if (_conversationChannel != null) {
      _supabaseClient.removeChannel(_conversationChannel!);
      _conversationChannel = null;
    }
  }
}
