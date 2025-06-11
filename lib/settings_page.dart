import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('Profile'),
              subtitle: Text('Manage your profile settings'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to profile settings
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.notifications,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('Notifications'),
              subtitle: Text('Configure notification preferences'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to notification settings
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.security,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('Privacy & Security'),
              subtitle: Text('Manage privacy and security settings'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to privacy settings
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.help,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('Help & Support'),
              subtitle: Text('Get help and contact support'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to help
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.info,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text('About ResQLink'),
              subtitle: Text('App version and information'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {
                // Show about dialog
              },
            ),
          ),
        ],
      ),
    );
  }
}
