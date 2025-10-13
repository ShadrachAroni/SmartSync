// lib/screens/auth/login_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../home/home_shell.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool resetMode;
  const LoginScreen({super.key, this.resetMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool remember = false;
  bool obscure = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _restoreRemember();
  }

  Future<void> _restoreRemember() async {
    final prefs = await SharedPreferences.getInstance();
    remember = prefs.getBool('remember_me') ?? false;
    if (remember) {
      email.text = prefs.getString('remember_email') ?? '';
    }
    setState(() {});
  }

  Future<void> _persistRemember() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', remember);
    if (remember) {
      await prefs.setString('remember_email', email.text.trim());
    } else {
      await prefs.remove('remember_email');
    }
  }

  Future<void> _login() async {
    setState(() => loading = true);
    try {
      await SupabaseService.signIn(
          email: email.text.trim(), password: pass.text.trim());
      await _persistRemember();
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeShell()));
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

  Future<void> _sendReset() async {
    try {
      // Use your actual redirectTo value, matching your Supabase Auth URL config and app deep link
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email.text.trim(),
        redirectTo:
            'io.smartsync.app://reset-callback/', // <-- match your deep link
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
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
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: gradient)),
          _headerLogo(),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _glassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Sign In To Your Account.',
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
                        controller: email,
                        hint: 'alma.lawson@example.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        controller: pass,
                        hint: 'Password',
                        icon: Icons.lock_outline,
                        obscure: obscure,
                        suffix: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                              obscure ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Checkbox(
                            value: remember,
                            onChanged: (v) =>
                                setState(() => remember = v ?? false),
                            side: const BorderSide(color: Colors.white54),
                            checkColor: Colors.white,
                            activeColor: const Color(0xFF8C5BFF),
                          ),
                          const Text('Remember me',
                              style: TextStyle(color: Colors.white70)),
                          const Spacer(),
                          TextButton(
                            onPressed: loading ? null : _sendReset,
                            child: const Text('Forgot password?',
                                style: TextStyle(color: Color(0xFFBFA7FF))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const StadiumBorder(),
                            backgroundColor: const Color(0xFF8C5BFF),
                          ),
                          onPressed: loading ? null : _login,
                          child: Text(loading ? 'Please wait...' : 'Login'),
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
                          const Text("Don't have an account? ",
                              style: TextStyle(color: Colors.white70)),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const SignupScreen())),
                            child: const Text('Sign up',
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
        ],
      ),
    );
  }

  Widget _headerLogo() {
    return Positioned(
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
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: child,
        ),
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
