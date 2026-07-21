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
          .eq('user_id', currentUser)
          .eq('status', 'active');

      final List<ConversationModel> conversations = [];
      final deletedConvs = await _getDeletedConversations();

      for (var participant in participantData) {
        try {
          final conversationId = participant['conversation_id'] as String;
          final deletedAtStr = deletedConvs[conversationId];
          final deletedAt = deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

          final conversationData = await _supabaseClient
              .from('conversations')
              .select()
              .eq('id', conversationId)
              .single();

          var conversation = ConversationModel.fromJson(conversationData);

          if (conversation.isGroup) {
            try {
              final countQuery = _supabaseClient
                  .from('conversation_participants')
                  .select('id')
                  .eq('conversation_id', conversationId)
                  .eq('status', 'active');
              final countResponse = await countQuery.count(CountOption.exact);
              final participantCount = countResponse.count;
              // Store the live participant count separately so it is NOT
              // confused with (and never overwrites) the group's bio/description.
              conversation = conversation.copyWith(
                participantCount: participantCount,
              );
            } catch (_) {
              // Could not count participants (e.g. status column missing)
            }
          } else {
            final otherUserData = await _supabaseClient
                .from('conversation_participants')
                .select('user_id, profiles(*)')
                .eq('conversation_id', conversationId)
                .neq('user_id', currentUser)
                .single();

            conversation.otherUser = UserModel.fromJson(
                otherUserData['profiles'] as Map<String, dynamic>);
          }

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
        } catch (e) {
          debugPrint('⚠️ Skipping conversation $participant: $e');
        }
      }

      conversations.sort((a, b) {
        final bTime = b.lastMessage?.createdAt ?? b.updatedAt ?? b.createdAt;
        final aTime = a.lastMessage?.createdAt ?? a.updatedAt ?? a.createdAt;
        return bTime.compareTo(aTime);
      });
      return conversations;
    } catch (e) {
      debugPrint('❌ Failed to get conversations: $e');
      return [];
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

      // Find messages from others that are unread
      final unreadMessages = await _supabaseClient
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUser)
          .eq('is_read', false);

      if ((unreadMessages as List).isNotEmpty) {
        final List<Map<String, dynamic>> receipts = unreadMessages.map((m) => {
          'message_id': m['id'] as String,
          'user_id': currentUser,
          'receipt_type': 'read',
        }).toList();

        await _supabaseClient
            .from('message_receipts')
            .upsert(receipts, onConflict: 'message_id, user_id, receipt_type');
      }
    } catch (e) {
      debugPrint('Failed to mark messages as read: $e');
    }
  }

  Future<void> markMessagesAsDelivered(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) return;

      // Find messages from others that are undelivered
      final undeliveredMessages = await _supabaseClient
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUser)
          .eq('is_delivered', false);

      if ((undeliveredMessages as List).isNotEmpty) {
        final List<Map<String, dynamic>> receipts = undeliveredMessages.map((m) => {
          'message_id': m['id'] as String,
          'user_id': currentUser,
          'receipt_type': 'delivered',
        }).toList();

        await _supabaseClient
            .from('message_receipts')
            .upsert(receipts, onConflict: 'message_id, user_id, receipt_type');
      }
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
    required void Function(PostgresChangePayload payload) onNewMessage, // Add this callback
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
        // Optimistic home-screen update for new incoming messages.
        // We do NOT mark delivered here — delivery is recorded only when
        // the recipient actually opens the conversation (via loadMessages).
        onNewMessage(payload);
      },
    );

    // ── CRITICAL FIX ────────────────────────────────────────────────────────
    // Listen for UPDATE events on the messages table.
    // When the DB trigger fires (e.g. recipient read a message), it sets
    // is_delivered = true or is_read = true on the messages row.
    // Without this listener, the SENDER'S client never knows about the change
    // and tick icons stay grey/single forever.
    _conversationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (PostgresChangePayload payload) => onRefresh(),
    );

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

  // ── Group Chat Methods ─────────────────────────────────────────────────────

  Future<String> createGroup({
    required String name,
    String description = '',
    String avatarUrl = '',
    required List<String> memberIds,
  }) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final convId = await _supabaseClient.rpc('create_group_conversation', params: {
        'creator_id': currentUser,
        'group_name': name,
        'group_description': description,
        'group_avatar_url': avatarUrl,
        'member_ids': memberIds,
      });
      return convId as String;
    } catch (e) {
      throw Exception('Failed to create group: $e');
    }
  }

  Future<List<ParticipantInfo>> getGroupParticipants(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final data = await _supabaseClient
          .rpc('get_group_participants', params: {
            'conv_id': conversationId,
          });

      return (data as List).map((json) {
        final p = ParticipantInfo(
          userId: json['user_id'] as String,
          role: json['role'] as String,
          status: json['status'] as String,
          user: UserModel(
            id: json['user_id'] as String,
            username: (json['username'] as String?) ?? '',
            fullName: (json['full_name'] as String?) ?? '',
            avatarUrl: (json['avatar_url'] as String?) ?? '',
            bio: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        return p;
      }).toList();
    } catch (e) {
      throw Exception('Failed to get group participants: $e');
    }
  }

  Future<String> getCurrentUserRole(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) return '';

      final data = await _supabaseClient
          .from('conversation_participants')
          .select('role')
          .eq('conversation_id', conversationId)
          .eq('user_id', currentUser)
          .eq('status', 'active')
          .maybeSingle();

      // No active membership means the user left the group.
      if (data == null) return '';

      final role = (data['role'] as String?) ?? 'member';
      return role;
    } catch (e) {
      debugPrint('Failed to get user role: $e');
      return '';
    }
  }

  Future<void> addGroupParticipants(String conversationId, List<String> userIds) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('add_group_participants', params: {
        'conv_id': conversationId,
        'caller_id': currentUser,
        'new_member_ids': userIds,
      });
    } catch (e) {
      throw Exception('Failed to add participants: $e');
    }
  }

  Future<void> removeGroupParticipant(String conversationId, String targetUserId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('remove_group_participant', params: {
        'conv_id': conversationId,
        'caller_id': currentUser,
        'target_id': targetUserId,
      });
    } catch (e) {
      throw Exception('Failed to remove participant: $e');
    }
  }

  Future<void> leaveGroup(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('leave_group', params: {
        'conv_id': conversationId,
        'leaving_user_id': currentUser,
      });
    } catch (e) {
      throw Exception('Failed to leave group: $e');
    }
  }

  Future<void> promoteToAdmin(String conversationId, String targetUserId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('promote_to_admin', params: {
        'conv_id': conversationId,
        'caller_id': currentUser,
        'target_id': targetUserId,
      });
    } catch (e) {
      throw Exception('Failed to promote: $e');
    }
  }

  Future<void> demoteFromAdmin(String conversationId, String targetUserId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('demote_from_admin', params: {
        'conv_id': conversationId,
        'caller_id': currentUser,
        'target_id': targetUserId,
      });
    } catch (e) {
      throw Exception('Failed to demote: $e');
    }
  }

  Future<void> updateGroupSettings({
    required String conversationId,
    bool? onlyAdminsCanMessage,
    bool? onlyAdminsCanEditInfo,
  }) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final Map<String, dynamic> params = {
        'conv_id': conversationId,
        'caller_id': currentUser,
      };
      if (onlyAdminsCanMessage != null) params['new_only_admins_can_message'] = onlyAdminsCanMessage;
      if (onlyAdminsCanEditInfo != null) params['new_only_admins_can_edit_info'] = onlyAdminsCanEditInfo;

      await _supabaseClient.rpc('update_group_settings', params: params);
    } catch (e) {
      throw Exception('Failed to update group settings: $e');
    }
  }

  Future<void> updateGroupInfo({
    required String conversationId,
    String? name,
    String? description,
    String? avatarUrl,
  }) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final Map<String, dynamic> params = {
        'conv_id': conversationId,
        'caller_id': currentUser,
      };
      if (name != null) params['new_name'] = name;
      if (description != null) params['new_description'] = description;
      if (avatarUrl != null) params['new_avatar_url'] = avatarUrl;

      await _supabaseClient.rpc('update_group_info', params: params);
    } catch (e) {
      throw Exception('Failed to update group info: $e');
    }
  }

  Future<void> transferOwnership(String conversationId, String newCreatorId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('transfer_ownership', params: {
        'conv_id': conversationId,
        'caller_id': currentUser,
        'new_creator_id': newCreatorId,
      });
    } catch (e) {
      throw Exception('Failed to transfer ownership: $e');
    }
  }

  Future<void> deleteGroup(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc('delete_group', params: {
        'conv_id': conversationId,
        'caller_id': currentUser,
      });
    } catch (e) {
      throw Exception('Failed to delete group: $e');
    }
  }
}
