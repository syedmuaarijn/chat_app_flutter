import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;
  LocalCacheService._internal();

  late Box _authBox;
  late Box _chatCache;

  Future<void> initialize() async {
    _authBox = Hive.box('authBox');
    _chatCache = Hive.box('chatCache');
  }

  // Expose _chatCache for AuthProvider
  Box get chatCache => _chatCache;

  /// Recursively converts Map<dynamic,dynamic> (as returned by Hive) into
  /// Map<String,dynamic> so that model fromJson() calls never throw _CastError.
  static dynamic deepConvert(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map(
          (e) => MapEntry(e.key.toString(), deepConvert(e.value)),
        ),
      );
    }
    if (value is List) {
      return value.map(deepConvert).toList();
    }
    return value;
  }

  // Auth persistence
  Future<void> saveSession(String accessToken, String refreshToken) async {
    await _authBox.put('access_token', accessToken);
    await _authBox.put('refresh_token', refreshToken);
    await _authBox.put('session_timestamp', DateTime.now().toIso8601String());
  }

  Map<String, String?> getSession() {
    return {
      'access_token': _authBox.get('access_token'),
      'refresh_token': _authBox.get('refresh_token'),
      'session_timestamp': _authBox.get('session_timestamp'),
    };
  }

  Future<void> clearSession() async {
    await _authBox.delete('access_token');
    await _authBox.delete('refresh_token');
    await _authBox.delete('session_timestamp');
  }

  Future<void> cacheConversations(List<Map<String, dynamic>> jsonList) async {
    try {
      await _chatCache.put('conversations', jsonList);
      await _chatCache.put(
          'conversations_timestamp', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error caching conversations: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCachedConversations() async {
    try {
      final cached = _chatCache.get('conversations');
      if (cached != null && cached is List) {
        return cached
            .map((e) => deepConvert(e) as Map<String, dynamic>)
            .toList();
      }
    } catch (e) {
      debugPrint('Error reading cached conversations: $e');
    }
    return [];
  }

  Future<void> cacheMessages(
      String conversationId, List<Map<String, dynamic>> jsonList) async {
    try {
      await _chatCache.put('messages_$conversationId', jsonList);
      await _chatCache.put('messages_${conversationId}_timestamp',
          DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error caching messages for $conversationId: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCachedMessages(
      String conversationId) async {
    try {
      final cached = _chatCache.get('messages_$conversationId');
      if (cached != null && cached is List) {
        return cached
            .map((e) => deepConvert(e) as Map<String, dynamic>)
            .toList();
      }
    } catch (e) {
      debugPrint('Error reading cached messages for $conversationId: $e');
    }
    return [];
  }

  Future<void> deleteCachedMessages(String conversationId) async {
    try {
      await _chatCache.delete('messages_$conversationId');
      await _chatCache.delete('messages_${conversationId}_timestamp');
    } catch (e) {
      debugPrint('Error deleting cached messages: $e');
    }
  }

  Future<void> clearCache() async {
    try {
      await _chatCache.clear();
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  // Media caching
  Future<void> cacheMedia(String url, String localPath) async {
    try {
      await _chatCache.put('media_$url', localPath);
    } catch (e) {
      debugPrint('Error caching media: $e');
    }
  }

  String? getCachedMedia(String url) {
    try {
      return _chatCache.get('media_$url');
    } catch (e) {
      debugPrint('Error reading cached media: $e');
      return null;
    }
  }

  Future<void> clearOldCache() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final timestamp = _chatCache.get('conversations_timestamp');
      if (timestamp != null) {
        final dt = DateTime.tryParse(timestamp as String);
        if (dt != null && dt.isBefore(cutoff)) {
          await _chatCache.delete('conversations');
          await _chatCache.delete('conversations_timestamp');
        }
      }
    } catch (e) {
      debugPrint('Error clearing old cache: $e');
    }
  }
}
