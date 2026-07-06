import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;

  String? get currentUserId => _supabaseClient.auth.currentUser?.id;

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) {
        throw Exception('No user Logged in');
      }
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
      if (currentUser == null) {
        throw Exception('No user Logged in');
      }
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

  Future<String> getOrCreateConversation(String otherUserId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) {
        throw Exception('No user Logged in');
      }
      final existingConversations = await _supabaseClient
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser);

      for (var conv in existingConversations) {
        final conversationId = conv['conversation_id'];
        final otherParticipants = await _supabaseClient
            .from('conversation_participants')
            .select()
            .eq('conversationId', conversationId)
            .eq('user_id', otherUserId);

        if (otherParticipants.isNotEmpty) {
          return conversationId;
        }
      }

      final conversationData = await _supabaseClient
          .from('conversations')
          .insert({})
          .select()
          .single();

      final conversationId = conversationData['id'];

      await _supabaseClient.from('conversation_participants').insert([
        {'conversation_id': conversationId, 'user_id': currentUser},
        {'conversation_id': conversationId, 'user_id': otherUserId},
      ]);
      return conversationId;
    } catch (e) {
      throw Exception('Failed to get or create conversation: $e');
    }
  }

  Future<List<ConversationModel>> getConversations() async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) {
        throw Exception('No user Logged in');
      }
      final participantData = await _supabaseClient
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser);

      List<ConversationModel> conversations = [];

      for (var participant in participantData) {
        final conversationId = participant['conversation_id'];

        final conversationData = await _supabaseClient
            .from('conversations')
            .select()
            .eq('id', conversationId)
            .single();

        ConversationModel conversation = ConversationModel.fromJson(
          conversationData,
        );

        final otherUserData = await _supabaseClient
            .from('conversation_participants')
            .select('user_id, profiles(*)')
            .eq('conversation_id', conversationId)
            .neq('user_id', currentUser)
            .single();

        conversation.otherUser = UserModel.fromJson(otherUserData['profiles']);

        final lastMessageData = await _supabaseClient
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(1);

        if (lastMessageData.isNotEmpty) {
          conversation.lastMessage = MessageModel.fromJson(
            lastMessageData.first,
          );
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
      conversations.sort(
        (a, b) =>
            (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt),
      );

      return conversations;
    } catch (e) {
      throw Exception('Failed to get conversation: $e');
    }
  }

  Future<List<MessageModel>> getMessages(String conversationId) async {
    try {
      final data = await _supabaseClient
          .from('messages')
          .select('*, profiles:sender_id(username, avatar_url)');
    } catch (e) {
      throw Exception('Failed to get messages: $e');
    }
  }
}
