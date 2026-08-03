# Bugfix Requirements Document

## Introduction

When caller A initiates a call to recipient B, the caller immediately sees a "call ended" screen and B never receives the incoming call. The regression is caused by stale Agora `onUserOffline` events (ghost events from a previous call session) firing against the newly joined channel while the call is still in the `ringing` state. Because `onRemoteUserLeft` is wired to `_handleCallDeclinedOrEnded()` unconditionally for both `ringing` and `active` states, a single ghost event is enough to tear down the outgoing call before B ever sees the invite. A secondary vector is a stale `end` or `decline` signal in Supabase that passes the session-ID filter and triggers the same teardown path during ringing.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the caller joins the Agora channel in the `ringing` state AND a stale `onUserOffline` (ghost) event fires from a previous call session THEN the system immediately calls `_handleCallDeclinedOrEnded()` and transitions to `ended` state before the recipient has a chance to receive or accept the call.

1.2 WHEN the caller is in the `ringing` state AND any `onRemoteUserLeft` callback fires (regardless of whether a real remote peer ever joined the current session) THEN the system treats it as a deliberate hang-up and ends the call.

1.3 WHEN a stale `end` or `decline` Supabase signal arrives that matches the current session ID THEN the system calls `_handleCallDeclinedOrEnded()` even while the call is in the `ringing` state on the caller side.

1.4 WHEN `_handleCallDeclinedOrEnded()` runs and `_resetState()` is called THEN `_currentCallSessionId` is set to `null`, but the Agora engine is not fully disposed, leaving residual engine state that can emit further ghost callbacks in the next call.

### Expected Behavior (Correct)

2.1 WHEN the caller is in the `ringing` state AND an `onRemoteUserLeft` (or `onUserOffline`) Agora event fires THEN the system SHALL ignore the event because no remote peer has yet joined the current call session, and the call SHALL remain in the `ringing` state.

2.2 WHEN the caller is in the `active` state AND `onRemoteUserLeft` fires THEN the system SHALL treat it as the remote peer hanging up and SHALL call `_handleCallDeclinedOrEnded()` to end the call.

2.3 WHEN a `decline` or `end` Supabase signal arrives while the caller is in the `ringing` state AND the signal session ID matches the current session THEN the system SHALL end the call (this is a deliberate decline/cancel from the remote side and must still be honoured).

2.4 WHEN `_handleCallDeclinedOrEnded()` runs THEN the system SHALL fully dispose the Agora engine (not just leave the channel) so that no ghost callbacks can propagate into the next call session.

2.5 WHEN the `onRemoteUserLeft` guard is applied THEN the system SHALL only act on the event if a remote peer was previously confirmed to have joined the current session (i.e., `onRemoteUserJoined` was received at least once for this session).

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a live call is `active` AND the remote peer genuinely leaves or drops the Agora channel THEN the system SHALL CONTINUE TO call `_handleCallDeclinedOrEnded()` and transition to the `ended` state.

3.2 WHEN recipient B explicitly declines an incoming invite THEN the system SHALL CONTINUE TO send a `decline` signal and the caller's call SHALL CONTINUE TO end correctly.

3.3 WHEN either party taps "End Call" during an `active` call THEN the system SHALL CONTINUE TO send an `end` signal and both sides SHALL CONTINUE TO transition to `ended` state.

3.4 WHEN the Agora token is about to expire mid-call THEN the system SHALL CONTINUE TO renew the token without interrupting the call.

3.5 WHEN an incoming invite is older than 15 seconds THEN the system SHALL CONTINUE TO ignore it as a stale invite.

3.6 WHEN a Supabase signal arrives with a session ID that does not match `_currentCallSessionId` THEN the system SHALL CONTINUE TO ignore it.

3.7 WHEN the incoming call timeout (30 seconds) elapses without the recipient answering THEN the system SHALL CONTINUE TO auto-decline and end the call locally.
