import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/services/message_service.dart';
import 'package:chat_app_flutter/services/receipt_service.dart';
import 'package:chat_app_flutter/services/conversation_service.dart';
import 'package:flutter/material.dart';

class ChatProvider with ChangeNotifier {
  final MessageService _messageService = MessageService();
  final ReceiptService _receiptService = ReceiptService();
  final ConversationService _conversationService = ConversationService();

  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  List<UserModel> _users = [];
  List<ParticipantInfo> _groupParticipants = [];

  bool _conversationsLoading = false;
  bool _messagesLoading = false;
  bool _usersLoading = false;
  bool _groupParticipantsLoading = false;
  bool _groupCreating = false;

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
  bool get isLoading => _conversationsLoading || _messagesLoading || _usersLoading;
  String? get error => _error;
  String get currentUserRole => _currentUserRole;

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

  Future<void> listenToConversations() async {}
  
  void stopListeningToConversations() {}

  // Messages
  Future<void> loadMessages(String conversationId) async {
    _messagesLoading = true;
    notifyListeners();
    try {
      final deletedMsgs = await _messageService.getDeletedMessages();
      _messages = await _messageService.getMessages(conversationId, deletedMsgs);
      
      for (var msg in _messages) {
        if (msg.senderId != _messageService.currentUserId) {
          _receiptService.markMessageAsDelivered(msg.id);
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _messagesLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAsRead(String messageId) async {
    await _receiptService.markMessageAsRead(messageId);
  }

  Future<Map<String, List<Map<String, dynamic>>>> getMessageInfo(String messageId) async {
    return await _receiptService.getMessageInfo(messageId);
  }

  Future<bool> sendMessage(String conversationId, String content) async {
    try {
      await _messageService.sendMessage(conversationId, content);
      return true;
    } catch (e) {
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
    _currentUserRole = await _conversationService.getCurrentUserRole(conversationId);
    notifyListeners();
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
