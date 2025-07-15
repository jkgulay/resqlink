import 'package:flutter/material.dart';
import 'package:resqlink/services/auth_service.dart';
import 'package:flutter/services.dart';

class SettingsPage extends StatefulWidget {
  @override
  SettingsPageState createState() => SettingsPageState();
}

const MethodChannel _vibrationChannel = MethodChannel('resqlink/vibration');

Future<void> triggerEmergencyFeedback() async {
  try {
    await _vibrationChannel.invokeMethod('vibrate');
  } catch (e) {
    print('Emergency feedback error: $e');
  }
}

// Responsive utilities class
class ResponsiveUtils {
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;

  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static double getResponsiveFontSize(
    BuildContext context,
    double baseFontSize,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < mobileBreakpoint) {
      return baseFontSize * 0.9;
    } else if (screenWidth < tabletBreakpoint) {
      return baseFontSize * 1.1;
    } else {
      return baseFontSize * 1.2;
    }
  }

  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < mobileBreakpoint) {
      return baseSpacing * 0.8;
    } else if (screenWidth < tabletBreakpoint) {
      return baseSpacing * 1.0;
    } else {
      return baseSpacing * 1.2;
    }
  }

  static double getResponsiveButtonWidth(
    BuildContext context,
    double maxWidth,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isMobile(context)) {
      return screenWidth * 0.8;
    } else if (isTablet(context)) {
      return screenWidth * 0.6;
    } else {
      return maxWidth;
    }
  }

  static double getResponsiveDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isMobile(context)) {
      return screenWidth * 0.9;
    } else if (isTablet(context)) {
      return screenWidth * 0.7;
    } else {
      return 500.0;
    }
  }

  static EdgeInsets getResponsivePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(12.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(16.0);
    } else {
      return const EdgeInsets.all(20.0);
    }
  }

  static EdgeInsets getResponsiveMargin(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0);
    } else {
      return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
    }
  }

  static double getResponsiveIconSize(BuildContext context, double baseSize) {
    if (isMobile(context)) {
      return baseSize * 0.9;
    } else if (isTablet(context)) {
      return baseSize * 1.1;
    } else {
      return baseSize * 1.2;
    }
  }

  static double getResponsiveMarkerSize(BuildContext context) {
    if (isMobile(context)) {
      return 60.0;
    } else if (isTablet(context)) {
      return 80.0;
    } else {
      return 100.0;
    }
  }

  static double getResponsiveFloatingActionButtonSize(BuildContext context) {
    if (isMobile(context)) {
      return 48.0;
    } else if (isTablet(context)) {
      return 56.0;
    } else {
      return 64.0;
    }
  }

  static double getResponsiveMaxWidth(BuildContext context) {
    if (isDesktop(context)) {
      return 800.0;
    } else if (isTablet(context)) {
      return 600.0;
    } else {
      return double.infinity;
    }
  }
}

class SettingsPageState extends State<SettingsPage> {
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
      body: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: ResponsiveUtils.getResponsiveMaxWidth(context),
          ),
          child: ListView(
            padding: ResponsiveUtils.getResponsivePadding(context),
            children: [
              // Emergency Settings Section
              _buildSectionHeader('Emergency Settings'),
              _buildEmergencyCard(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),

              // Connectivity Settings
              _buildSectionHeader('Connectivity'),
              _buildConnectivityCard(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),

              // Location Settings
              _buildSectionHeader('Location Services'),
              _buildLocationCard(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),

              // Notification Settings
              _buildSectionHeader('Notifications'),
              _buildNotificationCard(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),

              // App Settings
              _buildSectionHeader('App Settings'),
              _buildAppSettingsCard(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),

              // Profile & Account
              _buildSectionHeader('Account'),
              _buildProfileCard(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 24),
              ),

              // Logout Button
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveUtils.getResponsiveSpacing(context, 8.0),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 18),
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
        padding: ResponsiveUtils.getResponsivePadding(context),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.emergency,
                color: Colors.red,
                size: ResponsiveUtils.getResponsiveIconSize(context, 28),
              ),
              title: Text(
                'Emergency Message',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                ),
              ),
              subtitle: Text(
                _emergencyMessage,
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                ),
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.edit,
                  size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                ),
                onPressed: () => _editEmergencyMessage(),
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.radio_button_checked,
                color: Theme.of(context).colorScheme.primary,
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
              title: Text(
                'Broadcast Radius',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                ),
              ),
              subtitle: Text(
                '${_broadcastRadius.toInt()} meters',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                ),
              ),
              trailing: SizedBox(
                width: ResponsiveUtils.isMobile(context) ? 80 : 120,
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
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
              title: Text(
                'Auto Location Broadcast',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                ),
              ),
              subtitle: Text(
                'Automatically broadcast location in emergency',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                ),
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            secondary: Icon(
              Icons.wifi,
              color: _wifiDirectEnabled ? Colors.green : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Wi-Fi Direct',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Enable offline device communication',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            value: _wifiDirectEnabled,
            onChanged: (value) {
              setState(() {
                _wifiDirectEnabled = value;
              });
            },
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.devices,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Nearby Devices',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Scan and manage connected devices',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onTap: () => _showNearbyDevices(),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.network_check,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Connection Status',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Check network connectivity',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            secondary: Icon(
              Icons.gps_fixed,
              color: _locationServicesEnabled ? Colors.green : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Location Services',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Enable GPS for emergency location sharing',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            value: _locationServicesEnabled,
            onChanged: (value) {
              setState(() {
                _locationServicesEnabled = value;
              });
            },
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.timer,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Location Update Interval',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              '$_locationUpdateInterval seconds',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: SizedBox(
              width: ResponsiveUtils.isMobile(context) ? 80 : 120,
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.my_location,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Current Location',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'View and test location accuracy',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            secondary: Icon(
              Icons.notifications_active,
              color: _emergencyNotifications ? Colors.orange : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Emergency Notifications',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Receive emergency alerts from nearby users',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            value: _emergencyNotifications,
            onChanged: (value) {
              setState(() {
                _emergencyNotifications = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            secondary: Icon(
              Icons.volume_up,
              color: _soundAlerts
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Sound Alerts',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Play sound for emergency notifications',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            value: _soundAlerts,
            onChanged: (value) {
              setState(() {
                _soundAlerts = value;
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            secondary: Icon(
              Icons.vibration,
              color: _vibrationAlerts
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Vibration Alerts',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Vibrate for emergency notifications',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            secondary: Icon(
              Icons.battery_charging_full,
              color: _batteryOptimization ? Colors.green : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Battery Optimization',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Optimize battery usage for background operation',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.storage,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Storage & Cache',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Manage app data and cache',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onTap: () => _showStorageSettings(),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.security,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Privacy & Security',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Manage privacy and security settings',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
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
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              radius: ResponsiveUtils.getResponsiveIconSize(context, 20),
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: ResponsiveUtils.getResponsiveIconSize(context, 20),
              ),
            ),
            title: Text(
              'Profile',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Manage your profile and emergency contacts',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onTap: () => _showProfileDialog(),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.contacts,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Emergency Contacts',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Add and manage emergency contacts',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onTap: () => _showEmergencyContacts(),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.help,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'Help & Support',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'Get help and contact support',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onTap: () => _showHelpSupport(),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: ResponsiveUtils.getResponsivePadding(context),
            leading: Icon(
              Icons.info,
              color: Theme.of(context).colorScheme.primary,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            title: Text(
              'About ResQLink',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            subtitle: Text(
              'App version and information',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onTap: () => _showAboutDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: ResponsiveUtils.getResponsiveButtonWidth(context, 400),
      child: ElevatedButton.icon(
        icon: Icon(
          Icons.logout,
          size: ResponsiveUtils.getResponsiveIconSize(context, 20),
        ),
        label: Text(
          'Logout',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: ResponsiveUtils.getResponsivePadding(context),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        onPressed: () async {
          bool? confirmLogout = await _showLogoutConfirmationDialog(context);
          if (confirmLogout == true) {
            try {
              await AuthService.logout();

              if (!mounted) return;

              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false);
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Logout failed: ${e.toString()}')),
              );
            }
          }
        },
      ),
    );
  }

  // Function to show a responsive confirmation dialog
  Future<bool?> _showLogoutConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Logout',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Logout',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
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
        title: Text(
          'Edit Emergency Message',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 160,
          decoration: InputDecoration(
            hintText: 'Enter your emergency message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _emergencyMessage = controller.text;
              });
              Navigator.pop(context);
            },
            child: Text(
              'Save',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNearbyDevices() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Nearby Devices',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'This would show a list of nearby devices available for Wi-Fi Direct connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionStatus() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Connection Status',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
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
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String title, bool status) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveUtils.getResponsiveSpacing(context, 4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            ),
          ),
          Icon(
            status ? Icons.check_circle : Icons.cancel,
            color: status ? Colors.green : Colors.red,
            size: ResponsiveUtils.getResponsiveIconSize(context, 20),
          ),
        ],
      ),
    );
  }

  void _showCurrentLocation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Current Location',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'Latitude: 8.4542° N\nLongitude: 124.6319° E\nAccuracy: ±5 meters\nLast Updated: Just now',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStorageSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Storage & Cache',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'Cache Size: 12.5 MB\nApp Data: 8.2 MB\nTotal: 20.7 MB',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Clear Cache',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacySettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Privacy & Security',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'This would show privacy and security settings including data sharing preferences and security options.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Profile',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'Name: John Doe\nPhone: +63 912 345 6789\nEmail: john.doe@example.com',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Edit',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmergencyContacts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Emergency Contacts',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'This would show a list of emergency contacts that can be notified automatically during emergencies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Add Contact',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Help & Support',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        content: const Text(
          'For help and support:\n\nEmail: support@resqlink.com\nPhone: +63 2 1234 5678\nWebsite: www.resqlink.com',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
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
        Padding(
          padding: EdgeInsets.only(top: 16.0),
          child: Text(
            'Offline emergency support using Wi-Fi Direct and GPS.\n\nStay connected even when the internet is down.',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            ),
          ),
        ),
      ],
    );
  }
}
