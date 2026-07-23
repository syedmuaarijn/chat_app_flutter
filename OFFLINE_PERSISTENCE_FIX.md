# Offline Persistence Fix

## Problem Summary

When users had WiFi on, opened the app, then turned WiFi off:
1. ✅ App behaved normally initially - chats and messages showed
2. ❌ After navigating back from chat screens, chats and groups disappeared
3. ❌ Screen showed "No conversations yet. Start a new chat!"
4. ❌ When closing and reopening the app in offline mode, user stayed logged in but chats wouldn't show

## Root Causes Identified

### 1. Unconditional Network Refresh on Navigation
**Problem**: Every time the user navigated back from a chat screen or settings, `loadConversations()` was called unconditionally, even when offline.

**Impact**: When offline, the network fetch would fail and potentially overwrite the in-memory conversations with an empty list or stale data.

**Files Affected**: `lib/screens/home_screen.dart`

### 2. Realtime Subscription Triggering Offline Refreshes
**Problem**: The realtime subscription's `onRefresh` callback was calling `loadConversations()` unconditionally whenever messages or conversations were updated. When the connection was lost, Supabase might fire error/status change events that triggered unnecessary refreshes.

**Impact**: Offline refresh attempts could clear the in-memory conversations that were loaded from cache.

**Files Affected**: `lib/providers/chat_provider.dart`

### 3. Network Fetch Overwriting Good Cache Data
**Problem**: In `loadConversations()`, when the network fetch succeeded but returned an empty list (or failed with an error after a partial load), it would unconditionally overwrite `_conversations` with the fresh data, even if the cached data was better.

**Impact**: Good cached data was being replaced with empty or incomplete network responses.

**Files Affected**: `lib/providers/chat_provider.dart`

## Solutions Implemented

### Fix 1: Guard Network Refreshes After Navigation
**Change**: Modified `_openConversation()`, `_openNewChat()`, `_openCreateGroup()`, and `_openSettings()` in `home_screen.dart` to check if the device is online before calling `loadConversations()`.

```dart
// Before
.then((_) {
  if (mounted) context.read<ChatProvider>().loadConversations();
});

// After
.then((_) {
  if (!mounted) return;
  _offlineService.hasConnection().then((isOnline) {
    if (isOnline && mounted) {
      context.read<ChatProvider>().loadConversations();
    }
  });
});
```

### Fix 2: Guard Realtime Subscription Refreshes
**Change**: Modified `listenToConversations()` in `chat_provider.dart` to check connectivity before refreshing when realtime events fire.

```dart
// Before
onRefresh: () {
  loadConversations();
},

// After
onRefresh: () async {
  // Only refresh if we're online to avoid clearing cached data
  final isOnline = await _offlineService.hasConnection();
  if (isOnline) {
    loadConversations();
  } else {
    debugPrint('Skipping conversation refresh - offline');
  }
},
```

### Fix 3: Preserve Cache When Network Returns Empty
**Change**: Modified `loadConversations()` to only update `_conversations` if the network fetch returns data OR if the current list is empty. This prevents good cached data from being replaced with empty network responses.

```dart
// Before
if (isOnline) {
  try {
    final freshConversations = await _conversationService.getConversations();
    _conversations = freshConversations;  // Always overwrites!
    await _cacheConversationsLocally();
    notifyListeners();
  } catch (e) {
    _error = e.toString();
    // ...
  }
}

// After
if (isOnline) {
  try {
    final freshConversations = await _conversationService.getConversations();
    // Only update if we actually got data, preserving cache on failure
    if (freshConversations.isNotEmpty || _conversations.isEmpty) {
      _conversations = freshConversations;
    }
    await _cacheConversationsLocally();
    notifyListeners();
  } catch (e) {
    debugPrint('Network fetch failed, keeping cached conversations: $e');
    _error = e.toString();
    // Keep using cached data that's already loaded
  }
}
```

## Testing Recommendations

### Test Scenario 1: WiFi ON → OFF During App Use
1. Open app with WiFi ON
2. Verify chats and groups load
3. Turn WiFi OFF
4. Open a chat, send messages (should fail gracefully)
5. Navigate back to home screen
6. **Expected**: Chats and groups still visible from cache

### Test Scenario 2: App Restart While Offline
1. Close app completely
2. Ensure WiFi is OFF
3. Reopen app
4. **Expected**: 
   - User stays logged in
   - Chats and groups show from cache
   - Can view previously loaded messages

### Test Scenario 3: Navigation While Offline
1. Open app with WiFi ON
2. Turn WiFi OFF
3. Navigate through: Settings → Back → Chat → Back → New Chat → Back
4. **Expected**: Conversations remain visible throughout

### Test Scenario 4: Offline → Online Transition
1. Start offline with cached conversations showing
2. Turn WiFi ON
3. Pull to refresh or wait for auto-refresh
4. **Expected**: Fresh data loads and updates UI smoothly

## Files Modified

1. **lib/providers/chat_provider.dart**
   - Modified `loadConversations()` to preserve cache when network fails
   - Modified `listenToConversations()` to check connectivity before refreshing

2. **lib/screens/home_screen.dart**
   - Added `OfflineService` instance
   - Modified navigation callbacks to check connectivity before reloading
   - Added proper mounted checks across async gaps

## Dependencies

- Uses existing `OfflineService` for connectivity detection
- Uses existing `LocalCacheService` (Hive) for data persistence
- No new dependencies required

## Performance Impact

- **Positive**: Eliminates unnecessary network calls when offline
- **Positive**: Reduces UI flicker from data clearing/reloading
- **Neutral**: Adds lightweight connectivity checks before each refresh
- **Overall**: Improved perceived performance, especially on poor connections

## Backward Compatibility

✅ All changes are backward compatible. The fixes only add conditional logic around existing functionality without changing any data structures or APIs.
