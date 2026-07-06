import 'package:flutter/material.dart';
import 'package:chat_app_flutter/services/chat_service.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'dart:async';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();

  List<ConversationModel> _conversations = [];
  List<MessageModel> _messages = [];
  List<UserModel> _users = [];
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _messageSubscription;
  StreamSubscription? _conversationSubscription;

  List<ConversationModel> get conversations => _conversations;
  List<MessageModel> get messages => _messages;
  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _conversations = await _chatService.getConversations();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> LoadMessages(String query) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (query.isEmpty) {
        _users = await _chatService.getAllUsers();
      } else {
        _users = await _chatService.searchUsers(query);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> LoadAllUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _users = await _chatService.getAllUsers();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> getOrCreateConversation(String otherUserId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final conversationId = await _chatService.getOrCreateConversation(
        otherUserId,
      );
      _isLoading = false;
      notifyListeners();
      return conversationId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> loadMessages(String conversationId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _messages = await _chatService.getMessages(conversationId);
      await _chatService.markMessagesAsRead(conversationId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendMessage(String conversationId, String content) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final message = await _chatService.sendMessage(conversationId, content);
      _messages.add(message);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void listenToMessages(String conversationId) {
    _messageSubscription?.cancel();

    _messageSubscription = _chatService
        .listenToMessages(conversationId)
        .listen(
          (message) {
            final existingIndex = _messages.indexWhere(
              (m) => m.id == message.id,
            );
            if (existingIndex == -1) {
              _messages.add(message);
              notifyListeners();

              if (message.senderId != _chatService.currentUserId) {
                _chatService.markMessagesAsRead(conversationId);
              }
            } else {
              _messages[existingIndex] = message;
              notifyListeners();
            }
          },
          onError: (error) {
            _error = error.toString();
            notifyListeners();
          },
        );
  }

  void stopListeningToMessages() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
  }

  void listenToConversations() {
    _conversationSubscription?.cancel();
    _conversationSubscription = _chatService.listenToConversations().listen(
      (data) {
        loadConversations();
      },
      onError: (error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }


  void stopListeningToConversations(){
    _conversationSubscription?.cancel();
    _conversationSubscription = null;
  }


  void clearMessages(){
    _messages = [];
    notifyListeners();
  }

  void clearError(){
    _error = null;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _conversationSubscription?.cancel();
    super.dispose();
  }
}
