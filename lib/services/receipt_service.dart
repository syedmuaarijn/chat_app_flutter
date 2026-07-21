import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ReceiptService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  String? get _currentUserId => _supabaseClient.auth.currentUser?.id;

  /// Records that a user has read a specific message.
  Future<void> markMessageAsRead(String messageId) async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await _supabaseClient.from('message_receipts').upsert({
        'message_id': messageId,
        'user_id': userId,
        'receipt_type': 'read',
      });
    } catch (e) {
      debugPrint('Error marking message as read: $e');
    }
  }

  /// Records that a user has received a specific message on their device.
  Future<void> markMessageAsDelivered(String messageId) async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await _supabaseClient.from('message_receipts').upsert({
        'message_id': messageId,
        'user_id': userId,
        'receipt_type': 'delivered',
      });
    } catch (e) {
      debugPrint('Error marking message as delivered: $e');
    }
  }

  /// Fetches read/delivery info for a specific message with user details.
  Future<Map<String, List<Map<String, dynamic>>>> getMessageInfo(String messageId) async {
    try {
      final data = await _supabaseClient
          .from('message_receipts')
          .select('receipt_type, profiles(username, full_name, avatar_url)')
          .eq('message_id', messageId);

      final Map<String, List<Map<String, dynamic>>> info = {
        'read': [],
        'delivered': [],
      };

      for (final row in data as List) {
        final type = row['receipt_type'] as String;
        final profile = row['profiles'] as Map<String, dynamic>;
        info[type]?.add({
          'username': profile['username'],
          'fullName': profile['full_name'],
          'avatarUrl': profile['avatar_url'],
        });
      }
      return info;
    } catch (e) {
      debugPrint('Error fetching message info: $e');
      return {'read': [], 'delivered': []};
    }
  }
}
