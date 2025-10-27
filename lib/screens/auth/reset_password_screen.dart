// lib/screens/auth/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final pass = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set new password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
                obscureText: true,
                controller: pass,
                decoration: const InputDecoration(labelText: 'New password')),
            const SizedBox(height: 12),
            TextField(
                obscureText: true,
                controller: confirm,
                decoration:
                    const InputDecoration(labelText: 'Confirm new password')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : _reset,
                child: Text(busy ? 'Please wait...' : 'Update password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reset() async {
    if (pass.text.trim() != confirm.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    setState(() => busy = true);
    try {
      final res = await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: pass.text.trim()));
      if (res.user != null) {
        if (mounted) {
          Navigator.of(context).pop(); // back to previous (e.g., Login)
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password updated')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
