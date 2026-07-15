import 'dart:async';
import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:chat_app_flutter/services/chat_service.dart';
import 'package:flutter/material.dart';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();

  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  List<UserModel> _users = [];

  bool _conversationsLoading = false;
  bool _messagesLoading = false;
  bool _usersLoading = false;

  String? _error;

  String? _currentConversationId;
  Timer? _conversationDebounce;

  // ── Getters ────────────────────────────────────────────────────────────────

  List<ConversationModel> get conversations => _conversations;
  List<MessageModel> get messages => _messages;
  List<UserModel> get users => _users;
  bool get isConversationsLoading => _conversationsLoading;
  bool get isMessagesLoading => _messagesLoading;
  bool get isUsersLoading => _usersLoading;
  bool get isLoading =>
      _conversationsLoading || _messagesLoading || _usersLoading;
  String? get error => _error;

  // ── Conversations ──────────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    _conversationsLoading = true;
    _error = null;
    notifyListeners();
    try {
      _conversations = await _chatService.getConversations();
    } catch (e) {
      _error = e.toString();
    } finally {
      _conversationsLoading = false;
      notifyListeners();
    }
  }

  /// Starts a real-time subscription. Whenever conversations.updated_at
  /// changes (which sendMessage now updates), reload the conversation list.
  void listenToConversations() {
    _conversationDebounce?.cancel();

    _chatService.subscribeToConversations(
      onRefresh: () {
        // Debounce to avoid hammering the DB on rapid events
        _conversationDebounce?.cancel();
        _conversationDebounce = Timer(
          const Duration(milliseconds: 500),
          loadConversations,
        );
      },
    );
  }

  void stopListeningToConversations() {
    _chatService.unsubscribeFromConversations();
    _conversationDebounce?.cancel();
  }

  // ── Messages ───────────────────────────────────────────────────────────────

  Future<void> loadMessages(String conversationId) async {
    _messagesLoading = true;
    _error = null;
    notifyListeners();
    try {
      _messages = await _chatService.getMessages(conversationId);
      await _chatService.markMessagesAsRead(conversationId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _messagesLoading = false;
      notifyListeners();
    }
  }

  void listenToMessages(String conversationId) {
    _currentConversationId = conversationId;

    _chatService.subscribeToMessages(
      conversationId,
      onData: (messages) {
        if (_currentConversationId != conversationId) return;

        _messages = messages;
        notifyListeners();

        // Only mark as read when user is actively viewing the chat room.
        // The _currentConversationId guard ensures this never fires when
        // the user is on the home screen.
        _chatService.markMessagesAsRead(conversationId);

        _updateConversationUnread(conversationId, 0);
        final lastMsg = messages.isNotEmpty ? messages.last : null;
        if (lastMsg != null) {
          _updateConversationLastMessage(conversationId, lastMsg);
        }
      },
      onError: (error) {
        _error = 'Stream error: $error';
        notifyListeners();
        debugPrint('❌ listenToMessages error: $error');
      },
    );
  }

  void _updateConversationUnread(String conversationId, int count) {
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == conversationId) {
        _conversations[i].unreadCount = count;
        notifyListeners();
        break;
      }
    }
  }

  void _updateConversationLastMessage(String conversationId, MessageModel message) {
    for (int i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == conversationId) {
        _conversations[i].lastMessage = message;
        notifyListeners();
        break;
      }
    }
  }

  void markMessagesAsRead(String conversationId) {
    _chatService.markMessagesAsRead(conversationId);
  }

  void stopListeningToMessages() {
    _chatService.unsubscribeFromMessages();
    _currentConversationId = null;
  }

  Future<bool> sendMessage(String conversationId, String content) async {
    _error = null;
    try {
      // Optimistically add a temporary message so the UI updates immediately
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final tempMessage = MessageModel(
        id: tempId,
        conversationId: conversationId,
        senderId: _chatService.currentUserId ?? '',
        content: content,
        isRead: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _messages = [..._messages, tempMessage];
      notifyListeners();

      // Send to server — the Realtime channel will deliver the confirmed
      // message back to both sender and receiver, replacing _messages with
      // the full server snapshot (which drops the temp message).
      await _chatService.sendMessage(conversationId, content);

      return true;
    } catch (e) {
      _error = e.toString();
      // Remove the optimistic message on failure
      _messages = _messages.where((m) => !m.id.startsWith('temp_')).toList();
      notifyListeners();
      return false;
    }
  }

  void clearMessages() {
    _messages = [];
    notifyListeners();
  }

  // ── Users ──────────────────────────────────────────────────────────────────

  Future<void> loadAllUsers() async {
    _usersLoading = true;
    _error = null;
    notifyListeners();
    try {
      _users = await _chatService.getAllUsers();
    } catch (e) {
      _error = e.toString();
    } finally {
      _usersLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchUsers(String query) async {
    _usersLoading = true;
    _error = null;
    notifyListeners();
    try {
      _users = query.isEmpty
          ? await _chatService.getAllUsers()
          : await _chatService.searchUsers(query);
    } catch (e) {
      _error = e.toString();
    } finally {
      _usersLoading = false;
      notifyListeners();
    }
  }

  Future<String?> getOrCreateConversation(String otherUserId) async {
    for (final c in _conversations) {
      if (c.otherUser?.id == otherUserId) return c.id;
    }

    _error = null;
    try {
      return await _chatService.getOrCreateConversation(otherUserId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }
  Future<bool> deleteMessageForMe(String messageId) async {
    _error = null;
    try {
      // Optimistically remove message from local list
      _messages = _messages.where((m) => m.id != messageId).toList();
      notifyListeners();

      await _chatService.deleteMessageForMe(messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMessageForEveryone(String messageId) async {
    _error = null;
    try {
      // Optimistically remove message from local list
      _messages = _messages.where((m) => m.id != messageId).toList();
      notifyListeners();

      await _chatService.deleteMessageForEveryone(messageId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConversation(String conversationId) async {
    _error = null;
    try {
      // Optimistically remove conversation from the local list
      _conversations = _conversations
          .where((c) => c.id != conversationId)
          .toList();
      notifyListeners();

      await _chatService.deleteConversation(conversationId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Misc ───────────────────────────────────────────────────────────────────

  void clearError() {
    _error = null;
  }

  @override
  void dispose() {
    _chatService.unsubscribeFromMessages();
    _chatService.unsubscribeFromConversations();
    _conversationDebounce?.cancel();
    super.dispose();
  }
}
