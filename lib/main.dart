import 'package:chat_app_flutter/config/supabase_config.dart';
import 'package:chat_app_flutter/providers/auth_provider.dart';
import 'package:chat_app_flutter/providers/ai_chat_provider.dart';
import 'package:chat_app_flutter/providers/call_provider.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/forgot_password_screen.dart';
import 'package:chat_app_flutter/screens/home_screen.dart';
import 'package:chat_app_flutter/screens/login_screen.dart';
import 'package:chat_app_flutter/screens/reset_password_screen.dart';
import 'package:chat_app_flutter/screens/signup_screen.dart';
import 'package:chat_app_flutter/screens/splash_screen.dart';
import 'package:chat_app_flutter/screens/onboarding_screen.dart';
import 'package:chat_app_flutter/widgets/calling/call_screen.dart';
import 'package:chat_app_flutter/widgets/calling/incoming_call_dialog.dart';
import 'package:chat_app_flutter/widgets/calling/video_call_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:chat_app_flutter/providers/theme_provider.dart';

/// Global navigator key — allows CallProvider to navigate without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox('authBox');
  await Hive.openBox('chatCache');

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabasePublishableKey,
  );
  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AiChatProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final provider = CallProvider();
            // Inject the global navigator key so CallProvider can navigate
            provider.navigatorKey = appNavigatorKey;
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Yapp',
            debugShowCheckedModeBanner: false,
            // Use the global navigator key so CallProvider can push routes
            navigatorKey: appNavigatorKey,
            theme: themeProvider.buildLightTheme(),
            darkTheme: themeProvider.buildDarkTheme(),
            themeMode: themeProvider.themeMode,

            // SplashScreen is the entry point — it decides where to go
            home: const SplashScreen(),

            routes: {
              '/splash': (context) => const SplashScreen(),
              '/onboarding': (context) => const OnboardingScreen(),
              '/login': (context) => const LoginScreen(),
              '/signup': (context) => const SignupScreen(),
              '/forgotPassword': (context) => const ForgotPasswordScreen(),
              '/resetPassword': (context) => const ResetPasswordScreen(),
              '/home': (context) => const HomeScreen(),
              '/call': (context) => const CallScreen(),
              '/video-call': (context) => const VideoCallScreen(),
              '/incoming-call': (context) => const IncomingCallScreen(),
              '/incoming-video-call': (context) => const IncomingCallScreen(),
            },
            // NOTE: The builder overlay for IncomingCallDialog has been REMOVED.
            // Incoming calls are now navigated to '/incoming-call' as a proper route
            // from CallProvider._handleIncomingInvite(), eliminating the touch-blocking bug.
          );
        },
      ),
    );
  }
}
