# Bugfix Requirements Document

## Introduction

The Flutter chat app (Supabase + Hive + Provider) has a cluster of related offline-mode and
caching defects. When the device has no internet connection the app incorrectly redirects the
user to the login screen, shows an empty conversation list, and gives no access to previously
seen messages, media, or profile pictures. The root causes are: auth-state checks that depend
on a live network call instead of the locally persisted session; a `home_screen.dart` loading
gate that shows a spinner whenever `conversations` is empty (even when the cache has not yet
been read); and media / profile images that are never durably persisted across app restarts.
These bugs together make the app completely unusable offline and create unnecessary delays
online.

---

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the app is launched with no internet connection AND a valid session token exists in
Hive `authBox` THEN the system redirects the user to the login screen instead of navigating to
the home screen.

1.2 WHEN `AuthProvider._initAuth()` runs offline THEN the system leaves `_currentUser` as
`null` (because `_loadUserFromCache()` returns `null` when `chatCache` is not yet initialised
at the moment of the call) causing `isAuthenticated` to be `false`.

1.3 WHEN the home screen builds with an empty `conversations` list THEN the system renders a
`CircularProgressIndicator` unconditionally, even when cached conversations are available in
Hive `chatCache`.

1.4 WHEN `loadConversations()` is called offline THEN the system reads from cache correctly in
isolation, but `home_screen.dart` checks `chatProvider.conversations.isEmpty` before the async
`loadConversations()` call completes and renders the spinner, giving the visual appearance that
data is unavailable.

1.5 WHEN the app process is killed and restarted THEN the system loses all in-memory state and
does NOT automatically restore conversations, messages, user profile pictures, group profile
pictures, or other users' profile pictures from Hive or the file-system media cache.

1.6 WHEN media messages (images, files, voice) or profile photos are received online THEN the
system fetches them through `cached_network_image` or `http.get` but does NOT guarantee they
are written to a durable on-device path that survives app restarts and is served locally when
offline.

1.7 WHEN the app is online and the user opens the home screen THEN the system waits for the
Supabase network response before displaying any conversations, instead of showing cached data
immediately.

---

### Expected Behavior (Correct)

2.1 WHEN the app is launched with no internet connection AND a valid session token exists in
Hive `authBox` THEN the system SHALL restore `_currentUser` from `chatCache` and set
`isAuthenticated` to `true`, navigating the user to the home screen without requiring a network
call.

2.2 WHEN `AuthProvider._initAuth()` runs offline AND a cached user object exists in `chatCache`
under the key `current_user` THEN the system SHALL call `_cacheService.initialize()` before
attempting to read from `chatCache`, ensuring the Hive box reference is valid, and SHALL set
`_currentUser` to the deserialised `UserModel`.

2.3 WHEN the home screen builds THEN the system SHALL display cached conversations immediately
(zero-delay) if `chatProvider.conversations` is non-empty, and SHALL show the empty-state
widget (not a spinner) only when the list is empty after the initial load attempt completes.

2.4 WHEN `loadConversations()` is called (online or offline) THEN the system SHALL synchronously
populate `_conversations` from Hive cache before any `await` that touches the network, so that
the UI receives a non-empty list on the very first `notifyListeners()` call.

2.5 WHEN the app process is killed and restarted THEN the system SHALL restore conversations,
messages, the current user's profile, and cached participant/other-user profiles from Hive so
that the app is functional with zero-latency before any network response arrives.

2.6 WHEN media messages (images, files, voice) or profile photos are fetched online THEN the
system SHALL write them to the `MediaCacheService` local file cache AND SHALL serve them from
that file cache on subsequent opens, including when the device is offline.

2.7 WHEN the app is online and the user opens the home screen THEN the system SHALL serve
conversations from cache first (cache-first strategy) and SHALL trigger a background Supabase
fetch that silently updates the list, with no visible loading delay for data younger than 3–4
days.

---

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user explicitly signs out THEN the system SHALL CONTINUE TO clear the Hive session
tokens and navigate to the login screen.

3.2 WHEN the user is online and sends a text message THEN the system SHALL CONTINUE TO
optimistically append a temporary message to the list and replace it with the server-confirmed
message on success.

3.3 WHEN the user is online and sends a media message THEN the system SHALL CONTINUE TO
optimistically append a temporary message and upload the file to Supabase storage.

3.4 WHEN the device comes back online after being offline THEN the system SHALL CONTINUE TO
trigger a background refresh of conversations and messages from Supabase.

3.5 WHEN the user pulls-to-refresh on the home screen THEN the system SHALL CONTINUE TO fetch
fresh conversations from Supabase and update the local cache.

3.6 WHEN a new message arrives via the Supabase realtime subscription THEN the system SHALL
CONTINUE TO update the conversation list in memory and persist the updated list to Hive cache.

3.7 WHEN conversations or messages that are older than 3–4 days and have not been recently
cached are requested offline THEN the system SHALL CONTINUE TO show a loading indicator (these
are the only scenarios where a loader is acceptable).

3.8 WHEN the user deletes a conversation or clears a chat THEN the system SHALL CONTINUE TO
remove the corresponding Hive cache entries for messages and update the conversations cache.

3.9 WHEN a Supabase network error occurs during background refresh THEN the system SHALL
CONTINUE TO keep displaying the cached data without crashing or clearing the UI.

3.10 WHEN the `ThemeProvider` toggle is changed THEN the system SHALL CONTINUE TO apply the
selected theme (light/dark) across the app, unaffected by any cache or auth changes.

---

## Bug Condition Pseudocode

### Bug Condition Functions

```pascal
// Bug 1 – Auth offline redirect
FUNCTION isBugCondition_AuthOffline(X)
  INPUT: X of type AppLaunchContext
  OUTPUT: boolean
  RETURN X.hasNetworkConnection = FALSE
    AND X.hiveAuthBoxHasAccessToken = TRUE
    AND X.hiveChatCacheHasCurrentUser = TRUE
END FUNCTION

// Bug 2 – Spinner shown instead of cached conversations
FUNCTION isBugCondition_SpinnerOnCache(X)
  INPUT: X of type HomeScreenBuildContext
  OUTPUT: boolean
  RETURN X.hiveChatCacheHasConversations = TRUE
    AND X.conversationsListInMemory.isEmpty = TRUE
    AND X.loadConversationsCompleted = FALSE
END FUNCTION

// Bug 3 – Media/profiles not persisted across restarts
FUNCTION isBugCondition_MediaNotPersisted(X)
  INPUT: X of type MediaFetchEvent
  OUTPUT: boolean
  RETURN X.mediaFetchedOnline = TRUE
    AND X.writtenToLocalFileCache = FALSE
END FUNCTION
```

### Fix-Checking Properties

```pascal
// Property: Fix Checking – Auth Offline
FOR ALL X WHERE isBugCondition_AuthOffline(X) DO
  result ← initAuth'(X)
  ASSERT result.isAuthenticated = TRUE
  ASSERT result.navigatedTo = '/home'
END FOR

// Property: Fix Checking – Instant Cache Display
FOR ALL X WHERE isBugCondition_SpinnerOnCache(X) DO
  result ← buildHomeScreen'(X)
  ASSERT result.showsSpinner = FALSE
  ASSERT result.conversationsVisible = TRUE
END FOR

// Property: Fix Checking – Media Persisted
FOR ALL X WHERE isBugCondition_MediaNotPersisted(X) DO
  result ← fetchMedia'(X)
  ASSERT result.storedInLocalFileCache = TRUE
  ASSERT result.servedFromLocalCacheWhenOffline = TRUE
END FOR

// Property: Preservation Checking
FOR ALL X WHERE NOT isBugCondition_AuthOffline(X)
              AND NOT isBugCondition_SpinnerOnCache(X)
              AND NOT isBugCondition_MediaNotPersisted(X) DO
  ASSERT F(X) = F'(X)   // all other behaviors unchanged
END FOR
```
