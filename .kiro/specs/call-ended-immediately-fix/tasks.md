# Implementation Plan

- [ ] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Ghost `onRemoteUserLeft` Tears Down Ringing Call
  - **CRITICAL**: This test MUST FAIL on unfixed code — failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior — it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the ghost event causes premature teardown
  - **Scoped PBT Approach**: Scope the property to the concrete failing case — `onRemoteUserLeft` fires while status is `ringing` and `_hasRemotePeerJoined == false`
  - Create a `CallProvider` test harness with a mock `AgoraCallService`; set status to `ringing` (outgoing); do NOT fire `onRemoteUserJoined`; directly invoke the `onRemoteUserLeft` callback
  - Assert that `provider.status == CallStatus.ringing` (status must remain unchanged)
  - Also test: fire `onRemoteUserLeft` twice without any prior `onRemoteUserJoined` — assert status stays `ringing` after both events
  - Also test: simulate dispose + re-init + join cycle, fire `onRemoteUserLeft` immediately — assert call stays `ringing`
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS — status transitions to `CallStatus.ended` instead of staying `ringing` (this proves the bug exists)
  - Document the counterexample: e.g., `"onRemoteUserLeft fires during ringing → status becomes ended instead of staying ringing"`
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 2.1, 2.5_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Active-Call Teardown and Signal Handling Remain Intact
  - **IMPORTANT**: Follow observation-first methodology
  - Observe on UNFIXED code: `onRemoteUserJoined` fires then `onRemoteUserLeft` fires while `active` → status transitions to `ended` ✓
  - Observe on UNFIXED code: `decline` Supabase signal fires while `ringing` → status transitions to `ended` ✓
  - Observe on UNFIXED code: `end` Supabase signal fires while `active` → status transitions to `ended` ✓
  - Observe on UNFIXED code: `onTokenWillExpire` fires during active call → status stays `active`, renewal triggered ✓
  - Observe on UNFIXED code: signal with wrong session ID arrives → status unchanged ✓
  - Write property-based tests capturing these observed behaviors (for all non-ghost inputs, i.e., `_hasRemotePeerJoined == true` for Agora events or deliberate Supabase signals):
    - **Preservation 2a**: For any `onRemoteUserLeft` that fires after `onRemoteUserJoined` has already fired (`_hasRemotePeerJoined == true`) while status is `active` → `_handleCallDeclinedOrEnded()` must be called and status must become `ended`
    - **Preservation 2b**: For any `decline` Supabase signal matching the current session ID → status must become `ended` regardless of call state
    - **Preservation 2c**: For any `end` Supabase signal matching the current session ID → status must become `ended`
    - **Preservation 2d**: For any signal with mismatched session ID → status must remain unchanged
    - **Preservation 2e**: For any stale invite (>15 s) → status must remain `idle`
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 2.2, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [ ] 3. Fix for premature call teardown caused by ghost Agora `onRemoteUserLeft` events

  - [ ] 3.1 Add `_hasRemotePeerJoined` flag to `CallProvider`
    - In `lib/providers/call_provider.dart`, add the following field alongside the other private boolean fields (near `_isMicMuted`, `_isSpeakerphone`):
      ```dart
      bool _hasRemotePeerJoined = false;
      ```
    - _Bug_Condition: isBugCondition(state, event) where event == remoteUserLeft AND (state == ringing OR state == active) AND _hasRemotePeerJoined == false_
    - _Expected_Behavior: event is silently ignored; call status remains unchanged_
    - _Requirements: 2.1, 2.5_

  - [ ] 3.2 Reset `_hasRemotePeerJoined` in `_resetState()`
    - In `_resetState()`, add `_hasRemotePeerJoined = false;` alongside the other field resets
    - This ensures the flag is cleared at the start of every new call session
    - _Requirements: 2.1, 2.5_

  - [ ] 3.3 Set `_hasRemotePeerJoined = true` in `onRemoteUserJoined` callback
    - In `_registerAgoraCallbacks()`, inside the `onRemoteUserJoined` handler, add `_hasRemotePeerJoined = true;` as the first statement in the callback body
    - This marks the current session as having had a confirmed real remote peer join
    - _Requirements: 2.2, 2.5_

  - [ ] 3.4 Guard `onRemoteUserLeft` with `_hasRemotePeerJoined` check
    - In `_registerAgoraCallbacks()`, replace the unconditional `_handleCallDeclinedOrEnded()` call inside `onRemoteUserLeft` with an `if (_hasRemotePeerJoined)` guard:
      ```dart
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
    - _Bug_Condition: isBugCondition(state, event) — guard prevents teardown when flag is false_
    - _Expected_Behavior: ghost events are logged and ignored; only real peer departures trigger teardown_
    - _Preservation: when _hasRemotePeerJoined == true the path is identical to the original_
    - _Requirements: 2.1, 2.2, 2.5, 3.1_

  - [ ] 3.5 Replace `leaveChannel()` with `dispose()` in `_doLocalEnd()`
    - In `lib/providers/call_provider.dart`, in the `_doLocalEnd()` method, replace:
      ```dart
      await _agoraService.leaveChannel();
      ```
      with:
      ```dart
      await _agoraService.dispose();
      ```
    - This fully releases the Agora engine between sessions so residual ghost callbacks cannot propagate into the next session
    - _Expected_Behavior: _initialized is reset to false; next initialize() call recreates a clean engine_
    - _Requirements: 2.4, 3.1, 3.3_

  - [ ] 3.6 Replace `leaveChannel()` with `dispose()` in `_handleCallDeclinedOrEnded()`
    - In `lib/providers/call_provider.dart`, in the `_handleCallDeclinedOrEnded()` method, replace:
      ```dart
      await _agoraService.leaveChannel();
      ```
      with:
      ```dart
      await _agoraService.dispose();
      ```
    - Same rationale as 3.5 — ensures full engine teardown on every call-end path
    - _Bug_Condition: isBugCondition — leaveChannel() left _initialized = true, allowing ghost callbacks to carry forward_
    - _Expected_Behavior: dispose() sets _initialized = false; next session starts with a clean engine_
    - _Requirements: 2.4, 3.1, 3.3_

  - [ ] 3.7 Verify `AgoraCallService.dispose()` resets `_initialized` (read-only confirmation)
    - Open `lib/services/agora_call_service.dart` and confirm that `dispose()` already contains `_initialized = false;`
    - No code changes needed in this file — the existing implementation is correct
    - Document that `initialize()` will now re-create the engine fresh on the next call because `_initialized == false` after dispose
    - _Requirements: 2.4_

  - [ ] 3.8 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Ghost `onRemoteUserLeft` Is Ignored During Ringing
    - **IMPORTANT**: Re-run the SAME test from task 1 — do NOT write a new test
    - The test from task 1 encodes the expected behavior: ghost events must not change call status
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms the `_hasRemotePeerJoined` guard is working correctly)
    - _Requirements: 2.1, 2.5_

  - [ ] 3.9 Verify preservation tests still pass
    - **Property 2: Preservation** - Active-Call Teardown and Signal Handling Remain Intact
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run all preservation property tests from step 2
    - **EXPECTED OUTCOME**: All tests PASS (confirms no regressions in real peer departure, decline, end, token renewal, session ID filtering)
    - Confirm all preservation scenarios pass: active-call teardown (3.1), decline (3.2), end-call (3.3), stale invite filter (3.5), session ID mismatch (3.6)

- [ ] 4. Checkpoint — Ensure all tests pass
  - Run the full test suite: `flutter test`
  - Ensure task 1 exploration test passes (was failing before fix, now passes — bug confirmed fixed)
  - Ensure task 2 preservation tests still pass (no regressions)
  - Verify no new test failures were introduced by the six code changes
  - Ask the user if any questions arise about edge cases or additional scenarios to cover
