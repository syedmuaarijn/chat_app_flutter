import 'dart:io';
import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ConversationService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  String? get currentUserId => _supabaseClient.auth.currentUser?.id;

  // ── Helper Local Deletion Methods ────────────────────────────────────────

  Future<Map<String, String>> getDeletedConversations() async {
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

  Future<void> saveDeletedConversation(
    String conversationId,
    DateTime deletedAt,
  ) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await _supabaseClient.from('deleted_conversations').upsert({
        'user_id': userId,
        'conversation_id': conversationId,
        'deleted_at': deletedAt.toUtc().toIso8601String(),
      }, onConflict: 'user_id, conversation_id');
    } catch (e) {
      debugPrint('Error saving deleted conversation: $e');
    }
  }

  Future<String> getOrCreateConversation(String otherUserId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final convId = await _supabaseClient.rpc(
        'get_or_create_conversation',
        params: {'other_user_id': otherUserId},
      );

      final existingConvId = convId as String;

      final deletedConvs = await getDeletedConversations();
      if (deletedConvs.containsKey(existingConvId)) {
        final newConvData = await _supabaseClient.rpc(
          'create_fresh_conversation',
          params: {'other_user_id': otherUserId},
        );
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

      final participantFuture = _supabaseClient
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', currentUser)
          .eq('status', 'active');
      final deletedFuture = getDeletedConversations();
      final participantData = await participantFuture;
      final deletedConvs = await deletedFuture;

      final loaded = await Future.wait(
        (participantData as List).map(
          (participant) => _loadConversation(
            conversationId: participant['conversation_id'] as String,
            currentUserId: currentUser,
            deletedAt: deletedConvs[participant['conversation_id'] as String],
          ),
        ),
      );
      final conversations = loaded.whereType<ConversationModel>().toList();

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

  Future<ConversationModel?> _loadConversation({
    required String conversationId,
    required String currentUserId,
    required String? deletedAt,
  }) async {
    try {
      var unreadQuery = _supabaseClient
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .eq('is_read', false)
          .neq('sender_id', currentUserId);
      if (deletedAt != null) {
        unreadQuery = unreadQuery.gt('created_at', deletedAt);
      }

      final requests = await Future.wait<dynamic>([
        _supabaseClient
            .from('conversations')
            .select()
            .eq('id', conversationId)
            .single()
            .then((value) => value),
        _supabaseClient
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(1)
            .then((value) => value),
        unreadQuery
            .count(CountOption.exact)
            .then((value) => value),
      ]);

      var conversation = ConversationModel.fromJson(
        requests[0] as Map<String, dynamic>,
      );
      final lastMessageRows = requests[1] as List;
      final lastMessage = lastMessageRows.isEmpty
          ? null
          : MessageModel.fromJson(
              lastMessageRows.first as Map<String, dynamic>,
            );
      final deletedAtValue = deletedAt == null
          ? null
          : DateTime.parse(deletedAt);
      if (deletedAtValue != null &&
          (lastMessage == null ||
              !lastMessage.createdAt.isAfter(deletedAtValue))) {
        return null;
      }
      conversation.lastMessage = lastMessage;
      conversation.unreadCount = (requests[2] as PostgrestResponse).count;

      if (conversation.isGroup) {
        final count = await _supabaseClient
            .from('conversation_participants')
            .select('id')
            .eq('conversation_id', conversationId)
            .eq('status', 'active')
            .count(CountOption.exact);
        conversation = conversation.copyWith(participantCount: count.count);
      } else {
        final otherUser = await _supabaseClient
            .from('conversation_participants')
            .select('profiles(*)')
            .eq('conversation_id', conversationId)
            .neq('user_id', currentUserId)
            .single();
        conversation.otherUser = UserModel.fromJson(
          otherUser['profiles'] as Map<String, dynamic>,
        );
      }
      return conversation;
    } catch (e) {
      debugPrint('Skipping conversation $conversationId: $e');
      return null;
    }
  }

  Future<String> createGroup({
    required String name,
    String description = '',
    String avatarUrl = '',
    required List<String> memberIds,
  }) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final convId = await _supabaseClient.rpc(
        'create_group_conversation',
        params: {
          'creator_id': currentUser,
          'group_name': name,
          'group_description': description,
          'group_avatar_url': avatarUrl,
          'member_ids': memberIds,
        },
      );
      return convId as String;
    } catch (e) {
      throw Exception('Failed to create group: $e');
    }
  }

  Future<List<ParticipantInfo>> getGroupParticipants(
    String conversationId,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final data = await _supabaseClient.rpc(
        'get_group_participants',
        params: {'conv_id': conversationId},
      );

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

      if (data == null) return '';

      final role = (data['role'] as String?) ?? 'member';
      return role;
    } catch (e) {
      debugPrint('Failed to get user role: $e');
      return '';
    }
  }

  Future<void> addGroupParticipants(
    String conversationId,
    List<String> userIds,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'add_group_participants',
        params: {
          'conv_id': conversationId,
          'caller_id': currentUser,
          'new_member_ids': userIds,
        },
      );
    } catch (e) {
      throw Exception('Failed to add participants: $e');
    }
  }

  Future<void> removeGroupParticipant(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'remove_group_participant',
        params: {
          'conv_id': conversationId,
          'caller_id': currentUser,
          'target_id': targetUserId,
        },
      );
    } catch (e) {
      throw Exception('Failed to remove participant: $e');
    }
  }

  Future<void> leaveGroup(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'leave_group',
        params: {'conv_id': conversationId, 'leaving_user_id': currentUser},
      );
    } catch (e) {
      throw Exception('Failed to leave group: $e');
    }
  }

  Future<void> promoteToAdmin(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'promote_to_admin',
        params: {
          'conv_id': conversationId,
          'caller_id': currentUser,
          'target_id': targetUserId,
        },
      );
    } catch (e) {
      throw Exception('Failed to promote: $e');
    }
  }

  Future<void> demoteFromAdmin(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'demote_from_admin',
        params: {
          'conv_id': conversationId,
          'caller_id': currentUser,
          'target_id': targetUserId,
        },
      );
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
      if (onlyAdminsCanMessage != null)
        params['new_only_admins_can_message'] = onlyAdminsCanMessage;
      if (onlyAdminsCanEditInfo != null)
        params['new_only_admins_can_edit_info'] = onlyAdminsCanEditInfo;

      await _supabaseClient.rpc('update_group_settings', params: params);
    } catch (e) {
      throw Exception('Failed to update group settings: $e');
    }
  }

  Future<String> uploadGroupAvatar(String conversationId, File file) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      final fileExt = file.path.split('.').last;
      final storagePath = '$conversationId/group_avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _supabaseClient.storage
          .from('chat-attachments')
          .upload(
            storagePath,
            file,
            fileOptions: const FileOptions(cacheControl: '0', upsert: true),
          );

      final publicUrl = _supabaseClient.storage
          .from('chat-attachments')
          .getPublicUrl(storagePath);

      return publicUrl;
    } on StorageException catch (e) {
      if (e.message.contains('Bucket not found') || e.statusCode == 404) {
        throw Exception(
          'Storage bucket "chat-attachments" not found. Please create this bucket in your Supabase dashboard at: https://supabase.com/dashboard/project/nfjlgqylmggppsxabtbd/storage',
        );
      }
      throw Exception('Failed to upload group profile picture: ${e.message}');
    } catch (e) {
      throw Exception('Failed to upload group profile picture: $e');
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

  Future<void> transferOwnership(
    String conversationId,
    String newCreatorId,
  ) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'transfer_ownership',
        params: {
          'conv_id': conversationId,
          'caller_id': currentUser,
          'new_creator_id': newCreatorId,
        },
      );
    } catch (e) {
      throw Exception('Failed to transfer ownership: $e');
    }
  }

  Future<void> deleteGroup(String conversationId) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');

      await _supabaseClient.rpc(
        'delete_group',
        params: {'conv_id': conversationId, 'caller_id': currentUser},
      );
    } catch (e) {
      throw Exception('Failed to delete group: $e');
    }
  }

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');
      final data = await _supabaseClient.rpc(
        'search_visible_profiles',
        params: {'search_term': query},
      );
      return (data as List).map((json) => UserModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to search users: $e');
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    try {
      final currentUser = currentUserId;
      if (currentUser == null) throw Exception('No user logged in');
      final data = await _supabaseClient.rpc(
        'search_visible_profiles',
        params: {'search_term': ''},
      );
      return (data as List).map((json) => UserModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to get users: $e');
    }
  }
}
