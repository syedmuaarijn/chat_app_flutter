import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import '../services/firebase_auth_service.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import '../services/supabase_auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final _authService = FirebaseAuthService();
  final _auth = SupabaseAuthService();
  bool loading = false;

  Future handleForgotPassword() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _authService.passwordReset(_emailController.text);
        Navigator.pushReplacementNamed(context, '/login');
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
    });

    try {
      await _auth.sendPasswordResetEmail(_emailController.text.trim());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset email sent. Check your inbox."),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }

    setState(() {
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                "Forgot Password Screen",
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FractionallySizedBox(
              widthFactor: 0.8,

              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),

                child: Form(
                  key: _formKey,
                  child: Column(
                    spacing: 12,
                    children: [
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please Enter your email';
                          }
                          if (!EmailValidator.validate(value)) {
                            return 'Please Enter a Valid Email';
                          }
                          return null;
                        },
                      ),

                      Container(
                        padding: EdgeInsets.only(top: 30),
                        child: ElevatedButton(
                          //                          onPressed: handleForgotPassword,
                          onPressed: sendResetEmail,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: 15,
                              horizontal: 40,
                            ),
                            backgroundColor: Colors.blue,
                          ),
                          child: Text(
                            'Send Reset Link',
                            style: TextStyle(color: Colors.white, fontSize: 20),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacementNamed(context, '/login');
                            },
                            child: Row(
                              children: [
                                Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.blue,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Back to Login',
                                  style: TextStyle(color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:email_validator/email_validator.dart';
// import '../services/supabase_auth_service.dart';

// class ForgotPasswordScreen extends StatefulWidget {
//   const ForgotPasswordScreen({super.key});

//   @override
//   State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
// }

// class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
//   final _formKey = GlobalKey<FormState>();

//   final TextEditingController _emailController = TextEditingController();

//   final _auth = SupabaseAuthService();

//   bool loading = false;

//   Future<void> sendResetEmail() async {
//     if (!_formKey.currentState!.validate()) return;

//     setState(() {
//       loading = true;
//     });

//     try {
//       await _auth.sendPasswordResetEmail(_emailController.text.trim());

//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Password reset email sent. Check your inbox."),
//         ),
//       );

//       Navigator.pop(context);
//     } catch (e) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(e.toString())));
//     }

//     setState(() {
//       loading = false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Forgot Password")),
//       body: Padding(
//         padding: const EdgeInsets.all(20),

//         child: Form(
//           key: _formKey,

//           child: Column(
//             children: [
//               TextFormField(
//                 controller: _emailController,

//                 keyboardType: TextInputType.emailAddress,

//                 decoration: const InputDecoration(
//                   labelText: "Email",
//                   prefixIcon: Icon(Icons.email),
//                 ),

//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return "Enter your email";
//                   }

//                   if (!EmailValidator.validate(value)) {
//                     return "Invalid email";
//                   }

//                   return null;
//                 },
//               ),

//               const SizedBox(height: 25),

//               ElevatedButton(
//                 onPressed: loading ? null : sendResetEmail,

//                 child: loading
//                     ? const CircularProgressIndicator()
//                     : const Text("Send Reset Link"),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
