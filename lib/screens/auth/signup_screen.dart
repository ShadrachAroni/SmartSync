// lib/screens/auth/signup_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../home/home_shell.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final username = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  bool obscure = true;
  bool loading = false;

  Future<void> _signup() async {
    setState(() => loading = true);
    try {
      await SupabaseService.signUp(
        email: email.text.trim(),
        password: pass.text.trim(),
        username: username.text.trim(),
      );
      // If confirm email is disabled, a session exists; otherwise navigate to login
      final session = Supabase.instance.client.auth.currentSession;
      if (mounted) {
        if (session != null) {
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeShell()),
              (r) => false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Check email to confirm your account')));
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF211347), Color(0xFF6A2CF3)],
    );
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: gradient)),
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.energy_savings_leaf_outlined,
                      color: Colors.white, size: 40),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Sign up To Your Account.',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(
                              'Access account to manage settings and explore features.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white70)),
                          const SizedBox(height: 18),
                          _pillField(
                              controller: username,
                              hint: 'Username',
                              icon: Icons.person_outline),
                          const SizedBox(height: 12),
                          _pillField(
                              controller: email,
                              hint: 'alma.lawson@example.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 12),
                          _pillField(
                            controller: pass,
                            hint: 'Password',
                            icon: Icons.lock_outline,
                            obscure: obscure,
                            suffix: IconButton(
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                              icon: Icon(
                                  obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                  shape: const StadiumBorder(),
                                  backgroundColor: const Color(0xFF8C5BFF)),
                              onPressed: loading ? null : _signup,
                              child: Text(
                                  loading ? 'Please wait...' : 'Get Started'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _orDivider(),
                          const SizedBox(height: 12),
                          _oauthButton(
                              label: 'Sign in with Google',
                              icon: Icons.g_mobiledata,
                              onPressed: () {}),
                          const SizedBox(height: 10),
                          _oauthButton(
                              label: 'Continue with Apple',
                              icon: Icons.apple,
                              onPressed: () {}),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              const Text('Already have an account? ',
                                  style: TextStyle(color: Colors.white70)),
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: const Text('Sign in',
                                    style: TextStyle(
                                        color: Color(0xFFBFA7FF),
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: Icon(icon, color: Colors.white70),
        ),
        suffixIcon: suffix,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(40),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: Colors.white24)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('Or', style: TextStyle(color: Colors.white60)),
        ),
        Expanded(child: Container(height: 1, color: Colors.white24)),
      ],
    );
  }

  Widget _oauthButton(
      {required String label,
      required IconData icon,
      required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          shape: const StadiumBorder(),
          backgroundColor: Colors.white.withOpacity(0.04),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
