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

      // Find all conversations the current user is part of
      final myConvs = await _supabaseClient
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser);

      for (var row in myConvs) {
        final convId = row['conversation_id'] as String;
        // Check if the other user is also in this conversation
        final match = await _supabaseClient
            .from('conversation_participants')
            .select('conversation_id')
            .eq('conversation_id', convId)
            .eq('user_id', otherUserId);
        if (match.isNotEmpty) return convId;
      }

      // No existing conversation — create one
      final convData = await _supabaseClient
          .from('conversations')
          .insert({'updated_at': DateTime.now().toIso8601String()})
          .select()
          .single();

      final convId = convData['id'] as String;
      await _supabaseClient.from('conversation_participants').insert([
        {'conversation_id': convId, 'user_id': currentUser},
        {'conversation_id': convId, 'user_id': otherUserId},
      ]);
      return convId;
    } catch (e) {
      throw Exception('Failed to get or create conversation: $e');
    }
  }

  Future<List<ConversationModel>> getConversations() async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      // debugPrint('🔍 Fetching conversations for user: $currentUser');

      final participantData = await _supabaseClient
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser);

      // debugPrint('✅ Found ${(participantData as List).length} conversation participations');

      final List<ConversationModel> conversations = [];

      for (var participant in participantData) {
        final conversationId = participant['conversation_id'] as String;

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

        if ((lastMessageData as List).isNotEmpty) {
          conversation.lastMessage =
              MessageModel.fromJson(lastMessageData.first);
        }

        final unreadData = await _supabaseClient
            .from('messages')
            .select('id')
            .eq('conversation_id', conversationId)
            .eq('is_read', false)
            .neq('sender_id', currentUser)
            .count(CountOption.exact);
        conversation.unreadCount = unreadData.count;

        conversations.add(conversation);
      }

      conversations.sort((a, b) =>
          (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt));

      // debugPrint('✅ Loaded ${conversations.length} conversations');
      return conversations;
    } catch (e) {
      // debugPrint('❌ getConversations error: $e');
      throw Exception('Failed to get conversations: $e');
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<List<MessageModel>> getMessages(String conversationId) async {
    try {
      // debugPrint('🔍 Fetching messages for conversation: $conversationId');
      final data = await _supabaseClient
          .from('messages')
          .select('*, profiles:sender_id(username, avatar_url)')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      // debugPrint('✅ Fetched ${(data as List).length} messages');
      return (data).map((json) {
        final message = MessageModel.fromJson(json);
        if (json['profiles'] != null) {
          message.senderUsername =
              json['profiles']['username'] as String?;
          message.senderAvatarUrl =
              json['profiles']['avatar_url'] as String?;
        }
        return message;
      }).toList();
    } catch (e) {
      // debugPrint('❌ getMessages error: $e');
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

      // The DB trigger on_message_created automatically updates
      // conversations.updated_at — no manual update needed.

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

  // ── Real-time subscriptions ──────────────────────────────────────────────

  /// Subscribe to real-time message changes for a specific conversation.
  /// Uses Supabase Realtime Channels (postgres_changes) with a server-side
  /// filter, so INSERT / UPDATE / DELETE events from ANY user in the
  /// conversation are delivered reliably.
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
        // Reload the full message list for this conversation so we have
        // a consistent, ordered snapshot including sender profile data.
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

  /// Subscribe to events that should refresh the home-screen conversation
  /// list.  We listen for new message INSERTs and conversation UPDATEs.
  void subscribeToConversations({
    required void Function() onRefresh,
  }) {
    unsubscribeFromConversations();

    final currentUser = currentUserId;
    if (currentUser == null) return;

    _conversationChannel =
        _supabaseClient.channel('chat-conversations-$currentUser');

    // Any new message → refresh conversation list
    _conversationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (PostgresChangePayload payload) => onRefresh(),
    );

    // Conversation row updated (e.g. updated_at via trigger) → refresh
    _conversationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'conversations',
      callback: (PostgresChangePayload payload) => onRefresh(),
    );

    _conversationChannel!.subscribe((status, error) {
      debugPrint('📡 Conversation channel: $status');
      if (error != null) debugPrint('❌ Conversation channel error: $error');
    });
  }

  void unsubscribeFromConversations() {
    if (_conversationChannel != null) {
      _supabaseClient.removeChannel(_conversationChannel!);
      _conversationChannel = null;
    }
  }
}
