# Chat Realtime Bugs — Bugfix Design

## Overview

Three bugs combine to make the Flutter/Supabase chat app appear non-functional in normal two-party usage:

1. **Messages disappear on re-entry** — `ChatRoomScreen` never calls `clearMessages()` before re-subscribing, and the `.stream()` snapshot from `listenToMessages` replaces the profile-enriched list produced by `loadMessages`, stripping sender `username`/`avatar_url` fields.

2. **Receiver's home screen shows no conversations** — the two `conversation_participants` rows are inserted in a single batch, which can fail RLS for the second row; the `listenToConversations` stream watches the whole `conversations` table without a user filter; and `getConversations()` fires N×4 sequential DB queries in a loop.

3. **Cross-device real-time messages not delivered** — `.stream()` subscriptions require Realtime to be enabled on each table in the Supabase dashboard; the code also references `debugPrint` without importing `flutter/foundation.dart`.

The fix strategy is:
- Call `clearMessages()` first in `_initChat()`, then set up the stream, then load messages.
- Add a `Map<String, (String, String)>` profile cache in `ChatProvider`; populate it during `loadMessages`; use it to enrich stream snapshots so profile data is never lost.
- Split the batch `conversation_participants` insert into two sequential inserts.
- Replace the `conversations` global stream with a `conversation_participants`-filtered channel subscription.
- Replace the N×4 loop with batched queries (3–4 total round-trips).
- Add the missing `flutter/foundation.dart` import.

---

## Glossary

- **Bug_Condition (C)**: The predicate that identifies inputs/states that trigger a bug.
- **Property (P)**: The desired output or state that must hold when C is true after the fix is applied.
- **Preservation**: All behaviors that must remain identical for inputs where C is false.
- **`_initChat()`**: The method in `ChatRoomScreen` that sets up the real-time subscription and triggers the initial message load on every navigation to the screen.
- **`listenToMessages`**: The `.stream()` subscription in `ChatService` that emits a full sorted snapshot of `messages` rows from Supabase whenever the table changes. Does **not** join `profiles`.
- **`loadMessages`**: The one-shot `getMessages` query in `ChatProvider` that selects `messages.*` plus `profiles:sender_id(username, avatar_url)`, populating `senderUsername`/`senderAvatarUrl` on each `MessageModel`.
- **Profile cache**: A `Map<String, ({String username, String avatarUrl})>` held in `ChatProvider`, keyed by `senderId`, used to re-hydrate profile data onto messages that arrive from the stream without a profiles join.
- **`getOrCreateConversation`**: The method in `ChatService` that finds or creates a 1:1 conversation and inserts two `conversation_participants` rows.
- **RLS (Row Level Security)**: Supabase policy enforcement evaluated per row insert; a batch insert of two rows with different `user_id` values can fail if the policy's `NOT EXISTS` subquery is evaluated in an order that invalidates the first row's assumption for the second.
- **Channel subscription**: A Supabase `RealtimeChannel` created with `supabase.channel(name).onPostgresChanges(...)` — more explicit and filterable than `.stream()`, and does not require the table to have been configured via the `realtime` publication.

---

## Bug Details

### Bug 1 — Message Disappearance on Re-entry

The bug manifests when a user leaves and re-enters a `ChatRoomScreen`. `_initChat()` does not call `clearMessages()`, so `_messages` from the prior session persists. Simultaneously, the `.stream()` snapshot that arrives from `listenToMessages` replaces the entire `_messages` list with rows that lack `senderUsername`/`senderAvatarUrl` (because the stream query has no profiles join), overwriting the enriched list produced by `loadMessages`.

**Formal Specification:**
```
FUNCTION isBugCondition_1(X)
  INPUT: X = { event: NavigationEvent, conversationId: String, priorMessagesInMemory: bool }
  OUTPUT: boolean

  RETURN X.event = RE_ENTER_CONVERSATION
         AND (
           clearMessages_called_before_listenToMessages = false
           OR stream_snapshot_lacks_profile_data = true
         )
END FUNCTION
```

**Examples:**
- User opens conversation A (10 messages load with profile data), navigates back, reopens A → screen briefly shows stale messages from prior session, then stream fires and replaces them with profile-stripped rows; avatars/usernames disappear.
- User opens conversation A (0 messages), sends 2 messages, navigates back, reopens A → `_messages` still has the 2 temp/real messages in memory; stream fires immediately and overwrites with the DB snapshot minus profiles.
- User opens conversation B for the first time → no prior state, so no stale messages (bug does NOT manifest for first-time opens).
- User opens conversation A, stream event fires before `loadMessages` completes → `_messages` is populated by stream (no profiles), then `loadMessages` populates with profiles; works correctly only if load wins the race.

---

### Bug 2 — Missing Conversation on Receiver's Home Screen

The bug manifests when User A creates a new conversation with User B. The two `conversation_participants` rows are inserted in a single array call; RLS may reject the second row. Even if both rows are inserted, `listenToConversations()` uses a global `conversations` stream that is not filtered to the current user's conversations, making real-time delivery unreliable.

**Formal Specification:**
```
FUNCTION isBugCondition_2(X)
  INPUT: X = { actor: UserId, recipient: UserId, event: ConversationCreationEvent }
  OUTPUT: boolean

  RETURN X.event = NEW_CONVERSATION_CREATED
         AND (
           participant_row_missing(X.recipient)
           OR realtime_event_not_delivered(X.recipient)
         )
END FUNCTION
```

**Examples:**
- User A creates conversation with User B → batch insert fails for User B's row due to RLS; `getConversations` for User B returns 0 rows; home screen shows empty state.
- User A creates conversation and sends a message → `conversations.updated_at` changes; global stream fires but User B's client may not pick it up because the stream delivers the full unfiltered list and the updated row may be deduplicated away.
- User with 20 conversations opens app → N×4 = 80 sequential DB calls; loading indicator may time out or the Flutter async loop saturates before all conversations are returned.

---

### Bug 3 — Cross-Device Real-Time Failure

The bug manifests when two users are in the same conversation on different devices and Realtime is not enabled on the `messages` table in the Supabase dashboard. The `.stream()` subscription fires once (initial snapshot) and then never again. Additionally, `debugPrint` calls in `chat_service.dart` fail to compile because `flutter/foundation.dart` is not imported.

**Formal Specification:**
```
FUNCTION isBugCondition_3(X)
  INPUT: X = { sender: UserId, receiver: UserId, conversationId: String }
  OUTPUT: boolean

  RETURN X.sender != X.receiver
         AND (
           realtimeEnabled(messages_table) = false
           OR stream_subscription_never_fires_after_initial(X.receiver) = true
         )
END FUNCTION
```

**Examples:**
- Device A sends a message; Device B has `ChatRoomScreen` open → message appears on Device A (optimistic insert) but never on Device B's stream because `.stream()` never fires again.
- `flutter build` or analyzer run → `debugPrint` unresolved because `flutter/foundation.dart` is missing from `chat_service.dart` imports.
- Realtime IS enabled on `messages` but NOT on `conversations` → messages sync cross-device but home screen conversations do not refresh.

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- A first-time open of a conversation (no prior `_messages` in memory) SHALL continue to show the loading indicator followed by message list or "No messages yet. Say hello!" (Requirements 3.1).
- Sending a message SHALL continue to add an optimistic temp message immediately to the sender's UI (Requirements 3.2).
- When a send fails, the temp message SHALL be removed and the typed text restored (Requirements 3.3).
- Auto-scroll to the latest message SHALL continue when new messages arrive from the stream (Requirements 3.4).
- Conversations SHALL continue to be returned sorted by `updated_at` descending (Requirements 3.5).
- Pull-to-refresh on the home screen SHALL continue to call `loadConversations()` (Requirements 3.6).
- `stopListeningToMessages()` on dispose SHALL continue to cancel the stream subscription (Requirements 3.7).
- `markMessagesAsRead()` SHALL continue to update only unread messages in the current conversation sent by the other user (Requirements 3.8).

**Scope:**
All code paths that do NOT involve re-entering a conversation, creating a new conversation, or cross-device message delivery should be completely unaffected by this fix. Specifically:
- Mouse/tap interactions with conversation tiles and message bubbles.
- Authentication flows (login, signup, logout).
- User search and `NewChatScreen`.
- `sendMessage` optimistic UI and error handling.

---

## Hypothesized Root Cause

### Bug 1

1. **`clearMessages()` never called in `_initChat()`**: The prior session's `_messages` survives the navigation pop because `ChatProvider` is a shared provider (not rebuilt per route). On re-entry, the stream fires immediately before `loadMessages` finishes, and the stale state is briefly visible.

2. **Profile data loss via stream replacement**: `listenToMessages` calls `_supabaseClient.from('messages').stream(...)` which selects only columns from the `messages` table. There is no `.select('*, profiles:sender_id(...)')` in the stream query. When the stream fires and the provider does `_messages = messages`, the profile-enriched objects from `loadMessages` are thrown away.

3. **Race condition between stream and load**: `listenToMessages` is called before `loadMessages`, so the stream's first snapshot (profile-less) may arrive and replace `_messages` after `loadMessages` has already set the enriched list.

### Bug 2

4. **Batch insert RLS failure**: `await _supabaseClient.from('conversation_participants').insert([row1, row2])` evaluates RLS for both rows together. The policy likely checks `auth.uid() = user_id` for the first row (passes) but for the second row `user_id = otherUserId` and `auth.uid() != otherUserId`, so the policy check `EXISTS (SELECT 1 FROM conversation_participants WHERE conversation_id = new.conversation_id AND user_id = auth.uid())` may not find the first row yet (not yet committed in the same statement), rejecting the insert.

5. **Unfiltered conversations stream**: `listenToConversations()` uses `.stream(primaryKey: ['id'])` on the whole `conversations` table. This delivers all conversation rows to every client subscribed, but the Supabase Realtime system may only deliver rows the user has RLS access to. If User B has no participant row yet (due to bug 4 above), they have no RLS access to the conversation row and receive no event.

6. **N×4 query loop**: The `for` loop in `getConversations()` fires 4 awaited queries per conversation. For N conversations this is 4N serial round-trips, each ~50–200ms, making load time O(N) and blocking the UI for users with many conversations.

### Bug 3

7. **Realtime not enabled on `messages` table**: Supabase `.stream()` subscriptions require Realtime publication to be enabled for each table in the Supabase dashboard (`Database → Replication → 0 tables → Add table`). If not enabled, the subscription fires once (initial fetch) and silently stops receiving events.

8. **Missing `flutter/foundation.dart` import**: `debugPrint` is defined in `flutter/foundation.dart`. `chat_service.dart` only imports `supabase_flutter`, so `debugPrint` calls are unresolved. This causes a compile error or analyzer warning that can mask other issues.

---

## Correctness Properties

Property 1: Bug Condition — Messages Are Visible With Profile Data on Re-entry

_For any_ navigation event where a user re-enters a conversation (`isBugCondition_1` returns true), the fixed `_initChat()` SHALL clear stale messages first, then attach the stream, then load messages with profile data — such that after the initial load completes, every displayed message has its `senderUsername` and `senderAvatarUrl` populated and the list matches the database contents for that conversation.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Bug Condition — Both Participants Have a Conversation Row

_For any_ conversation creation event where User A creates a conversation with User B (`isBugCondition_2` returns true), the fixed `getOrCreateConversation` SHALL commit both `conversation_participants` rows successfully (current user first, then other user in a separate insert), and User B's `getConversations()` SHALL return that conversation.

**Validates: Requirements 2.4, 2.5**

Property 3: Bug Condition — Real-Time Events Are Delivered Cross-Device

_For any_ message send event where the sender and receiver are different users and the receiver's `ChatRoomScreen` is open (`isBugCondition_3` returns true), the fixed subscription mechanism SHALL deliver the new message to the receiver's screen without requiring a manual refresh, given that Realtime is enabled on the `messages` table in the Supabase dashboard.

**Validates: Requirements 2.7, 2.8**

Property 4: Preservation — Non-Buggy Inputs Produce Identical Behavior

_For any_ input that does NOT satisfy any of the three bug conditions (first-time conversation open, message send, send failure, auto-scroll, pull-to-refresh, dispose), the fixed code SHALL produce exactly the same observable behavior as the original code.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8**

---

## Fix Implementation

### Changes Required

#### File: `lib/screens/chat_room_screen.dart`

**Function**: `_initChat()`

**Specific Changes:**
1. **Call `clearMessages()` first**: Add `chatProvider.clearMessages()` as the very first line inside `_initChat()` before `listenToMessages` and `loadMessages`. This ensures no stale state from a prior session is visible on re-entry.

```dart
Future<void> _initChat() async {
  final chatProvider = context.read<ChatProvider>();
  chatProvider.clearMessages();                          // ← ADD
  chatProvider.listenToMessages(widget.conversationId);
  await chatProvider.loadMessages(widget.conversationId);
  _scrollToBottom();
}
```

---

#### File: `lib/providers/chat_provider.dart`

**Specific Changes:**
1. **Add profile cache field**: Add `final Map<String, ({String username, String avatarUrl})> _profileCache = {};` as an instance field.

2. **Populate cache in `loadMessages`**: After `_messages = await _chatService.getMessages(conversationId)`, iterate `_messages` and upsert each message's `senderId → (senderUsername, senderAvatarUrl)` into the cache.

3. **Enrich stream snapshot with cache**: In the `listenToMessages` stream listener, after receiving the `messages` list, iterate each message and if `senderUsername == null`, look it up in `_profileCache` and assign it (by calling `copyWith` or directly setting the mutable fields on `MessageModel`).

4. **Clear cache in `clearMessages()`**: Reset `_profileCache` when clearing messages so stale profile data from a previous conversation doesn't bleed into a new one.

---

#### File: `lib/services/chat_service.dart`

**Specific Changes:**

1. **Add missing import**:
```dart
import 'package:flutter/foundation.dart';
```

2. **Split batch participant insert into two sequential inserts**:
```dart
// Before (single batch — RLS risk):
await _supabaseClient.from('conversation_participants').insert([
  {'conversation_id': convId, 'user_id': currentUser},
  {'conversation_id': convId, 'user_id': otherUserId},
]);

// After (sequential — each evaluated independently by RLS):
await _supabaseClient.from('conversation_participants')
    .insert({'conversation_id': convId, 'user_id': currentUser});
await _supabaseClient.from('conversation_participants')
    .insert({'conversation_id': convId, 'user_id': otherUserId});
```

3. **Replace `getConversations()` N×4 loop with batched queries**:
   - Query 1: Get all `conversation_id` values from `conversation_participants` where `user_id = currentUser`.
   - Query 2: Get all other participants with their profiles for those conversation IDs using `.in_('conversation_id', convIds).neq('user_id', currentUser)` with a profiles join.
   - Query 3: Get all messages for those conversation IDs ordered by `created_at DESC`, then group by `conversation_id` in Dart keeping the first (most recent) per conversation.
   - Query 4: Get unread counts for all conversations in one shot using `.in_('conversation_id', convIds).eq('is_read', false).neq('sender_id', currentUser).count(CountOption.exact)` — or group by `conversation_id` in Dart after fetching all unread message IDs.
   - Query 4 alternative: fetch `conversation_id, count` from messages filtered by the above conditions, grouping in Dart.
   - Assemble `ConversationModel` objects in Dart from the three result sets.

4. **Replace `listenToConversations()` with a channel-based subscription** filtered to `conversation_participants` INSERT events for the current user:
```dart
Stream<void> listenToConversations() {
  final currentUser = currentUserId;
  if (currentUser == null) return const Stream.empty();

  final controller = StreamController<void>.broadcast();
  final channel = _supabaseClient
      .channel('conversations:$currentUser')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'conversation_participants',
        filter: PostgresChangeFilter(
          type: FilterType.eq,
          column: 'user_id',
          value: currentUser,
        ),
        callback: (_) => controller.add(null),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => controller.add(null),
      )
      .subscribe();

  controller.onCancel = () {
    _supabaseClient.removeChannel(channel);
    controller.close();
  };
  return controller.stream;
}
```
   Note: This still requires Realtime to be enabled on `conversation_participants` and `messages` tables in the Supabase dashboard. A `README` comment should document this dashboard prerequisite.

5. **Update `ChatProvider.listenToConversations`** to handle the new `Stream<void>` type (instead of `Stream<List<Map<String, dynamic>>>`): change `_conversationSubscription` type to `StreamSubscription<void>?`.

---

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate each bug on unfixed code, then verify the fix works correctly and preserves all existing behavior.

---

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bugs BEFORE implementing the fix. Confirm or refute the root cause analysis.

**Test Plan**: Write unit tests that simulate the state transitions described by each bug condition and assert the correct outcomes. Run these tests against the UNFIXED code to observe the failures.

**Test Cases:**

1. **Re-entry without clearMessages (Bug 1)**: Simulate calling `listenToMessages` followed by `loadMessages` on a `ChatProvider` that already holds messages from a prior session. Assert that stale messages appear before `loadMessages` completes → will fail on unfixed code because `clearMessages` is never called.

2. **Stream replaces enriched messages (Bug 1)**: Populate `_messages` with `MessageModel` objects that have `senderUsername = 'alice'`. Fire a stream event with the same messages but `senderUsername = null`. Assert that after the stream fires, `senderUsername` is still `'alice'` → will fail on unfixed code because the stream snapshot replaces the enriched list.

3. **Batch participant insert RLS simulation (Bug 2)**: Mock the Supabase client to reject the second row in a batch insert. Assert that `getOrCreateConversation` throws or that User B has no participant row → confirms the batch insert is the failure point.

4. **Receiver sees conversation after creation (Bug 2)**: In an integration context, have User A call `getOrCreateConversation(userB.id)`, then call `getConversations()` as User B and assert the result is non-empty → will fail on unfixed code if the batch insert RLS issue occurs.

5. **Missing import compile check (Bug 3)**: Run `dart analyze lib/services/chat_service.dart` and assert zero errors → will show `debugPrint` unresolved on unfixed code.

**Expected Counterexamples:**
- Stale messages are visible on re-entry because `clearMessages` was not called.
- `senderUsername` becomes `null` after the stream fires because the stream snapshot has no profiles join.
- `getConversations()` for User B returns an empty list because the second participant row was not inserted.
- `dart analyze` reports `debugPrint` as undefined.

---

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed code produces the expected behavior.

**Pseudocode:**
```
FOR ALL X WHERE isBugCondition_1(X) DO
  result := initChat_fixed(X.conversationId)
  ASSERT result.messages are cleared before stream subscription
  ASSERT result.messages[*].senderUsername != null
  ASSERT result.messages == DB_messages(X.conversationId)
END FOR

FOR ALL X WHERE isBugCondition_2(X) DO
  getOrCreateConversation_fixed(X.actor, X.recipient)
  ASSERT participantRow_exists(X.recipient, convId) = true
  ASSERT getConversations_fixed(X.recipient).length >= 1
END FOR

FOR ALL X WHERE isBugCondition_3(X) DO
  sendMessage_fixed(X.sender, X.conversationId, 'ping')
  ASSERT message_appears_on(X.receiver, X.conversationId) = true
  ASSERT dart_analyze(chat_service.dart).errors = 0
END FOR
```

---

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed code produces the same result as the original code.

**Pseudocode:**
```
FOR ALL X WHERE NOT isBugCondition_1(X) AND NOT isBugCondition_2(X) AND NOT isBugCondition_3(X) DO
  ASSERT original_behavior(X) = fixed_behavior(X)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because it generates many random inputs (different message counts, conversation states, user IDs) and verifies that the fixed code never changes behavior for non-buggy inputs.

**Test Cases:**
1. **First-time open preservation**: Verify that opening a conversation for the first time (empty `_messages`, no cache) still shows loading then "No messages yet." or message list after `loadMessages`.
2. **Optimistic send preservation**: Verify that `sendMessage` still adds a temp message immediately and replaces it with the server response.
3. **Send failure preservation**: Verify that when `sendMessage` throws, the temp message is removed and `_error` is set.
4. **Auto-scroll preservation**: Verify that after the stream delivers new messages, `_scrollToBottom` is still triggered.
5. **Sort order preservation**: Verify that `getConversations_fixed()` returns conversations in `updatedAt` descending order.
6. **Pull-to-refresh preservation**: Verify that `loadConversations()` is still triggered on pull-to-refresh.
7. **Dispose preservation**: Verify that `stopListeningToMessages()` cancels the subscription so no further `notifyListeners()` fires.
8. **markMessagesAsRead preservation**: Verify that only messages where `sender_id != currentUser AND is_read = false` are updated.

---

### Unit Tests

- Test that `_initChat()` calls `clearMessages()` before `listenToMessages()` and `loadMessages()`.
- Test that the profile cache is populated correctly after `loadMessages()`.
- Test that the stream listener uses the profile cache to fill `null` `senderUsername` fields.
- Test that `getOrCreateConversation()` makes two sequential inserts (not one batch).
- Test that `getConversations()` makes at most 4 DB calls regardless of conversation count (mock the client).
- Test the `dart analyze` / compile check for `debugPrint` resolving correctly after the import is added.

### Property-Based Tests

- Generate random lists of `MessageModel` objects (some with `senderUsername = null`, some with values) and verify that after profile cache hydration, all messages have non-null `senderUsername` for known senders.
- Generate random numbers of conversations (1–50) and verify that the batched `getConversations` implementation returns the correct count and sort order.
- Generate random sequences of `sendMessage` calls (some failing) and verify that optimistic messages are always cleaned up correctly.

### Integration Tests

- Full flow: User A creates conversation with User B → User B's `getConversations()` returns it → User B opens it → messages load with profile data.
- Re-entry flow: User opens conversation, sees messages with usernames, navigates back, reopens → messages still show with usernames.
- Cross-device flow (requires Realtime enabled): User A sends message → User B's open `ChatRoomScreen` receives it via stream within 2 seconds.
- Compile/analyze: `flutter analyze` reports zero errors after the `flutter/foundation.dart` import is added.
