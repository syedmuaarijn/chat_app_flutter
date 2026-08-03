import 'dart:async';
import 'package:chat_app_flutter/models/ai_message_model.dart';
import 'package:chat_app_flutter/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum AiChatStatus { idle, loading, thinking, error }

class AiChatProvider with ChangeNotifier {
  final AiChatService _service = AiChatService.instance;
  final List<AiMessageModel> _messages = [];

  AiChatStatus _status = AiChatStatus.idle;
  String? _errorMessage;
  bool _historyLoaded = false;
  String _typingQueue = '';
  Timer? _typewriterTimer;

  List<AiMessageModel> get messages => List.unmodifiable(_messages);
  AiChatStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AiChatStatus.loading;
  bool get isThinking => _status == AiChatStatus.thinking;

  Future<void> loadHistory() async {
    if (_historyLoaded) return;
    _status = AiChatStatus.loading;
    notifyListeners();
    try {
      _messages
        ..clear()
        ..addAll(await _service.loadHistory());
      _historyLoaded = true;
      _status = AiChatStatus.idle;
    } catch (_) {
      _errorMessage = 'Could not load your AI chat history.';
      _status = AiChatStatus.error;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty || isThinking) return;

    _errorMessage = null;
    final userMessage = AiMessageModel(
      id: const Uuid().v4(),
      role: AiMessageRole.user,
      content: message,
      createdAt: DateTime.now(),
    );
    _messages.add(userMessage);
    final assistantMessage = AiMessageModel(
      id: const Uuid().v4(),
      role: AiMessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );
    _messages.add(assistantMessage);
    _status = AiChatStatus.thinking;
    notifyListeners();

    try {
      await _service.streamMessage(
        message: message,
        onText: (text) => _enqueueTypewriterText(assistantMessage, text),
      );
      await _waitForTypewriter();
      _status = AiChatStatus.idle;
    } catch (error) {
      _clearTypewriter();
      _messages.removeWhere((item) => item.id == userMessage.id);
      _messages.removeWhere((item) => item.id == assistantMessage.id);
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      _status = AiChatStatus.error;
    }
    notifyListeners();
  }

  Future<void> clearChat() async {
    try {
      await _service.clearHistory();
      _messages.clear();
      _historyLoaded = true;
      _errorMessage = null;
      _status = AiChatStatus.idle;
    } catch (_) {
      _errorMessage = 'Could not clear the AI chat.';
      _status = AiChatStatus.error;
    }
    notifyListeners();
  }

  void showGreetingIfEmpty() {
    if (_messages.isNotEmpty) return;
    _messages.add(
      AiMessageModel(
        id: 'nova-greeting',
        role: AiMessageRole.assistant,
        content: "Hi, I'm Nova ✨ How can I help today?",
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void dismissError() {
    _errorMessage = null;
    if (_status == AiChatStatus.error) _status = AiChatStatus.idle;
    notifyListeners();
  }

  void _enqueueTypewriterText(AiMessageModel message, String text) {
    _typingQueue += text;
    _typewriterTimer ??= Timer.periodic(const Duration(milliseconds: 14), (_) {
      if (_typingQueue.isEmpty) {
        _clearTypewriter();
        return;
      }
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index == -1) {
        _clearTypewriter();
        return;
      }
      final nextCharacter = _typingQueue[0];
      _typingQueue = _typingQueue.substring(1);
      _messages[index] = AiMessageModel(
        id: message.id,
        role: message.role,
        content: _messages[index].content + nextCharacter,
        createdAt: message.createdAt,
      );
      notifyListeners();
    });
  }

  Future<void> _waitForTypewriter() async {
    while (_typingQueue.isNotEmpty || _typewriterTimer != null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void _clearTypewriter() {
    _typewriterTimer?.cancel();
    _typewriterTimer = null;
    _typingQueue = '';
  }

  @override
  void dispose() {
    _clearTypewriter();
    super.dispose();
  }
}
