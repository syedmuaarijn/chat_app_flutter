import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/supabase_auth_service.dart';
import '../widgets/common/abstract_background.dart';
import '../widgets/common/glass_container.dart';
import '../widgets/common/neon_button.dart';

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
        const SnackBar(
          content: Text('Password updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? Colors.white24 : Colors.black26;
    final backButtonColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: backButtonColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const AbstractBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: GlassContainer(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.1),
                        ),
                        child: Icon(
                          Icons.password_rounded,
                          size: 48,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'New Password',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Enter your new password below.",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: subtextColor,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _passwordController,
                              obscureText: obscure1,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                labelStyle: TextStyle(
                                  color: subtextColor,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: iconColor,
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: accent),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscure1
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: iconColor,
                                  ),
                                  onPressed: () =>
                                      setState(() => obscure1 = !obscure1),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty)
                                  return 'Enter password';
                                if (value.length < 8)
                                  return 'Minimum 8 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmController,
                              obscureText: obscure2,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                labelText: 'Confirm Password',
                                labelStyle: TextStyle(
                                  color: subtextColor,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: iconColor,
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: accent),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscure2
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: iconColor,
                                  ),
                                  onPressed: () =>
                                      setState(() => obscure2 = !obscure2),
                                ),
                              ),
                              validator: (value) {
                                if (value != _passwordController.text) {
                                  return "Passwords don't match";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 32),
                            NeonButton(
                              text: 'Update Password',
                              isLoading: loading,
                              onPressed: _resetPassword,
                            ),
                            const SizedBox(height: 24),
                            TextButton.icon(
                              onPressed: () => Navigator.pushReplacementNamed(
                                context,
                                '/login',
                              ),
                              icon: Icon(
                                Icons.close_rounded,
                                color: subtextColor,
                              ),
                              label: Text(
                                'Cancel',
                                style: TextStyle(color: subtextColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
