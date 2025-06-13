import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Profile'),
              subtitle: const Text('Manage your profile settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProfileDialog(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.notifications,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Notifications'),
              subtitle: const Text('Configure notification preferences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.security,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Privacy & Security'),
              subtitle: const Text('Manage privacy and security settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.help,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Help & Support'),
              subtitle: const Text('Get help and contact support'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.info,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('About ResQLink'),
              subtitle: const Text('App version and information'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAboutDialog(context),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            onPressed: () {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile'),
        content: const Text('This would show user profile info in a real app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'ResQLink',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.info_outline),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16.0),
          child: Text('Offline emergency support using Wi-Fi Direct and GPS.'),
        ),
      ],
    );
  }
}
