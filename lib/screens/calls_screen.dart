import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_app_flutter/providers/call_provider.dart';
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
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _calls,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('No calls yet'));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _calls = _load()),
            child: ListView.separated(
              itemCount: snapshot.data!.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _tile(snapshot.data![i]),
            ),
          );
        },
      );

  // ── List tile ──────────────────────────────────────────────────────────────
  Widget _tile(Map<String, dynamic> c) {
    final p = c['profile'] as Map<String, dynamic>? ?? {};
    final name = _displayName(p);
    final video = c['call_type'] == 'video';
    final status = c['status'] as String;
    final outgoing = c['outgoing'] as bool;
    final missed = status == 'not_picked' || status == 'declined';
    final time =
        DateFormat('MMM d, h:mm a').format(DateTime.parse(c['started_at']).toLocal());

    return ListTile(
      onTap: () => _showDetail(c),
      leading: CircleAvatar(
        backgroundImage: (p['avatar_url'] as String?)?.isNotEmpty == true
            ? CachedNetworkImageProvider(p['avatar_url'] as String)
            : null,
        child: (p['avatar_url'] as String?)?.isNotEmpty == true
            ? null
            : Text(name[0].toUpperCase()),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: missed ? Colors.red : null,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(
            outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
            size: 14,
            color: missed
                ? Colors.red
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$time  ·  ${_statusLabel(status, c['duration_seconds'] as int? ?? 0)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: missed ? Colors.red : null,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: video ? 'Video call' : 'Voice call',
        icon: Icon(video ? Icons.videocam_rounded : Icons.phone_rounded),
        onPressed: () =>
            _startCall(c, name, p['avatar_url'] as String? ?? ''),
      ),
    );
  }

  // ── Detail bottom sheet ────────────────────────────────────────────────────
  void _showDetail(Map<String, dynamic> c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CallDetailSheet(call: c, onCallBack: _startCall),
    );
  }

  // ── Start a new call from history ──────────────────────────────────────────
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

  // ── Helpers ────────────────────────────────────────────────────────────────
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
      'declined'   => 'Declined',
      'completed'  => 'Completed',
      'active'     => 'Active',
      'ringing'    => 'Ringing',
      _            => status,
    };
  }
}

// ── Call detail bottom sheet ───────────────────────────────────────────────────
class _CallDetailSheet extends StatelessWidget {
  const _CallDetailSheet({
    required this.call,
    required this.onCallBack,
  });

  final Map<String, dynamic> call;
  final Future<void> Function(Map<String, dynamic>, String, String) onCallBack;

  @override
  Widget build(BuildContext context) {
    final p = call['profile'] as Map<String, dynamic>? ?? {};
    final name = _name(p);
    final avatar = p['avatar_url'] as String? ?? '';
    final status = call['status'] as String;
    final outgoing = call['outgoing'] as bool;
    final video = call['call_type'] == 'video';
    final duration = call['duration_seconds'] as int? ?? 0;
    final missed = status == 'not_picked' || status == 'declined';

    final startedAt = DateTime.parse(call['started_at'] as String).toLocal();
    final acceptedAt = call['accepted_at'] != null
        ? DateTime.parse(call['accepted_at'] as String).toLocal()
        : null;
    final endedAt = call['ended_at'] != null
        ? DateTime.parse(call['ended_at'] as String).toLocal()
        : null;

    return Padding(
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
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Avatar + name
          CircleAvatar(
            radius: 36,
            backgroundImage: avatar.isNotEmpty
                ? CachedNetworkImageProvider(avatar)
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
            value: duration > 0
                ? _formatDuration(duration)
                : '—',
          ),
          const SizedBox(height: 28),

          // Call back button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: Icon(video ? Icons.videocam_rounded : Icons.phone_rounded),
              label: Text(video ? 'Video call back' : 'Call back'),
              onPressed: () {
                Navigator.pop(context);
                onCallBack(call, name, avatar);
              },
            ),
          ),
        ],
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

// ── Status badge ───────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.outgoing});

  final String status;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      'completed'  => ('Completed',    Colors.green,       Icons.check_circle_rounded),
      'declined'   => ('Declined',     Colors.red,         Icons.cancel_rounded),
      'not_picked' => ('Not picked up', Colors.orange,     Icons.phone_missed_rounded),
      'active'     => ('Active',        Colors.blue,       Icons.call_rounded),
      _            => ('Missed',        Colors.red,        Icons.phone_missed_rounded),
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

// ── Detail row ─────────────────────────────────────────────────────────────────
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
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
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
