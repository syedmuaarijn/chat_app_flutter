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

  StreamSubscription<List<MessageModel>>? _messageSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _conversationSubscription;
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
    _conversationSubscription?.cancel();
    _conversationDebounce?.cancel();

    _conversationSubscription =
        _chatService.listenToConversations().listen((data) {
      // Debounce to avoid hammering the DB on rapid events
      _conversationDebounce?.cancel();
      _conversationDebounce =
          Timer(const Duration(milliseconds: 300), loadConversations);
    }, onError: (e) {
      _error = 'Conversations stream error: $e';
      notifyListeners();
      debugPrint('❌ listenToConversations error: $e');
    });
  }

  void stopListeningToConversations() {
    _conversationSubscription?.cancel();
    _conversationSubscription = null;
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

  /// The stream now emits the FULL sorted list on every change.
  /// We merge it with existing messages, preserving optimistic temp messages
  /// until the real ones arrive from the server.
  void listenToMessages(String conversationId) {
    _messageSubscription?.cancel();
    _messageSubscription =
        _chatService.listenToMessages(conversationId).listen((messages) {
      // Remove any optimistic temp messages that have been replaced by real ones
      final realIds = messages.map((m) => m.id).toSet();
      _messages.removeWhere((m) => m.id.startsWith('temp_') && realIds.isNotEmpty);

      // Replace the message list with the server's authoritative snapshot
      _messages = messages;
      notifyListeners();

      // Mark incoming messages as read
      _chatService.markMessagesAsRead(conversationId);
    }, onError: (e) {
      _error = 'Stream error: $e';
      notifyListeners();
      // Print to console for debugging
      debugPrint('❌ listenToMessages error: $e');
    });
  }

  void stopListeningToMessages() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
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
      _messages.add(tempMessage);
      notifyListeners();

      // Send to server — this will trigger the stream on both devices
      final sentMessage =
          await _chatService.sendMessage(conversationId, content);

      // Replace the temp message with the real one from the server
      final tempIndex = _messages.indexWhere((m) => m.id == tempId);
      if (tempIndex != -1) {
        _messages[tempIndex] = sentMessage;
        notifyListeners();
      }

      return true;
    } catch (e) {
      _error = e.toString();
      // Remove the optimistic message if send failed
      _messages.removeWhere((m) => m.id.startsWith('temp_'));
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
    _error = null;
    try {
      return await _chatService.getOrCreateConversation(otherUserId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── Misc ───────────────────────────────────────────────────────────────────

  void clearError() {
    _error = null;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _conversationSubscription?.cancel();
    _conversationDebounce?.cancel();
    super.dispose();
  }
}
