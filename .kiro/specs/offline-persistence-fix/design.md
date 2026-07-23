# Offline Persistence Fix — Bugfix Design

## Overview

The Flutter chat app (Supabase + Hive + Provider) suffers from three related offline-mode and
caching defects that together make the app completely non-functional when the device has no
internet connection.

**Bug 1 — Auth offline redirect**: `AuthProvider._initAuth()` calls `_loadUserFromCache()`
which accesses `_cacheService.chatCache` directly. `LocalCacheService` uses a singleton with a
`late Box _chatCache` field. If `initialize()` has not yet been awaited on the singleton before
`chatCache.get()` is called, a `LateInitializationError` is thrown and `_currentUser` stays
`null`, causing `isAuthenticated = false` and a redirect to `/login`. Additionally, when the
device is offline, `_authService.isLoggedin` reads `Supabase.instance.client.auth.currentUser`
which is `null` if the Supabase SDK has not restored the persisted session — meaning the
`else` branch (no cached session path) also fails to load the user, even if `authBox` holds a
valid access token. The correct approach is: (a) ensure `initialize()` is always awaited
before any `chatCache` access, and (b) restore the Supabase session from the stored tokens
before checking `_authService.isLoggedin`.

**Bug 2 — Spinner instead of cached conversations**: `home_screen.dart` checks
`chatProvider.conversations.isEmpty` and unconditionally renders `CircularProgressIndicator`
when that list is empty. `_load()` is posted to `addPostFrameCallback`, so the very first
`build()` call always sees an empty list and shows the spinner — even when Hive already holds
cached conversations. `ChatProvider.loadConversations()` does perform a cache-first read, but
the `notifyListeners()` it calls only reaches the widget after the spinner has already
rendered. The fix requires a `_initialLoadDone` flag (or equivalent sentinel) in
`ChatProvider` so the home screen can distinguish "still loading" from "loaded and genuinely
empty".

**Bug 3 — Media/profiles not persisted across restarts**: Profile images in
`conversation_tile.dart` and `chat_room_screen.dart` use `NetworkImage` directly — not
`CachedNetworkImage` — so they are never written to disk and disappear after a process kill.
`cached_network_image` in `message_bubble.dart` uses its own cache directory managed by the
`flutter_cache_manager` package, which is separate from `MediaCacheService`. When offline,
any profile avatar or group avatar that was not cached by `CachedNetworkImage`'s own mechanism
returns a broken image. The fix is to replace direct `NetworkImage` calls with
`CachedNetworkImage` (which persists to disk automatically), and to ensure `MediaCacheService`
integrates with `CachedNetworkImage`'s `BaseCacheManager` or serves local file paths when the
disk copy is available.

---

## Glossary

- **Bug_Condition (C)**: The condition that triggers one of the three bugs — offline auth
  failure, premature spinner display, or missing media persistence.
- **Property (P)**: The desired correct behavior when the bug condition holds — authenticated
  offline, instant cache display, and durable media storage respectively.
- **Preservation**: All existing online behaviors — sign-out, optimistic messages, realtime
  subscriptions, pull-to-refresh, delete conversation — that must remain unchanged.
- **`AuthProvider._initAuth()`**: The async constructor bootstrap in
  `lib/providers/auth_provider.dart` that initialises services and restores session state.
- **`LocalCacheService`**: A singleton in `lib/services/local_cache_service.dart` that wraps
  two Hive boxes (`authBox` and `chatCache`). The `late` fields are only safe after
  `initialize()` has been awaited.
- **`LocalCacheService.chatCache`**: The `Box` getter exposed for direct Hive key-value access
  by `AuthProvider`. Only valid after `initialize()`.
- **`ChatProvider.loadConversations()`**: The method in `lib/providers/chat_provider.dart`
  that performs a cache-first load from Hive, then a background network refresh.
- **`_initialLoadDone`**: The proposed boolean flag to be added to `ChatProvider` so
  `home_screen.dart` can tell "not started" from "loaded but empty".
- **`NetworkImage`**: Flutter's built-in image provider — fetches from network on every build,
  no disk persistence.
- **`CachedNetworkImage`**: Widget from the `cached_network_image` package that downloads and
  caches images to the device's file system via `flutter_cache_manager`.
- **`MediaCacheService`**: Service in `lib/services/media_cache_service.dart` that manually
  downloads and stores files at `documents/media_cache/<sha256(url)>`.

---

## Bug Details

### Bug Condition 1 — Auth Offline Redirect

The bug manifests on cold app launch with no network when `Supabase.instance.client.auth
.currentUser` is `null` (SDK has not restored the persisted session yet) and/or when
`LocalCacheService._chatCache` is accessed before `initialize()` is awaited.

**Formal Specification:**
```
FUNCTION isBugCondition_AuthOffline(X)
  INPUT: X of type AppLaunchContext
  OUTPUT: boolean

  RETURN X.hasNetworkConnection = FALSE
    AND X.hiveAuthBoxHasAccessToken = TRUE
    AND X.hiveChatCacheHasCurrentUser = TRUE
    AND (
      X.supabaseSDKCurrentUserIsNull = TRUE   // session not yet restored
      OR X.localCacheServiceNotInitialized = TRUE  // late field accessed early
    )
END FUNCTION
```

**Examples:**
- Device offline, valid token in `authBox`, `current_user` key in `chatCache` → app redirects
  to `/login` (bug). Expected: navigates to `/home` with `_currentUser` restored from cache.
- Device offline, no token in `authBox` → app correctly redirects to `/login` (not a bug).
- Device online → `_authService.isLoggedin` is true, Supabase refreshes session, no bug.

**Root locus in code:**
- `auth_provider.dart` lines 31–35: `_initAuth()` awaits `_cacheService.initialize()` ✓ but
  then calls `_authService.isLoggedin` which checks the live Supabase SDK session — this is
  `null` offline if Supabase hasn't replayed the stored token yet.
- `auth_provider.dart` line 38: when `hasSession = true` and offline, `_loadUserFromCache()`
  is called — this is the correct path, but the Supabase SDK must first be told to recover
  the session from its own persistence layer before `isLoggedin` is checked in the `else`
  branch.

### Bug Condition 2 — Spinner Instead of Cached Conversations

The bug manifests on the first `build()` of `HomeScreen` before `loadConversations()` has
populated `_conversations` in memory, even though Hive holds cached data.

**Formal Specification:**
```
FUNCTION isBugCondition_SpinnerOnCache(X)
  INPUT: X of type HomeScreenBuildContext
  OUTPUT: boolean

  RETURN X.hiveChatCacheHasConversations = TRUE
    AND X.chatProviderConversations.isEmpty = TRUE
    AND X.chatProviderInitialLoadDone = FALSE
END FUNCTION
```

**Examples:**
- App launches, Hive has 5 cached conversations, `loadConversations()` has not yet finished →
  spinner shown (bug). Expected: conversations listed immediately once cache is read.
- App launches, Hive is empty, `loadConversations()` has not finished → spinner shown
  (acceptable — no data to show, but per requirement 3.7 a spinner is only acceptable when
  data is genuinely unavailable).
- `loadConversations()` has completed and returned 0 conversations → `EmptyConversations`
  widget shown (correct).

**Root locus in code:**
- `home_screen.dart` line 107: `if (chatProvider.conversations.isEmpty)` fires before
  `loadConversations()` completes because `_load()` is posted via `addPostFrameCallback`.
- `chat_provider.dart` `loadConversations()`: already does synchronous cache-first read and
  calls `notifyListeners()`, but there is no `_initialLoadDone` flag, so the widget cannot
  distinguish "not started" from "done and empty".

### Bug Condition 3 — Media/Profiles Not Persisted Across Restarts

The bug manifests when the app process is killed: all `NetworkImage`-backed profile pictures
vanish because `NetworkImage` has no disk cache.

**Formal Specification:**
```
FUNCTION isBugCondition_MediaNotPersisted(X)
  INPUT: X of type ProfileImageRenderEvent
  OUTPUT: boolean

  RETURN X.profileImageUrl.isNotEmpty = TRUE
    AND X.imageProviderClass = NetworkImage   // not CachedNetworkImage
    AND X.processWasKilled = TRUE
END FUNCTION
```

**Examples:**
- User seen online, their avatar loads. App killed and reopened offline → broken avatar icon
  (bug). Expected: avatar served from disk cache.
- Group avatar URL present, app restarted offline → broken icon (bug). Expected: cached icon.
- Image message with `CachedNetworkImage` → survives restart (not a bug for image messages).
- User with no avatar URL → placeholder initial letter, no network needed (not a bug).

**Root locus in code:**
- `conversation_tile.dart` line 36: `backgroundImage: NetworkImage(conv.displayAvatar)`.
- `chat_room_screen.dart` AppBar: `backgroundImage: NetworkImage(conv.displayAvatar)`.
- `settings_screen.dart`: `NetworkImage(avatarUrl)` and `NetworkImage(url)` for preset
  avatars.
- `contact_info_screen.dart` and `group_info_screen.dart` (not yet read — likely same issue).

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Sign-out MUST continue to clear `authBox` session tokens and navigate to `/login`.
- Optimistic text messages MUST continue to append a temp message immediately and replace
  with the server-confirmed message on success.
- Optimistic media messages MUST continue to append a temp message and upload to Supabase.
- Realtime subscription updates via `ChatService.subscribeToConversations()` MUST continue
  to update the in-memory conversation list and persist to Hive.
- Pull-to-refresh on `HomeScreen` MUST continue to trigger a full Supabase fetch.
- Delete/clear conversation MUST continue to remove Hive cache entries.
- Background refresh on connectivity restored MUST continue to fire.
- Theme toggle MUST continue to work independently of any cache or auth changes.

**Scope:**
All inputs that do NOT trigger any of the three bug conditions should be completely unaffected.
This includes all online-mode flows, all user-initiated actions (send, delete, forward), and
all non-auth navigation.

---

## Hypothesized Root Cause

### Bug 1 — Auth Offline Redirect

1. **Supabase SDK session not restored before isLoggedin check**: The Supabase Flutter SDK
   persists sessions internally (via `flutter_secure_storage` or `shared_preferences`). On a
   fresh process start, `Supabase.initialize()` triggers async session restoration. If
   `_initAuth()` runs before that async work completes, `currentUser` is `null` even though
   a valid session exists. The fix is to `await` `Supabase.instance.client.auth.recoverSession()`
   using the stored tokens from `authBox` before checking `isLoggedin`.

2. **`LocalCacheService.chatCache` late field accessed without initialization guard**: The
   singleton pattern means the `late Box _chatCache` could theoretically be accessed before
   `initialize()` if the singleton is obtained from another code path. The current
   `_initAuth()` does await `initialize()` correctly, but `_loadUserFromCache()` accesses
   `_cacheService.chatCache` which throws if the late field is unset. Wrapping with a null
   check / isOpen guard is defensive hardening.

### Bug 2 — Spinner Instead of Cached Conversations

1. **No "initial load done" sentinel in ChatProvider**: `loadConversations()` is async and
   `home_screen.dart` renders on the first synchronous build before the cache read completes.
   Adding `bool _initialLoadDone = false` (set to `true` at the end of `loadConversations()`)
   allows the UI to distinguish "loading" from "empty after load".

2. **First build fires before `addPostFrameCallback` completes**: `_load()` is scheduled via
   `addPostFrameCallback`, so the very first paint always hits the empty-list branch.
   Initializing `_initialLoadDone = false` and checking it in the UI guard resolves this.

### Bug 3 — Media/Profiles Not Persisted

1. **`NetworkImage` used instead of `CachedNetworkImage` for all profile/group avatars**:
   `NetworkImage` is a Flutter built-in with no disk persistence. Replacing it with
   `CachedNetworkImage` (or `CachedNetworkImageProvider` as a `backgroundImage`) gives
   automatic file-system caching via `flutter_cache_manager` with zero extra code.

2. **`MediaCacheService` not integrated with profile image loading**: `MediaCacheService`
   correctly caches files for media messages but is never called for profile images. With
   `CachedNetworkImage`, this is not needed — the package handles it. However, image messages
   that use `CachedNetworkImage` already benefit from this; the gap is purely in the
   `NetworkImage` usages.

---

## Correctness Properties

Property 1: Bug Condition — Auth Offline Restore

_For any_ app launch context where `isBugCondition_AuthOffline` returns true (device offline,
valid session token in Hive `authBox`, serialised user in `chatCache`), the fixed
`_initAuth()` SHALL set `_currentUser` to the deserialised `UserModel` from `chatCache`,
set `isAuthenticated` to `true`, and result in navigation to `/home` — without making any
network call.

**Validates: Requirements 2.1, 2.2**

Property 2: Bug Condition — Instant Cache Display

_For any_ home screen build context where `isBugCondition_SpinnerOnCache` returns true (Hive
has cached conversations, in-memory list is empty, load not yet complete), the fixed
`HomeScreen` build method SHALL NOT render `CircularProgressIndicator` and SHALL instead
render the cached conversation list as soon as the first `notifyListeners()` fires from
`loadConversations()` cache read — with zero network dependency.

**Validates: Requirements 2.3, 2.4**

Property 3: Bug Condition — Media/Profile Persistence

_For any_ profile image render event where `isBugCondition_MediaNotPersisted` returns true
(non-empty URL rendered via `NetworkImage`, process killed and restarted), the fixed widgets
SHALL serve the profile image from the on-device file-system cache established by
`CachedNetworkImage`, producing a valid image display with no network call.

**Validates: Requirements 2.5, 2.6**

Property 4: Preservation — All Other Behaviors Unchanged

_For any_ input that does NOT satisfy any of the three bug conditions (online mode operations,
sign-out, send message, realtime updates, pull-to-refresh, delete conversation, theme toggle),
the fixed code SHALL produce exactly the same observable behavior as the original code,
preserving all existing functionality.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10**

---

## Fix Implementation

### Changes Required

#### Bug 1 — Auth Offline Redirect

**File:** `lib/providers/auth_provider.dart`
**Function:** `_initAuth()`

**Specific Changes:**
1. **Recover Supabase session from stored tokens before checking `isLoggedin`**: After reading
   `authBox` tokens and confirming `hasSession = true`, call
   `Supabase.instance.client.auth.recoverSession(storedAccessToken)` (or set the session via
   `setSession(accessToken, refreshToken)`) so the SDK's `currentUser` is populated before any
   SDK calls are made. This ensures `isLoggedin` is accurate even on cold boot offline.

2. **Defensive `initialize()` call in `_loadUserFromCache()`**: Although `_initAuth()` already
   awaits `_cacheService.initialize()`, add a guard in `_loadUserFromCache()` to ensure the
   `chatCache` box is open before accessing it, preventing `LateInitializationError` if the
   method is ever called from another code path.

3. **Type-safe Hive map reading**: `_cacheService.chatCache.get('current_user')` returns
   `dynamic`; Hive deserialises maps as `Map<dynamic, dynamic>`. The cast to
   `Map<String, dynamic>` should use a deep-copy conversion (`map.cast<String, dynamic>()` or
   a helper) rather than a direct cast, to prevent runtime `_CastError` when reading back the
   stored user.

#### Bug 2 — Spinner Instead of Cached Conversations

**File:** `lib/providers/chat_provider.dart`
**Function:** `loadConversations()`

**Specific Changes:**
1. **Add `bool _initialLoadDone = false` field**: Initialise to `false` in the class body.
   Set to `true` at the end of `loadConversations()` (after both the cache read and the
   optional network refresh, so it reflects "at least one load attempt has completed").

2. **Expose `bool get initialLoadDone => _initialLoadDone` getter**.

**File:** `lib/screens/home_screen.dart`
**Widget:** `HomeScreen.build()` — Consumer body

**Specific Changes:**
3. **Replace the unconditional spinner with a load-aware guard**:

   ```dart
   // Before (buggy):
   if (chatProvider.conversations.isEmpty) {
     return const Center(child: CircularProgressIndicator());
   }

   // After (fixed):
   if (!chatProvider.initialLoadDone) {
     return const Center(child: CircularProgressIndicator());
   }
   if (conversations.isEmpty) {
     return EmptyConversations(...);
   }
   ```

   The spinner is shown only while `_initialLoadDone` is false (i.e., before the first cache
   read completes — typically < 50 ms). Once at least one load attempt has finished, either
   the conversation list or the empty-state widget is rendered.

#### Bug 3 — Media/Profiles Not Persisted

**Files:**
- `lib/widgets/home/conversation_tile.dart`
- `lib/screens/chat_room_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/contact_info_screen.dart` (verify and fix if present)
- `lib/screens/group_info_screen.dart` (verify and fix if present)

**Specific Changes:**
1. **Replace `NetworkImage(url)` with `CachedNetworkImageProvider(url)` as the
   `backgroundImage`** in every `CircleAvatar` that shows a profile or group avatar. The
   `CachedNetworkImageProvider` is a drop-in replacement for `NetworkImage` and writes the
   image to the `flutter_cache_manager` disk cache automatically.

2. **Replace `Image.network(url)` with `CachedNetworkImage(imageUrl: url)` widget** in
   `settings_screen.dart` `_ImageViewerScreen` and any other full-screen image viewers that
   use the Flutter built-in network image widget.

3. **Add `errorWidget` and `placeholder` on every `CachedNetworkImage` call** that doesn't
   already have them, so offline rendering degrades gracefully to the initial-letter avatar
   or an icon instead of a broken-image box.

4. **Cache profile avatars via `MediaCacheService` on first load (optional enhancement)**:
   When a `UserModel` or `ConversationModel` with a non-empty `avatarUrl` is saved to Hive,
   also call `MediaCacheService().cacheMedia(avatarUrl)` in the background. This pre-warms
   `CachedNetworkImage`'s cache before the widget tree tries to display it. This is a
   belt-and-suspenders measure — `CachedNetworkImage` caches on first widget render by
   default, so this is only needed if the image must be available before the widget is ever
   shown.

---

## Testing Strategy

### Validation Approach

Testing follows a two-phase approach: first surface counterexamples on unfixed code to confirm
root causes, then verify the fixes are correct and that existing behaviors are preserved.

---

### Exploratory Bug Condition Checking

**Goal**: Reproduce each bug deterministically before touching any production code, to confirm
the root cause analysis. These tests are expected to FAIL on the current codebase.

**Test Plan**:

**Bug 1 — Auth offline:**
1. **Hive-populated cold-boot test**: Pre-populate `authBox` with a fake access token and
   `chatCache` with a serialised `UserModel`. Call `_initAuth()` with network mocked as
   offline (override `OfflineService.hasConnection()` to return `false`) and
   `Supabase.client.auth.currentUser` stubbed to `null`. Assert `isAuthenticated == true` and
   `currentUser != null` — this will FAIL on the current code if `recoverSession` is not
   called.

2. **Late field guard test**: Call `LocalCacheService().chatCache` before calling
   `initialize()`. Expect a `LateInitializationError` — confirms the need for the guard.

**Bug 2 — Spinner:**
3. **First-build spinner test**: Render `HomeScreen` in a widget test with a `ChatProvider`
   whose `loadConversations` is mocked to complete after a 100 ms delay, pre-populate
   `chatCache` with one conversation. Assert that a `CircularProgressIndicator` is shown on
   the initial frame — this CONFIRMS the bug.

4. **Post-load display test**: After `loadConversations` mock completes, pump the widget and
   assert that the `CircularProgressIndicator` is gone and the conversation tile is visible —
   this will PASS on the current code, showing data eventually shows up, just not instantly.

**Bug 3 — Media persistence:**
5. **NetworkImage no-disk-cache test**: Render a `ConversationTile` with a non-empty
   `displayAvatar`, simulate a process restart by clearing `PaintingBinding.instance
   .imageCache`, make the URL unreachable (mock `http` to return 404), and assert a broken
   image is shown — confirms `NetworkImage` does not persist to disk.

**Expected Counterexamples:**
- Bug 1: `isAuthenticated == false` despite valid Hive session (auth offline failure).
- Bug 2: `CircularProgressIndicator` rendered on first frame despite cached data in Hive.
- Bug 3: Profile avatar shows broken image after cache clear and URL unavailability.

---

### Fix Checking

**Goal**: Verify that for all inputs where each bug condition holds, the fixed code produces
the correct output.

**Pseudocode:**
```
FOR ALL X WHERE isBugCondition_AuthOffline(X) DO
  result ← _initAuth_fixed(X)
  ASSERT result.isAuthenticated = TRUE
  ASSERT result.currentUser != NULL
  ASSERT result.navigatedTo = '/home'
END FOR

FOR ALL X WHERE isBugCondition_SpinnerOnCache(X) DO
  result ← buildHomeScreen_fixed(X)
  ASSERT result.showsSpinner = FALSE
  ASSERT result.conversationsVisible = TRUE
END FOR

FOR ALL X WHERE isBugCondition_MediaNotPersisted(X) DO
  result ← renderAvatar_fixed(X)
  ASSERT result.imageLoadedFromDiskCache = TRUE
  ASSERT result.networkCallMade = FALSE  // served from cache
END FOR
```

---

### Preservation Checking

**Goal**: Verify that for all inputs where none of the bug conditions hold, the fixed code
produces the same result as the original code.

**Pseudocode:**
```
FOR ALL X WHERE NOT isBugCondition_AuthOffline(X)
              AND NOT isBugCondition_SpinnerOnCache(X)
              AND NOT isBugCondition_MediaNotPersisted(X) DO
  ASSERT F(X) = F'(X)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because
it generates many test cases automatically across the input domain, catching edge cases that
manual unit tests miss, and providing strong guarantees that behavior is unchanged.

**Test Cases:**
1. **Sign-out preservation**: Call `signOut()` and verify `authBox` is cleared and
   `_currentUser` is null — must work identically before and after the fix.
2. **Optimistic send preservation**: Mock network as online, call `sendMessage()`, verify temp
   message appears immediately and is replaced on success.
3. **Realtime subscription preservation**: Verify `listenToConversations()` continues to
   update `_conversations` and persist to Hive when a new message arrives.
4. **Pull-to-refresh preservation**: Verify `loadConversations()` hits the network and updates
   the list when online.
5. **Theme toggle preservation**: Toggle `ThemeProvider.setThemeMode()` and verify theme
   changes — must be unaffected by any auth or cache changes.

---

### Unit Tests

- Test `_initAuth()` with offline network + populated Hive → `isAuthenticated == true`.
- Test `_loadUserFromCache()` with uninitialized `LocalCacheService` → returns `null` (no
  crash).
- Test `Hive Map` cast safety: store a `Map<String, dynamic>` in Hive, retrieve it, and
  confirm `UserModel.fromJson()` succeeds without `_CastError`.
- Test `ChatProvider.loadConversations()` sets `_initialLoadDone = true` after completion.
- Test `ChatProvider.loadConversations()` calls `notifyListeners()` with cached data before
  any network call.
- Test `HomeScreen` widget with `initialLoadDone = false` shows spinner.
- Test `HomeScreen` widget with `initialLoadDone = true` and empty list shows `EmptyConversations`.
- Test `HomeScreen` widget with `initialLoadDone = true` and non-empty list shows tiles.

### Property-Based Tests

- Generate random `UserModel` instances, serialise to Hive, deserialise, and assert equality
  (validates the Map cast fix does not corrupt data).
- Generate random lists of `ConversationModel` instances, cache to Hive, restore, and assert
  the restored list equals the original (validates conversation cache round-trip).
- Generate random `avatarUrl` strings (empty, HTTP, HTTPS, local path), render `ConversationTile`,
  and assert no `LateInitializationError` or unhandled exception is thrown.
- Generate random connectivity states (online/offline alternating) and verify
  `loadConversations()` always terminates with `_initialLoadDone == true`.

### Integration Tests

- Full offline launch flow: seed Hive, kill process (clear in-memory state), relaunch with
  mocked network offline, assert user is authenticated and home screen shows cached
  conversations.
- Cache-first display: seed Hive conversations, open `HomeScreen`, assert conversation list
  is visible before 200 ms elapses (no spinner for users with cached data).
- Profile image persistence: display conversation tile with avatar URL, restart app with URL
  unreachable, assert avatar is still visible (served from `CachedNetworkImage` disk cache).
- Online → offline transition: load fresh data online, then switch to offline, navigate away
  and back, assert conversations and messages are still visible.
