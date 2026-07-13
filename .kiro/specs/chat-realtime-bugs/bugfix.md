# Bugfix Requirements Document

## Introduction

Three critical bugs affect the Flutter/Supabase chat application's reliability. Messages disappear when a user re-enters a conversation, the receiver's home screen never shows new conversations created by the sender, and real-time message delivery fails between devices. These issues combine to make the app appear non-functional in normal two-party chat usage. The fixes must restore correct message persistence, conversation visibility for all participants, and live cross-device delivery — without regressing any currently working flows.

## Bug Analysis

### Current Behavior (Defect)

**Bug 1 — Messages disappear on re-entry**

1.1 WHEN a user sends messages in `ChatRoomScreen`, leaves (disposing the screen), and reopens the same conversation, THEN the system shows "No messages yet. Say hello!" even though the messages exist in the database.

1.2 WHEN `ChatRoomScreen` is re-initialized after a prior visit, THEN the system calls `clearMessages()` is never invoked, so `_messages` retains stale state from the previous session; the `listenToMessages` stream in `ChatService` does not include the `profiles:sender_id(username, avatar_url)` join that `getMessages` does, so when the stream snapshot replaces `_messages` it loses sender profile data.

1.3 WHEN `listenToMessages` fires its first stream event concurrently with `loadMessages` setting `_messagesLoading = true`, THEN the system may briefly show an empty loading state, and if the stream event arrives after `loadMessages` completes the profile-enriched list is overwritten with the plain stream snapshot.

**Bug 2 — Receiver's home screen shows "No Conversations Yet"**

1.4 WHEN User A creates a new conversation with User B and sends the first message, THEN User B's home screen shows "No Conversations Yet" because `listenToConversations()` in `ChatService` watches the `conversations` table globally without filtering to the current user's rows, so the Supabase Realtime stream may not reliably deliver the change event to User B's client.

1.5 WHEN `getConversations()` executes, THEN the system performs 4 sequential database round-trips per conversation inside a loop (N×4 queries total), which is slow, can exceed timeouts for users with many conversations, and increases the chance that the loading indicator dismisses before data arrives.

1.6 WHEN `conversation_participants` batch insert executes for a brand-new conversation, THEN inserting both the current user's row and the other user's row in a single array insert may fail RLS validation for the second row if the policy's `NOT EXISTS` check on the conversation is evaluated per-row in a non-deterministic order, leaving User B without a participant record.

**Bug 3 — Cross-device real-time messages not delivered**

1.7 WHEN User A sends a message and User B is viewing the same `ChatRoomScreen`, THEN the message does not appear on User B's screen because the `messages` table (and `conversations` table) may not have Realtime publication enabled in the Supabase project dashboard, causing `.stream()` subscriptions to fire only once on subscription and never again on subsequent inserts.

1.8 WHEN `chat_service.dart` calls `debugPrint`, THEN the system may fail to compile or emit a warning because `flutter/foundation.dart` is not imported in `chat_service.dart` — only `supabase_flutter` is imported — making `debugPrint` an unresolved identifier.

### Expected Behavior (Correct)

**Bug 1 — Messages must load correctly on every visit**

2.1 WHEN a user re-enters a conversation that was previously open, THEN the system SHALL call `clearMessages()` before setting up the new stream subscription and initiating `loadMessages`, so the UI starts from a clean state.

2.2 WHEN `listenToMessages` stream fires, THEN the system SHALL enrich each message with sender profile data (username, avatar_url) by either fetching profiles in a batch alongside the stream snapshot or by merging profile data from the existing `_messages` list before replacing it.

2.3 WHEN `_initChat()` runs, THEN the system SHALL ensure `loadMessages` (which includes the profiles join) serves as the authoritative initial data source, and the stream subscription SHALL only replace `_messages` after the initial load completes or SHALL always augment stream snapshots with profile data.

**Bug 2 — Conversation list must be correct for both participants**

2.4 WHEN User A creates a conversation with User B, THEN the system SHALL insert the two `conversation_participants` rows sequentially (current user first, then other user) so each insert is independently evaluated against RLS, ensuring both rows are committed successfully.

2.5 WHEN a new message is sent, THEN User B's home screen SHALL reflect the new conversation within a reasonable time by using a Supabase Realtime channel-based subscription (`.on(PostgresChangeEvent.insert/update, ...)`) filtered to conversations the current user participates in, rather than relying solely on a global `.stream()` on the `conversations` table.

2.6 WHEN `getConversations()` loads conversations, THEN the system SHALL replace the N×4-query loop with a batched approach: a single join query to retrieve all conversations, their other participants and profiles, the last message per conversation, and unread counts — reducing total round-trips to 3–4 regardless of conversation count.

**Bug 3 — Real-time delivery must work across devices**

2.7 WHEN both users have Supabase Realtime enabled on the `messages` table AND User B's `ChatRoomScreen` is open for a given conversation, THEN the system SHALL deliver User A's new message to User B's screen via the `.stream()` subscription without requiring a manual refresh.

2.8 WHEN `chat_service.dart` is compiled, THEN the system SHALL include `import 'package:flutter/foundation.dart';` so that all `debugPrint` calls resolve without error.

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a user opens a conversation for the very first time (no prior messages), THEN the system SHALL CONTINUE TO show "No messages yet. Say hello!" until the first message is sent.

3.2 WHEN a user sends a message, THEN the system SHALL CONTINUE TO display an optimistic (temporary) message immediately in the sender's UI before the server confirms the insert.

3.3 WHEN a message send fails, THEN the system SHALL CONTINUE TO remove the optimistic message and restore the typed text so the user can retry.

3.4 WHEN the user is already inside a `ChatRoomScreen`, THEN the system SHALL CONTINUE TO scroll to the latest message automatically when new messages arrive from the stream.

3.5 WHEN `loadConversations()` is called, THEN the system SHALL CONTINUE TO return conversations sorted by `updated_at` descending (most recent first).

3.6 WHEN the home screen is pulled down to refresh, THEN the system SHALL CONTINUE TO trigger a full reload of the conversation list via `loadConversations()`.

3.7 WHEN `stopListeningToMessages()` is called on dispose, THEN the system SHALL CONTINUE TO cancel the active stream subscription so no further callbacks fire after the screen is gone.

3.8 WHEN `markMessagesAsRead()` is called, THEN the system SHALL CONTINUE TO update only messages in the current conversation that were sent by the other user and are currently unread.

---

## Bug Condition Pseudocode

### Bug 1 — Message Disappearance on Re-entry

```pascal
FUNCTION isBugCondition_1(X)
  INPUT: X = { action: NavigationEvent, conversationId: String }
  OUTPUT: boolean
  RETURN X.action = RE_ENTER_CONVERSATION
         AND clearMessages() was NOT called before listenToMessages()
END FUNCTION

// Fix Checking
FOR ALL X WHERE isBugCondition_1(X) DO
  result ← openChatRoomScreen'(X.conversationId)
  ASSERT messages_visible(result) = true
  ASSERT sender_profile_data_present(result) = true
END FOR

// Preservation Checking
FOR ALL X WHERE NOT isBugCondition_1(X) DO
  ASSERT openChatRoomScreen(X) = openChatRoomScreen'(X)
END FOR
```

### Bug 2 — Missing Conversation on Receiver's Home Screen

```pascal
FUNCTION isBugCondition_2(X)
  INPUT: X = { actor: UserA, recipient: UserB, event: NewConversationCreated }
  OUTPUT: boolean
  RETURN X.event = NEW_CONVERSATION_CREATED
         AND conversation_participants_for(X.recipient) = empty
            OR realtime_subscription_missed_event(X.recipient)
END FUNCTION

// Fix Checking
FOR ALL X WHERE isBugCondition_2(X) DO
  result ← loadConversations'(X.recipient)
  ASSERT conversation_count(result) >= 1
END FOR

// Preservation Checking
FOR ALL X WHERE NOT isBugCondition_2(X) DO
  ASSERT loadConversations(X.recipient) = loadConversations'(X.recipient)
END FOR
```

### Bug 3 — Cross-Device Real-Time Failure

```pascal
FUNCTION isBugCondition_3(X)
  INPUT: X = { sender: UserA, receiver: UserB, conversationId: String }
  OUTPUT: boolean
  RETURN X.sender != X.receiver
         AND realtimeEnabled(messages_table) = false
            OR stream_subscription_active(X.receiver, X.conversationId) = false
END FUNCTION

// Fix Checking
FOR ALL X WHERE isBugCondition_3(X) DO
  sendMessage'(X.sender, X.conversationId, 'ping')
  ASSERT message_received_by(X.receiver, X.conversationId) = true
END FOR

// Preservation Checking
FOR ALL X WHERE NOT isBugCondition_3(X) DO
  ASSERT sendMessage(X) = sendMessage'(X)
END FOR
```
