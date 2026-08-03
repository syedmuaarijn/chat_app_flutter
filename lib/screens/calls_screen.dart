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
    if (user == null) {
      return [];
    }
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
    if (ids.isEmpty) {
      return calls;
    }
    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id,full_name,username,avatar_url')
        .inFilter('id', ids);
    final byId = {
      for (final p in profiles as List)
        p['id'] as String: p as Map<String, dynamic>,
    };
    for (final call in calls) {
      final other = call['caller_id'] == user
          ? call['receiver_id']
          : call['caller_id'];
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
  Widget _tile(Map<String, dynamic> c) {
    final p = c['profile'] as Map<String, dynamic>? ?? {};
    final name = (p['full_name'] as String?)?.isNotEmpty == true
        ? p['full_name']
        : (p['username'] ?? 'Unknown');
    final video = c['call_type'] == 'video';
    final status = c['status'] as String;
    final outgoing = c['outgoing'] as bool;
    final time = DateFormat(
      'MMM d, h:mm a',
    ).format(DateTime.parse(c['started_at']).toLocal());
    final duration = c['duration_seconds'] as int? ?? 0;
    final direction = outgoing ? 'Outgoing' : 'Incoming';
    final detail = duration > 0
        ? Duration(seconds: duration).toString().substring(2, 7)
        : status;
    final subtitle = '$direction · $time · $detail';
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: (p['avatar_url'] as String?)?.isNotEmpty == true
            ? CachedNetworkImageProvider(p['avatar_url'])
            : null,
        child: (p['avatar_url'] as String?)?.isNotEmpty == true
            ? null
            : Text(name.toString()[0].toUpperCase()),
      ),
      title: Text(name),
      subtitle: Row(
        children: [
          Icon(
            outgoing ? Icons.call_made : Icons.call_received,
            size: 15,
            color: status == 'missed' || status == 'cancelled'
                ? Colors.red
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(subtitle, overflow: TextOverflow.ellipsis)),
        ],
      ),
      trailing: IconButton(
        icon: Icon(video ? Icons.videocam : Icons.phone),
        onPressed: () =>
            _call(c, name.toString(), p['avatar_url'] as String? ?? ''),
      ),
    );
  }

  Future<void> _call(Map<String, dynamic> c, String name, String avatar) async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    final remote = c['caller_id'] == user ? c['receiver_id'] : c['caller_id'];
    final ok = c['call_type'] == 'video'
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
      Navigator.pushNamed(
        context,
        c['call_type'] == 'video' ? '/video-call' : '/call',
      );
    }
  }
}
