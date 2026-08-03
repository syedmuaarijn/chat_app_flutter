# Call Ended Immediately Fix — Bugfix Design

## Overview

When the caller joins the Agora channel during the `ringing` state, the Agora engine can fire a stale `onUserOffline` (ghost) event left over from a previous call session. Because `onRemoteUserLeft` is wired unconditionally to `_handleCallDeclinedOrEnded()` for both `ringing` and `active` states, this single ghost event immediately tears down the outgoing call before the recipient ever sees the invite.

The fix introduces a `_hasRemotePeerJoined` guard flag in `CallProvider`. The flag is set to `true` only when `onRemoteUserJoined` fires for the current session, and the `onRemoteUserLeft` handler only calls `_handleCallDeclinedOrEnded()` when that flag is `true`. Ghost events (arriving when no remote peer has ever joined the session) are logged and ignored.

A secondary improvement is replacing `leaveChannel()` with a full `dispose()` + re-`initialize()` cycle at the end of each call so residual engine state — the source of ghost events — is fully cleared before the next session starts.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the premature teardown — an `onRemoteUserLeft` event fires while no real remote peer has joined the current call session (`_hasRemotePeerJoined == false`).
- **Property (P)**: The desired behavior when the bug condition holds — the event is silently ignored and the call remains in its current state.
- **Preservation**: All other call flows (active-call teardown, deliberate decline, end-call, token renewal, stale-signal filtering) must continue to work exactly as before.
- **CallProvider**: The Flutter `ChangeNotifier` in `lib/providers/call_provider.dart` that owns call state and wires Agora callbacks.
- **AgoraCallService**: The singleton in `lib/services/agora_call_service.dart` that wraps the Agora RTC engine.
- **_hasRemotePeerJoined**: The new boolean flag in `CallProvider`; `false` at session start, set to `true` when `onRemoteUserJoined` fires.
- **Ghost event**: An `onUserOffline` callback emitted by the Agora engine for a UID that was never part of the current session, typically left over from a previous engine lifecycle.
- **_initialized**: The boolean in `AgoraCallService` that gates `initialize()`. Must be reset to `false` by `dispose()` so the engine can be re-created for the next call.

## Bug Details

### Bug Condition

The bug manifests when the caller joins the Agora channel in the `ringing` state and the Agora engine emits a stale `onUserOffline` event from a previous session. The `onRemoteUserLeft` callback in `CallProvider._registerAgoraCallbacks()` fires `_handleCallDeclinedOrEnded()` for both `ringing` and `active` states without checking whether a real remote peer ever joined the current session.

**Formal Specification:**
```
FUNCTION isBugCondition(state, event)
  INPUT:  state — current CallStatus (ringing | active | idle | ended)
          event — Agora callback type (remoteUserLeft | other)
  OUTPUT: boolean

  RETURN event == remoteUserLeft
         AND (state == ringing OR state == active)
         AND _hasRemotePeerJoined == false
END FUNCTION
```

### Examples

- **Ghost event during ringing**: Caller joins channel; Agora emits `onUserOffline` for a UID from the previous session. `_hasRemotePeerJoined` is `false`. Expected: event ignored, call stays `ringing`. Actual (before fix): call immediately transitions to `ended`.
- **Real departure during active call**: Both parties are connected (`_hasRemotePeerJoined == true`); remote peer drops. Expected: `_handleCallDeclinedOrEnded()` called, call ends. Actual: same — this must continue to work.
- **Recipient declines**: `_isIncoming == false`, caller receives `decline` Supabase signal. Expected: `_handleCallDeclinedOrEnded()` called. Actual: same — this must continue to work.
- **Multiple ghost events**: Engine fires two stale `onUserOffline` events. Expected: both ignored, no double-teardown. Actual (before fix): first event tears down call, second hits `idle` guard and is ignored; but the first event already caused the bug.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- When a live call is `active` and the remote peer genuinely leaves or drops the Agora channel, the system must still call `_handleCallDeclinedOrEnded()` and transition to `ended`.
- When recipient B explicitly declines an incoming invite, the caller's call must still end correctly via the `decline` Supabase signal path.
- When either party taps "End Call", both sides must transition to `ended` as before.
- Token renewal mid-call must continue to work without interruption.
- Stale invite filtering (>15 s) and session-ID mismatch filtering must continue to work.
- The 30-second incoming-call auto-decline timeout must continue to fire correctly.

**Scope:**
All code paths that do NOT involve `onRemoteUserLeft` firing while `_hasRemotePeerJoined == false` must be completely unaffected by this fix. This includes:
- All Supabase signal handling (`invite`, `accept`, `decline`, `end`)
- Mouse/tap interaction with the call UI
- `onRemoteUserJoined` itself (it only sets the flag — no behavior change there)
- Audio mute / speaker toggle
- Duration timer logic

## Hypothesized Root Cause

Based on the bug description and code review:

1. **Unconditional `onRemoteUserLeft` handler**: `_registerAgoraCallbacks()` wires `onRemoteUserLeft` to call `_handleCallDeclinedOrEnded()` whenever status is `ringing` or `active` — with no check that a real peer ever joined the current session. A ghost event during `ringing` satisfies this condition.

2. **Engine not fully disposed between sessions**: `_doLocalEnd()` and `_handleCallDeclinedOrEnded()` both call `_agoraService.leaveChannel()` but do not destroy the engine. The next `initialize()` call returns early (`if (_initialized) return;`) so the same engine instance (with its event queue) is reused, carrying ghost callbacks forward.

3. **`_initialized` flag not reset by `leaveChannel()`**: `leaveChannel()` resets `_isJoinedChannel` and `_currentChannelName` but leaves `_initialized = true`. When `initialize()` is called for the next session it short-circuits, meaning the old engine state persists.

4. **No per-session remote-peer tracking**: There is no boolean that distinguishes "a remote peer has joined *this* session" from "the engine reported a peer departure from a stale context".

## Correctness Properties

Property 1: Bug Condition — Ghost `onRemoteUserLeft` Events Are Ignored During Ringing

_For any_ Agora `onRemoteUserLeft` event that fires while `_hasRemotePeerJoined == false` (i.e., no real remote peer has joined the current session), the fixed `_registerAgoraCallbacks` SHALL ignore the event, log a diagnostic message, and leave the call state unchanged.

**Validates: Requirements 2.1, 2.5**

Property 2: Preservation — Active-Call Teardown Still Works

_For any_ Agora `onRemoteUserLeft` event that fires while `_hasRemotePeerJoined == true` (i.e., a real remote peer previously joined the current session and has now left), the fixed handler SHALL call `_handleCallDeclinedOrEnded()` exactly as before, preserving live call teardown behavior.

**Validates: Requirements 2.2, 3.1**

Property 3: Preservation — Engine Fully Cleared Between Sessions

_For any_ call session that ends (via `_doLocalEnd()` or `_handleCallDeclinedOrEnded()`), the fixed code SHALL dispose the Agora engine and reset `_initialized` to `false`, ensuring no ghost callbacks from the ended session can affect the next session.

**Validates: Requirements 2.4, 3.1, 3.3**

## Fix Implementation

### Changes Required

**File**: `lib/providers/call_provider.dart`

**Change 1 — Add `_hasRemotePeerJoined` flag**

Add a private boolean field to `CallProvider`:

```dart
bool _hasRemotePeerJoined = false;
```

**Change 2 — Reset flag in `_resetState()`**

In `_resetState()`, add:

```dart
_hasRemotePeerJoined = false;
```

This guarantees the flag is `false` at the start of every new call session.

**Change 3 — Set flag in `onRemoteUserJoined` callback**

In `_registerAgoraCallbacks()`, inside the `onRemoteUserJoined` handler, add:

```dart
_hasRemotePeerJoined = true;
```

This marks the current session as having had a real remote peer.

**Change 4 — Guard `onRemoteUserLeft` with the flag**

Replace the unconditional call in the `onRemoteUserLeft` handler:

```dart
// Before:
_agoraService.onRemoteUserLeft = (uid) {
  debugPrint('CallProvider: remote user left Agora uid=$uid');
  if (_status == CallStatus.active || _status == CallStatus.ringing) {
    _handleCallDeclinedOrEnded();
  }
};

// After:
_agoraService.onRemoteUserLeft = (uid) {
  debugPrint('CallProvider: remote user left Agora uid=$uid');
  if (_status == CallStatus.active || _status == CallStatus.ringing) {
    if (_hasRemotePeerJoined) {
      _handleCallDeclinedOrEnded();
    } else {
      debugPrint('CallProvider: ignoring ghost onRemoteUserLeft — no real peer joined this session (uid=$uid)');
    }
  }
};
```

**Change 5 — Dispose engine in `_doLocalEnd()` and `_handleCallDeclinedOrEnded()`**

Replace `await _agoraService.leaveChannel()` with `await _agoraService.dispose()` in both methods. This fully releases the engine between sessions.

---

**File**: `lib/services/agora_call_service.dart`

**Change 6 — Allow re-initialization after `dispose()`**

`dispose()` already sets `_initialized = false`, so `initialize()` will recreate the engine on the next call. No code change needed here — this is a confirmation that the existing `dispose()` implementation is sufficient once `CallProvider` starts calling it.

Verify `dispose()` correctly resets `_initialized`:

```dart
Future<void> dispose() async {
  _clearCallbacks();
  await leaveChannel();
  if (_engine != null) {
    await _engine!.release();
    _engine = null;
  }
  _initialized = false;   // ← already present; confirms re-init works
  _isJoinedChannel = false;
  _currentChannelName = null;
  debugPrint('AgoraCallService: disposed');
}
```

No changes needed in `AgoraCallService` — the existing `dispose()` already resets `_initialized`.

### Summary of All Diffs

| Location | Change |
|---|---|
| `CallProvider` — field | Add `bool _hasRemotePeerJoined = false;` |
| `CallProvider._resetState()` | Add `_hasRemotePeerJoined = false;` |
| `CallProvider._registerAgoraCallbacks()` — `onRemoteUserJoined` | Add `_hasRemotePeerJoined = true;` |
| `CallProvider._registerAgoraCallbacks()` — `onRemoteUserLeft` | Wrap `_handleCallDeclinedOrEnded()` with `if (_hasRemotePeerJoined)` guard |
| `CallProvider._doLocalEnd()` | Replace `leaveChannel()` with `dispose()` |
| `CallProvider._handleCallDeclinedOrEnded()` | Replace `leaveChannel()` with `dispose()` |

## Testing Strategy

### Validation Approach

Testing follows a two-phase approach: first run exploratory tests against the **unfixed** code to surface counterexamples and confirm the root cause, then run fix-checking and preservation tests against the **fixed** code.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis.

**Test Plan**: Simulate the Agora ghost-event scenario by directly invoking the `onRemoteUserLeft` callback on a `CallProvider` that is in the `ringing` state (before any `onRemoteUserJoined` has fired) and assert that the call status changes — which should fail on unfixed code (it will change to `ended` rather than staying `ringing`).

**Test Cases**:

1. **Ghost event during ringing (outgoing)**: Create a `CallProvider`, set status to `ringing`, do NOT fire `onRemoteUserJoined`, then fire `onRemoteUserLeft`. Assert status is still `ringing`. *(Will fail on unfixed code — status becomes `ended`.)*
2. **Multiple ghost events**: Fire `onRemoteUserLeft` twice without `onRemoteUserJoined`. Assert status is still `ringing` after both events. *(Will fail on unfixed code.)*
3. **Re-initialization after dispose**: Call `dispose()` on `AgoraCallService`, then call `initialize()` again. Assert that the engine is re-created (`_initialized == true`). *(Should pass — verifying the service supports re-init.)*
4. **Ghost event from previous session**: Simulate dispose + re-init + join, then fire `onRemoteUserLeft` immediately. Assert call stays `ringing`. *(Will fail on unfixed code.)*

**Expected Counterexamples**:
- On unfixed code: `_status` transitions to `CallStatus.ended` after a ghost `onRemoteUserLeft` during ringing, even though `_hasRemotePeerJoined` would be `false`.
- Root cause confirmed: the unconditional handler in `_registerAgoraCallbacks()`.

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior (ghost event is ignored).

**Pseudocode:**
```
FOR ALL (state, event) WHERE isBugCondition(state, event) DO
  provider.simulateEvent(event)
  ASSERT provider.status == UNCHANGED  // ringing stays ringing
  ASSERT provider.status != ended
END FOR
```

**Test Cases**:
1. Fire `onRemoteUserLeft` while `ringing`, `_hasRemotePeerJoined == false` → status stays `ringing`.
2. Fire `onRemoteUserLeft` while `active`, `_hasRemotePeerJoined == false` → status stays `active`. *(Edge case: active without a prior joined event shouldn't happen in practice but must be safe.)*

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function behaves identically to the original.

**Pseudocode:**
```
FOR ALL (state, event) WHERE NOT isBugCondition(state, event) DO
  ASSERT fixedHandler(state, event) == originalHandler(state, event)
END FOR
```

**Testing Approach**: Property-based testing generates many state/event combinations to verify no regressions. The test oracle is the original behavior for non-ghost scenarios.

**Test Cases**:
1. **Real peer departure (active)**: Fire `onRemoteUserJoined` then `onRemoteUserLeft` while `active`. Status must transition to `ended`. *(Preservation of requirement 3.1.)*
2. **Decline signal (ringing)**: Receive `decline` Supabase signal while `ringing`. Status must transition to `ended`. *(Preservation of requirement 3.2.)*
3. **End signal (active)**: Receive `end` Supabase signal while `active`. Status must transition to `ended`. *(Preservation of requirement 3.3.)*
4. **Token renewal**: Fire `onTokenWillExpire` during active call. Token renewal completes without status change. *(Preservation of requirement 3.4.)*
5. **Stale invite filter**: Receive invite older than 15 s. Status stays `idle`. *(Preservation of requirement 3.5.)*
6. **Session ID mismatch**: Receive any signal with wrong session ID. Status unchanged. *(Preservation of requirement 3.6.)*
7. **Incoming timeout**: 30-second timer fires without answer. Status transitions to `ended`. *(Preservation of requirement 3.7.)*

### Unit Tests

- Test that `_hasRemotePeerJoined` starts as `false` for a fresh `CallProvider`.
- Test that `_hasRemotePeerJoined` is set to `true` when `onRemoteUserJoined` fires.
- Test that `_hasRemotePeerJoined` is reset to `false` after `_resetState()`.
- Test that `onRemoteUserLeft` during `ringing` with `_hasRemotePeerJoined == false` does NOT call `_handleCallDeclinedOrEnded()`.
- Test that `onRemoteUserLeft` during `active` with `_hasRemotePeerJoined == true` DOES call `_handleCallDeclinedOrEnded()`.
- Test that `_doLocalEnd()` calls `_agoraService.dispose()` (not just `leaveChannel()`).
- Test that `AgoraCallService.dispose()` resets `_initialized` to `false`, allowing `initialize()` to run again.

### Property-Based Tests

- Generate random sequences of Agora events (joined/left interleaved) and verify that `_handleCallDeclinedOrEnded()` is only reached when `onRemoteUserJoined` has fired at least once in the sequence.
- Generate random call sessions (start → ghost events → real join → real leave) and verify that the call ends only after the real leave, not the ghost events.
- Generate random non-ghost event sequences and verify that the fixed code produces the same status transitions as the original code (preservation property).

### Integration Tests

- Full call flow: caller starts call, ghost event fires, recipient accepts, both parties active, one hangs up — verify clean end.
- Re-call after ended call: complete one call, dispose engine, start a new call immediately — verify no ghost events from the first session affect the second.
- Decline flow end-to-end: caller starts call, recipient declines — verify both sides reach `ended` without ghost-event interference.
