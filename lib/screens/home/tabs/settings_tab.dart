// lib/screens/home/tabs/settings_tab.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../auth/login_screen.dart';
import '../../home/home_shell.dart';
import '../../home/home_shell.dart' show HomeShell;

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _section(
                context,
                'Account',
                [
                  _tile(context,
                      icon: Icons.badge_outlined,
                      title: 'Account details',
                      subtitle: email,
                      onTap: null),
                  _tile(context,
                      icon: Icons.person_outline,
                      title: 'Change username',
                      onTap: () => _changeUsername(context)),
                  _tile(context,
                      icon: Icons.lock_reset_outlined,
                      title: 'Change password',
                      onTap: () => _changePassword(context)),
                  _tile(context,
                      icon: Icons.key_outlined,
                      title: 'Forgot password', onTap: () async {
                    await SupabaseService.sendResetPasswordEmail(email);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reset email sent')));
                  }),
                ],
                cs),
            _section(
                context,
                'Bluetooth',
                [
                  _tile(context,
                      icon: Icons.bluetooth_searching,
                      title: 'Bluetooth settings',
                      onTap: () =>
                          Navigator.of(context).pushNamed('/bluetooth')),
                ],
                cs),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              style: FilledButton.styleFrom(
                  backgroundColor: cs.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              onPressed: () async {
                await SupabaseService.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (r) => false);
              },
              label: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Logout',
                      style: TextStyle(color: Colors.redAccent))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
      BuildContext context, String title, List<Widget> items, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant)),
            child: Column(
                children: List.generate(
                    items.length,
                    (i) => Column(children: [
                          items[i],
                          if (i != items.length - 1)
                            Divider(height: 1, color: cs.outlineVariant)
                        ]))),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(8),
                child: Icon(icon, color: cs.onSurfaceVariant)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant))
                  ]
                ])),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Future<void> _changeUsername(BuildContext context) async {
    final current = await SupabaseService.getMyProfile();
    final c = TextEditingController(text: current?['username'] ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Change username',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 12),
          TextField(
              controller: c,
              decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 14),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () async {
                    await SupabaseService.updateUsername(c.text.trim());
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Username updated')));
                  },
                  child: const Text('Save'))),
        ]),
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final oldPass = TextEditingController();
    final newPass = TextEditingController();
    final confirm = TextEditingController();
    bool busy = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Change password',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
                controller: oldPass,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 12),
            TextField(
                controller: newPass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password')),
            const SizedBox(height: 12),
            TextField(
                controller: confirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm new password')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.lock_reset_outlined),
                onPressed: busy
                    ? null
                    : () async {
                        if (newPass.text.trim() != confirm.text.trim()) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Passwords do not match')));
                          return;
                        }
                        setS(() => busy = true);
                        try {
                          await Supabase.instance.client.auth
                              .signInWithPassword(
                                  email: email, password: oldPass.text.trim());
                          await Supabase.instance.client.auth.updateUser(
                              UserAttributes(password: newPass.text.trim()));
                          if (Navigator.of(ctx).canPop()) {
                            Navigator.of(ctx).pop();
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Password updated')));
                        } catch (e) {
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        } finally {
                          setS(() => busy = false);
                        }
                      },
                label: Text(busy ? 'Please wait...' : 'Update password'),
              ),
            ),
          ]),
        );
      }),
    );
  }
}
