import 'dart:ui';
import 'package:chat_app_flutter/providers/call_provider.dart';
import 'package:chat_app_flutter/widgets/common/avatar_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});
  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  late Future<List<Map<String, dynamic>>> _calls;

  @override
  void initState() {
    super.initState();
    _calls = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (user == null) return [];

    final rows = await Supabase.instance.client
        .from('call_history')
        .select()
        .or('caller_id.eq.$user,receiver_id.eq.$user')
        .order('started_at', ascending: false);

    final calls = List<Map<String, dynamic>>.from(rows);
    final ids = calls
        .expand((c) => [c['caller_id'], c['receiver_id']])
        .toSet()
        .toList();

    if (ids.isEmpty) return calls;

    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id,full_name,username,avatar_url')
        .inFilter('id', ids);

    final byId = {
      for (final p in profiles as List)
        p['id'] as String: p as Map<String, dynamic>,
    };

    for (final call in calls) {
      final other =
          call['caller_id'] == user ? call['receiver_id'] : call['caller_id'];
      call['profile'] = byId[other];
      call['outgoing'] = call['caller_id'] == user;
    }
    return calls;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _calls,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.phone_missed_rounded,
                  size: 72,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  'No calls yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _calls = _load()),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.07),
            ),
            itemBuilder: (context, i) => _tile(snapshot.data![i]),
          ),
        );
      },
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final p = c['profile'] as Map<String, dynamic>? ?? {};
    final name = _displayName(p);
    final video = c['call_type'] == 'video';
    final status = c['status'] as String;
    final outgoing = c['outgoing'] as bool;
    final missed = status == 'not_picked' || status == 'declined';
    final time =
        DateFormat('MMM d, h:mm a').format(DateTime.parse(c['started_at']).toLocal());
    final avatarUrl = p['avatar_url'] as String? ?? '';

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          color: Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => _showDetail(c),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              backgroundImage: avatarUrl.isNotEmpty
                  ? AvatarHelper.getAvatarProvider(avatarUrl)
                  : null,
              child: avatarUrl.isEmpty
                  ? Text(
                      name[0].toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : null,
            ),
            title: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: missed
                    ? Colors.red
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            subtitle: Row(
              children: [
                Icon(
                  outgoing
                      ? Icons.call_made_rounded
                      : Icons.call_received_rounded,
                  size: 13,
                  color: missed ? Colors.red : theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$time  ·  ${_statusLabel(status, c['duration_seconds'] as int? ?? 0)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: missed
                          ? Colors.red
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.55)
                              : Colors.black.withValues(alpha: 0.5)),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: IconButton(
                tooltip: video ? 'Video call' : 'Voice call',
                icon: Icon(
                  video ? Icons.videocam_rounded : Icons.phone_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                onPressed: () =>
                    _startCall(c, name, avatarUrl),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CallDetailSheet(call: c, onCallBack: _startCall),
    );
  }

  Future<void> _startCall(
      Map<String, dynamic> c, String name, String avatar) async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    final remote =
        c['caller_id'] == user ? c['receiver_id'] : c['caller_id'];
    final video = c['call_type'] == 'video';
    final ok = video
        ? await context.read<CallProvider>().startVideoCall(
              conversationId: c['conversation_id'],
              remoteUserId: remote,
              remoteUserName: name,
              remoteUserAvatarUrl: avatar,
            )
        : await context.read<CallProvider>().startCall(
              conversationId: c['conversation_id'],
              remoteUserId: remote,
              remoteUserName: name,
              remoteUserAvatarUrl: avatar,
            );
    if (ok && mounted) {
      Navigator.pushNamed(context, video ? '/video-call' : '/call');
    }
  }

  static String _displayName(Map<String, dynamic> p) {
    final full = p['full_name'] as String?;
    if (full != null && full.isNotEmpty) return full;
    return (p['username'] as String?) ?? 'Unknown';
  }

  static String _statusLabel(String status, int durationSeconds) {
    if (durationSeconds > 0) {
      final d = Duration(seconds: durationSeconds);
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$s' : '$m:$s';
    }
    return switch (status) {
      'not_picked' => 'Not picked up',
      'declined' => 'Declined',
      'completed' => 'Completed',
      'active' => 'Active',
      'ringing' => 'Ringing',
      _ => status,
    };
  }
}

// ── Call detail bottom sheet ──────────────────────────────────────────────────
class _CallDetailSheet extends StatelessWidget {
  const _CallDetailSheet({
    required this.call,
    required this.onCallBack,
  });

  final Map<String, dynamic> call;
  final Future<void> Function(Map<String, dynamic>, String, String) onCallBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final p = call['profile'] as Map<String, dynamic>? ?? {};
    final name = _name(p);
    final avatar = p['avatar_url'] as String? ?? '';
    final status = call['status'] as String;
    final outgoing = call['outgoing'] as bool;
    final video = call['call_type'] == 'video';
    final duration = call['duration_seconds'] as int? ?? 0;
    final missed = status == 'not_picked' || status == 'declined';

    final startedAt =
        DateTime.parse(call['started_at'] as String).toLocal();
    final acceptedAt = call['accepted_at'] != null
        ? DateTime.parse(call['accepted_at'] as String).toLocal()
        : null;
    final endedAt = call['ended_at'] != null
        ? DateTime.parse(call['ended_at'] as String).toLocal()
        : null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.75),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Avatar + name
                CircleAvatar(
                  radius: 36,
                  backgroundColor:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  backgroundImage: avatar.isNotEmpty
                      ? AvatarHelper.getAvatarProvider(avatar)
                      : null,
                  child: avatar.isEmpty
                      ? Text(
                          name[0].toUpperCase(),
                          style: const TextStyle(fontSize: 28),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),

                // Status badge
                _StatusBadge(status: status, outgoing: outgoing),
                const SizedBox(height: 24),

                // Detail rows
                _DetailRow(
                  icon: video ? Icons.videocam_rounded : Icons.phone_rounded,
                  label: 'Type',
                  value: video ? 'Video call' : 'Voice call',
                ),
                _DetailRow(
                  icon: outgoing
                      ? Icons.call_made_rounded
                      : Icons.call_received_rounded,
                  label: 'Direction',
                  value: outgoing ? 'Outgoing' : 'Incoming',
                  valueColor: missed ? Colors.red : null,
                ),
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  label: 'Started',
                  value: DateFormat('MMM d, yyyy  h:mm a').format(startedAt),
                ),
                if (acceptedAt != null)
                  _DetailRow(
                    icon: Icons.call_rounded,
                    label: 'Answered',
                    value: DateFormat('h:mm a').format(acceptedAt),
                  ),
                if (endedAt != null)
                  _DetailRow(
                    icon: Icons.call_end_rounded,
                    label: 'Ended',
                    value: DateFormat('h:mm a').format(endedAt),
                  ),
                _DetailRow(
                  icon: Icons.timer_rounded,
                  label: 'Duration',
                  value: duration > 0 ? _formatDuration(duration) : '—',
                ),
                const SizedBox(height: 28),

                // Call back button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon:
                        Icon(video ? Icons.videocam_rounded : Icons.phone_rounded),
                    label: Text(video ? 'Video call back' : 'Call back'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      onCallBack(call, name, avatar);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _name(Map<String, dynamic> p) {
    final full = p['full_name'] as String?;
    if (full != null && full.isNotEmpty) return full;
    return (p['username'] as String?) ?? 'Unknown';
  }

  static String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h h $m m $s s' : '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.outgoing});

  final String status;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      'completed' => ('Completed', Colors.green, Icons.check_circle_rounded),
      'declined' => ('Declined', Colors.red, Icons.cancel_rounded),
      'not_picked' => ('Not picked up', Colors.orange, Icons.phone_missed_rounded),
      'active' => ('Active', Colors.blue, Icons.call_rounded),
      _ => ('Missed', Colors.red, Icons.phone_missed_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Detail row ────────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.45),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: valueColor ??
                    (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
