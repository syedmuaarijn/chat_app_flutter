import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import '../config/supabase_config.dart';

enum CallMode { audio, video }

class AgoraCallService {
  AgoraCallService._internal();
  static final AgoraCallService instance = AgoraCallService._internal();

  RtcEngine? _engine;
  bool _initialized = false;
  bool _isJoinedChannel = false;
  String? _currentChannelName;

  bool get isInitialized => _initialized;
  bool get isJoinedChannel => _isJoinedChannel;
  String? get currentChannelName => _currentChannelName;
  RtcEngine? get engine => _engine;

  // ── Callbacks registered by CallProvider ───────────────────────────────────
  /// Called when the remote peer joins the Agora channel.
  void Function(int uid)? onRemoteUserJoined;

  /// Called when the remote peer leaves or drops from the channel.
  void Function(int uid)? onRemoteUserLeft;

  /// Called when the local user successfully joins the channel.
  void Function()? onJoinSuccess;

  /// Called on any Agora engine error.
  void Function(ErrorCodeType err, String msg)? onAgoraError;

  /// Called when the token is about to expire — host should renew.
  void Function()? onTokenWillExpire;
  void Function(bool paused)? onRemoteVideoPaused;

  // ── Engine lifecycle ────────────────────────────────────────────────────────
  Future<void> initialize({required CallMode mode}) async {
    if (_initialized) return;
    if (SupabaseConfig.agoraAppId.isEmpty) {
      throw Exception('AgoraCallService: agoraAppId is empty.');
    }
    try {
      // 1. Request Runtime Permissions FIRST (Android & iOS real device)
      if (!kIsWeb) {
        if (Platform.isAndroid || Platform.isIOS) {
          final permissions = <Permission>[Permission.microphone];
          if (mode == CallMode.video) permissions.add(Permission.camera);
          if (Platform.isAndroid) permissions.add(Permission.bluetoothConnect);
          await permissions.request();

          final micStatus = await Permission.microphone.status;
          if (!micStatus.isGranted) {
            debugPrint('AgoraCallService: Microphone permission DENIED!');
            throw Exception(
              'Microphone permission is required for voice call.',
            );
          }
          if (mode == CallMode.video &&
              !(await Permission.camera.status).isGranted) {
            throw Exception('Camera permission is required for video call.');
          }
          debugPrint('AgoraCallService: Microphone permission granted');
        }
      }

      // 2. Create engine
      _engine = createAgoraRtcEngine();

      // 3. Initialize with app ID
      await _engine!.initialize(
        RtcEngineContext(
          appId: SupabaseConfig.agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // 4. Enable audio BEFORE setting up callbacks or joining
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);

      // 5. Set audio profile for voice call
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // 6. Default audio route to earpiece (user can toggle to speaker via button)
      await _engine!.setDefaultAudioRouteToSpeakerphone(false);

      if (mode == CallMode.video) {
        await _engine!.enableVideo();
        await _engine!.enableLocalVideo(true);
        await _engine!.startPreview();
      }

      // 7. Register event handlers AFTER enabling audio
      _setupEngineCallbacks();

      _initialized = true;
      debugPrint('AgoraCallService: initialized successfully');
    } catch (e) {
      debugPrint('AgoraCallService: initialize failed: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    _clearCallbacks();
    await leaveChannel();
    if (_engine != null) {
      await _engine!.release();
      _engine = null;
    }
    _initialized = false;
    _isJoinedChannel = false;
    _currentChannelName = null;
    debugPrint('AgoraCallService: disposed');
  }

  // ── Token fetching ──────────────────────────────────────────────────────────
  /// Fetches a signed Agora token from the Supabase Edge Function.
  /// [channelName] — the Agora channel (= conversation ID)
  /// Returns the token string.
  Future<String> _fetchToken({
    required String channelName,
    required String conversationId,
    required String sessionId,
    required CallMode mode,
  }) async {
    debugPrint('AgoraCallService: fetching token for channel=$channelName');
    final response = await Supabase.instance.client.functions.invoke(
      'generate-agora-token',
      body: {
        'channelName': channelName,
        'conversationId': conversationId,
        'sessionId': sessionId,
        'callType': mode.name,
        'uid': 0, // 0 = let Agora auto-assign, token covers any uid
      },
    );

    if (response.status != 200) {
      throw Exception(
        'AgoraCallService: token fetch failed — '
        'status=${response.status} data=${response.data}',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('AgoraCallService: received empty token from server');
    }

    debugPrint('AgoraCallService: token fetched successfully');
    return token;
  }

  // ── Agora channel ───────────────────────────────────────────────────────────
  /// Joins the Agora channel.
  /// [channelName] is the conversation ID (shared between caller and recipient).
  Future<void> joinChannel({
    required String channelName,
    required String conversationId,
    required String sessionId,
    required CallMode mode,
  }) async {
    if (_engine == null || !_initialized) {
      throw Exception(
        'AgoraCallService: engine not initialized. Call initialize() first.',
      );
    }
    if (_isJoinedChannel && _currentChannelName == channelName) {
      debugPrint('AgoraCallService: already in channel $channelName');
      return;
    }

    // Fetch a server-signed token (required when App Certificate is enabled)
    final token = await _fetchToken(
      channelName: channelName,
      conversationId: conversationId,
      sessionId: sessionId,
      mode: mode,
    );

    debugPrint(
      'AgoraCallService: joining channel=$channelName uid=0 (auto-assigned)',
    );

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0, // 0 = Agora auto-assigns a unique UID — no collision possible
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        publishCameraTrack: mode == CallMode.video,
        autoSubscribeVideo: mode == CallMode.video,
      ),
    );

    // Note: _isJoinedChannel is set to true inside onJoinChannelSuccess callback,
    // not here, to reflect the actual Agora confirmed state.
    _currentChannelName = channelName;
  }

  Future<void> leaveChannel() async {
    _isJoinedChannel = false;
    _currentChannelName = null;
    if (_engine != null) {
      await _engine!.leaveChannel();
      debugPrint('AgoraCallService: leaveChannel() called');
    }
  }

  /// Renews the Agora token mid-call (called when token is about to expire).
  Future<void> renewToken(String newToken) async {
    if (_engine == null || !_isJoinedChannel) return;
    await _engine!.renewToken(newToken);
    debugPrint('AgoraCallService: token renewed');
  }

  // ── Audio controls ──────────────────────────────────────────────────────────
  Future<void> muteMic(bool muted) async {
    if (_engine == null) return;
    await _engine!.muteLocalAudioStream(muted);
    debugPrint('AgoraCallService: mic muted=$muted');
  }

  Future<void> toggleSpeaker(bool speakerphone) async {
    if (_engine == null) return;
    await _engine!.setEnableSpeakerphone(speakerphone);
    debugPrint('AgoraCallService: speakerphone=$speakerphone');
  }

  Future<void> muteCamera(bool muted) async {
    if (_engine == null) return;
    await _engine!.muteLocalVideoStream(muted);
  }

  Future<void> switchCamera() async {
    if (_engine == null) return;
    await _engine!.switchCamera();
  }

  // ── Signaling methods (Supabase) ────────────────────────────────────────────
  Future<void> invite(
    String conversationId,
    String receiverId,
    CallMode mode,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    await _insertCallSignal(
      conversationId: conversationId,
      callerId: currentUserId,
      receiverId: receiverId,
      signalType: 'invite',
      mode: mode,
    );
  }

  Future<void> accept(
    String conversationId,
    String callerId,
    CallMode mode,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    await _insertCallSignal(
      conversationId: conversationId,
      callerId: currentUserId,
      receiverId: callerId,
      signalType: 'accept',
      mode: mode,
    );
  }

  Future<void> decline(
    String conversationId,
    String callerId,
    CallMode mode,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    await _insertCallSignal(
      conversationId: conversationId,
      callerId: currentUserId,
      receiverId: callerId,
      signalType: 'decline',
      mode: mode,
    );
  }

  Future<void> endCall(
    String conversationId,
    String remoteUserId,
    CallMode mode,
  ) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    await _insertCallSignal(
      conversationId: conversationId,
      callerId: currentUserId,
      receiverId: remoteUserId,
      signalType: 'end',
      mode: mode,
    );
  }

  Future<void> _insertCallSignal({
    required String conversationId,
    required String callerId,
    required String receiverId,
    required String signalType,
    required CallMode mode,
  }) async {
    try {
      await Supabase.instance.client.from('call_signals').insert({
        'conversation_id': conversationId,
        'caller_id': callerId,
        'receiver_id': receiverId,
        'signal_type': signalType,
        'call_type': mode.name,
      });
      debugPrint('AgoraCallService: signal=$signalType sent');
    } catch (e) {
      debugPrint(
        'AgoraCallService: insert call signal ($signalType) failed: $e',
      );
      rethrow;
    }
  }

  // ── Engine callbacks ────────────────────────────────────────────────────────
  void _setupEngineCallbacks() {
    _engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, uid) {
          debugPrint(
            'Agora: ✅ joined channel=${connection.channelId} myUid=$uid',
          );
          _isJoinedChannel =
              true; // Set join state only after confirmed by Agora
          onJoinSuccess?.call();
        },
        onUserJoined: (connection, uid, elapsed) {
          debugPrint('Agora: remote user joined uid=$uid');
          onRemoteUserJoined?.call(uid);
        },
        onUserOffline: (connection, uid, reason) {
          debugPrint('Agora: remote user offline uid=$uid reason=$reason');
          onRemoteUserLeft?.call(uid);
        },
        onRemoteVideoStateChanged: (connection, uid, state, reason, elapsed) {
          if (reason ==
              RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
            onRemoteVideoPaused?.call(true);
          } else if (reason ==
                  RemoteVideoStateReason.remoteVideoStateReasonRemoteUnmuted ||
              state == RemoteVideoState.remoteVideoStateDecoding) {
            onRemoteVideoPaused?.call(false);
          }
        },
        onError: (err, msg) {
          debugPrint('Agora ❌ error: code=$err msg=$msg');
          onAgoraError?.call(err, msg);
        },
        onLeaveChannel: (connection, stats) {
          debugPrint('Agora: left channel cleanly');
          _isJoinedChannel = false;
          _currentChannelName = null;
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          debugPrint('Agora: ⚠️ token will expire — renewal needed');
          onTokenWillExpire?.call();
        },
        onRequestToken: (connection) {
          debugPrint('Agora: token expired — renewal required!');
          onTokenWillExpire?.call();
        },
      ),
    );
  }

  void _clearCallbacks() {
    onRemoteUserJoined = null;
    onRemoteUserLeft = null;
    onJoinSuccess = null;
    onAgoraError = null;
    onTokenWillExpire = null;
    onRemoteVideoPaused = null;
  }
}
