# Implementation Plan

- [ ] 1. Write bug condition exploration tests (BEFORE implementing any fix)
  - **Property 1: Bug Condition** - Messages Disappear on Re-entry, Missing Participant Row, and debugPrint Compile Error
  - **CRITICAL**: These tests MUST FAIL on unfixed code — failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior — they will validate the fix when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate each bug exists
  - **Scoped PBT Approach**: For deterministic bugs, scope the property to the concrete failing cases for reproducibility

  **Test 1.1 — Re-entry without clearMessages (Bug 1)**
  - File: `test/chat_provider_bug1_test.dart`
  - Create a `ChatProvider` with a mocked `ChatService` that returns 2 messages (with `senderUsername = 'alice'`)
  - Pre-populate `_messages` (simulate a prior session) by calling `loadMessages` once
  - Call `listenToMessages` a second time (simulating re-entry) WITHOUT calling `clearMessages` first
  - Fire a stream event from the mock that returns the same 2 messages but with `senderUsername = null` (no profiles join on stream)
  - Assert that after the stream fires, `senderUsername` is still `'alice'` (not null)
  - **EXPECTED OUTCOME**: Test FAILS on unfixed code — stream replaces enriched list with null-profile messages
  - Document counterexample: "`senderUsername` became null after stream fired because stream snapshot has no profiles join"
  - _Requirements: 1.2, 1.3, 2.1, 2.2, 2.3_

  **Test 1.2 — Batch insert RLS simulation (Bug 2)**
  - File: `test/chat_service_bug2_test.dart`
  - Mock `SupabaseClient` to succeed for the first participant row insert and throw an RLS error on the second row when called in a single batch array insert
  - Call `getOrCreateConversation(otherUserId)` (unfixed version with batch insert)
  - Assert that both participant rows exist (i.e., that the method does NOT throw and both rows are committed)
  - **EXPECTED OUTCOME**: Test FAILS on unfixed code — second participant row is rejected by RLS mock
  - Document counterexample: "`conversation_participants` insert failed for `user_id = otherUserId` when inserted as batch"
  - _Requirements: 1.6, 2.4_

  **Test 1.3 — debugPrint compile check (Bug 3)**
  - Run `dart analyze lib/services/chat_service.dart` in the terminal
  - Assert zero errors/warnings regarding `debugPrint` being undefined
  - **EXPECTED OUTCOME**: Analyzer reports `debugPrint` as undefined (unresolved identifier) on unfixed code because `flutter/foundation.dart` is missing
  - Document counterexample: "Analyzer error: `The function 'debugPrint' isn't defined`"
  - _Requirements: 1.8, 2.8_

  - Run all three exploration tests against unfixed code
  - **EXPECTED OUTCOME**: All three tests FAIL (this is correct — it proves the bugs exist)
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 1.8_

- [ ] 2. Write preservation property tests (BEFORE implementing any fix)
  - **Property 2: Preservation** - Non-Buggy Input Behaviors Remain Identical
  - **IMPORTANT**: Follow observation-first methodology — run UNFIXED code with non-buggy inputs first and record actual outputs
  - **GOAL**: Capture baseline behavior that the fix must not regress

  **Test 2.1 — First-time open preservation**
  - File: `test/chat_provider_preservation_test.dart`
  - Observe: calling `loadMessages` on a fresh `ChatProvider` (empty `_messages`, no prior session) returns messages or empty list correctly
  - Write property-based test: for any conversation with N messages (0 ≤ N ≤ 100), `loadMessages` sets `_messages.length == N` and `isMessagesLoading` transitions false→true→false
  - Verify test PASSES on unfixed code
  - _Requirements: 3.1_

  **Test 2.2 — Optimistic send preservation**
  - Observe: `sendMessage` adds a `temp_*` message to `_messages` synchronously before the server responds
  - Write property-based test: for any valid `conversationId` + `content` string, after `sendMessage` is called the `_messages` list contains exactly one entry with `id.startsWith('temp_')` while the async call is in flight
  - Verify test PASSES on unfixed code
  - _Requirements: 3.2_

  **Test 2.3 — Send failure preservation**
  - Observe: when `ChatService.sendMessage` throws, the temp message is removed and `_error` is non-null
  - Write property-based test: for any message content, when the underlying service throws, `_messages` contains no entries starting with `'temp_'` after the call resolves, and `error != null`
  - Verify test PASSES on unfixed code
  - _Requirements: 3.3_

  **Test 2.4 — Sort order preservation**
  - Observe: `getConversations()` returns conversations sorted by `updatedAt` descending
  - Write property-based test: generate a random list of N conversations (1 ≤ N ≤ 20) with random `updatedAt` values; after `loadConversations()`, assert `conversations[i].updatedAt >= conversations[i+1].updatedAt` for all i
  - Verify test PASSES on unfixed code
  - _Requirements: 3.5_

  **Test 2.5 — stopListeningToMessages cancels subscription**
  - Observe: after `stopListeningToMessages()`, no further `notifyListeners()` fires from the stream
  - Write test: call `listenToMessages`, then `stopListeningToMessages`, then fire a mock stream event, assert `_messages` did not change and `notifyListeners` was not called
  - Verify test PASSES on unfixed code
  - _Requirements: 3.7_

  **Test 2.6 — markMessagesAsRead scope preservation**
  - Observe: `markMessagesAsRead` only targets `is_read = false` messages where `sender_id != currentUser`
  - Write test: assert that the Supabase update call has filters `eq('conversation_id', id)`, `neq('sender_id', currentUser)`, `eq('is_read', false)` applied — no other rows touched
  - Verify test PASSES on unfixed code
  - _Requirements: 3.8_

  - Run all preservation tests against unfixed code
  - **EXPECTED OUTCOME**: All preservation tests PASS (confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.5, 3.7, 3.8_

- [ ] 3. Fix Bug 1 — Messages disappear on re-entry

  - [ ] 3.1 Fix `chat_room_screen.dart`: call `clearMessages()` first in `_initChat()`
    - File: `lib/screens/chat_room_screen.dart`
    - In `_initChat()`, add `chatProvider.clearMessages()` as the very first line, before `listenToMessages` and `loadMessages`
    - The final `_initChat()` body must be:
      ```dart
      Future<void> _initChat() async {
        final chatProvider = context.read<ChatProvider>();
        chatProvider.clearMessages();                          // ← ADD THIS LINE
        chatProvider.listenToMessages(widget.conversationId);
        await chatProvider.loadMessages(widget.conversationId);
        _scrollToBottom();
      }
      ```
    - No other changes to `chat_room_screen.dart`
    - _Bug_Condition: isBugCondition_1(X) where X.event = RE_ENTER_CONVERSATION AND clearMessages_called_before_listenToMessages = false_
    - _Expected_Behavior: messages are cleared before stream subscription is set up, so stale messages from prior session are never visible_
    - _Preservation: first-time opens still show loading → message list or "No messages yet." (Requirement 3.1); stream and load still run in the correct order (Requirement 3.4)_
    - _Requirements: 2.1, 3.1, 3.4_

  - [ ] 3.2 Fix `chat_provider.dart`: add profile cache and populate it during `loadMessages`
    - File: `lib/providers/chat_provider.dart`
    - Add instance field after `_messages` declaration:
      ```dart
      final Map<String, ({String username, String avatarUrl})> _profileCache = {};
      ```
    - In `loadMessages()`, after `_messages = await _chatService.getMessages(conversationId)`, add a loop to populate the cache:
      ```dart
      for (final msg in _messages) {
        if (msg.senderUsername != null) {
          _profileCache[msg.senderId] = (
            username: msg.senderUsername!,
            avatarUrl: msg.senderAvatarUrl ?? '',
          );
        }
      }
      ```
    - In `clearMessages()`, also clear the cache:
      ```dart
      void clearMessages() {
        _messages = [];
        _profileCache.clear();   // ← ADD THIS LINE
        notifyListeners();
      }
      ```
    - _Bug_Condition: isBugCondition_1(X) where stream_snapshot_lacks_profile_data = true_
    - _Expected_Behavior: profile data populated by loadMessages is preserved in cache for stream enrichment_
    - _Requirements: 2.2, 2.3_

  - [ ] 3.3 Fix `chat_provider.dart`: enrich stream snapshots using the profile cache
    - File: `lib/providers/chat_provider.dart`
    - In the `listenToMessages` stream listener, after receiving the `messages` list and before assigning `_messages = messages`, iterate and fill null sender fields from cache:
      ```dart
      _messageSubscription =
          _chatService.listenToMessages(conversationId).listen((messages) {
        // Remove any optimistic temp messages that have been replaced by real ones
        final realIds = messages.map((m) => m.id).toSet();
        _messages.removeWhere((m) => m.id.startsWith('temp_') && realIds.isNotEmpty);

        // Enrich stream snapshot with cached profile data                      // ← ADD
        for (final msg in messages) {                                            // ← ADD
          if (msg.senderUsername == null && _profileCache.containsKey(msg.senderId)) { // ← ADD
            final profile = _profileCache[msg.senderId]!;                       // ← ADD
            msg.senderUsername = profile.username;                               // ← ADD
            msg.senderAvatarUrl = profile.avatarUrl;                            // ← ADD
          }                                                                      // ← ADD
        }                                                                        // ← ADD

        // Replace the message list with the server's authoritative snapshot
        _messages = messages;
        notifyListeners();

        // Mark incoming messages as read
        _chatService.markMessagesAsRead(conversationId);
      }, onError: ...);
      ```
    - _Bug_Condition: isBugCondition_1(X) where stream_snapshot_lacks_profile_data = true_
    - _Expected_Behavior: after stream fires, every message with a known senderId has senderUsername != null_
    - _Preservation: stream replacement behavior for non-cached senders is unchanged; optimistic message cleanup still works (Requirement 3.2)_
    - _Requirements: 2.2, 2.3, 3.2_

  - [ ] 3.4 Verify Bug 1 exploration test now passes
    - **Property 1: Expected Behavior** - Messages Are Visible With Profile Data on Re-entry
    - **IMPORTANT**: Re-run the SAME tests from task 1 (Tests 1.1) — do NOT write new tests
    - These tests encode the expected behavior for Bug 1
    - Run `test/chat_provider_bug1_test.dart` against fixed code
    - **EXPECTED OUTCOME**: Test PASSES (confirms Bug 1 is fixed — stream no longer strips senderUsername)
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 3.5 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Buggy Input Behaviors Remain Identical
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run `test/chat_provider_preservation_test.dart`
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions from Bug 1 fix)
    - Verify specifically: first-time open (3.1), optimistic send (3.2), send failure (3.3), auto-scroll (3.4), dispose cancels subscription (3.7)

- [ ] 4. Fix Bug 2 — Receiver's home screen shows no conversations

  - [ ] 4.1 Fix `chat_service.dart`: split batch participant insert into two sequential inserts
    - File: `lib/services/chat_service.dart`
    - In `getOrCreateConversation()`, replace the single batch insert with two sequential awaited inserts:
      ```dart
      // BEFORE (batch — RLS risk):
      await _supabaseClient.from('conversation_participants').insert([
        {'conversation_id': convId, 'user_id': currentUser},
        {'conversation_id': convId, 'user_id': otherUserId},
      ]);

      // AFTER (sequential — each row evaluated independently by RLS):
      await _supabaseClient
          .from('conversation_participants')
          .insert({'conversation_id': convId, 'user_id': currentUser});
      await _supabaseClient
          .from('conversation_participants')
          .insert({'conversation_id': convId, 'user_id': otherUserId});
      ```
    - The `return convId;` line remains unchanged after the two inserts
    - _Bug_Condition: isBugCondition_2(X) where participant_row_missing(X.recipient) = true_
    - _Expected_Behavior: both participant rows are committed successfully; User B's getConversations() returns the new conversation_
    - _Preservation: the returned conversationId is unchanged; existing conversation lookup logic is unchanged_
    - _Requirements: 2.4, 3.5_

  - [ ] 4.2 Fix `chat_service.dart`: replace N×4 query loop in `getConversations()` with batched queries
    - File: `lib/services/chat_service.dart`
    - Replace the entire `for (var participant in participantData)` loop with 3 batched queries and Dart-side assembly:

    **Query 1** — already done (participant IDs):
    ```dart
    final participantData = await _supabaseClient
        .from('conversation_participants')
        .select('conversation_id')
        .eq('user_id', currentUser);
    final convIds = (participantData as List)
        .map((r) => r['conversation_id'] as String)
        .toList();
    if (convIds.isEmpty) return [];
    ```

    **Query 2** — fetch all other participants + profiles in one call:
    ```dart
    final otherParticipants = await _supabaseClient
        .from('conversation_participants')
        .select('conversation_id, user_id, profiles(*)')
        .inFilter('conversation_id', convIds)
        .neq('user_id', currentUser);
    // Build map: conversationId → UserModel
    final Map<String, UserModel> otherUserMap = {};
    for (final row in otherParticipants as List) {
      final convId = row['conversation_id'] as String;
      if (!otherUserMap.containsKey(convId) && row['profiles'] != null) {
        otherUserMap[convId] =
            UserModel.fromJson(row['profiles'] as Map<String, dynamic>);
      }
    }
    ```

    **Query 3** — fetch conversations table rows for metadata (createdAt, updatedAt):
    ```dart
    final convsData = await _supabaseClient
        .from('conversations')
        .select()
        .inFilter('id', convIds);
    final Map<String, ConversationModel> convMap = {};
    for (final row in convsData as List) {
      final c = ConversationModel.fromJson(row);
      convMap[c.id] = c;
    }
    ```

    **Query 4** — fetch all messages for those conversations, group in Dart:
    ```dart
    final allMessages = await _supabaseClient
        .from('messages')
        .select()
        .inFilter('conversation_id', convIds)
        .order('created_at', ascending: false);
    // Last message per conversation (first in descending order)
    final Map<String, MessageModel> lastMessageMap = {};
    // Unread count per conversation
    final Map<String, int> unreadCountMap = {};
    for (final row in allMessages as List) {
      final convId = row['conversation_id'] as String;
      final msg = MessageModel.fromJson(row);
      if (!lastMessageMap.containsKey(convId)) {
        lastMessageMap[convId] = msg;
      }
      if (!msg.isRead && msg.senderId != currentUser) {
        unreadCountMap[convId] = (unreadCountMap[convId] ?? 0) + 1;
      }
    }
    ```

    **Assemble and sort:**
    ```dart
    final List<ConversationModel> conversations = [];
    for (final convId in convIds) {
      final conv = convMap[convId];
      if (conv == null) continue;
      conv.otherUser = otherUserMap[convId];
      conv.lastMessage = lastMessageMap[convId];
      conv.unreadCount = unreadCountMap[convId] ?? 0;
      conversations.add(conv);
    }
    conversations.sort((a, b) =>
        (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt));
    return conversations;
    ```
    - Total DB round-trips: 4 (independent of N conversations)
    - _Bug_Condition: isBugCondition_2(X) where N×4 query loop causes timeout or loading failure_
    - _Expected_Behavior: getConversations() completes in O(1) round-trips regardless of conversation count_
    - _Preservation: conversations are still sorted by updatedAt descending (Requirement 3.5); otherUser, lastMessage, and unreadCount are still populated on each ConversationModel_
    - _Requirements: 2.6, 3.5_

  - [ ] 4.3 Fix `chat_service.dart`: replace `listenToConversations()` with channel-based subscription
    - File: `lib/services/chat_service.dart`
    - Add import at the top of the file: `import 'dart:async';`
    - Replace the existing `listenToConversations()` method (return type `Stream<List<Map<String, dynamic>>>`) with a new implementation returning `Stream<void>`:
      ```dart
      /// Fires whenever a new conversation_participants row is inserted for the
      /// current user (new conversation created) or a new message is inserted
      /// (conversation updated). Requires Realtime enabled on both tables in
      /// the Supabase dashboard (Database → Replication → Supabase Realtime).
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
    - _Bug_Condition: isBugCondition_2(X) where realtime_event_not_delivered(X.recipient) = true_
    - _Expected_Behavior: User B receives a stream event when User A creates a conversation or sends a message, triggering loadConversations() on User B's home screen_
    - _Preservation: the debounce + loadConversations() call in ChatProvider.listenToConversations() is unchanged; stopListeningToConversations() still cancels the subscription_
    - _Requirements: 2.5, 3.6, 3.7_

  - [ ] 4.4 Fix `chat_provider.dart`: update subscription type to match new `Stream<void>`
    - File: `lib/providers/chat_provider.dart`
    - Change the `_conversationSubscription` field type from `StreamSubscription<List<Map<String, dynamic>>>?` to `StreamSubscription<void>?`:
      ```dart
      // BEFORE:
      StreamSubscription<List<Map<String, dynamic>>>? _conversationSubscription;

      // AFTER:
      StreamSubscription<void>? _conversationSubscription;
      ```
    - The body of `listenToConversations()` in `ChatProvider` is unchanged — the debounce and `loadConversations()` call remain exactly as-is; only the type annotation changes
    - _Bug_Condition: type mismatch compiler error after ChatService.listenToConversations() return type change_
    - _Expected_Behavior: code compiles cleanly; subscription cancel/null behavior is identical_
    - _Preservation: debounce behavior (300ms) and loadConversations() trigger are unchanged (Requirement 3.6)_
    - _Requirements: 2.5, 3.6_

  - [ ] 4.5 Verify Bug 2 exploration test now passes
    - **Property 1: Expected Behavior** - Both Participants Have a Conversation Row
    - **IMPORTANT**: Re-run the SAME test from task 1 (Test 1.2) — do NOT write a new test
    - Run `test/chat_service_bug2_test.dart` against fixed code
    - **EXPECTED OUTCOME**: Test PASSES (confirms both participant rows are committed — sequential inserts succeed independently)
    - _Requirements: 2.4, 2.5_

  - [ ] 4.6 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Buggy Input Behaviors Remain Identical
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run `test/chat_provider_preservation_test.dart`
    - **EXPECTED OUTCOME**: Tests PASS (no regressions from Bug 2 fix)
    - Verify specifically: sort order (3.5), pull-to-refresh triggers loadConversations (3.6), stopListeningToConversations cancels subscription (3.7)

- [ ] 5. Fix Bug 3 — Missing import causes compile error / cross-device real-time failure

  - [ ] 5.1 Fix `chat_service.dart`: add missing `flutter/foundation.dart` import
    - File: `lib/services/chat_service.dart`
    - Add the import as the first line of the import block:
      ```dart
      import 'package:flutter/foundation.dart';
      ```
    - The file's existing imports remain unchanged; the new import is added alongside them
    - This resolves the `debugPrint` unresolved identifier compiler error/warning
    - _Bug_Condition: isBugCondition_3(X) where dart_analyze reports debugPrint undefined_
    - _Expected_Behavior: dart analyze lib/services/chat_service.dart reports zero errors_
    - _Preservation: no behavior change — debugPrint calls were already in the file; this only fixes the unresolved symbol_
    - _Requirements: 2.8_

  - [ ] 5.2 Document Supabase Realtime dashboard prerequisite
    - File: `lib/services/chat_service.dart`
    - Add a comment block above the `listenToMessages()` method documenting the dashboard requirement:
      ```dart
      /// PREREQUISITE: Realtime must be enabled for the `messages` table in the
      /// Supabase dashboard: Database → Replication → Supabase Realtime → Add table.
      /// Without this, the stream fires only once (initial snapshot) and never again.
      Stream<List<MessageModel>> listenToMessages(String conversationId) { ... }
      ```
    - This is documentation only — no code behavior change
    - _Requirements: 2.7_

  - [ ] 5.3 Verify Bug 3 exploration test now passes
    - **Property 1: Expected Behavior** - Real-Time Events Are Delivered; debugPrint Compiles
    - **IMPORTANT**: Re-run the SAME test from task 1 (Test 1.3) — do NOT write a new test
    - Run `dart analyze lib/services/chat_service.dart`
    - **EXPECTED OUTCOME**: Zero errors (confirms `debugPrint` resolves correctly after import is added)
    - _Requirements: 2.7, 2.8_

  - [ ] 5.4 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Buggy Input Behaviors Remain Identical
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run `test/chat_provider_preservation_test.dart`
    - **EXPECTED OUTCOME**: Tests PASS (no regressions from Bug 3 fix)
    - Verify specifically: markMessagesAsRead scope (3.8), stopListeningToMessages (3.7)

- [ ] 6. Checkpoint — Ensure all tests pass
  - Run the full test suite: `flutter test`
  - Run static analysis: `flutter analyze`
  - Verify all exploration tests (Property 1) now PASS — confirming all three bugs are fixed
  - Verify all preservation tests (Property 2) still PASS — confirming no regressions
  - Confirm `flutter analyze` reports zero errors across the entire project
  - Ensure all tasks are marked complete
  - Ask the user if any questions arise about Supabase dashboard configuration (Realtime table enablement for `messages` and `conversation_participants`)
