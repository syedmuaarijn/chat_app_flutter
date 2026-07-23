# Implementation Plan

- [ ] 1. Write bug condition exploration tests (BEFORE implementing any fix)
  - **Property 1: Bug Condition** - Offline Auth Redirect, Spinner on Cache, Media Not Persisted
  - **CRITICAL**: These tests MUST FAIL on unfixed code — failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior — they will validate the fix when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate each bug exists

  - **Bug 1 — Auth Offline Redirect:**
    - Scope: `isBugCondition_AuthOffline(X)` where `X.hasNetworkConnection = FALSE`, `X.hiveAuthBoxHasAccessToken = TRUE`, `X.hiveChatCacheHasCurrentUser = TRUE`
    - Pre-populate `authBox` with a fake access token and refresh token; pre-populate `chatCache` with a serialised `UserModel` under key `current_user`
    - Mock `OfflineService.hasConnection()` to return `false` and stub `Supabase.instance.client.auth.currentUser` to `null` (SDK hasn't restored session yet)
    - Call `AuthProvider._initAuth()` (or create a fresh `AuthProvider` instance so constructor runs it)
    - Assert `authProvider.isAuthenticated == true` and `authProvider.currentUser != null`
    - **EXPECTED OUTCOME**: Test FAILS — `isAuthenticated` is `false` because `setSession`/`recoverSession` was never called before reading the Supabase SDK state
    - Document counterexample: `isAuthenticated = false` despite valid Hive session tokens

  - **Bug 2 — Spinner Instead of Cached Conversations:**
    - Scope: `isBugCondition_SpinnerOnCache(X)` where `X.hiveChatCacheHasConversations = TRUE`, `X.chatProviderConversations.isEmpty = TRUE`, `X.chatProviderInitialLoadDone = FALSE`
    - Pre-populate Hive `chatCache` with at least one serialised `ConversationModel`
    - Create a `ChatProvider` and call `loadConversations()` with a mock that delays the network path by 100 ms (so the cache-only path fires first)
    - On the very first `build()` of `HomeScreen` (before `addPostFrameCallback` fires), assert `CircularProgressIndicator` is NOT shown
    - **EXPECTED OUTCOME**: Test FAILS — spinner is shown unconditionally because `conversations.isEmpty` is `true` on the first synchronous build frame
    - Document counterexample: spinner shown even though cached data is available in Hive

  - **Bug 3 — Media/Profiles Not Persisted Across Restarts:**
    - Scope: `isBugCondition_MediaNotPersisted(X)` where `X.profileImageUrl.isNotEmpty = TRUE`, `X.imageProviderClass = NetworkImage`, `X.processWasKilled = TRUE`
    - Render a `ConversationTile` with a non-empty `displayAvatar` URL (using the current `NetworkImage` path)
    - Simulate a process restart by calling `PaintingBinding.instance.imageCache.clear()` and `PaintingBinding.instance.imageCache.clearLiveImages()`
    - Make the URL unreachable by mocking the `http` client to return 404
    - Assert that the avatar still renders a valid image (not a broken icon or fallback placeholder)
    - **EXPECTED OUTCOME**: Test FAILS — broken/missing image shown because `NetworkImage` has no on-disk persistence
    - Document counterexample: avatar shows error widget after cache clear + URL unavailability

  - Run all three property tests on UNFIXED code, record counterexamples
  - Mark task complete when all three exploration tests are written, run, and their failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - All Existing Online Behaviors Unchanged
  - **IMPORTANT**: Follow observation-first methodology — run UNFIXED code with non-buggy inputs, observe outputs, then encode as property tests
  - Preservation scope: all inputs where NONE of `isBugCondition_AuthOffline`, `isBugCondition_SpinnerOnCache`, or `isBugCondition_MediaNotPersisted` hold
  - This means online mode, sign-out, optimistic messaging, realtime subscriptions, pull-to-refresh, delete conversation, theme toggle

  - **Preservation Test 2a — Sign-out clears session:**
    - Observe on unfixed code: `AuthProvider.signOut()` clears `authBox` tokens and sets `_currentUser = null`
    - Write property test: for any authenticated user, calling `signOut()` results in `isAuthenticated == false` and `authBox` having no `access_token` key
    - Verify test PASSES on unfixed code (baseline behaviour confirmed)

  - **Preservation Test 2b — Optimistic text message send:**
    - Observe on unfixed code: `ChatProvider.sendMessage()` with online=true appends a temp message immediately before the await, then replaces it with the server-confirmed message on success
    - Write property test: for any conversationId and content string, a temp message with `id.startsWith('temp_')` appears in `messages` list before the network call resolves
    - Verify test PASSES on unfixed code

  - **Preservation Test 2c — Realtime subscription updates:**
    - Observe on unfixed code: `ChatProvider.listenToConversations()` calls `_cacheConversationsLocally()` and `notifyListeners()` when a new message payload arrives
    - Write property test: for any inbound message payload where the conversation exists in-memory, the conversation's `lastMessage` and `unreadCount` are updated
    - Verify test PASSES on unfixed code

  - **Preservation Test 2d — Pull-to-refresh triggers network fetch:**
    - Observe on unfixed code: `loadConversations()` when online calls `_conversationService.getConversations()` after the cache read
    - Write property test: with connectivity = true, `loadConversations()` always calls the network service regardless of cache state
    - Verify test PASSES on unfixed code

  - **Preservation Test 2e — Delete conversation removes cache entry:**
    - Observe on unfixed code: `deleteConversation()` removes the item from `_conversations` in-memory and calls `_cacheConversationsLocally()` and `deleteCachedMessages()`
    - Write property test: for any valid conversationId, after `deleteConversation()`, the id is absent from `chatProvider.conversations`
    - Verify test PASSES on unfixed code

  - **Preservation Test 2f — Theme toggle is independent:**
    - Observe on unfixed code: `ThemeProvider.setThemeMode()` correctly updates `themeMode` regardless of auth or cache state
    - Write a simple property test confirming this setter stores and returns the correct mode
    - Verify test PASSES on unfixed code

  - **IMPORTANT**: Property-based testing is recommended here (generate random inputs across the non-buggy domain) for stronger guarantees. At a minimum, write parameterised tests covering the cases above.
  - Verify ALL preservation tests PASS on UNFIXED code (this is the preserved baseline)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_

- [ ] 3. Fix all three offline persistence bugs

  - [ ] 3.1 Fix Bug 1 — Call `setSession` before `isLoggedin` check in `AuthProvider._initAuth()`
    - File: `lib/providers/auth_provider.dart`
    - In `_initAuth()`, after reading `session = _cacheService.getSession()` and confirming `hasSession = true`, add an `await Supabase.instance.client.auth.setSession(accessToken, refreshToken)` call using the stored tokens before any `_authService.isLoggedin` access or Supabase SDK calls
    - This ensures the Supabase SDK's `currentUser` is populated even on cold-boot-offline, so the `if (hasSession)` → `_loadUserFromCache()` path correctly sets `_currentUser`
    - Wrap the `setSession` call in a try-catch so that an expired token error (AuthException) falls through gracefully without crashing
    - In `_loadUserFromCache()`: add a defensive guard — if `_cacheService.chatCache` would throw (box not yet open), return `null` early. Use `Hive.isBoxOpen('chatCache')` as the guard condition
    - Fix the `Map` cast in `_loadUserFromCache()`: change `cachedUserData as Map<String, dynamic>` to use `Map<String, dynamic>.from(cachedUserData as Map)` (deep-copy cast) to prevent `_CastError` when Hive deserialises as `Map<dynamic, dynamic>`
    - _Bug_Condition: `isBugCondition_AuthOffline(X)` — device offline, `authBox` has `access_token` and `refresh_token`, `chatCache` has `current_user` key_
    - _Expected_Behavior: `initAuth'(X).isAuthenticated = TRUE` and `initAuth'(X).navigatedTo = '/home'` (from design Property 1)_
    - _Preservation: sign-out must still clear `authBox` and set `_currentUser = null` (design Preservation Req 3.1); online refresh path must continue to update `_currentUser` from server_
    - _Requirements: 2.1, 2.2_

  - [ ] 3.2 Fix Bug 2 — Add `_initialLoadDone` flag to `ChatProvider` and update `home_screen.dart` guard
    - File: `lib/providers/chat_provider.dart`
    - Add field `bool _initialLoadDone = false;` to the class body
    - Add getter `bool get initialLoadDone => _initialLoadDone;`
    - At the end of `loadConversations()` (after both the cache read path and the optional network refresh, i.e., just before the method returns), set `_initialLoadDone = true` and call `notifyListeners()` if it was previously `false`
    - File: `lib/screens/home_screen.dart`
    - In the `Consumer<ChatProvider>` builder, replace the current guard:
      ```dart
      // BEFORE (buggy):
      if (chatProvider.conversations.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      ```
      with:
      ```dart
      // AFTER (fixed):
      if (!chatProvider.initialLoadDone) {
        return const Center(child: CircularProgressIndicator());
      }
      if (conversations.isEmpty) {
        return EmptyConversations(
          icon: _currentTab == 0
              ? Icons.chat_bubble_outline_rounded
              : Icons.group_outlined,
          message: _currentTab == 0
              ? 'No conversations yet.\nStart a new chat!'
              : 'No groups yet.\nCreate a group!',
        );
      }
      ```
    - _Bug_Condition: `isBugCondition_SpinnerOnCache(X)` — Hive has cached conversations, in-memory list empty, load not yet complete_
    - _Expected_Behavior: `buildHomeScreen'(X).showsSpinner = FALSE` and `buildHomeScreen'(X).conversationsVisible = TRUE` (from design Property 2)_
    - _Preservation: spinner MUST still appear when `initialLoadDone = false` (genuinely loading); `EmptyConversations` MUST still appear when `initialLoadDone = true` and list is empty; pull-to-refresh must still work (design Req 3.5)_
    - _Requirements: 2.3, 2.4_

  - [ ] 3.3 Fix Bug 3 — Replace `NetworkImage` with `CachedNetworkImageProvider`/`CachedNetworkImage` in all avatar widgets
    - Ensure `cached_network_image` is in `pubspec.yaml` dependencies (it is already used in `message_bubble.dart` — confirm the import and version)
    - **`lib/widgets/home/conversation_tile.dart`** — `CircleAvatar.backgroundImage`:
      - Replace `NetworkImage(conv.displayAvatar)` with `CachedNetworkImageProvider(conv.displayAvatar)`
      - Add `import 'package:cached_network_image/cached_network_image.dart';`
    - **`lib/screens/chat_room_screen.dart`** — AppBar `CircleAvatar.backgroundImage`:
      - Replace `NetworkImage(conv.displayAvatar)` with `CachedNetworkImageProvider(conv.displayAvatar)`
      - Add `import 'package:cached_network_image/cached_network_image.dart';`
    - **`lib/screens/settings_screen.dart`**:
      - Main profile `CircleAvatar.backgroundImage`: replace `NetworkImage(avatarUrl)` with `CachedNetworkImageProvider(avatarUrl)`
      - Preset avatar row `CircleAvatar.backgroundImage`: replace each `NetworkImage(url)` with `CachedNetworkImageProvider(url)`
      - `_ImageViewerScreen` body: replace `Image.network(imageUrl, ...)` with `CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain, errorBuilder: (ctx, err, st) => const Icon(Icons.error, color: Colors.white, size: 64))`
      - Add `import 'package:cached_network_image/cached_network_image.dart';`
    - **`lib/screens/contact_info_screen.dart`** — header `CircleAvatar.backgroundImage`:
      - Replace `NetworkImage(avatarUrl)` with `CachedNetworkImageProvider(avatarUrl)`
      - Add `import 'package:cached_network_image/cached_network_image.dart';`
    - **`lib/screens/group_info_screen.dart`**:
      - Group header `CircleAvatar.backgroundImage`: replace `NetworkImage(updatedConv.avatarUrl!)` with `CachedNetworkImageProvider(updatedConv.avatarUrl!)`
      - `_showParticipantOptions` bottom sheet `CircleAvatar.backgroundImage`: replace `NetworkImage(participant.user!.avatarUrl)` with `CachedNetworkImageProvider(participant.user!.avatarUrl)`
      - `_ParticipantTile` `CircleAvatar.backgroundImage`: replace `NetworkImage(user!.avatarUrl)` with `CachedNetworkImageProvider(user!.avatarUrl)`
      - `_AddParticipantsSheet` `CircleAvatar.backgroundImage`: replace `NetworkImage(user.avatarUrl)` with `CachedNetworkImageProvider(user.avatarUrl)`
      - `_ImageViewerScreen` body: replace `Image.network(imageUrl, ...)` with `CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain, errorBuilder: (ctx, err, st) => const Icon(Icons.error, color: Colors.white, size: 64))`
      - Add `import 'package:cached_network_image/cached_network_image.dart';`
    - For every `CachedNetworkImageProvider` used as `backgroundImage` in a `CircleAvatar`, ensure the `CircleAvatar` still has its `child` fallback (initial-letter icon) for when the URL is empty — this is already present in all files, so no change needed there
    - _Bug_Condition: `isBugCondition_MediaNotPersisted(X)` — non-empty `profileImageUrl`, `imageProviderClass = NetworkImage`, `processWasKilled = TRUE`_
    - _Expected_Behavior: `renderAvatar'(X).imageLoadedFromDiskCache = TRUE` and `renderAvatar'(X).networkCallMade = FALSE` on relaunch (from design Property 3)_
    - _Preservation: initial-letter/icon fallback for empty URLs must continue to show; online image load must still succeed on first open; `CachedNetworkImage` in `message_bubble.dart` must remain unchanged_
    - _Requirements: 2.5, 2.6_

  - [ ] 3.4 Verify bug condition exploration test (Property 1) now passes
    - **Property 1: Expected Behavior** - Auth Offline Restore, Instant Cache Display, Media Persistence
    - **IMPORTANT**: Re-run the SAME three tests from task 1 — do NOT write new tests
    - The tests from task 1 encode the expected behavior for all three bug conditions
    - Re-run Bug 1 exploration test: assert `authProvider.isAuthenticated == true` with offline network and populated Hive — **EXPECTED OUTCOME: PASSES** (confirms Bug 1 fixed)
    - Re-run Bug 2 exploration test: assert `CircularProgressIndicator` is NOT shown on first frame when Hive has conversations — **EXPECTED OUTCOME: PASSES** (confirms Bug 2 fixed)
    - Re-run Bug 3 exploration test: assert avatar still renders from disk cache after `imageCache.clear()` and URL unavailability — **EXPECTED OUTCOME: PASSES** (confirms Bug 3 fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ] 3.5 Verify preservation tests still pass
    - **Property 2: Preservation** - All Existing Online Behaviors Unchanged
    - **IMPORTANT**: Re-run the SAME six preservation tests from task 2 — do NOT write new tests
    - Run tests 2a through 2f on the FIXED code
    - **EXPECTED OUTCOME**: All six tests PASS (confirms no regressions introduced by any of the three fixes)
    - If any preservation test fails, investigate which fix caused the regression and address it before continuing
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_

- [ ] 4. Checkpoint — Ensure all tests pass
  - Run the full test suite (`flutter test`)
  - Ensure all exploration tests (Property 1) pass — confirming all three bugs are fixed
  - Ensure all preservation tests (Property 2) pass — confirming no regressions
  - Do a manual smoke test: launch the app with airplane mode enabled (with a previously seeded Hive), confirm navigation goes to `/home` (not `/login`), conversations are visible without a spinner, and profile avatars display from cache
  - If any tests fail or questions arise, pause and ask the user before proceeding
