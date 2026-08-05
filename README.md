# Yapp — Flutter Chat App

Yapp is a full-featured, real-time chat application built with Flutter and Supabase. It supports one-on-one messaging, group chats, live voice and video calls via Agora, a built-in AI assistant powered by Google Gemini, rich media sharing, and a polished glassmorphism UI with light/dark theme support.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Screens & Navigation](#screens--navigation)
- [State Management](#state-management)
- [Backend — Supabase](#backend--supabase)
- [Edge Functions](#edge-functions)
- [AI Assistant (Yapp AI)](#ai-assistant-yapp-ai)
- [Voice & Video Calls (Agora)](#voice--video-calls-agora)
- [Local Storage & Offline Support](#local-storage--offline-support)
- [UI & Theming](#ui--theming)
- [Key Dependencies](#key-dependencies)
- [Getting Started](#getting-started)
- [Environment & Secrets](#environment--secrets)

---

## Features

### Messaging
- Real-time one-on-one and group conversations powered by Supabase Realtime
- Text messages, emoji picker, file attachments, and image sharing
- Voice message recording and playback (via `record` + `just_audio`)
- Message delivery receipts: sent, delivered, and read status
- Message forwarding and per-message deletion
- Long-press context menu for message actions
- Date separators in chat history
- Inline media preview and file opening via `open_filex`

### Group Chats
- Create groups with a custom name and selected participants
- Group info screen with member management
- Groups shown in a dedicated tab separate from direct chats

### Voice & Video Calls
- One-on-one audio and video calling using the Agora RTC Engine v6
- Secure Agora token generation via a Supabase Edge Function (server-side, not client-side)
- Incoming call screen with ringtone playback (`flutter_ringtone_player`)
- Call history log in the Calls tab
- Call signaling via Supabase Realtime channels

### AI Assistant — Yapp AI
- Dedicated AI chat screen with a custom avatar
- Powered by Google Gemini 3.5 Flash via a Supabase Edge Function
- Server-Sent Events (SSE) streaming — responses appear word by word with a typewriter effect
- Full conversation history stored in Supabase (`ai_messages` table), loaded on session start
- Context window: last 12 messages retrieved server-side to prevent prompt injection
- Clear chat history with confirmation dialog
- Greeting message shown when chat is empty

### Authentication
- Email/password sign-up and sign-in
- Forgot password and password reset flows (deep link / OTP)
- Session persistence via Hive local storage
- Splash screen that routes to onboarding, login, or home based on session state

### User Profiles
- Avatar selection from a built-in asset library
- Display name and bio editing
- Profile settings screen accessible from the home app bar

### Contacts & User Discovery
- New Chat screen with full user search
- Block/unblock users (`block_service.dart`)
- Contact info screen showing shared conversation details

### Connectivity & Offline Support
- `connectivity_plus` detects network state changes
- Offline message cache via Hive (`chatCache` box)
- `OfflineService` guards network-dependent operations
- Conversations refresh automatically when connectivity is restored

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3 (Dart SDK ^3.12.2) |
| Backend-as-a-Service | Supabase (Auth, Database, Storage, Realtime, Edge Functions) |
| AI Model | Google Gemini 3.5 Flash (via Edge Function) |
| Voice/Video Calls | Agora RTC Engine 6.5.3 |
| State Management | Provider 6 (`ChangeNotifier`) |
| Local Storage | Hive 2 + Hive Flutter |
| HTTP Client | `http` package + native Dart `HttpClient` for SSE |
| UI Extras | Liquid Glass Widgets, Google Fonts, Lottie, Smooth Page Indicator |
| Icons | Hugeicons, Cupertino Icons, Material Icons |
| Image Handling | `cached_network_image`, `image_picker` |
| File Handling | `file_picker`, `open_filex`, `path_provider` |
| Audio | `record` (recording), `just_audio` (playback) |
| Notifications | `flutter_ringtone_player` (incoming calls) |
| Edge Function Runtime | Deno (TypeScript) |
| Agora Token Library | `agora-token@2.0.3` (npm, in Edge Function) |
| Linting | `flutter_lints` |
| App Icon | `flutter_launcher_icons` |

---

## Architecture

The app follows a layered architecture:

```
UI (Screens & Widgets)
        ↕
  Providers (State)
        ↕
   Services (Logic)
        ↕
 Supabase / Agora / Local Storage
```

- **Screens** are pure UI — they read from providers and dispatch actions.
- **Providers** hold all mutable state and orchestrate service calls.
- **Services** are stateless classes that wrap Supabase queries, Agora SDK calls, and Hive operations.
- **Models** are immutable data classes (`UserModel`, `MessageModel`, `ConversationModel`, `AiMessageModel`).

---

## Project Structure

```
chat_app_flutter/
├── lib/
│   ├── main.dart                    # Entry point: provider setup, routing, Supabase + Hive init
│   ├── config/
│   │   └── supabase_config.dart     # Supabase URL, anon key, Agora App ID
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── message_model.dart
│   │   ├── conversation_model.dart
│   │   └── ai_message_model.dart
│   ├── providers/
│   │   ├── auth_provider.dart       # Auth state, login/logout/signup
│   │   ├── chat_provider.dart       # Conversations, messages, groups, realtime
│   │   ├── ai_chat_provider.dart    # AI chat state, typewriter effect, history
│   │   ├── call_provider.dart       # Voice/video call lifecycle, Agora engine
│   │   └── theme_provider.dart      # Light/dark theme, custom theme builder
│   ├── services/
│   │   ├── supabase_auth_service.dart
│   │   ├── chat_service.dart
│   │   ├── conversation_service.dart
│   │   ├── message_service.dart
│   │   ├── ai_chat_service.dart     # Calls Edge Function, parses SSE stream
│   │   ├── agora_call_service.dart  # Agora SDK wrapper, token fetch
│   │   ├── block_service.dart
│   │   ├── receipt_service.dart     # Delivery + read receipts
│   │   ├── local_cache_service.dart # Hive-backed message cache
│   │   ├── media_cache_service.dart
│   │   └── offline_service.dart     # Connectivity checking
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── onboarding_screen.dart
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   ├── forgot_password_screen.dart
│   │   ├── reset_password_screen.dart
│   │   ├── home_screen.dart         # 4-tab main screen (Chats, Groups, Calls, Settings)
│   │   ├── chat_room_screen.dart
│   │   ├── ai_chat_screen.dart
│   │   ├── calls_screen.dart
│   │   ├── new_chat_screen.dart
│   │   ├── create_group_screen.dart
│   │   ├── contact_info_screen.dart
│   │   ├── group_info_screen.dart
│   │   ├── profile_settings_screen.dart
│   │   └── settings_screen.dart
│   └── widgets/
│       ├── ai/
│       │   ├── ai_message_bubble.dart
│       │   └── ai_typing_indicator.dart
│       ├── calling/
│       │   ├── call_screen.dart
│       │   ├── video_call_screen.dart
│       │   └── incoming_call_dialog.dart
│       ├── chat/
│       │   ├── message_bubble.dart
│       │   ├── message_input_bar.dart
│       │   ├── message_info_sheet.dart
│       │   └── date_separator.dart
│       ├── common/
│       │   ├── abstract_background.dart  # Animated gradient background
│       │   ├── glass_app_bar.dart        # Frosted glass app bar
│       │   ├── glass_bottom_bar.dart     # Frosted glass tab bar
│       │   ├── glass_container.dart
│       │   ├── glass_search_bar.dart
│       │   ├── avatar_helper.dart
│       │   └── neon_button.dart
│       └── home/
│           ├── conversation_tile.dart
│           └── empty_state.dart
├── supabase/
│   ├── config.toml
│   └── functions/
│       ├── chat-with-nova/
│       │   └── index.ts             # Gemini AI Edge Function with SSE streaming
│       └── generate-agora-token/
│           └── index.ts             # Agora RTC token generator
├── assets/
│   ├── avatars/                     # Built-in avatar images
│   ├── onboarding/                  # Onboarding screen illustrations
│   ├── animations/                  # Lottie animation files
│   ├── yapp_ai_avatar.png
│   ├── yapp-logo.png
│   ├── yapp-logo-light-mode.png
│   ├── yapp_ai_full.png
│   ├── yapp-app-icon.png
│   ├── light-mode-bg.png
│   └── dark-mode-bg.png
└── pubspec.yaml
```

---

## Screens & Navigation

The app uses named routes registered in `main.dart` with a global `NavigatorKey` shared with `CallProvider` so incoming calls can push routes without a `BuildContext`.

| Route | Screen | Description |
|---|---|---|
| `/` (home) | `SplashScreen` | Checks session and redirects |
| `/onboarding` | `OnboardingScreen` | First-launch walkthrough with page indicator |
| `/login` | `LoginScreen` | Email/password sign-in |
| `/signup` | `SignupScreen` | Registration with avatar picker |
| `/forgotPassword` | `ForgotPasswordScreen` | Sends password reset email |
| `/resetPassword` | `ResetPasswordScreen` | OTP or deep-link password reset |
| `/home` | `HomeScreen` | 4-tab hub: Chats, Groups, Calls, Settings |
| *(push)* | `ChatRoomScreen` | Individual or group message thread |
| *(push)* | `AiChatScreen` | Yapp AI assistant conversation |
| *(push)* | `NewChatScreen` | User search to start a direct chat |
| *(push)* | `CreateGroupScreen` | Multi-select contacts + group name |
| *(push)* | `ContactInfoScreen` | View a contact's profile |
| *(push)* | `GroupInfoScreen` | Group name, members, leave/delete |
| *(push)* | `ProfileSettingsScreen` | Edit own name, bio, avatar |
| `/call` | `CallScreen` | Active audio call UI |
| `/video-call` | `VideoCallScreen` | Active video call UI |
| `/incoming-call` | `IncomingCallScreen` | Incoming call with accept/decline |

### Home Screen Layout

The `HomeScreen` is the main hub after login. It uses a `TabController` with four tabs rendered via `TabBarView`:

1. **Chats** — Direct conversations list with search, pull-to-refresh, swipe/long-press to delete
2. **Groups** — Group conversations list (same pattern as Chats)
3. **Calls** — Call history log
4. **Settings** — App settings including theme toggle

A custom glass bottom bar handles tab switching. Floating action buttons appear on the Chats and Groups tabs (new chat / create group) and a persistent AI FAB provides one-tap access to Yapp AI from anywhere.

---

## State Management

The app uses the `provider` package (`ChangeNotifier` + `MultiProvider`). Five providers are registered at the root:

### `AuthProvider`
Wraps `SupabaseAuthService`. Manages:
- Current user object and session state
- Login, signup, logout, password reset
- `refreshUser()` for pulling updated profile data

### `ChatProvider`
The largest provider. Manages:
- Conversation list loading and Supabase Realtime subscription
- Per-conversation message loading and realtime message streaming
- Sending text, voice, images, and files
- Message deletion, forwarding, read receipts
- Group creation and management
- Offline cache read/write via `LocalCacheService`
- Block state integration

### `AiChatProvider`
Manages the AI chat lifecycle:
- Loads chat history from Supabase on first open
- Calls `AiChatService.streamMessage()` which consumes the Edge Function's SSE stream
- Drives a typewriter effect (14ms timer per character) to animate streaming text
- Persists chat state between screen navigations (`_historyLoaded` guard)
- States: `idle`, `loading`, `thinking`, `error`

### `CallProvider`
Full call lifecycle:
- Listens to Supabase Realtime `call_signals` for incoming invites
- Initiates outgoing calls: creates a call session record, fetches an Agora token from the Edge Function, joins the Agora channel
- Manages Agora `RtcEngine` events (join, leave, remote user streams)
- Navigates to call/incoming-call screens via the global navigator key
- Plays/stops ringtones
- Writes call history records

### `ThemeProvider`
- Stores and persists the user's preferred theme mode (light/dark/system)
- Provides `buildLightTheme()` and `buildDarkTheme()` using Google Fonts and custom color schemes

---

## Backend — Supabase

Supabase provides the entire backend: authentication, PostgreSQL database, file storage, realtime, and Edge Functions.

### Database Tables (inferred from services and migrations)

| Table | Purpose |
|---|---|
| `profiles` | User display name, avatar URL, bio |
| `conversations` | Conversation metadata, `is_group` flag |
| `conversation_participants` | Junction table: user ↔ conversation, with `status` (active/left) |
| `messages` | All chat messages with `sender_id`, `conversation_id`, `type`, `content`, `file_url` |
| `message_receipts` | Per-user delivery and read timestamps |
| `call_sessions` | Call records with type, status, timestamps |
| `call_signals` | Realtime signaling payloads for call invite/accept/decline/end |
| `blocked_users` | Block relationships between users |
| `ai_messages` | AI chat history per user (`role`, `content`, `created_at`) |

### Realtime
- Conversations and messages use Supabase Realtime channel subscriptions
- Call signaling uses a dedicated Realtime channel filtered by user ID
- Subscriptions are started in `HomeScreen.initState()` and torn down in `dispose()`

### Storage
- Profile avatars and media attachments are stored in Supabase Storage buckets
- `MediaCacheService` handles local caching of downloaded media

---

## Edge Functions

Both Edge Functions are written in TypeScript and run on the Deno runtime inside Supabase.

### `chat-with-nova`

Handles all Yapp AI conversations.

**Flow:**
1. Authenticates the request using the Supabase JWT from the `Authorization` header
2. Validates the message (max 8,000 characters)
3. Fetches the last 12 messages from the `ai_messages` table to build conversation context — server-side, preventing history spoofing
4. Sends the request to Google Gemini 3.5 Flash via its streaming REST API (`alt=sse`)
5. Forwards each SSE chunk back to the Flutter client immediately as it arrives
6. When the stream ends, saves both the user message and the complete AI reply to `ai_messages` in a single insert

**Gemini config:**
- Model: `gemini-3.5-flash`
- Max output tokens: 1,024
- Temperature: 0.7
- System instruction: sets the assistant persona as "Yapp", a friendly mobile chat companion

**Required secrets:** `GEMINI_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`

---

### `generate-agora-token`

Issues signed Agora RTC tokens for voice and video calls.

**Flow:**
1. Authenticates the caller via Supabase JWT
2. Validates `conversationId`, `sessionId`, and `callType` (`audio`|`video`) from the request body
3. Verifies the caller is an active participant of the given conversation and that it is not a group (calls are one-on-one only)
4. Constructs the channel name as `call_<sessionId>` server-side so clients cannot request tokens for arbitrary channels
5. Builds a token using `agora-token@2.0.3` (`RtcTokenBuilder.buildTokenWithUid`) with a 1-hour expiry
6. Returns `{ token, uid, appId }` to the client

**Required secrets:** `AGORA_APP_ID`, `AGORA_APP_CERTIFICATE`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`

---

## AI Assistant (Yapp AI)

Yapp AI is a built-in assistant accessible via a floating action button on the home screen.

- **Persona:** "Yapp" — warm, concise, conversational; suited to a mobile chat context
- **Model:** Google Gemini 3.5 Flash
- **Streaming:** SSE stream parsed character by character with a 14ms typewriter timer for smooth text animation
- **History:** Stored in the `ai_messages` Supabase table, loaded on screen open, persisted across sessions
- **Context:** The Edge Function always reads conversation history from the database, not from the client payload, preventing prompt injection or history manipulation
- **Clear Chat:** Users can permanently delete their AI conversation history
- **Greeting:** A welcome message is injected locally when history is empty

---

## Voice & Video Calls (Agora)

The calling system uses the Agora RTC Engine SDK (`agora_rtc_engine: 6.5.3`).

### Call Flow

**Outgoing call:**
1. `CallProvider` creates a `call_session` record in Supabase
2. Calls `generate-agora-token` Edge Function to get a signed token
3. Broadcasts a call invite signal via Supabase Realtime to the recipient
4. Navigates to `CallScreen` or `VideoCallScreen`
5. Joins the Agora channel using the token

**Incoming call:**
1. `CallProvider` listens on a Supabase Realtime channel filtered to the current user
2. On invite signal, plays a ringtone and navigates to `IncomingCallScreen`
3. On accept: fetches a token, joins the Agora channel
4. On decline: sends a decline signal, stops ringtone

**Call End:**
- Either party can end the call; a signal is broadcast and both sides leave the Agora channel
- Call duration and status are updated in the `call_sessions` table

### Call UI
- `CallScreen` — audio call with mute, speaker toggle, end call
- `VideoCallScreen` — video call with local/remote video renders, camera flip, mute
- `IncomingCallScreen` — caller info, accept/decline buttons, ringtone

---

## Local Storage & Offline Support

### Hive
Two Hive boxes are opened at startup:
- `authBox` — persists the user session
- `chatCache` — caches conversation and message data for offline reading

`LocalCacheService` reads from the cache when the device is offline and writes to it when data is fetched online.

### Offline Detection
`OfflineService` uses `connectivity_plus` to check for network access. Navigation actions that require the network (loading conversations, refreshing profile) are guarded and retry automatically when connectivity is restored.

---

## UI & Theming

### Glassmorphism Design System
The entire UI is built around a glass/blur aesthetic using the `liquid_glass_widgets` package, which is initialized at app startup. Key components:

- **`AbstractBackground`** — animated gradient background rendered behind all screens
- **`GlassAppBar`** — frosted glass top bar with user avatar and app title
- **`GlassBottomBar`** — frosted glass tab bar with icon + label tabs
- **`GlassContainer`** — reusable frosted glass card/container
- **`GlassSearchBar`** — frosted glass search input

### Theme
- Fully supports **light mode** and **dark mode**, switchable from the Settings tab
- `ThemeProvider` builds both themes with custom `ColorScheme` values and **Google Fonts** typography
- Background images: `light-mode-bg.png` / `dark-mode-bg.png`
- Onboarding uses `smooth_page_indicator` and `lottie` animations
- Icons from the `hugeicons` package throughout the app

### Assets
```
assets/
├── avatars/          # Pre-built avatar selection for user profiles
├── onboarding/       # Onboarding screen illustrations
├── animations/       # Lottie JSON animation files
├── yapp_ai_avatar.png
├── yapp-logo.png
├── yapp-logo-light-mode.png
├── yapp_ai_full.png
├── yapp-app-icon.png
├── light-mode-bg.png
└── dark-mode-bg.png
```

---

## Key Dependencies

| Package | Version | Purpose |
|---|---|---|
| `supabase_flutter` | ^2.17.1 | Auth, database, storage, realtime |
| `provider` | ^6.1.5+1 | State management |
| `agora_rtc_engine` | 6.5.3 | Voice and video calls |
| `hive` + `hive_flutter` | ^2.2.3 / ^1.1.0 | Local storage and offline cache |
| `liquid_glass_widgets` | ^0.29.1 | Glassmorphism UI components |
| `google_fonts` | ^8.2.1 | Typography |
| `lottie` | ^3.1.2 | Animated illustrations |
| `cached_network_image` | ^3.4.1 | Efficient remote image loading |
| `emoji_picker_flutter` | ^4.4.0 | Emoji keyboard |
| `record` | ^7.1.1 | Voice message recording |
| `just_audio` | ^0.10.5 | Audio playback |
| `flutter_ringtone_player` | ^4.0.0+4 | Incoming call ringtones |
| `file_picker` | ^8.1.7 | Attach files from device |
| `image_picker` | ^1.1.2 | Pick images from gallery/camera |
| `open_filex` | ^4.3.0 | Open downloaded files |
| `url_launcher` | ^6.3.1 | Launch URLs |
| `permission_handler` | ^11.3.1 | Microphone, camera, storage permissions |
| `connectivity_plus` | ^6.1.0 | Network connectivity detection |
| `timeago` | ^3.7.1 | Human-readable timestamps |
| `intl` | ^0.20.3 | Date/time formatting |
| `uuid` | ^4.5.3 | UUID generation |
| `crypto` | ^3.0.3 | Cryptographic utilities |
| `smooth_page_indicator` | ^2.0.1 | Onboarding page dots |
| `hugeicons` | ^1.0.0 | Icon library |
| `shared_preferences` | ^2.5.5 | Lightweight key-value persistence |
| `email_validator` | ^3.0.0 | Email format validation |
| `http` | ^1.3.0 | HTTP requests (SSE streaming) |
| `path_provider` | ^2.1.5 | Platform file paths |
| `flutter_launcher_icons` | ^0.13.1 | App icon generation |

---

## Getting Started

### Prerequisites
- Flutter SDK (Dart ^3.12.2)
- A Supabase project with the required tables and RLS policies
- A Google Gemini API key
- An Agora account with an App ID and App Certificate

### Setup

1. **Clone the repo**
   ```bash
   git clone <repo-url>
   cd chat_app_flutter
   flutter pub get
   ```

2. **Configure Supabase**
   
   Update `lib/config/supabase_config.dart` with your project URL and anon key:
   ```dart
   class SupabaseConfig {
     static const supabaseUrl = 'https://your-project.supabase.co';
     static const supabasePublishableKey = 'your-anon-key';
     static const agoraAppId = 'your-agora-app-id';
   }
   ```

3. **Deploy Edge Functions**
   ```bash
   supabase functions deploy chat-with-nova
   supabase functions deploy generate-agora-token
   ```

4. **Set Supabase Secrets**
   ```bash
   supabase secrets set GEMINI_API_KEY=your-gemini-key
   supabase secrets set AGORA_APP_ID=your-agora-app-id
   supabase secrets set AGORA_APP_CERTIFICATE=your-agora-certificate
   ```

5. **Run the app**
   ```bash
   flutter run
   ```

---

## Environment & Secrets

| Secret | Location | Used By |
|---|---|---|
| `GEMINI_API_KEY` | Supabase Secrets | `chat-with-nova` Edge Function |
| `AGORA_APP_ID` | Supabase Secrets + `supabase_config.dart` | `generate-agora-token` Edge Function + Flutter app |
| `AGORA_APP_CERTIFICATE` | Supabase Secrets | `generate-agora-token` Edge Function |
| Supabase URL + Anon Key | `supabase_config.dart` | Flutter app initialization |

> **Note:** Never commit `supabase_config.dart` with real credentials to a public repository. Use environment injection or a `.env` file approach for production builds.
