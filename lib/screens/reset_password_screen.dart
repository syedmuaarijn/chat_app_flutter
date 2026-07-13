import 'package:flutter/material.dart';
import '../services/supabase_auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _auth = SupabaseAuthService();
  bool loading = false;
  bool obscure1 = true;
  bool obscure2 = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    try {
      await _auth.updateUserPassword(_passwordController.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _passwordController,
                obscureText: obscure1,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure1 ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => obscure1 = !obscure1),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter password';
                  if (value.length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _confirmController,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure2 ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => obscure2 = !obscure2),
                  ),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return "Passwords don't match";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: loading ? null : _resetPassword,
                child: loading
                    ? const CircularProgressIndicator()
                    : const Text('Reset Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
