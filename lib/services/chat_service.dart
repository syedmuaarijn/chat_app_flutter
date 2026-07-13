import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;

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

      // Touch conversations.updated_at so the home screen listener fires
      await _supabaseClient
          .from('conversations')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', conversationId);

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

  // ── Real-time streams ────────────────────────────────────────────────────

  /// Emits the full up-to-date list of messages whenever the DB changes.
  /// The provider is responsible for merging/replacing the list.
  Stream<List<MessageModel>> listenToMessages(String conversationId) {
    return _supabaseClient
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) =>
            data.map((json) => MessageModel.fromJson(json)).toList());
  }

  /// Fires whenever the conversations table changes (updated_at changes on
  /// every message send, so this is our trigger for home screen refresh).
  Stream<List<Map<String, dynamic>>> listenToConversations() {
    final currentUser = currentUserId;
    if (currentUser == null) return const Stream.empty();
    return _supabaseClient
        .from('conversations')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false);
  }
}
