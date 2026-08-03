# Audio Calling Module — Implementation Plan

## Overview

Add real-time audio calling to the chat app using Agora RTC SDK. The calling flow
is entirely peer-to-peer via Agora's SD-RTN; Supabase is used only for signaling
(call initiation, ringing, accept/decline, end-of-call events).

## Why Agora

- Free tier: 10,000 participant-minutes/month, no cost for early-stage usage
- Voice-only SDK is the cheapest tier ($0.99/1k min on pay-as-you-go)
- Flutter SDK `agora_rtc_engine` is mature (v6.6+) and published on pub.dev
- Sub-400ms latency, global edge network, built-in echo cancellation/noise suppression
- Signaling is trivial to implement with Supabase Realtime (already in the stack)

## 1. Dependencies

Add to `pubspec.yaml` dependencies:

```yaml
agora_rtc_engine: ^6.6.3
```

## 2. File Structure

```
lib/
  services/
    agora_call_service.dart      ← Agora engine wrapper + call lifecycle
  providers/
    call_provider.dart           ← Call state management (ChangeNotifier)
  widgets/
    calling/
      call_screen.dart           ← Full-screen active call UI
      incoming_call_dialog.dart  ← Overlay when a call is ringing
  screens/
    call_screen.dart             ← (alias re-export or route target)
```

## 3. Agora Service Layer (`lib/services/agora_call_service.dart`)

### Responsibilities
- Initialize the Agora engine with app ID
- Join/leave a channel (1-to-1, channel name = conversationId)
- Manage mic/camera toggles (audio only for v1)
- Handle Agora engine callbacks (join success, leave, remote user joined/left, errors)
- Generate ephemeral tokens from Supabase Edge Function (or use Agora's token-less mode for dev)

### Public API
```dart
class AgoraCallService {
  static final AgoraCallService _instance = AgoraCallService._internal();
  factory AgoraCallService() => _instance;

  // Engine lifecycle
  Future<void> initialize() async { ... }
  void dispose() async { ... }

  // Call signaling via Supabase (call invitations table)
  Future<void> invite(String conversationId, String callerId) async { ... }
  Future<void> accept(String conversationId, String callerId) async { ... }
  Future<void> decline(String conversationId, String callerId) async { ... }
  Future<void> endCall(String conversationId, String callerId) async { ... }

  // Agora channel
  Future<void> joinChannel(String channelName, String uid) async { ... }
  Future<void> leaveChannel() async { ... }

  // Audio controls
  Future<void> muteMic(bool muted) async { ... }
  Future<void> toggleSpeaker(bool speakerphone) async { ... }

  // Callbacks (registered by caller)
  Function(String callerId)? onIncomingCall;
  Function(String callerId)? onCallAccepted;
  Function(String callerId)? onCallDeclined;
  Function(String callerId)? onCallEnded;
  Function(String uid)? onRemoteUserJoined;
  Function(String uid)? onRemoteUserLeft;
}
```

### Key Details
- Use `agora_rtc_engine` v6.x `createAgoraRtcEngine()` + `initialize()` + `joinChannel()`
- App ID stored in `SupabaseConfig` or a separate env file
- For production, tokens should be generated server-side; for MVP, disable token
  authentication in the Agora console (enable "App Certificate" off or use temporary
  tokens from a Supabase Edge Function)
- Channel name = `conversationId` so the sender/receiver share the same Agora channel
- Only audio mode: `ChannelProfile.LiveBroadcasting`, `ClientRole.Broadcaster` (speaker)
  and `ClientRole.Audience` (receiver in a 1-to-1 call, though both can be Broadcasters)

## 4. Call Provider (`lib/providers/call_provider.dart`)

A `ChangeNotifier` that holds the single source of truth for call state:

```dart
enum CallStatus { idle, ringing, active, ended }

class CallProvider with ChangeNotifier {
  CallStatus _status = CallStatus.idle;
  String? _conversationId;
  String? _remoteUserId;
  String? _remoteUserName;
  bool _isMicMuted = false;
  bool _isSpeakerphone = false;
  bool _isIncoming = false;
  int _callDurationSeconds = 0;
  Timer? _callDurationTimer;

  CallStatus get status => _status;
  String? get conversationId => _conversationId;
  String? get remoteUserId => _remoteUserId;
  String? get remoteUserName => _remoteUserName;
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerphone => _isSpeakerphone;
  bool get isIncoming => _isIncoming;
  int get callDurationSeconds => _callDurationSeconds;
}
```

Key methods:
- `startCall(conversationId, remoteUserId, remoteUserName)` — sets status to ringing, shows incoming call dialog on the recipient side
- `acceptCall()` — joins Agora channel, sets status to active
- `declineCall()` — sets status to ended
- `endCall()` — leaves Agora channel, sets status to idle
- `toggleMute()` / `toggleSpeaker()` — audio controls
- `_startDurationTimer()` / `_stopDurationTimer()` — tracks call length

## 5. Incoming Call Dialog (`lib/widgets/calling/incoming_call_dialog.dart`)

A full-screen overlay (or Dialog) that shows when a call is incoming:
- Displays the caller's name and avatar (from `UserModel`)
- "Accept" button (green, phone icon) — calls `callProvider.acceptCall()`
- "Decline" button (red, phone hangup icon) — calls `callProvider.declineCall()`
- Auto-cancels after 30 seconds if no action
- Uses `AudioPlayer` (already in `just_audio` dependency) to play a ringtone tone

## 6. Active Call Screen (`lib/screens/call_screen.dart` and `lib/widgets/calling/call_screen.dart`)

Full-screen UI during an active call:
- Header with remote user's name, avatar
- Large center: circular avatar (remote user), pulsing ring animation when speaking
- Bottom control bar:
  - Mic mute/unmute toggle
  - Speakerphone on/off toggle
  - End call button (red, large)
  - Call duration timer display
- Back button exits the call (ends call)
- Uses `AgoraCallService` callbacks to detect remote user disconnect and auto-end

## 7. Integration Points

### 7a. Conversation Tile — Call Button
In `lib/widgets/home/conversation_tile.dart`, add a phone icon button in the
trailing area (visible only for 1-to-1 conversations, not groups):

```dart
// Add after the trailing column
if (!conv.isGroup && conv.otherUser != null)
  IconButton(
    icon: const Icon(Icons.phone_outlined, size: 22),
    tooltip: 'Call',
    onPressed: () => _startCall(context, conv),
  ),
```

The `_startCall` method navigates to the call screen or triggers the call provider.

### 7b. Chat Room Screen — Call Button
In `lib/screens/chat_room_screen.dart`, add a call icon button to the AppBar
actions (for 1-to-1 conversations):

```dart
// In AppBar actions, after the PopupMenuButton
if (!conv.isGroup && conv.otherUser != null)
  IconButton(
    icon: const Icon(Icons.phone_outlined),
    tooltip: 'Voice Call',
    onPressed: () => _startCall(context),
  ),
```

### 7c. Navigation
Create a named route `/call` in `main.dart` or push a MaterialPageRoute directly
from the call button. The call screen widget is a full-screen route.

### 7d. Supabase Real-time Subscriptions for Signaling
In `call_provider.dart`, subscribe to a Supabase Realtime channel for a
`calls` table (or use a generic `call_signals` table):

```sql
-- SQL to create in Supabase
CREATE TABLE call_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id TEXT NOT NULL,
  caller_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  signal_type TEXT NOT NULL,  -- 'invite', 'accept', 'decline', 'end'
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_call_signals_conversation ON call_signals(conversation_id);
```

Listen for new rows on the `call_signals` channel filtered by the current user's ID.
When an `invite` signal arrives, show the incoming call dialog.

## 8. Supabase Edge Function (Optional, for Token Generation)

For production, generate short-lived Agora tokens using a Supabase Edge Function:

```typescript
// supabase/functions/agora-token/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const { channelName, uid } = await req.json();
  // Use agora token builder to generate a temporary token
  // Return token to client
});
```

For MVP, skip this and use Agora's token-less mode (disable App Certificate).

## 9. Permissions

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
```

Add to `Info.plist` (iOS):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice calls</string>
```

The `permission_handler` package is already a dependency and is used in
`message_input_bar.dart` — reuse the same pattern.

## 10. Implementation Order

1. Add `agora_rtc_engine` dependency and `pubspec.yaml`
2. Create `AgoraCallService` — engine init, join/leave channel, audio controls
3. Create `CallProvider` — state management
4. Create `IncomingCallDialog` widget
5. Create `CallScreen` widget (active call UI)
6. Add `/call` route to `main.dart`
7. Integrate call button into `ConversationTile` and `ChatRoomScreen`
8. Add Supabase `call_signals` table and real-time subscription
9. Handle permissions with `permission_handler`
10. Test the full flow

## 11. Risks & Unknowns

- Agora token authentication: the free tier allows token-less mode for dev.
  For production, a token server (Supabase Edge Function) is required. This plan
  uses token-less for MVP.
- Background audio: on Android, the app needs a foreground service to keep audio
  alive when the screen is off. The `agora_rtc_engine` SDK handles this internally
  when properly initialized.
- iOS background audio: requires the `Audio` background mode capability in Xcode.
- WebRTC compatibility: Agora's SDK abstracts this away, but Web-based clients
  would need a different approach (this plan only covers Flutter mobile).
- Group calls: v1 scope is 1-to-1 only. Group calls require Agora's multi-user
  channel mode and would be a separate enhancement.