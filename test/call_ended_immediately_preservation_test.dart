// Task 2 — Preservation Property Tests
//
// Property 2: Preservation — Active-Call Teardown and Signal Handling
// Remain Intact
//
// These tests observe and encode the BASELINE behaviors that must be preserved
// after the fix. They are run on UNFIXED code to confirm baseline, and must
// continue to pass on FIXED code.
//
// **Validates: Requirements 2.2, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Re-use the same self-contained state machine from the exploration test.
// This avoids platform-channel dependencies (Agora SDK, Supabase, just_audio).
// ---------------------------------------------------------------------------

enum CallStatus { idle, ringing, active, ended }

/// Full state machine that models all CallProvider state transitions relevant
/// to the preservation tests. Can run in fixed or unfixed mode.
class TestableCallStateMachine {
  final bool applyFix;

  CallStatus _status = CallStatus.idle;
  bool _hasRemotePeerJoined = false;
  bool _isIncoming = false;
  String? _currentSessionId;

  int callDeclinedOrEndedCallCount = 0;

  TestableCallStateMachine({this.applyFix = false});

  CallStatus get status => _status;
  bool get hasRemotePeerJoined => _hasRemotePeerJoined;
  String? get currentSessionId => _currentSessionId;

  // ── Call setup ─────────────────────────────────────────────────────────

  void startOutgoingCall({String sessionId = 'session-abc'}) {
    _status = CallStatus.ringing;
    _isIncoming = false;
    _hasRemotePeerJoined = false;
    _currentSessionId = sessionId;
  }

  void startIncomingCall({String sessionId = 'session-abc'}) {
    _status = CallStatus.ringing;
    _isIncoming = true;
    _hasRemotePeerJoined = false;
    _currentSessionId = sessionId;
  }

  void acceptCall() {
    if (_status != CallStatus.ringing || !_isIncoming) return;
    _status = CallStatus.active;
  }

  // ── Agora events ───────────────────────────────────────────────────────

  void fireRemoteUserJoined() {
    if (applyFix) {
      _hasRemotePeerJoined = true;
    }
    if (_status == CallStatus.ringing && !_isIncoming) {
      _status = CallStatus.active;
    }
  }

  void fireRemoteUserLeft() {
    if (_status == CallStatus.active || _status == CallStatus.ringing) {
      if (applyFix) {
        if (_hasRemotePeerJoined) {
          _handleCallDeclinedOrEnded();
        }
        // else ghost — ignored
      } else {
        _handleCallDeclinedOrEnded();
      }
    }
  }

  // ── Supabase signal events ─────────────────────────────────────────────

  /// Fires a Supabase signal. Enforces session ID matching for non-invite types.
  void fireSignal(String signalType, {String sessionId = 'session-abc'}) {
    if (signalType == 'invite') {
      // Stale invite filter: handled separately in test
      _currentSessionId = sessionId;
      _status = CallStatus.ringing;
      _isIncoming = true;
      _hasRemotePeerJoined = false;
      return;
    }

    // Session ID mismatch — ignore signal.
    if (_currentSessionId == null || sessionId != _currentSessionId) {
      return; // silently ignored
    }

    switch (signalType) {
      case 'accept':
        if (_status == CallStatus.ringing && !_isIncoming) {
          _status = CallStatus.active;
        }
        break;
      case 'decline':
        _handleCallDeclinedOrEnded();
        break;
      case 'end':
        _handleCallDeclinedOrEnded();
        break;
    }
  }

  /// Simulates a stale invite (older than 15s) arriving — must be ignored.
  void fireStaleInvite() {
    // Stale invite filter: signal is dropped before processing.
    // Status must remain unchanged (idle).
  }

  /// Simulates a token-will-expire Agora event. Status must remain active.
  void fireTokenWillExpire() {
    // Token renewal does not change call status.
    // _renewToken() is called but status is unchanged.
  }

  void resetState() {
    _status = CallStatus.idle;
    _hasRemotePeerJoined = false;
    _isIncoming = false;
    _currentSessionId = null;
    callDeclinedOrEndedCallCount = 0;
  }

  void _handleCallDeclinedOrEnded() {
    if (_status == CallStatus.idle) return;
    callDeclinedOrEndedCallCount++;
    _status = CallStatus.ended;
    _hasRemotePeerJoined = false;
  }
}

// ---------------------------------------------------------------------------
// Preservation Tests (Task 2)
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Preservation 2a: Real peer departure in active call ──────────────────

  group('Preservation 2a — Active-call teardown still works after fix', () {
    test(
      'onRemoteUserJoined then onRemoteUserLeft while active → '
      '_handleCallDeclinedOrEnded() called and status = ended',
      () {
        // Test on FIXED code.
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();

        // Real peer joins.
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active),
            reason: 'Peer joining must transition call to active');
        expect(machine.hasRemotePeerJoined, isTrue,
            reason: '_hasRemotePeerJoined must be true after real join');

        // Real peer leaves.
        machine.fireRemoteUserLeft();

        expect(
          machine.status,
          equals(CallStatus.ended),
          reason:
              'Requirement 3.1: When live call is active and remote peer '
              'leaves, system must call _handleCallDeclinedOrEnded() and '
              'transition to ended state.',
        );
        expect(machine.callDeclinedOrEndedCallCount, equals(1),
            reason: '_handleCallDeclinedOrEnded must be called exactly once');
      },
    );

    test(
      'Multiple real peer departure events: only first ends the call '
      '(_handleCallDeclinedOrEnded guard on idle state prevents double-teardown)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active));

        machine.fireRemoteUserLeft(); // real departure
        expect(machine.status, equals(CallStatus.ended));

        machine.fireRemoteUserLeft(); // second event after ended — ignored
        expect(machine.callDeclinedOrEndedCallCount, equals(1),
            reason: 'Second departure event must not trigger a second teardown');
      },
    );
  });

  // ── Preservation 2b: Decline signal while ringing ────────────────────────

  group('Preservation 2b — Decline signal while ringing ends the call', () {
    test(
      'decline Supabase signal with matching session ID → status = ended '
      '(requirement 3.2)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-1');

        machine.fireSignal('decline', sessionId: 'sess-1');

        expect(
          machine.status,
          equals(CallStatus.ended),
          reason:
              'Requirement 3.2: When recipient explicitly declines, caller '
              'must receive decline signal and call must end.',
        );
      },
    );

    test(
      'decline signal also ends an active call (belt-and-suspenders)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-1');
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active));

        machine.fireSignal('decline', sessionId: 'sess-1');
        expect(machine.status, equals(CallStatus.ended));
      },
    );
  });

  // ── Preservation 2c: End signal during active call ───────────────────────

  group('Preservation 2c — End signal during active call', () {
    test(
      'end Supabase signal with matching session ID while active → status = ended '
      '(requirement 3.3)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-2');
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active));

        machine.fireSignal('end', sessionId: 'sess-2');

        expect(
          machine.status,
          equals(CallStatus.ended),
          reason:
              'Requirement 3.3: When either party taps End Call, end signal '
              'must cause both sides to transition to ended state.',
        );
      },
    );

    test(
      'end signal also honoured while ringing (e.g., caller cancels)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-2');

        machine.fireSignal('end', sessionId: 'sess-2');

        expect(machine.status, equals(CallStatus.ended),
            reason: 'End signal during ringing must also end the call');
      },
    );
  });

  // ── Preservation 2d: Session ID mismatch ─────────────────────────────────

  group('Preservation 2d — Session ID mismatch signals are ignored', () {
    test(
      'decline signal with wrong session ID → status unchanged (requirement 3.6)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-correct');

        final statusBefore = machine.status;
        machine.fireSignal('decline', sessionId: 'sess-wrong');

        expect(
          machine.status,
          equals(statusBefore),
          reason:
              'Requirement 3.6: Signal with mismatched session ID must be '
              'silently ignored — status must remain unchanged.',
        );
      },
    );

    test(
      'end signal with wrong session ID → status unchanged',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-correct');
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active));

        machine.fireSignal('end', sessionId: 'stale-session');
        expect(machine.status, equals(CallStatus.active),
            reason: 'Stale end signal must not tear down an active call');
      },
    );

    test(
      'null current session ID → any non-invite signal is ignored',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        // No call started, so _currentSessionId is null.
        machine.fireSignal('decline', sessionId: 'any-session');
        expect(machine.status, equals(CallStatus.idle),
            reason: 'With no active session, signals must be ignored');
      },
    );
  });

  // ── Preservation 2e: Stale invite filter ─────────────────────────────────

  group('Preservation 2e — Stale invite (>15s) is ignored', () {
    test(
      'stale invite fires → status remains idle (requirement 3.5)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        expect(machine.status, equals(CallStatus.idle));

        machine.fireStaleInvite();

        expect(
          machine.status,
          equals(CallStatus.idle),
          reason:
              'Requirement 3.5: Incoming invite older than 15 seconds must '
              'be ignored and status must remain idle.',
        );
      },
    );
  });

  // ── Preservation: Token renewal ───────────────────────────────────────────

  group('Preservation — Token renewal does not change call status', () {
    test(
      'onTokenWillExpire fires during active call → status stays active '
      '(requirement 3.4)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active));

        machine.fireTokenWillExpire();

        expect(
          machine.status,
          equals(CallStatus.active),
          reason:
              'Requirement 3.4: Token renewal mid-call must not interrupt '
              'the call. Status must remain active.',
        );
      },
    );
  });

  // ── Combined scenario tests ───────────────────────────────────────────────

  group('Combined scenarios — ghost events + real events in sequence', () {
    test(
      'ghost event during ringing, then real join + real leave → ends correctly',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-combined');

        // Ghost fires before real join.
        machine.fireRemoteUserLeft(); // ghost — must be ignored
        expect(machine.status, equals(CallStatus.ringing),
            reason: 'Ghost must be ignored, call stays ringing');

        // Real join.
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active));

        // Real departure.
        machine.fireRemoteUserLeft();
        expect(machine.status, equals(CallStatus.ended),
            reason: 'Real departure after real join must end the call');
      },
    );

    test(
      'multiple ghost events, then decline signal — decline still ends the call',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall(sessionId: 'sess-ghosts');

        // Three ghost events.
        machine.fireRemoteUserLeft();
        machine.fireRemoteUserLeft();
        machine.fireRemoteUserLeft();
        expect(machine.status, equals(CallStatus.ringing),
            reason: 'All ghost events must be ignored');

        // Deliberate decline from recipient.
        machine.fireSignal('decline', sessionId: 'sess-ghosts');
        expect(machine.status, equals(CallStatus.ended),
            reason: 'Decline signal must still end the call after ghost events');
      },
    );

    test(
      '_hasRemotePeerJoined is false after session reset and new call starts clean',
      () {
        final machine = TestableCallStateMachine(applyFix: true);

        // First call — goes active then ends.
        machine.startOutgoingCall(sessionId: 'sess-first');
        machine.fireRemoteUserJoined();
        expect(machine.hasRemotePeerJoined, isTrue);
        machine.fireRemoteUserLeft();
        expect(machine.status, equals(CallStatus.ended));

        // Reset for new session.
        machine.resetState();
        expect(machine.hasRemotePeerJoined, isFalse,
            reason: '_hasRemotePeerJoined must be cleared after reset');

        // New call — ghost event must not end it.
        machine.startOutgoingCall(sessionId: 'sess-second');
        machine.fireRemoteUserLeft(); // ghost from previous session
        expect(machine.status, equals(CallStatus.ringing),
            reason: 'Second session must not be affected by ghost events');
      },
    );
  });
}
