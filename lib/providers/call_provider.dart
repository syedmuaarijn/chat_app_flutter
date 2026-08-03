import 'dart:async';
import 'package:chat_app_flutter/services/agora_call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum CallStatus { idle, ringing, active, ended }

class CallProvider with ChangeNotifier {
  final AgoraCallService _agoraService = AgoraCallService.instance;

  CallStatus _status = CallStatus.idle;
  String? _conversationId;
  String? _currentCallSessionId;
  String? _remoteUserId;
  String? _remoteUserName;
  String? _remoteUserAvatarUrl;
  bool _isMicMuted = false;
  bool _isSpeakerphone = false;
  bool _hasRemotePeerJoined = false;
  bool _isIncoming = false;
  String? _lastError;
  int _callDurationSeconds = 0;
  Timer? _callDurationTimer;
  Timer? _incomingCallTimeoutTimer;
  Timer? _endedAutoClearTimer;

  // Realtime subscription
  RealtimeChannel? _callSignalChannel;

  // Supabase signal identifier. It keeps the conversation ID for routing and
  // the per-call session ID for stale-signal protection.
  String? get _signalConversationId =>
      (_conversationId != null && _currentCallSessionId != null)
      ? '$_conversationId:$_currentCallSessionId'
      : null;

  // Agora channel IDs are limited to 64 bytes. A pair of UUIDs joined with a
  // colon is 73 bytes and Agora rejects it with error -102. The session UUID
  // is already unique for every call, so it is sufficient as the RTC channel.
  String? get _agoraChannelName => _currentCallSessionId == null
      ? null
      : 'call_$_currentCallSessionId';

  Timer? _ringtoneTimer;

  // Navigator key — injected from main.dart so provider can navigate
  GlobalKey<NavigatorState>? navigatorKey;

  // ── Getters ──────────────────────────────────────────────────────────────────
  CallStatus get status => _status;
  String? get conversationId => _conversationId;
  String? get remoteUserId => _remoteUserId;
  String? get remoteUserName => _remoteUserName;
  String? get remoteUserAvatarUrl => _remoteUserAvatarUrl;
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerphone => _isSpeakerphone;
  bool get isIncoming => _isIncoming;
  int get callDurationSeconds => _callDurationSeconds;
  String? get lastError => _lastError;

  String get formattedDuration {
    final m = _callDurationSeconds ~/ 60;
    final s = _callDurationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get isActive => _status == CallStatus.active;
  bool get isRinging => _status == CallStatus.ringing;
  bool get isIdle => _status == CallStatus.idle;
  bool get isEnded => _status == CallStatus.ended;

  // ── Outgoing call ─────────────────────────────────────────────────────────
  Future<bool> startCall({
    required String conversationId,
    required String remoteUserId,
    required String remoteUserName,
    required String remoteUserAvatarUrl,
  }) async {
    if (_status != CallStatus.idle) {
      debugPrint('CallProvider: startCall ignored — already in a call');
      return false;
    }

    _conversationId = conversationId;
    _currentCallSessionId = const Uuid()
        .v4(); // Generate unique session ID for this call
    _remoteUserId = remoteUserId;
    _remoteUserName = remoteUserName;
    _remoteUserAvatarUrl = remoteUserAvatarUrl;
    _isIncoming = false;
    _isMicMuted = false;
    _isSpeakerphone = false;
    _callDurationSeconds = 0;
    _lastError = null;
    _status = CallStatus.ringing;
    notifyListeners();

    var inviteSent = false;
    try {
      // The invitation is the source of truth for the incoming-call UI. Send
      // it before joining Agora so an RTC/token failure cannot make the call
      // silently disappear before the recipient is notified.
      await _agoraService.invite(_signalConversationId!, remoteUserId);
      inviteSent = true;

      // Initialize Agora & register callbacks before joining.
      await _agoraService.initialize();
      _registerAgoraCallbacks();

      // Play outgoing ringing tone (fire and forget, do not await)
      _playRingtone(outgoing: true);

      // Caller joins channel so audio is ready when recipient accepts
      await _agoraService.joinChannel(_agoraChannelName!);
      return true;
    } catch (e) {
      debugPrint('CallProvider: startCall error: $e');
      _lastError = _callFailureMessage(e);

      // If the recipient has already been invited, dismiss their incoming
      // screen as well. Do not leave a call ringing that the caller could not
      // start.
      if (inviteSent) {
        try {
          await _agoraService.endCall(_signalConversationId!, remoteUserId);
        } catch (signalError) {
          debugPrint('CallProvider: failed to cancel invite: $signalError');
        }
      }
      await _doLocalEnd();
      return false;
    }
  }

  // ── Accept incoming call ───────────────────────────────────────────────────
  Future<void> acceptCall() async {
    if (_status != CallStatus.ringing || !_isIncoming) return;

    _stopRingtone();
    _incomingCallTimeoutTimer?.cancel();

    _isMicMuted = false;
    _isSpeakerphone = false;
    _callDurationSeconds = 0;
    // Do NOT set active here — timer starts when Agora confirms remote user joined
    _status = CallStatus.active;
    notifyListeners();

    try {
      await _agoraService.initialize();
      _registerAgoraCallbacks();
      await _agoraService.joinChannel(_agoraChannelName!);

      // Notify caller that we accepted
      await _agoraService.accept(_signalConversationId!, _remoteUserId!);

      // Start timer immediately (caller may already be in channel)
      _startDurationTimer();
    } catch (e) {
      debugPrint('CallProvider: acceptCall error: $e');
      await _doLocalEnd();
    }
  }

  // ── Decline incoming call ──────────────────────────────────────────────────
  Future<void> declineCall() async {
    if (_status != CallStatus.ringing || !_isIncoming) return;

    _stopRingtone();
    _incomingCallTimeoutTimer?.cancel();

    try {
      await _agoraService.decline(_signalConversationId!, _remoteUserId!);
    } catch (e) {
      debugPrint('CallProvider: declineCall signal error: $e');
    }

    await _doLocalEnd(popNav: true);
  }

  // ── End call ───────────────────────────────────────────────────────────────
  Future<void> endCall() async {
    if (_status == CallStatus.idle || _status == CallStatus.ended) return;

    _stopRingtone();
    _stopDurationTimer();
    _incomingCallTimeoutTimer?.cancel();

    final signalConversationId = _signalConversationId;
    final remoteId = _remoteUserId;

    if (signalConversationId != null && remoteId != null) {
      try {
        await _agoraService.endCall(signalConversationId, remoteId);
      } catch (e) {
        debugPrint('CallProvider: endCall signal error: $e');
      }
    }

    await _doLocalEnd(popNav: true);
  }

  // ── Audio controls ─────────────────────────────────────────────────────────
  Future<void> toggleMute() async {
    _isMicMuted = !_isMicMuted;
    await _agoraService.muteMic(_isMicMuted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerphone = !_isSpeakerphone;
    await _agoraService.toggleSpeaker(_isSpeakerphone);
    notifyListeners();
  }

  // ── Duration timer ─────────────────────────────────────────────────────────
  void _startDurationTimer() {
    _stopDurationTimer();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  void _stopDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
  }

  // ── Incoming call timeout ──────────────────────────────────────────────────
  void startIncomingCallTimeout() {
    _incomingCallTimeoutTimer?.cancel();
    _incomingCallTimeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (_status == CallStatus.ringing && _isIncoming) {
        _stopRingtone();
        await _doLocalEnd(popNav: true);
      }
    });
  }

  // ── Signal listener ────────────────────────────────────────────────────────
  void listenToCallSignals() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Unsubscribe from any existing channel
    if (_callSignalChannel != null) {
      Supabase.instance.client.removeChannel(_callSignalChannel!);
      _callSignalChannel = null;
    }

    _callSignalChannel = Supabase.instance.client.channel(
      'call-signals-$currentUserId',
    );

    _callSignalChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'receiver_id',
        value: currentUserId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        final rawConversationId = newRecord['conversation_id'] as String? ?? '';
        final signalType = newRecord['signal_type'] as String? ?? '';
        final callerId = newRecord['caller_id'] as String? ?? '';
        final createdAtStr = newRecord['created_at'] as String? ?? '';

        final parts = rawConversationId.split(':');
        final conversationId = parts[0];
        final sessionId = parts.length > 1 ? parts[1] : '';

        DateTime? createdAt;
        if (createdAtStr.isNotEmpty) {
          try {
            createdAt = DateTime.parse(createdAtStr).toLocal();
          } catch (e) {
            debugPrint('CallProvider: error parsing signal timestamp: $e');
          }
        }

        final now = DateTime.now();
        debugPrint(
          'CallProvider: received signal=$signalType from=$callerId at=$createdAt (now=$now) conv=$conversationId session=$sessionId',
        );

        // 1. Stale Invite Filtering (ignore if invite is older than 15 seconds)
        if (signalType == 'invite') {
          if (createdAt != null && now.difference(createdAt).inSeconds > 15) {
            debugPrint(
              'CallProvider: ignoring stale incoming invite (older than 15s)',
            );
            return;
          }
          // Set active session ID for incoming call
          _currentCallSessionId = sessionId;
        } else {
          // 2. Session ID Match Check (ignore signals not belonging to the active call session)
          if (_currentCallSessionId == null ||
              sessionId != _currentCallSessionId) {
            debugPrint(
              'CallProvider: ignoring stale signal=$signalType because session ID mismatch (expected=$_currentCallSessionId, got=$sessionId)',
            );
            return;
          }
        }

        switch (signalType) {
          case 'invite':
            _handleIncomingInvite(conversationId, callerId);
            break;
          case 'accept':
            _handleCallAccepted();
            break;
          case 'decline':
            _handleCallDeclinedOrEnded();
            break;
          case 'end':
            _handleCallDeclinedOrEnded();
            break;
        }
      },
    );

    _callSignalChannel!.subscribe((status, error) {
      debugPrint('CallProvider: call signals channel status=$status');
      if (error != null) debugPrint('CallProvider: call signals error=$error');
    });
  }

  void stopListeningToCallSignals() {
    if (_callSignalChannel != null) {
      Supabase.instance.client.removeChannel(_callSignalChannel!);
      _callSignalChannel = null;
    }
  }

  // ── Signal handlers ────────────────────────────────────────────────────────
  void _handleIncomingInvite(String conversationId, String callerId) async {
    // Ignore if already in a call
    if (_status != CallStatus.idle) {
      debugPrint(
        'CallProvider: ignoring invite — already in a call (status=$_status)',
      );
      return;
    }

    try {
      final userData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', callerId)
          .single();

      // Check if call was ended while fetching user data
      if (_status != CallStatus.idle) {
        debugPrint(
          'CallProvider: invite aborted — status changed to $_status during profile fetch',
        );
        return;
      }

      _conversationId = conversationId;
      _remoteUserId = callerId;
      _remoteUserName = (userData['full_name'] as String?)?.isNotEmpty == true
          ? userData['full_name'] as String
          : (userData['username'] as String? ?? 'Unknown');
      _remoteUserAvatarUrl = userData['avatar_url'] as String? ?? '';
      _isIncoming = true;
      _isMicMuted = false;
      _isSpeakerphone = false;
      _callDurationSeconds = 0;
      _status = CallStatus.ringing;
      notifyListeners();

      // Start ringtone (fire and forget)
      _playRingtone(outgoing: false);

      // Start auto-decline timeout
      startIncomingCallTimeout();

      // Navigate to incoming call screen
      navigatorKey?.currentState?.pushNamed('/incoming-call');
    } catch (e) {
      debugPrint('CallProvider: error handling invite: $e');
      _resetState();
      _status = CallStatus.idle;
      notifyListeners();
    }
  }

  void _handleCallAccepted() {
    if (_status != CallStatus.ringing || _isIncoming) return;
    // Caller: recipient accepted — stop ringtone, start timer, go active
    _stopRingtone();
    _status = CallStatus.active;
    _startDurationTimer();
    notifyListeners();
    debugPrint('CallProvider: call accepted — now active');
  }

  void _handleCallDeclinedOrEnded() async {
    if (_status == CallStatus.idle) return;
    _stopRingtone();
    _stopDurationTimer();
    _incomingCallTimeoutTimer?.cancel();

    await _agoraService.dispose();
    _resetState();
    _status = CallStatus.ended;
    notifyListeners();

    // Auto-pop after brief delay so user sees "Call Ended"
    _endedAutoClearTimer?.cancel();
    _endedAutoClearTimer = Timer(const Duration(seconds: 2), () {
      if (_status == CallStatus.ended) {
        // Pop the call screen if still open
        navigatorKey?.currentState?.popUntil(
          (route) => route.isFirst || route.settings.name == '/home',
        );
        _status = CallStatus.idle;
        notifyListeners();
      }
    });
  }

  // ── Agora callback registration ────────────────────────────────────────────
  void _registerAgoraCallbacks() {
    _agoraService.onRemoteUserJoined = (uid) {
      debugPrint('CallProvider: remote user joined Agora uid=$uid');
      _hasRemotePeerJoined = true;
      if (_status == CallStatus.ringing && !_isIncoming) {
        // Caller: recipient joined the channel
        _stopRingtone();
        _status = CallStatus.active;
        _startDurationTimer();
        notifyListeners();
      } else if (_status == CallStatus.active) {
        // Recipient: confirm active, ensure timer is running
        if (_callDurationTimer == null) {
          _startDurationTimer();
        }
      }
    };

    _agoraService.onRemoteUserLeft = (uid) {
      debugPrint('CallProvider: remote user left Agora uid=$uid');
      if (_status == CallStatus.active || _status == CallStatus.ringing) {
        if (_hasRemotePeerJoined) {
          _handleCallDeclinedOrEnded();
        } else {
          debugPrint(
            'CallProvider: ignoring ghost onRemoteUserLeft — no real peer joined this session (uid=$uid)',
          );
        }
      }
    };

    _agoraService.onJoinSuccess = () {
      debugPrint('CallProvider: ✅ local user confirmed joined Agora channel');
    };

    _agoraService.onAgoraError = (err, msg) {
      debugPrint('CallProvider: ❌ Agora error $err: $msg');
    };

    _agoraService.onTokenWillExpire = () {
      debugPrint('CallProvider: ⚠️ Agora token expiring — renewing...');
      _renewToken();
    };
  }

  /// Renews the Agora token when it is about to expire mid-call.
  Future<void> _renewToken() async {
    final channelName = _agoraChannelName;
    if (channelName == null) return;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'generate-agora-token',
        body: {'channelName': channelName, 'uid': 0},
      );
      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>;
        final newToken = data['token'] as String? ?? '';
        if (newToken.isNotEmpty) {
          await AgoraCallService.instance.renewToken(newToken);
          debugPrint('CallProvider: token renewed successfully');
        }
      }
    } catch (e) {
      debugPrint('CallProvider: token renewal failed: $e');
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────
  Future<void> _doLocalEnd({bool popNav = false}) async {
    _stopDurationTimer();
    _incomingCallTimeoutTimer?.cancel();
    _endedAutoClearTimer?.cancel();

    await _agoraService.dispose();
    _resetState();
    _status = CallStatus.ended;
    notifyListeners();

    _endedAutoClearTimer = Timer(const Duration(seconds: 2), () {
      if (_status == CallStatus.ended) {
        if (popNav) {
          navigatorKey?.currentState?.popUntil(
            (route) => route.isFirst || route.settings.name == '/home',
          );
        }
        _status = CallStatus.idle;
        notifyListeners();
      }
    });
  }

  void _resetState() {
    _conversationId = null;
    _currentCallSessionId = null;
    _remoteUserId = null;
    _remoteUserName = null;
    _remoteUserAvatarUrl = null;
    _isMicMuted = false;
    _isSpeakerphone = false;
    _hasRemotePeerJoined = false;
    _isIncoming = false;
    _callDurationSeconds = 0;
  }

  String _callFailureMessage(Object error) {
    final message = error.toString();
    if (message.contains('Microphone permission')) {
      return 'Microphone permission is required to start a call.';
    }
    if (message.contains('token')) {
      return 'Could not connect to the call service. Please try again.';
    }
    if (message.contains('call_signals') || message.contains('permission')) {
      return 'Could not notify the recipient. Please try again.';
    }
    return 'Could not start the call. Please try again.';
  }

  // ── Ringtone ───────────────────────────────────────────────────────────────
  Future<void> _playRingtone({required bool outgoing}) async {
    _stopRingtone();

    // A system alert is reliable on both platforms. The previous remote MP3
    // URLs started returning HTTP 403 and produced noisy ExoPlayer errors.
    void playAlert() {
      if (_status == CallStatus.ringing) {
        SystemSound.play(SystemSoundType.alert);
      } else {
        _stopRingtone();
      }
    }

    playAlert();
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      playAlert();
    });
  }

  void _stopRingtone() {
    _ringtoneTimer?.cancel();
    _ringtoneTimer = null;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────
  void clearCallState() {
    _stopDurationTimer();
    _stopRingtone();
    _incomingCallTimeoutTimer?.cancel();
    _endedAutoClearTimer?.cancel();
    _resetState();
    _status = CallStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopDurationTimer();
    _stopRingtone();
    _incomingCallTimeoutTimer?.cancel();
    _endedAutoClearTimer?.cancel();
    stopListeningToCallSignals();
    super.dispose();
  }
}
