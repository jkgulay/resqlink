import 'package:flutter/material.dart';
import 'package:resqlink/services/auth_service.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _wifiDirectEnabled = true;
  bool _locationServicesEnabled = true;
  bool _emergencyNotifications = true;
  bool _soundAlerts = true;
  bool _vibrationAlerts = true;
  bool _autoLocationBroadcast = false;
  bool _batteryOptimization = true;
  String _emergencyMessage =
      "Emergency! I need help. This is my last known location.";
  double _broadcastRadius = 500.0; // meters
  int _locationUpdateInterval = 30; // seconds

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Emergency Settings Section
          _buildSectionHeader('Emergency Settings'),
          _buildEmergencyCard(),
          const SizedBox(height: 16),

          // Connectivity Settings
          _buildSectionHeader('Connectivity'),
          _buildConnectivityCard(),
          const SizedBox(height: 16),

          // Location Settings
          _buildSectionHeader('Location Services'),
          _buildLocationCard(),
          const SizedBox(height: 16),

          // Notification Settings
          _buildSectionHeader('Notifications'),
          _buildNotificationCard(),
          const SizedBox(height: 16),

          // App Settings
          _buildSectionHeader('App Settings'),
          _buildAppSettingsCard(),
          const SizedBox(height: 16),

          // Profile & Account
          _buildSectionHeader('Account'),
          _buildProfileCard(),
          const SizedBox(height: 24),

          // Logout Button
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildEmergencyCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.emergency, color: Colors.red, size: 28),
              title: const Text('Emergency Message'),
              subtitle: Text(_emergencyMessage),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editEmergencyMessage(),
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.radio_button_checked,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Broadcast Radius'),
              subtitle: Text('${_broadcastRadius.toInt()} meters'),
              trailing: Container(
                width: 100,
                child: Slider(
                  value: _broadcastRadius,
                  min: 100,
                  max: 2000,
                  divisions: 19,
                  onChanged: (value) {
                    setState(() {
                      _broadcastRadius = value;
                    });
                  },
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.location_on,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Auto Location Broadcast'),
              subtitle: const Text(
                'Automatically broadcast location in emergency',
              ),
              value: _autoLocationBroadcast,
              onChanged: (value) {
                setState(() {
                  _autoLocationBroadcast = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectivityCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.wifi,
              color: _wifiDirectEnabled ? Colors.green : Colors.grey,
            ),
            title: const Text('Wi-Fi Direct'),
            subtitle: const Text('Enable offline device communication'),
            value: _wifiDirectEnabled,
            onChanged: (value) {
              setState(() {
                _wifiDirectEnabled = value;
              });
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.devices,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Nearby Devices'),
            subtitle: const Text('Scan and manage connected devices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showNearbyDevices(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.network_check,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Connection Status'),
            subtitle: const Text('Check network connectivity'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showConnectionStatus(),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.gps_fixed,
              color: _locationServicesEnabled ? Colors.green : Colors.grey,
            ),
            title: const Text('Location Services'),
            subtitle: const Text('Enable GPS for emergency location sharing'),
            value: _locationServicesEnabled,
            onChanged: (value) {
              setState(() {
                _locationServicesEnabled = value;
              });
            },
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Icon(
              Icons.timer,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Location Update Interval'),
            subtitle: Text('$_locationUpdateInterval seconds'),
            trailing: Container(
              width: 100,
              child: Slider(
                value: _locationUpdateInterval.toDouble(),
                min: 10,
                max: 300,
                divisions: 29,
                onChanged: (value) {
                  setState(() {
                    _locationUpdateInterval = value.toInt();
                  });
                },
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.my_location,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Current Location'),
            subtitle: const Text('View and test location accuracy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCurrentLocation(),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.notifications_active,
              color: _emergencyNotifications ? Colors.orange : Colors.grey,
            ),
            title: const Text('Emergency Notifications'),
            subtitle: const Text('Receive emergency alerts from nearby users'),
            value: _emergencyNotifications,
            onChanged: (value) {
              setState(() {
                _emergencyNotifications = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(
              Icons.volume_up,
              color: _soundAlerts
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: const Text('Sound Alerts'),
            subtitle: const Text('Play sound for emergency notifications'),
            value: _soundAlerts,
            onChanged: (value) {
              setState(() {
                _soundAlerts = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(
              Icons.vibration,
              color: _vibrationAlerts
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: const Text('Vibration Alerts'),
            subtitle: const Text('Vibrate for emergency notifications'),
            value: _vibrationAlerts,
            onChanged: (value) {
              setState(() {
                _vibrationAlerts = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppSettingsCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.battery_charging_full,
              color: _batteryOptimization ? Colors.green : Colors.grey,
            ),
            title: const Text('Battery Optimization'),
            subtitle: const Text(
              'Optimize battery usage for background operation',
            ),
            value: _batteryOptimization,
            onChanged: (value) {
              setState(() {
                _batteryOptimization = value;
              });
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.storage,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Storage & Cache'),
            subtitle: const Text('Manage app data and cache'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showStorageSettings(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.security,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Privacy & Security'),
            subtitle: const Text('Manage privacy and security settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPrivacySettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.person, color: Colors.white),
            ),
            title: const Text('Profile'),
            subtitle: const Text('Manage your profile and emergency contacts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showProfileDialog(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.contacts,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Emergency Contacts'),
            subtitle: const Text('Add and manage emergency contacts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showEmergencyContacts(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.help,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Help & Support'),
            subtitle: const Text('Get help and contact support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showHelpSupport(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.info,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('About ResQLink'),
            subtitle: const Text('App version and information'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        onPressed: () async {
          // Show a confirmation dialog before logging out
          bool? confirmLogout = await _showLogoutConfirmationDialog(context);
          if (confirmLogout == true) {
            try {
              await AuthService.logout(); // Call the logout method
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/',
                (route) => false,
              ); // Navigate to the landing page
            } catch (e) {
              // Handle any errors that occur during logout
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Logout failed: ${e.toString()}')),
              );
            }
          }
        },
      ),
    );
  }

  // Function to show a confirmation dialog
  Future<bool?> _showLogoutConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Return false
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Return true
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // Dialog and navigation methods
  void _editEmergencyMessage() {
    TextEditingController controller = TextEditingController(
      text: _emergencyMessage,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Emergency Message'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 160,
          decoration: const InputDecoration(
            hintText: 'Enter your emergency message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _emergencyMessage = controller.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showNearbyDevices() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nearby Devices'),
        content: const Text(
          'This would show a list of nearby devices available for Wi-Fi Direct connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showConnectionStatus() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusItem('Wi-Fi Direct', _wifiDirectEnabled),
            _buildStatusItem('Location Services', _locationServicesEnabled),
            _buildStatusItem('Background App Refresh', _batteryOptimization),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String title, bool status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Icon(
            status ? Icons.check_circle : Icons.cancel,
            color: status ? Colors.green : Colors.red,
            size: 20,
          ),
        ],
      ),
    );
  }

  void _showCurrentLocation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current Location'),
        content: const Text(
          'Latitude: 8.4542° N\nLongitude: 124.6319° E\nAccuracy: ±5 meters\nLast Updated: Just now',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showStorageSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage & Cache'),
        content: const Text(
          'Cache Size: 12.5 MB\nApp Data: 8.2 MB\nTotal: 20.7 MB',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Clear Cache'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPrivacySettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy & Security'),
        content: const Text(
          'This would show privacy and security settings including data sharing preferences and security options.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile'),
        content: const Text(
          'Name: John Doe\nPhone: +63 912 345 6789\nEmail: john.doe@example.com',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEmergencyContacts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Contacts'),
        content: const Text(
          'This would show a list of emergency contacts that can be notified automatically during emergencies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Add Contact'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const Text(
          'For help and support:\n\nEmail: support@resqlink.com\nPhone: +63 2 1234 5678\nWebsite: www.resqlink.com',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'ResQLink',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.emergency, size: 48),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16.0),
          child: Text(
            'Offline emergency support using Wi-Fi Direct and GPS.\n\nStay connected even when the internet is down.',
          ),
        ),
      ],
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Close the dialog
              Navigator.pop(context);
              // Navigate back to landing page and clear navigation stack
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
