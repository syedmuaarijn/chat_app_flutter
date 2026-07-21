import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/services/message_service.dart';
import 'package:chat_app_flutter/services/receipt_service.dart';
import 'package:chat_app_flutter/services/conversation_service.dart';
import 'package:chat_app_flutter/services/chat_service.dart';
import 'package:flutter/material.dart';

class ChatProvider with ChangeNotifier {
  final MessageService _messageService = MessageService();
  final ReceiptService _receiptService = ReceiptService();
  final ConversationService _conversationService = ConversationService();
  final ChatService _chatService = ChatService();

  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  List<UserModel> _users = [];
  List<ParticipantInfo> _groupParticipants = [];

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
  bool get isLoading => _conversationsLoading || _messagesLoading || _usersLoading;
  String? get error => _error;
  String get currentUserRole => _currentUserRole;

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  // Conversations
  Future<void> loadConversations() async {
    _conversationsLoading = true;
    notifyListeners();
    try {
      _conversations = await _conversationService.getConversations();
    } catch (e) {
      _error = e.toString();
    } finally {
      _conversationsLoading = false;
      notifyListeners();
    }
  }

  void listenToConversations() {
    _chatService.subscribeToConversations(
      onRefresh: () {
        loadConversations();
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
            isSystemMessage: (newMsgJson['is_system_message'] as bool?) ?? false,
          );

          conv = conv.copyWith(
            lastMessage: updatedMsg,
            unreadCount: (!isMe && !isCurrentChatOpen) ? conv.unreadCount + 1 : conv.unreadCount,
          );

          _conversations[index] = conv;
          _conversations.sort((a, b) {
            final bTime = b.lastMessage?.createdAt ?? b.updatedAt ?? b.createdAt;
            final aTime = a.lastMessage?.createdAt ?? a.updatedAt ?? a.createdAt;
            return bTime.compareTo(aTime);
          });
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
    _messagesLoading = true;
    notifyListeners();
    try {
      final deletedMsgs = await _messageService.getDeletedMessages();
      _messages = await _messageService.getMessages(conversationId, deletedMsgs);
      // Mark all messages as delivered AND read (we're looking at them right now).
      // Both calls insert receipts into message_receipts which fires the DB
      // trigger that sets is_delivered / is_read on the messages rows.
      await _chatService.markMessagesAsDelivered(conversationId);
      await _chatService.markMessagesAsRead(conversationId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _messagesLoading = false;
      notifyListeners();
    }
  }

  void listenToMessages(String conversationId) async {
    final deletedMsgs = await _messageService.getDeletedMessages();
    _messageService.subscribeToMessages(
      conversationId,
      deletedMsgs: deletedMsgs,
      onData: (updatedMessages) {
        _messages = updatedMessages;

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

  Future<Map<String, List<Map<String, dynamic>>>> getMessageInfo(String messageId) async {
    return await _receiptService.getMessageInfo(messageId);
  }

  Future<bool> sendMessage(String conversationId, String content) async {
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
      final realMessage = await _messageService.sendMessage(conversationId, content);
      _messages = _messages.map((m) => m.id == tempId ? realMessage : m).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _messages = _messages.where((m) => m.id != tempId).toList();
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> clearChat(String conversationId) async {
    try {
      _messages = [];
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
    _usersLoading = true;
    notifyListeners();
    try {
      _users = await _conversationService.getAllUsers();
    } catch (e) {
      _error = e.toString();
    } finally {
      _usersLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchUsers(String query) async {
    _usersLoading = true;
    notifyListeners();
    try {
      _users = await _conversationService.searchUsers(query);
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
      final convId = await _conversationService.createGroup(name: name, memberIds: memberIds);
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
      _groupParticipants = await _conversationService.getGroupParticipants(conversationId);
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
      _currentUserRole = await _conversationService.getCurrentUserRole(conversationId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _roleLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addGroupParticipants(String conversationId, List<String> userIds) async {
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

  Future<bool> removeGroupParticipant(String conversationId, String targetUserId) async {
    try {
      await _conversationService.removeGroupParticipant(conversationId, targetUserId);
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
      _conversations = _conversations.where((c) => c.id != conversationId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> promoteToAdmin(String conversationId, String targetUserId) async {
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

  Future<bool> demoteFromAdmin(String conversationId, String targetUserId) async {
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

  Future<bool> transferOwnership(String conversationId, String newCreatorId) async {
    try {
      await _conversationService.transferOwnership(conversationId, newCreatorId);
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
      _conversations = _conversations.where((c) => c.id != conversationId).toList();
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
      _conversations = _conversations.where((c) => c.id != conversationId).toList();
      notifyListeners();
      await _conversationService.saveDeletedConversation(conversationId, DateTime.now().toUtc());
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
