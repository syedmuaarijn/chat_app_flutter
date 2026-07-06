// // import 'package:flutter/material.dart';
// // import 'features/chat/presentation/chat_room_screen.dart';

// // void main() {
// //   runApp(const MyApp());
// // }

// // class MyApp extends StatelessWidget {
// //   const MyApp({super.key});

// //   @override
// //   Widget build(BuildContext context) {
// //     return MaterialApp(
// //       title: 'Lavender Chat',
// //       debugShowCheckedModeBanner: false,
// //       // Light Lavender Theme Setup
// //       theme: ThemeData(
// //         colorScheme: ColorScheme.fromSeed(
// //           seedColor: const Color(0xFF6750A4), // Primary Deep Purple/Lavender
// //           primary: const Color(0xFF6750A4),
// //           secondary: const Color(0xFF9A82DB), // Lighter Lavender Accent
// //           background: const Color(0xFFF9F7FC), // Soft lavender white background
// //           surface: Colors.white,
// //         ),
// //         scaffoldBackgroundColor: const Color(0xFFF9F7FC),
// //         useMaterial3: true,
// //       ),
// //       // App ab seedha Chat Room Screen par khulega
// //       home: const ChatRoomScreen(),
// //     );
// //   }
// // }

// import 'package:chat_app_flutter/signup_screen.dart';
// import 'package:flutter/material.dart';

// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Chat App',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
//         inputDecorationTheme: InputDecorationTheme(
//           focusedBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(10),
//             borderSide: BorderSide(color: Colors.blue, width: 2),
//           ),
//         ),
//       ),
//       home: SignupScreen(),
//     );
//   }
// }

import 'package:chat_app_flutter/config/supabase_config.dart';
import 'package:chat_app_flutter/screens/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/signup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabasePublishableKey,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue, width: 2),
          ),
        ),
      ),
      initialRoute: '/signup',
      routes: {
        '/signup': (context) => SignupScreen(),
        '/login': (context) => LoginScreen(),
        '/forgotPassword': (context) => ForgotPasswordScreen(),
        '/home': (context) => home_screen(),
      },
      home: SignupScreen(),
    );
  }
}
