import 'package:flutter/material.dart';
import 'package:resqlink/services/auth_service.dart';
import 'package:resqlink/services/database_service.dart';
import 'package:resqlink/services/message_sync_service.dart';
import 'package:resqlink/services/p2p_service.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import 'services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  final P2PConnectionService? p2pService;
  final MessageSyncService? syncService;

  const SettingsPage({super.key, this.p2pService, this.syncService});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  // Statistics
  int _totalMessages = 0;
  int _pendingMessages = 0;
  String _storageUsed = "0 MB";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
    setState(() => _isLoading = false);
  }

  Future<void> _loadStatistics() async {
    try {
      final allMessages = await DatabaseService.getAllMessages();
      final pendingMessages = await DatabaseService.getPendingMessages();

      setState(() {
        _totalMessages = allMessages.length;
        _pendingMessages = pendingMessages.length;
        // Calculate approximate storage (rough estimate)
        final avgMessageSize = 200; // bytes
        final totalBytes = _totalMessages * avgMessageSize;
        _storageUsed = "${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB";
      });
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }
  }

  Future<void> _toggleOfflineMode(bool value) async {
    if (!mounted) return; // Add mounted check

    await context.read<SettingsService>().setOfflineMode(value);

    if (!mounted) return; // Check again after async operation

    _showMessage(
      value
          ? 'Offline mode enabled - App will work purely with SQLite and P2P'
          : 'Online mode enabled - Firebase sync restored',
      isSuccess: true,
    );
  }

  Future<void> _toggleLocationSharing(bool value) async {
    if (value) {
      // Check location permissions when enabling
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final newPermission = await Geolocator.requestPermission();
        if (newPermission == LocationPermission.denied ||
            newPermission == LocationPermission.deniedForever) {
          if (!mounted) return;
          _showMessage(
            'Location permission required for location sharing',
            isDanger: true,
          );
          return;
        }
      }
    }

    if (!mounted) return;
    await context.read<SettingsService>().setLocationSharing(value);

    if (!mounted) return;
    _showMessage(
      value ? 'Location sharing enabled' : 'Location sharing disabled',
      isSuccess: true,
    );
  }

  Future<void> _toggleMultiHop(bool value) async {
    if (!mounted) return;
    await context.read<SettingsService>().setMultiHop(value);

    // Apply to P2P service if available
    if (widget.p2pService != null) {
      debugPrint('Multi-hop ${value ? 'enabled' : 'disabled'}');
    }

    if (!mounted) return;
    _showMessage(
      value
          ? 'Multi-hop message relaying enabled'
          : 'Multi-hop message relaying disabled',
      isSuccess: true,
    );
  }

  Future<void> _clearChatHistory() async {
    final confirm = await _showConfirmationDialog(
      title: 'Clear Chat History',
      content:
          'This will permanently delete all messages from your device. This action cannot be undone.',
      confirmText: 'Delete All',
      isDangerous: true,
    );

    if (confirm == true) {
      try {
        await DatabaseService.clearAllData();
        await _loadStatistics();
        if (!mounted) return;
        _showMessage('Chat history cleared successfully', isSuccess: true);
      } catch (e) {
        if (!mounted) return;
        _showMessage('Failed to clear chat history: $e', isDanger: true);
      }
    }
  }

  Future<void> _resyncAllMessages() async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();

    if (settings.offlineMode) {
      _showMessage('Cannot sync in offline mode', isWarning: true);
      return;
    }

    try {
      _showMessage('Syncing pending messages...', isSuccess: false);

      if (widget.syncService != null) {
        await widget.syncService!.syncPendingMessages();
      }

      await _loadStatistics();
      if (!mounted) return;
      _showMessage('All pending messages synced successfully', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Sync failed: $e', isDanger: true);
    }
  }

  Future<void> _testNotifications() async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();

    try {
      // Test notification with current settings
      HapticFeedback.mediumImpact();

      if (settings.vibrationNotifications && !settings.silentMode) {
        await HapticFeedback.heavyImpact();
      }

      if (!mounted) return;
      _showMessage(
        'Test notification sent with current settings',
        isSuccess: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to test notifications: $e', isDanger: true);
    }
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String content,
    required String confirmText,
    bool isDangerous = false,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: ResQLinkTheme.cardDark,
          title: Text(title, style: TextStyle(color: Colors.white)),
          content: Text(content, style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                confirmText,
                style: TextStyle(
                  color: isDangerous
                      ? ResQLinkTheme.primaryRed
                      : ResQLinkTheme.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(
    String message, {
    bool isSuccess = false,
    bool isWarning = false,
    bool isDanger = false,
  }) {
    if (!mounted) return;

    final color = isDanger
        ? ResQLinkTheme.primaryRed
        : isWarning
        ? ResQLinkTheme.warningYellow
        : isSuccess
        ? ResQLinkTheme.safeGreen
        : Colors.blue;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _logout(bool clearOfflineCredentials) async {
    final confirm = await _showConfirmationDialog(
      title: clearOfflineCredentials ? 'Full Logout & Clear Data' : 'Logout',
      content: clearOfflineCredentials
          ? 'This will sign you out and remove all offline login capabilities. You will need an internet connection to sign in again.'
          : 'This will sign you out but preserve your ability to login offline with the same credentials.',
      confirmText: clearOfflineCredentials ? 'Clear All Data' : 'Logout',
      isDangerous: clearOfflineCredentials,
    );

    if (confirm != true) return;
    if (!mounted) return;

    // Show loading state
    setState(() => _isLoading = true);

    try {
      // Perform logout
      if (clearOfflineCredentials) {
        await AuthService.clearAllUserData();
      } else {
        await AuthService.logout(clearOfflineCredentials: false);
      }

      // Navigate after a microtask to ensure state updates
      Future.microtask(() {
        if (mounted) {
          // Navigate to the LandingPage (now properly imported)
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LandingPage()),
            (route) => false,
          );
        }
      });
    } catch (e) {
      print('Logout error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Logout failed: $e', isDanger: true);
      }
    }
  }

  // Update your build method to show loading overlay when _isLoading is true
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Your existing build content
        Consumer<SettingsService>(
          builder: (context, settings, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                primaryColor: ResQLinkTheme.orange,
                scaffoldBackgroundColor: ResQLinkTheme.backgroundDark,
              ),
              child: Scaffold(
                backgroundColor: ResQLinkTheme.backgroundDark,
                body: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Your existing content...
                          _buildStatisticsCard(),
                          SizedBox(height: 24),
                          _buildSectionHeader('Messaging'),
                          _buildMessagingSection(settings),
                          SizedBox(height: 24),
                          _buildSectionHeader('Connectivity'),
                          _buildConnectivitySection(settings),
                          SizedBox(height: 24),
                          _buildSectionHeader('Location Services'),
                          _buildLocationSection(settings),
                          SizedBox(height: 24),
                          _buildSectionHeader('Notifications'),
                          _buildNotificationSection(settings),
                          SizedBox(height: 24),
                          _buildSectionHeader('Data Management'),
                          _buildDataManagementSection(settings),
                          SizedBox(height: 24),
                          _buildSectionHeader('Account'),
                          _buildAccountSection(),
                          SizedBox(height: 100),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Loading overlay
        if (_isLoading)
          Material(
            color: Colors.black.withAlpha(178),
            child: Center(
              child: Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.cardDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: ResQLinkTheme.primaryRed),
                    SizedBox(width: 16),
                    Text(
                      'Logging out...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: ResQLinkTheme.orange,
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: ResQLinkTheme.orange),
                SizedBox(width: 8),
                Text(
                  'App Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Total Messages',
                  '$_totalMessages',
                  Icons.message,
                ),
                _buildStatItem(
                  'Pending Sync',
                  '$_pendingMessages',
                  Icons.sync_problem,
                ),
                _buildStatItem('Storage Used', _storageUsed, Icons.storage),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: ResQLinkTheme.orange, size: 24),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMessagingSection(SettingsService settings) {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            title: Text('Offline Mode', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Force app to work purely with SQLite and P2P',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.offlineMode,
            onChanged: _toggleOfflineMode,
            secondary: Icon(
              settings.offlineMode ? Icons.cloud_off : Icons.cloud_done,
              color: settings.offlineMode
                  ? ResQLinkTheme.warningYellow
                  : ResQLinkTheme.safeGreen,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          SwitchListTile(
            title: Text('Auto Sync', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Automatically sync messages when online',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.autoSync && !settings.offlineMode,
            onChanged: settings.offlineMode
                ? null
                : (value) async {
                    await settings.setAutoSync(value);
                  },
            secondary: Icon(
              Icons.sync,
              color: (settings.autoSync && !settings.offlineMode)
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Re-sync All Messages',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Force sync all pending messages to Firebase',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(
              Icons.cloud_upload,
              color: settings.offlineMode ? Colors.grey : ResQLinkTheme.orange,
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: settings.offlineMode ? null : _resyncAllMessages,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectivitySection(SettingsService settings) {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(
              'Multi-hop Relaying',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Allow messages to relay through other devices',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.multiHopEnabled,
            onChanged: _toggleMultiHop,
            secondary: Icon(
              Icons.device_hub,
              color: settings.multiHopEnabled
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'P2P Network Status',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              widget.p2pService?.isConnected == true
                  ? 'Connected to ${widget.p2pService?.connectedDevices.length ?? 0} devices'
                  : 'Not connected',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(
              Icons.wifi_tethering,
              color: widget.p2pService?.isConnected == true
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            trailing: Icon(Icons.info_outline, color: Colors.white54),
            onTap: () {
              final info = widget.p2pService?.getConnectionInfo() ?? {};
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: ResQLinkTheme.cardDark,
                  title: Text(
                    'P2P Status',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Role: ${info['role'] ?? 'None'}',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Connected Devices: ${info['connectedDevices'] ?? 0}',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Known Devices: ${info['knownDevices'] ?? 0}',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Emergency Mode: ${widget.p2pService?.emergencyMode == true ? 'On' : 'Off'}',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'OK',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(SettingsService settings) {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(
              'Location Sharing',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Allow app to share your location in messages',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.locationSharingEnabled,
            onChanged: _toggleLocationSharing,
            secondary: Icon(
              Icons.location_on,
              color: settings.locationSharingEnabled
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Location Permissions',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Manage location access for the app',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.security, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () async {
              await Geolocator.openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(SettingsService settings) {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(
              'Emergency Notifications',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Receive alerts for emergency messages',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.emergencyNotifications,
            onChanged: (value) async {
              await settings.setEmergencyNotifications(value);
            },
            secondary: Icon(
              Icons.emergency,
              color: settings.emergencyNotifications
                  ? ResQLinkTheme.orange
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          SwitchListTile(
            title: Text(
              'Sound Notifications',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Play sound for new messages',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.soundNotifications && !settings.silentMode,
            onChanged: settings.silentMode
                ? null
                : (value) async {
                    await settings.setSoundNotifications(value);
                  },
            secondary: Icon(
              Icons.volume_up,
              color: (settings.soundNotifications && !settings.silentMode)
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          SwitchListTile(
            title: Text('Vibration', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Vibrate for new messages',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.vibrationNotifications && !settings.silentMode,
            onChanged: settings.silentMode
                ? null
                : (value) async {
                    await settings.setVibrationNotifications(value);
                  },
            secondary: Icon(
              Icons.vibration,
              color: (settings.vibrationNotifications && !settings.silentMode)
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          SwitchListTile(
            title: Text('Silent Mode', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Disable all sounds and vibrations',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.silentMode,
            onChanged: (value) async {
              await settings.setSilentMode(value);
            },
            secondary: Icon(
              Icons.notifications_off,
              color: settings.silentMode
                  ? ResQLinkTheme.warningYellow
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Test Notifications',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Test current notification settings',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(
              Icons.notifications_active,
              color: ResQLinkTheme.orange,
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: _testNotifications,
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementSection(SettingsService settings) {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          SwitchListTile(
            title: Text(
              'Background Sync',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Sync messages in the background',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: settings.backgroundSync && !settings.offlineMode,
            onChanged: settings.offlineMode
                ? null
                : (value) async {
                    await settings.setBackgroundSync(value);
                  },
            secondary: Icon(
              Icons.sync_outlined,
              color: (settings.backgroundSync && !settings.offlineMode)
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
            activeColor: ResQLinkTheme.orange,
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Clear Chat History',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Delete all messages from device',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.delete_forever, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: _clearChatHistory,
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Export Chat Data',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Export messages for backup',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.file_download, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              _showMessage('Export feature coming soon', isWarning: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection() {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            title: Text(
              'About ResQLink',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'App version and information',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.info, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'ResQLink',
                applicationVersion: '1.0.0',
                applicationIcon: Icon(
                  Icons.emergency,
                  size: 48,
                  color: ResQLinkTheme.orange,
                ),
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Offline emergency communication using Wi-Fi Direct and GPS.\n\n'
                      'Stay connected even when the internet is down.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              );
            },
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Logout (Keep Offline Access)',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Sign out but allow offline login later',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.logout, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _logout(false), // Don't clear offline credentials
          ),
          Divider(color: Colors.white24, height: 1),
          ListTile(
            title: Text(
              'Full Logout & Clear Data',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
            subtitle: Text(
              'Sign out and remove all offline access',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(
              Icons.delete_forever,
              color: ResQLinkTheme.primaryRed,
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _logout(true), // Clear everything
          ),
        ],
      ),
    );
  }
}
