import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages blocks created by the signed-in user. The database migration also
/// enforces the block for searches, direct-conversation creation, and messages.
class BlockService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;

  String? get currentUserId => _supabaseClient.auth.currentUser?.id;

  Future<bool> isCurrentUserBlocking(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('No user logged in');

    final block = await _supabaseClient
        .from('user_blocks')
        .select('blocked_user_id')
        .eq('blocker_id', userId)
        .eq('blocked_user_id', otherUserId)
        .maybeSingle();
    return block != null;
  }

  Future<void> blockUser(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('No user logged in');
    if (userId == otherUserId) throw Exception('You cannot block yourself');

    await _supabaseClient.from('user_blocks').upsert({
      'blocker_id': userId,
      'blocked_user_id': otherUserId,
    }, onConflict: 'blocker_id, blocked_user_id');
  }

  Future<void> unblockUser(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('No user logged in');

    await _supabaseClient
        .from('user_blocks')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_user_id', otherUserId);
  }
}
