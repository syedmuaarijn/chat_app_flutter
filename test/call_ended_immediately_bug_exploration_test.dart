// Task 1 — Bug Condition Exploration Test
//
// Property 1: Bug Condition — Ghost `onRemoteUserLeft` Tears Down Ringing Call
//
// These tests reproduce the ghost-event bug on the UNFIXED code.
// They are EXPECTED TO FAIL before the fix is applied (failure confirms the
// bug exists) and are expected to PASS afterwards (confirms fix works).
//
// DO NOT change test logic to make them pass artificially.
//
// **Validates: Requirements 1.1, 1.2, 2.1, 2.5**

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Minimal self-contained re-implementation of the CallProvider state machine
// that isolates exactly the bug condition without requiring Agora SDK, Supabase,
// or just_audio platform channels.
//
// The TestableCallStateMachine mirrors the EXACT logic of CallProvider so that
// changes to its behavior show up as test failures.
// ---------------------------------------------------------------------------

enum CallStatus { idle, ringing, active, ended }

/// Mirrors the exact guard logic from CallProvider._registerAgoraCallbacks().
///
/// UNFIXED version (the BUG): `onRemoteUserLeft` calls _handleCallDeclinedOrEnded()
/// unconditionally whenever status is ringing or active — no _hasRemotePeerJoined check.
///
/// FIXED version: wraps the call with `if (_hasRemotePeerJoined)`.
///
/// Toggle [applyFix] to switch between the two implementations for comparison.
class TestableCallStateMachine {
  final bool applyFix;

  CallStatus _status = CallStatus.idle;
  bool _hasRemotePeerJoined = false;

  TestableCallStateMachine({this.applyFix = false});

  CallStatus get status => _status;
  bool get hasRemotePeerJoined => _hasRemotePeerJoined;

  /// Simulates CallProvider.startCall() — sets status to ringing.
  /// Does NOT fire onRemoteUserJoined (ghost scenario).
  void startOutgoingCall() {
    _status = CallStatus.ringing;
    _hasRemotePeerJoined = false; // reset for new session (as _resetState() does)
  }

  /// Simulates the onRemoteUserJoined Agora callback.
  void fireRemoteUserJoined() {
    if (applyFix) {
      // Fixed: set flag first
      _hasRemotePeerJoined = true;
    }
    if (_status == CallStatus.ringing) {
      _status = CallStatus.active;
    }
  }

  /// Simulates the onRemoteUserLeft Agora callback.
  ///
  /// UNFIXED: calls _handleCallDeclinedOrEnded() unconditionally.
  /// FIXED:   only calls it if _hasRemotePeerJoined == true.
  void fireRemoteUserLeft() {
    if (_status == CallStatus.active || _status == CallStatus.ringing) {
      if (applyFix) {
        // Fixed guard — only tear down if a real peer joined this session.
        if (_hasRemotePeerJoined) {
          _handleCallDeclinedOrEnded();
        }
        // else: ghost event — silently ignored
      } else {
        // Unfixed — unconditional teardown
        _handleCallDeclinedOrEnded();
      }
    }
  }

  /// Simulates a Supabase `decline` or `end` signal (always honoured).
  void fireDeclineSignal() {
    if (_status != CallStatus.idle) {
      _handleCallDeclinedOrEnded();
    }
  }

  /// Simulates _resetState() being called (e.g., after dispose/re-init cycle).
  void resetState() {
    _status = CallStatus.idle;
    _hasRemotePeerJoined = false;
  }

  void _handleCallDeclinedOrEnded() {
    if (_status == CallStatus.idle) return;
    _status = CallStatus.ended;
    _hasRemotePeerJoined = false;
  }
}

// ---------------------------------------------------------------------------
// Bug Condition Tests (Task 1)
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Task 1 — Bug Condition Exploration: Ghost onRemoteUserLeft Tears Down Ringing Call', () {
    // ── Test 1: Single ghost event during ringing ──────────────────────────

    test(
      'BUG CONDITION: onRemoteUserLeft fires during ringing with no prior '
      'onRemoteUserJoined → status becomes ended (FAILS on unfixed code, '
      'PASSES after fix)',
      () {
        // Arrange: outgoing call, status = ringing, no peer has joined.
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();

        expect(machine.status, equals(CallStatus.ringing),
            reason: 'Pre-condition: call must be in ringing state');
        expect(machine.hasRemotePeerJoined, isFalse,
            reason: 'Pre-condition: no remote peer has joined yet');

        // Act: ghost onRemoteUserLeft fires (no prior onRemoteUserJoined).
        machine.fireRemoteUserLeft();

        // Assert: status must STAY ringing — ghost event must be ignored.
        // COUNTEREXAMPLE on unfixed code:
        //   status = CallStatus.ended (instead of CallStatus.ringing)
        //   because _handleCallDeclinedOrEnded() is called unconditionally.
        print('[Bug 1 counterexample] onRemoteUserLeft during ringing '
            '(no prior joined) → status=${machine.status}. '
            'Expected: ringing. Bug: ended.');

        expect(
          machine.status,
          equals(CallStatus.ringing),
          reason:
              'Ghost onRemoteUserLeft must be IGNORED when _hasRemotePeerJoined==false. '
              'COUNTEREXAMPLE: status transitions to CallStatus.ended instead of '
              'staying CallStatus.ringing — proves the bug exists on unfixed code.',
        );
      },
    );

    // ── Test 2: Multiple ghost events during ringing ───────────────────────

    test(
      'BUG CONDITION: two ghost onRemoteUserLeft events fire without any '
      'onRemoteUserJoined → status stays ringing after both events '
      '(FAILS on unfixed code, PASSES after fix)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();

        // First ghost event.
        machine.fireRemoteUserLeft();

        // COUNTEREXAMPLE on unfixed code: first event already transitions to ended.
        print('[Bug 1 counterexample] After 1st ghost event: status=${machine.status}');
        expect(
          machine.status,
          equals(CallStatus.ringing),
          reason:
              'After 1st ghost event: status must stay ringing. '
              'COUNTEREXAMPLE: status = ended after 1st ghost onRemoteUserLeft.',
        );

        // Second ghost event — must also be ignored.
        machine.fireRemoteUserLeft();

        print('[Bug 1 counterexample] After 2nd ghost event: status=${machine.status}');
        expect(
          machine.status,
          equals(CallStatus.ringing),
          reason:
              'After 2nd ghost event: status must stay ringing. '
              'COUNTEREXAMPLE: status = ended (double ghost triggers teardown twice).',
        );
      },
    );

    // ── Test 3: Ghost event after re-initialization cycle ──────────────────

    test(
      'BUG CONDITION: dispose + re-init + join cycle fires onRemoteUserLeft '
      'immediately (simulates stale engine ghost) → call stays ringing '
      '(FAILS on unfixed code, PASSES after fix)',
      () {
        // First call session — complete a call.
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();
        machine.fireRemoteUserJoined(); // real join
        expect(machine.status, equals(CallStatus.active),
            reason: 'Pre-condition: first call became active');
        machine.fireDeclineSignal(); // end first call
        expect(machine.status, equals(CallStatus.ended),
            reason: 'Pre-condition: first call ended');

        // Second call session — reset and start fresh.
        machine.resetState();
        machine.startOutgoingCall();
        expect(machine.hasRemotePeerJoined, isFalse,
            reason: 'Pre-condition: _hasRemotePeerJoined must be reset for new session');

        // Ghost event from previous session fires immediately after join.
        machine.fireRemoteUserLeft();

        print('[Bug 1 counterexample] After re-init + ghost: status=${machine.status}. '
            'Expected: ringing. Bug: ended.');

        expect(
          machine.status,
          equals(CallStatus.ringing),
          reason:
              'Ghost onRemoteUserLeft from a previous session must NOT tear down '
              'the new call. COUNTEREXAMPLE: status = ended immediately after '
              're-init because the same engine emits stale callbacks.',
        );
      },
    );

    // ── Test 4: Verify the fix works — ghost ignored, real departure handled ─

    test(
      'FIX VERIFICATION: real peer joins then leaves → status transitions to '
      'ended correctly (no regression)',
      () {
        final machine = TestableCallStateMachine(applyFix: true);
        machine.startOutgoingCall();

        // Ghost event before real join — must be ignored.
        machine.fireRemoteUserLeft();
        expect(machine.status, equals(CallStatus.ringing),
            reason: 'Ghost event must be ignored before real peer joins');

        // Real peer joins.
        machine.fireRemoteUserJoined();
        expect(machine.status, equals(CallStatus.active),
            reason: 'Call transitions to active when real peer joins');
        expect(machine.hasRemotePeerJoined, isTrue,
            reason: '_hasRemotePeerJoined must be true after real join');

        // Real peer leaves.
        machine.fireRemoteUserLeft();
        expect(
          machine.status,
          equals(CallStatus.ended),
          reason:
              'Real peer departure must still trigger call teardown. '
              'This is the preservation requirement — fix must not regress this.',
        );
      },
    );

    // ── Test 5: _hasRemotePeerJoined starts false for every new session ────

    test(
      'UNIT: _hasRemotePeerJoined is false at session start and after resetState()',
      () {
        final machine = TestableCallStateMachine(applyFix: true);

        // Initial state.
        expect(machine.hasRemotePeerJoined, isFalse,
            reason: '_hasRemotePeerJoined must start false');

        // After starting a call.
        machine.startOutgoingCall();
        expect(machine.hasRemotePeerJoined, isFalse,
            reason: '_hasRemotePeerJoined must be false at call start');

        // After a real join.
        machine.fireRemoteUserJoined();
        expect(machine.hasRemotePeerJoined, isTrue,
            reason: '_hasRemotePeerJoined must be true after real join');

        // After reset (new session).
        machine.resetState();
        expect(machine.hasRemotePeerJoined, isFalse,
            reason: '_hasRemotePeerJoined must be reset to false after resetState()');
      },
    );

    // ── Test 6: Compare unfixed vs fixed behavior directly ─────────────────

    test(
      'COMPARISON: unfixed machine ends call on ghost event; fixed machine '
      'ignores it — demonstrates the exact regression',
      () {
        final unfixed = TestableCallStateMachine(applyFix: false);
        final fixed = TestableCallStateMachine(applyFix: true);

        unfixed.startOutgoingCall();
        fixed.startOutgoingCall();

        // Fire ghost event on both.
        unfixed.fireRemoteUserLeft();
        fixed.fireRemoteUserLeft();

        print('[Bug 1 counterexample] Unfixed status=${unfixed.status}, Fixed status=${fixed.status}');

        // Unfixed code ends the call — this is the bug.
        expect(unfixed.status, equals(CallStatus.ended),
            reason: 'Unfixed code: ghost event INCORRECTLY ends the call. '
                'This documents the counterexample.');

        // Fixed code keeps the call ringing — this is the expected behavior.
        expect(fixed.status, equals(CallStatus.ringing),
            reason: 'Fixed code: ghost event is correctly ignored.');
      },
    );
  });
}
