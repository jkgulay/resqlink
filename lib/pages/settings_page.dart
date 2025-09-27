import 'package:flutter/material.dart';
import 'package:resqlink/pages/landing_page.dart';
import 'package:resqlink/services/auth_service.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/features/database/repositories/system_repository.dart';
import 'package:resqlink/services/messaging/message_sync_service.dart';
import 'package:resqlink/services/p2p/p2p_base_service.dart';
import 'package:resqlink/services/p2p/p2p_main_service.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsPage extends StatefulWidget {
  final P2PMainService? p2pService;
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
      final allMessages = await MessageRepository.getAllMessages();
      final pendingMessages = await MessageRepository.getPendingMessages();

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
        await SystemRepository.clearAllData();
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

  Future<void> _forceRole(P2PRole role) async {
    if (widget.p2pService == null) return;

    try {
      _showMessage(
        'Forcing role to ${role.name.toUpperCase()}...',
        isSuccess: false,
      );

      if (role == P2PRole.host) {
        await widget.p2pService!.forceHostRole();
      } else if (role == P2PRole.client) {
        await widget.p2pService!.forceClientRole();
      }

      setState(() {}); // Refresh UI

      if (!mounted) return;
      _showMessage(
        'Role forced to ${role.name.toUpperCase()}',
        isSuccess: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to force role: $e', isDanger: true);
    }
  }

  Future<void> _clearForcedRole() async {
    if (widget.p2pService == null) return;

    try {
      await widget.p2pService!.clearForcedRole();
      setState(() {}); // Refresh UI

      if (!mounted) return;
      _showMessage('Returned to automatic role selection', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to clear forced role: $e', isDanger: true);
    }
  }

  void _showNetworkStatusDialog() {
    final info = widget.p2pService?.getConnectionInfo() ?? {};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'P2P Network Status',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Role', info['role'] ?? 'None'),
            _buildInfoRow(
              'Connection',
              info['isConnected'] == true ? 'Connected' : 'Disconnected',
            ),
            _buildInfoRow(
              'Connected Devices',
              '${info['connectedDevices'] ?? 0}',
            ),
            _buildInfoRow('Known Devices', '${info['knownDevices'] ?? 0}'),
            _buildInfoRow(
              'Emergency Mode',
              info['emergencyMode'] == true ? 'On' : 'Off',
            ),
            _buildInfoRow(
              'Socket Health',
              info['socketHealthy'] == true ? 'Healthy' : 'Issues',
            ),
            _buildInfoRow('Failures', '${info['consecutiveFailures'] ?? 0}'),
            if (info['isRoleForced'] == true)
              _buildInfoRow(
                'Forced Role',
                info['forcedRole'] ?? 'Unknown',
                color: ResQLinkTheme.orange,
              ),
            SizedBox(height: 8),
            // Pure WiFi Direct status only
            _buildInfoRow(
              'WiFi Direct Status',
              widget.p2pService?.wifiDirectService?.connectionState.toString().split('.').last ?? 'Unknown',
              color: widget.p2pService?.wifiDirectService?.connectionState.toString().contains('connected') == true
                  ? ResQLinkTheme.safeGreen
                  : Colors.grey,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white70)),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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
        content: Text(
          message,
          style: TextStyle(fontWeight: FontWeight.bold),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: message.contains('Password:') ? SnackBarAction(
          label: 'COPY',
          textColor: Colors.white,
          onPressed: () {
            final lines = message.split('\n');
            final passwordLine = lines.firstWhere(
              (line) => line.contains('Password:'),
              orElse: () => '',
            );
            if (passwordLine.isNotEmpty) {
              final password = passwordLine.split('Password: ').last;
              Clipboard.setData(ClipboardData(text: password));
              HapticFeedback.lightImpact();
            }
          },
        ) : null,
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

      Future.microtask(() {
        if (mounted) {
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
      padding: ResponsiveSpacing.padding(context, bottom: 12),
      child: ResponsiveTextWidget(
        title,
        styleBuilder: (context) {
          final scale = MediaQuery.of(context).size.width < 600 ? 1.0 : 1.2;
          return GoogleFonts.rajdhani(
            fontSize: 18 * scale,
            fontWeight: FontWeight.w700,
            color: ResQLinkTheme.orange,
            letterSpacing: 0.5,
          );
        },
        maxLines: 1,
        textAlign: TextAlign.start,
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 4,
      child: Padding(
        padding: ResponsiveSpacing.padding(context, all: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: ResQLinkTheme.orange),
                SizedBox(width: ResponsiveSpacing.xs(context)),
                // FIXED: Use ResponsiveTextWidget instead of ResponsiveText
                ResponsiveTextWidget(
                  'App Statistics',
                  styleBuilder: (context) => ResponsiveText.heading3(context),
                  maxLines: 1,
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            SizedBox(height: ResponsiveSpacing.md(context)),
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
        SizedBox(height: ResponsiveSpacing.xs(context)),
        ResponsiveTextWidget(
          value,
          styleBuilder: (context) => ResponsiveText.heading3(context),
          maxLines: 1,
          textAlign: TextAlign.center,
        ),
        ResponsiveTextWidget(
          label,
          styleBuilder: (context) =>
              ResponsiveText.caption(context).copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
          maxLines: 2,
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
    return Column(
      children: [
        // Existing connectivity card
        Card(
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
                onTap: _showNetworkStatusDialog,
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        // Enhanced role selection with manual force options
        _buildEnhancedRoleSection(settings),
        // Connection mode and hotspot sections removed - pure WiFi Direct only
      ],
    );
  }

  Widget _buildEnhancedRoleSection(SettingsService settings) {
    final connectionInfo = widget.p2pService?.getConnectionInfo() ?? {};
    final isRoleForced = connectionInfo['isRoleForced'] ?? false;
    final forcedRole = connectionInfo['forcedRole'];
    final currentRole = connectionInfo['role'] ?? 'none';

    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.device_hub, color: ResQLinkTheme.orange),
                SizedBox(width: 8),
                Text(
                  'Network Role Control',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Current status
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isRoleForced
                  ? ResQLinkTheme.orange.withAlpha(51)
                  : ResQLinkTheme.cardDark.withAlpha(128),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isRoleForced
                    ? ResQLinkTheme.orange.withAlpha(128)
                    : Colors.grey.withAlpha(128),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isRoleForced ? Icons.lock : Icons.auto_mode,
                      color: isRoleForced ? ResQLinkTheme.orange : Colors.grey,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      isRoleForced ? 'FORCED MODE' : 'AUTO MODE',
                      style: TextStyle(
                        color: isRoleForced
                            ? ResQLinkTheme.orange
                            : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Current role: ${currentRole.toUpperCase()}',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (isRoleForced)
                  Text(
                    'Forced as: ${forcedRole?.toString().toUpperCase() ?? 'Unknown'}',
                    style: TextStyle(color: ResQLinkTheme.orange, fontSize: 12),
                  ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Manual control buttons
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _forceRole(P2PRole.host),
                        icon: Icon(Icons.wifi_tethering, size: 18),
                        label: Text('Force HOST'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (isRoleForced && forcedRole == 'host')
                              ? ResQLinkTheme.orange
                              : ResQLinkTheme.cardDark,
                          foregroundColor: Colors.white,
                          side: BorderSide(color: ResQLinkTheme.orange),
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _forceRole(P2PRole.client),
                        icon: Icon(Icons.connect_without_contact, size: 18),
                        label: Text('Force CLIENT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (isRoleForced && forcedRole == 'client')
                              ? ResQLinkTheme.orange
                              : ResQLinkTheme.cardDark,
                          foregroundColor: Colors.white,
                          side: BorderSide(color: ResQLinkTheme.orange),
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isRoleForced ? _clearForcedRole : null,
                    icon: Icon(Icons.auto_mode, size: 18),
                    label: Text('Return to AUTO Mode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRoleForced
                          ? Colors.grey.shade700
                          : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Help text
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '• HOST: Creates a group for others to join\n'
              '• CLIENT: Connects to existing groups\n'
              '• AUTO: Let the app decide automatically\n\n'
              'Use manual control when experiencing connection issues.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),

          SizedBox(height: 16),
        ],
      ),
    );
  }

  // Connection mode section removed - pure WiFi Direct only

  // Connection mode setting removed - pure WiFi Direct only

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
