import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart'; // <-- added

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      bottomNavigationBar: const BottomNav(), // <-- added
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Account'),
            subtitle: Text('Manage your account'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications),
            title: Text('Notifications'),
          ),
          const ListTile(
            leading: Icon(Icons.bluetooth),
            title: Text('Integrations (Bluetooth / PlatformIO)'),
          ),
          const ListTile(
            leading: Icon(Icons.storage),
            title: Text('Supabase'),
            subtitle: Text('Manage backend connectivity'),
          ),
          const Divider(),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
