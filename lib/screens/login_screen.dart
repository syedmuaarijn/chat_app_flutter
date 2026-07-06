import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import '../services/firebase_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;

  final passwordRegex = RegExp(
    r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&#]{8,}$',
  );

  final _authService = FirebaseAuthService();

  Future handleSignIn() async {
    if (_formKey.currentState!.validate()) {
      try {
        User? user = await _authService.signInWithEmailAndPassword(
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
                "Login Screen",
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
                  // color: const Color.fromARGB(20, 33, 149, 243),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),

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
                        obscureText: _obscureText,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureText = !_obscureText;
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacementNamed(
                                context,
                                '/forgotPassword',
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),

                      Container(
                        padding: EdgeInsets.only(top: 30),
                        child: ElevatedButton(
                          onPressed: handleSignIn,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: 15,
                              horizontal: 40,
                            ),
                            backgroundColor: Colors.blue,
                          ),
                          child: Text(
                            'Login',
                            style: TextStyle(color: Colors.white, fontSize: 20),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => {
                          Navigator.pushReplacementNamed(context, '/signup'),
                        },
                        child: Text(
                          "Don't have an account? Sign Up.",
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
