import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/services/message_service.dart';
import 'package:chat_app_flutter/services/receipt_service.dart';
import 'package:chat_app_flutter/services/conversation_service.dart';
import 'package:chat_app_flutter/services/chat_service.dart';
import 'package:chat_app_flutter/services/block_service.dart';
import 'package:chat_app_flutter/services/local_cache_service.dart';
import 'package:chat_app_flutter/services/offline_service.dart';
import 'package:flutter/material.dart';

class ChatProvider with ChangeNotifier {
  final MessageService _messageService = MessageService();
  final ReceiptService _receiptService = ReceiptService();
  final ConversationService _conversationService = ConversationService();
  final ChatService _chatService = ChatService();
  final BlockService _blockService = BlockService();
  final LocalCacheService _cacheService = LocalCacheService();
  final OfflineService _offlineService = OfflineService();

  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  List<UserModel> _users = [];
  List<ParticipantInfo> _groupParticipants = [];
  final Map<String, List<UserModel>> _userSearchCache = {};

  bool _conversationsLoading = false;
  bool _messagesLoading = false;
  bool _usersLoading = false;
  bool _groupParticipantsLoading = false;
  bool _groupCreating = false;
  bool _roleLoading = false;

  String? _error;
  String _currentUserRole = '';

  // Getters
  List<ConversationModel> get conversations => _conversations;
  List<MessageModel> get messages => _messages;
  List<UserModel> get users => _users;
  List<ParticipantInfo> get groupParticipants => _groupParticipants;
  bool get isConversationsLoading => _conversationsLoading;
  bool get isMessagesLoading => _messagesLoading;
  bool get isUsersLoading => _usersLoading;
  bool get isGroupParticipantsLoading => _groupParticipantsLoading;
  bool get isGroupCreating => _groupCreating;
  bool get isRoleLoading => _roleLoading;
  bool get isLoading =>
      _conversationsLoading || _messagesLoading || _usersLoading;
  String? get error => _error;
  String get currentUserRole => _currentUserRole;

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  bool _initialLoadDone = false;
  bool get initialLoadDone => _initialLoadDone;

  Future<void> _cacheConversationsLocally() async {
    final cacheData = _conversations.map((c) {
      final json = c.toJson();
      if (c.lastMessage != null) {
        json['last_message'] = c.lastMessage!.toJson();
      }
      if (c.otherUser != null) {
        json['other_user'] = c.otherUser!.toJson();
      }
      return json;
    }).toList();
    await _cacheService.cacheConversations(cacheData);
  }

  // Conversations
  Future<void> loadConversations() async {
    await _cacheService.initialize();

    // ── Step 1: Load from cache immediately (zero network latency) ──────────
    final cachedJson = await _cacheService.getCachedConversations();
    if (cachedJson.isNotEmpty) {
      _conversations = cachedJson.map((json) {
        final conv = ConversationModel.fromJson(json);
        if (json['last_message'] != null) {
          conv.lastMessage = MessageModel.fromJson(
            Map<String, dynamic>.from(json['last_message'] as Map),
          );
        }
        if (json['other_user'] != null) {
          conv.otherUser = UserModel.fromJson(
            Map<String, dynamic>.from(json['other_user'] as Map),
          );
        }
        return conv;
      }).toList();
    }

    // ── Step 2: Mark initial load done NOW (before any network call) ─────────
    // This allows the home screen to render the cached list immediately
    // instead of showing a spinner while we wait for the network check.
    if (!_initialLoadDone) {
      _initialLoadDone = true;
    }
    notifyListeners();

    // ── Step 3: Background network refresh (non-blocking) ────────────────────
    // We do NOT await hasConnection() on the main path — fire-and-forget so
    // the UI stays responsive. The cached result in OfflineService is used
    // on subsequent calls, so Android never blocks for minutes here.
    _refreshConversationsFromNetwork();
  }

  /// Fire-and-forget background refresh. Never blocks the calling frame.
  Future<void> _refreshConversationsFromNetwork() async {
    final isOnline = await _offlineService.hasConnection();
    if (!isOnline) return;

    try {
      final freshConversations = await _conversationService.getConversations();
      if (freshConversations.isNotEmpty || _conversations.isEmpty) {
        _conversations = freshConversations;
      }
      await _cacheConversationsLocally();
      notifyListeners();
    } catch (e) {
      debugPrint('Network fetch failed, keeping cached conversations: $e');
      _error = e.toString();
      if (_conversations.isEmpty) {
        _error = 'Failed to load conversations and no cache available';
      }
    }
  }

  void listenToConversations() {
    _chatService.subscribeToConversations(
      onRefresh: () async {
        // Only refresh if we're online to avoid clearing cached data
        final isOnline = await _offlineService.hasConnection();
        if (isOnline) {
          loadConversations();
        } else {
          debugPrint('Skipping conversation refresh - offline');
        }
      },
      onNewMessage: (payload) {
        final newMsgJson = payload.newRecord;
        final conversationId = newMsgJson['conversation_id'] as String;
        final senderId = newMsgJson['sender_id'] as String;
        final content = newMsgJson['content'] as String;
        final createdAt = DateTime.parse(newMsgJson['created_at'] as String);

        // Mark as delivered since we received it in real time
        if (senderId != _messageService.currentUserId) {
          _chatService.markMessagesAsDelivered(conversationId);
        }

        final index = _conversations.indexWhere((c) => c.id == conversationId);
        if (index != -1) {
          var conv = _conversations[index];
          final isMe = senderId == _messageService.currentUserId;
          final isCurrentChatOpen = _activeConversationId == conversationId;

          final updatedMsg = MessageModel(
            id: newMsgJson['id'] as String,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            isRead: (newMsgJson['is_read'] as bool?) ?? false,
            isDelivered: (newMsgJson['is_delivered'] as bool?) ?? false,
            createdAt: createdAt,
            updatedAt: DateTime.parse(newMsgJson['updated_at'] as String),
            isSystemMessage:
                (newMsgJson['is_system_message'] as bool?) ?? false,
          );

          conv = conv.copyWith(
            lastMessage: updatedMsg,
            unreadCount: (!isMe && !isCurrentChatOpen)
                ? conv.unreadCount + 1
                : conv.unreadCount,
          );

          _conversations[index] = conv;
          _conversations.sort((a, b) {
            final bTime =
                b.lastMessage?.createdAt ?? b.updatedAt ?? b.createdAt;
            final aTime =
                a.lastMessage?.createdAt ?? a.updatedAt ?? a.createdAt;
            return bTime.compareTo(aTime);
          });
          _cacheConversationsLocally();
          notifyListeners();
        } else {
          loadConversations();
        }
      },
    );
  }

  void stopListeningToConversations() {
    _chatService.unsubscribeFromConversations();
  }

  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    if (conversationId != null) {
      // Mark messages as read in the DB (fires DB trigger → is_read = true)
      _chatService.markMessagesAsRead(conversationId);
      // ── CRITICAL FIX ────────────────────────────────────────────────────
      // Immediately zero-out the in-memory unreadCount for this conversation
      // so the badge disappears the moment the user taps on it — just like
      // WhatsApp, without waiting for a DB round-trip or loadConversations().
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx != -1 && _conversations[idx].unreadCount > 0) {
        _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
      }
    }
    notifyListeners();
  }

  // Messages
  Future<void> loadMessages(String conversationId) async {
    // ── Step 1: Load from cache immediately (zero network latency) ──────────
    final cachedJson = await _cacheService.getCachedMessages(conversationId);
    if (cachedJson.isNotEmpty) {
      _messages = cachedJson.map((json) => MessageModel.fromJson(json)).toList();
      notifyListeners();
      _scrollToBottomCallback?.call();
    }

    // ── Step 2: Background network refresh (non-blocking) ────────────────────
    _refreshMessagesFromNetwork(conversationId);
  }

  // Optional scroll callback set by the chat room so we can scroll to bottom
  // after messages load without coupling the provider to the view.
  VoidCallback? _scrollToBottomCallback;
  void setScrollToBottomCallback(VoidCallback? cb) {
    _scrollToBottomCallback = cb;
  }

  /// Fire-and-forget background refresh for messages. Never blocks UI.
  Future<void> _refreshMessagesFromNetwork(String conversationId) async {
    final isOnline = await _offlineService.hasConnection();
    if (!isOnline) return;

    try {
      final deletedMsgs = await _messageService.getDeletedMessages();
      final freshMessages = await _messageService.getMessages(
        conversationId,
        deletedMsgs,
      );
      _messages = freshMessages;

      final cacheData = _messages.map((m) => m.toJson()).toList();
      await _cacheService.cacheMessages(conversationId, cacheData);

      await _chatService.markMessagesAsDelivered(conversationId);
      await _chatService.markMessagesAsRead(conversationId);
      notifyListeners();
      _scrollToBottomCallback?.call();
    } catch (e) {
      debugPrint('Network message fetch failed, keeping cached: $e');
      _error = e.toString();
      if (_messages.isEmpty) {
        _error = 'Failed to load messages and no cache available';
      }
    }
  }

  void listenToMessages(String conversationId) async {
    final deletedMsgs = await _messageService.getDeletedMessages();
    _messageService.subscribeToMessages(
      conversationId,
      deletedMsgs: deletedMsgs,
      onData: (updatedMessages) {
        _messages = updatedMessages;

        final cacheData = updatedMessages.map((m) => m.toJson()).toList();
        LocalCacheService().cacheMessages(conversationId, cacheData);

        // If the chat is open, mark any unread incoming messages as read
        final currentUser = _messageService.currentUserId;
        bool hasUnread = false;
        for (var msg in updatedMessages) {
          if (msg.senderId != currentUser && !msg.isRead) {
            hasUnread = true;
            break;
          }
        }
        if (hasUnread) {
          _chatService.markMessagesAsRead(conversationId);
          // Also zero out the in-memory unread counter so the badge on
          // the home screen stays at 0 while this conversation is active.
          final idx = _conversations.indexWhere((c) => c.id == conversationId);
          if (idx != -1 && _conversations[idx].unreadCount > 0) {
            _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
          }
        }

        notifyListeners();
      },
      onError: (err) {
        _error = err.toString();
        notifyListeners();
      },
    );
  }

  Future<void> markAsRead(String messageId) async {
    await _receiptService.markMessageAsRead(messageId);
  }

  Future<Map<String, List<Map<String, dynamic>>>> getMessageInfo(
    String messageId,
  ) async {
    return await _receiptService.getMessageInfo(messageId);
  }

  Future<bool> sendMessage(String conversationId, String content) async {
    final isOnline = await _offlineService.hasConnection();
    
    if (!isOnline) {
      _error = 'Cannot send messages while offline';
      notifyListeners();
      return false;
    }
    
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = MessageModel(
      id: tempId,
      conversationId: conversationId,
      senderId: _messageService.currentUserId,
      content: content,
      isRead: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _messages = [..._messages, tempMessage];
    notifyListeners();

    try {
      final realMessage = await _messageService.sendMessage(
        conversationId,
        content,
      );
      _messages = _messages
          .map((m) => m.id == tempId ? realMessage : m)
          .toList();
      
      final cacheData = _messages.map((m) => m.toJson()).toList();
      await _cacheService.cacheMessages(conversationId, cacheData);
      
      notifyListeners();
      return true;
    } catch (e) {
      _messages = _messages.where((m) => m.id != tempId).toList();
      final errorText = e.toString().toLowerCase();
      _error = errorText.contains('blocked you')
          ? 'You cannot send messages to this user because they have blocked you.'
          : 'Could not send your message. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendMediaMessage({
    required String conversationId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String type,
    String? caption,
    int? audioDuration,
  }) async {
    final isOnline = await _offlineService.hasConnection();
    
    if (!isOnline) {
      _error = 'Cannot send media while offline';
      notifyListeners();
      return false;
    }
    
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final currentUserId = _messageService.currentUserId;

    final tempMessage = MessageModel(
      id: tempId,
      conversationId: conversationId,
      senderId: currentUserId,
      content: caption != null && caption.isNotEmpty ? caption : fileName,
      type: type,
      mediaUrl: filePath,
      fileName: fileName,
      fileSize: fileSize,
      audioDuration: audioDuration,
      isRead: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _messages = [..._messages, tempMessage];
    notifyListeners();

    try {
      final realMessage = await _messageService.sendMediaMessage(
        conversationId: conversationId,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
        type: type,
        caption: caption,
        audioDuration: audioDuration,
      );
      _messages = _messages
          .map((m) => m.id == tempId ? realMessage : m)
          .toList();

      final cacheData = _messages.map((m) => m.toJson()).toList();
      await _cacheService.cacheMessages(conversationId, cacheData);

      notifyListeners();
      return true;
    } catch (e) {
      _messages = _messages.where((m) => m.id != tempId).toList();
      final errorText = e.toString().toLowerCase();
      _error = errorText.contains('blocked you')
          ? 'You cannot send messages to this user because they have blocked you.'
          : e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> forwardMessage({
    required String conversationId,
    required MessageModel message,
  }) async {
    try {
      final forwarded = await _messageService.forwardMessage(
        conversationId: conversationId,
        source: message,
      );
      if (conversationId == _activeConversationId) {
        _messages = [..._messages, forwarded];
        final cacheData = _messages.map((m) => m.toJson()).toList();
        await _cacheService.cacheMessages(conversationId, cacheData);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> clearChat(String conversationId) async {
    try {
      _messages = [];
      await LocalCacheService().cacheMessages(conversationId, []);
      notifyListeners();
      await _messageService.clearChat(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMessageForMe(String messageId) async {
    try {
      _messages = _messages.where((m) => m.id != messageId).toList();
      if (_activeConversationId != null) {
        final cacheData = _messages.map((m) => m.toJson()).toList();
        await LocalCacheService().cacheMessages(_activeConversationId!, cacheData);
      }
      notifyListeners();
      await _messageService.deleteMessageForMe(messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMessageForEveryone(String messageId) async {
    try {
      _messages = _messages.where((m) => m.id != messageId).toList();
      if (_activeConversationId != null) {
        final cacheData = _messages.map((m) => m.toJson()).toList();
        await LocalCacheService().cacheMessages(_activeConversationId!, cacheData);
      }
      notifyListeners();
      await _messageService.deleteMessageForEveryone(messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void stopListeningToMessages() {
    _messageService.unsubscribeFromMessages();
  }

  // Users
  Future<void> loadAllUsers() async {
    const cacheKey = '';
    if (_userSearchCache.containsKey(cacheKey)) {
      _users = _userSearchCache[cacheKey]!;
      notifyListeners();
      return;
    }
    _usersLoading = true;
    notifyListeners();
    try {
      _users = await _conversationService.getAllUsers();
      _userSearchCache[cacheKey] = _users;
    } catch (e) {
      _error = e.toString();
    } finally {
      _usersLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchUsers(String query) async {
    final cacheKey = query.trim().toLowerCase();
    if (_userSearchCache.containsKey(cacheKey)) {
      _users = _userSearchCache[cacheKey]!;
      notifyListeners();
      return;
    }
    _usersLoading = true;
    notifyListeners();
    try {
      _users = await _conversationService.searchUsers(cacheKey);
      _userSearchCache[cacheKey] = _users;
    } catch (e) {
      _error = e.toString();
    } finally {
      _usersLoading = false;
      notifyListeners();
    }
  }

  Future<String?> getOrCreateConversation(String otherUserId) async {
    try {
      return await _conversationService.getOrCreateConversation(otherUserId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> isCurrentUserBlocking(String otherUserId) async {
    try {
      return await _blockService.isCurrentUserBlocking(otherUserId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> blockUser(String otherUserId) async {
    try {
      await _blockService.blockUser(otherUserId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> unblockUser(String otherUserId) async {
    try {
      await _blockService.unblockUser(otherUserId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Group methods
  Future<String?> createGroup({
    required String name,
    String description = '',
    String avatarUrl = '',
    required List<String> memberIds,
  }) async {
    _groupCreating = true;
    notifyListeners();
    try {
      final convId = await _conversationService.createGroup(
        name: name,
        memberIds: memberIds,
      );
      await loadConversations();
      return convId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _groupCreating = false;
      notifyListeners();
    }
  }

  Future<void> loadGroupParticipants(String conversationId) async {
    _groupParticipantsLoading = true;
    notifyListeners();
    try {
      _groupParticipants = await _conversationService.getGroupParticipants(
        conversationId,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _groupParticipantsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCurrentUserRole(String conversationId) async {
    _roleLoading = true;
    _currentUserRole = '';
    notifyListeners();
    try {
      _currentUserRole = await _conversationService.getCurrentUserRole(
        conversationId,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _roleLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addGroupParticipants(
    String conversationId,
    List<String> userIds,
  ) async {
    try {
      await _conversationService.addGroupParticipants(conversationId, userIds);
      await loadGroupParticipants(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeGroupParticipant(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      await _conversationService.removeGroupParticipant(
        conversationId,
        targetUserId,
      );
      await loadGroupParticipants(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> leaveGroup(String conversationId) async {
    try {
      await _conversationService.leaveGroup(conversationId);
      _conversations = _conversations
          .where((c) => c.id != conversationId)
          .toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> promoteToAdmin(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      await _conversationService.promoteToAdmin(conversationId, targetUserId);
      await loadGroupParticipants(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> demoteFromAdmin(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      await _conversationService.demoteFromAdmin(conversationId, targetUserId);
      await loadGroupParticipants(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateGroupSettings({
    required String conversationId,
    bool? onlyAdminsCanMessage,
    bool? onlyAdminsCanEditInfo,
  }) async {
    try {
      await _conversationService.updateGroupSettings(
        conversationId: conversationId,
        onlyAdminsCanMessage: onlyAdminsCanMessage,
        onlyAdminsCanEditInfo: onlyAdminsCanEditInfo,
      );
      await loadConversations();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateGroupInfo({
    required String conversationId,
    String? name,
    String? description,
    String? avatarUrl,
  }) async {
    try {
      await _conversationService.updateGroupInfo(
        conversationId: conversationId,
        name: name,
        description: description,
        avatarUrl: avatarUrl,
      );
      await loadConversations();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> transferOwnership(
    String conversationId,
    String newCreatorId,
  ) async {
    try {
      await _conversationService.transferOwnership(
        conversationId,
        newCreatorId,
      );
      await loadGroupParticipants(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteGroup(String conversationId) async {
    try {
      await _conversationService.deleteGroup(conversationId);
      _conversations = _conversations
          .where((c) => c.id != conversationId)
          .toList();
      await _cacheConversationsLocally();
      await _cacheService.deleteCachedMessages(conversationId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConversation(String conversationId) async {
    try {
      _conversations = _conversations
          .where((c) => c.id != conversationId)
          .toList();
      await _cacheConversationsLocally();
      await _cacheService.deleteCachedMessages(conversationId);
      notifyListeners();
      await _conversationService.saveDeletedConversation(
        conversationId,
        DateTime.now().toUtc(),
      );
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearGroupParticipants() {
    _groupParticipants = [];
    _groupParticipantsLoading = false;
    _currentUserRole = '';
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _messages = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _messageService.unsubscribeFromMessages();
    super.dispose();
  }
}
