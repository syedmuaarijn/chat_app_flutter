import 'package:chat_app_flutter/services/supabase_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import '../services/firebase_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SignupScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscureText1 = true;
  bool _obscureText2 = true;
  final _firebaseAuthService = FirebaseAuthService();
  final _supabaseAuthService = SupabaseAuthService();

  final passwordRegex = RegExp(
    r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&#]{8,}$',
  );

  Future<void> handleFirebaseSignUp() async {
    if (_formKey.currentState!.validate()) {
      try {
        User? user = await _firebaseAuthService.signUpWithEmailAndPassword(
          _emailController.text,
          _passwordController.text,
        );
        if (user != null) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> handleSupabaseSignUp() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _supabaseAuthService.signUpWithEmailAndPassword(
          _emailController.text,
          _passwordController.text,
        );
        Navigator.pushReplacementNamed(context, '/home');
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
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
                "Signup Screen",
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

                      TextFormField(
                        controller: _passwordController,
                        keyboardType: TextInputType.visiblePassword,
                        obscureText: _obscureText1,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText1
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureText1 = !_obscureText1;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 8) {
                            return 'Password must be atleast 8 characters long';
                          }
                          if (!RegExp(
                            r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                          ).hasMatch(value)) {
                            return 'Must have uppercase, number and special character';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _confirmPasswordController,
                        keyboardType: TextInputType.visiblePassword,
                        obscureText: _obscureText2,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText2
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureText2 = !_obscureText2;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 8) {
                            return 'Password must be atleast 8 characters long';
                          }
                          if (!RegExp(
                            r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
                          ).hasMatch(value)) {
                            return 'Must have uppercase, number and special character';
                          }
                          if (value != _passwordController.text) {
                            return 'Password does not match';
                          }
                          return null;
                        },
                      ),
                      Container(
                        padding: EdgeInsets.only(top: 30),
                        child: ElevatedButton(
                          // onPressed: handleFirebaseSignUp,
                          onPressed: handleSupabaseSignUp,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: 15,
                              horizontal: 40,
                            ),
                            backgroundColor: Colors.blue,
                          ),
                          child: Text(
                            'Register',
                            style: TextStyle(color: Colors.white, fontSize: 20),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => {
                          Navigator.pushReplacementNamed(context, '/login'),
                        },
                        child: Text(
                          "Already have an account? Login.",
                          style: TextStyle(color: Colors.blue),
                        ),
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
