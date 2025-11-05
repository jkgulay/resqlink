import 'package:flutter/material.dart';
import 'package:resqlink/features/database/repositories/chat_repository.dart';
import 'package:resqlink/features/database/repositories/location_repository.dart';
import 'package:resqlink/pages/landing_page.dart';
import 'package:resqlink/services/auth_service.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/features/database/repositories/system_repository.dart';
import 'package:resqlink/services/messaging/message_sync_service.dart';
import 'package:resqlink/services/p2p/p2p_main_service.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

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
  int _totalSessions = 0;
  int _totalLocations = 0;
  int _activeConnections = 0;
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
      // Get message counts
      final allMessages = await MessageRepository.getAllMessages();

      // Get chat session count
      final allSessions = await ChatRepository.getAllSessions();

      // Get location statistics
      final locationStats = await LocationRepository.getLocationStats();
      final totalLocations = locationStats['totalLocations'] as int? ?? 0;

      // Calculate total storage (Database + FMTC offline maps)
      double totalStorage = 0;

      // 1. Get database file size
      final dbPath = await getDatabasesPath();
      final dbFile = File(path.join(dbPath, 'resqlink_enhanced.db'));
      final dbSize = await dbFile.exists() ? await dbFile.length() : 0;
      totalStorage += dbSize.toDouble();

      // 2. Get FMTC offline map storage
      try {
        // Get Philippines base tiles storage
        final philippinesStore = FMTCStore('philippines_tiles');
        final philippinesSize = await philippinesStore.stats.size;
        totalStorage += philippinesSize;

        // Get user cache storage
        final userCacheStore = FMTCStore('user_cache');
        final userCacheSize = await userCacheStore.stats.size;
        totalStorage += userCacheSize;

        debugPrint('📊 Storage breakdown:');
        debugPrint(
          '  Database: ${(dbSize / (1024 * 1024)).toStringAsFixed(2)} MB',
        );
        debugPrint(
          '  Philippines tiles: ${(philippinesSize / (1024 * 1024)).toStringAsFixed(2)} MB',
        );
        debugPrint(
          '  User cache: ${(userCacheSize / (1024 * 1024)).toStringAsFixed(2)} MB',
        );
        debugPrint(
          '  Total: ${(totalStorage / (1024 * 1024)).toStringAsFixed(2)} MB',
        );
      } catch (e) {
        debugPrint('⚠️ Error getting FMTC storage: $e');
      }

      // Get active P2P connections
      final connectedDevices = widget.p2pService?.connectedDevices.length ?? 0;

      setState(() {
        _totalMessages = allMessages.length;
        _totalSessions = allSessions.length;
        _totalLocations = totalLocations;
        _activeConnections = connectedDevices;
        // Calculate actual storage including offline maps
        _storageUsed =
            "${(totalStorage / (1024 * 1024)).toStringAsFixed(2)} MB";
      });
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }
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

  Future<void> _mergeDuplicateSessions() async {
    final confirm = await _showConfirmationDialog(
      title: 'Merge Duplicate Sessions',
      content:
          'This will find and merge all duplicate chat sessions for the same device. Messages will be preserved.',
      confirmText: 'Merge Sessions',
      isDangerous: false,
    );

    if (confirm == true) {
      try {
        _showMessage('Merging duplicate sessions...', isSuccess: false);

        final duplicatesMerged =
            await ChatRepository.cleanupDuplicateSessions();

        await _loadStatistics();
        if (!mounted) return;

        if (duplicatesMerged > 0) {
          _showMessage(
            'Successfully merged $duplicatesMerged duplicate session${duplicatesMerged == 1 ? '' : 's'}',
            isSuccess: true,
          );
        } else {
          _showMessage('No duplicate sessions found', isSuccess: true);
        }
      } catch (e) {
        if (!mounted) return;
        _showMessage('Failed to merge sessions: $e', isDanger: true);
      }
    }
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
        action: message.contains('Password:')
            ? SnackBarAction(
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
              )
            : null,
      ),
    );
  }

  Future<void> _logout(bool clearOfflineCredentials) async {
    final confirm = await _showConfirmationDialog(
      title: 'Logout',
      content: 'This will sign you out from the application.',
      confirmText: 'Logout',
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
                ResponsiveTextWidget(
                  'App Statistics',
                  styleBuilder: (context) => ResponsiveText.heading3(context),
                  maxLines: 1,
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            SizedBox(height: ResponsiveSpacing.md(context)),
            // Row 1: Messages and Sessions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Messages', '$_totalMessages', Icons.message),
                _buildStatItem(
                  'Sessions',
                  '$_totalSessions',
                  Icons.chat_bubble,
                ),
                _buildStatItem(
                  'Locations',
                  '$_totalLocations',
                  Icons.location_on,
                ),
              ],
            ),
            SizedBox(height: ResponsiveSpacing.md(context)),
            Divider(color: Colors.white24, height: 1),
            SizedBox(height: ResponsiveSpacing.md(context)),
            // Row 2: Connections and storage
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Connections',
                  '$_activeConnections',
                  Icons.devices,
                ),
                _buildStatItem('Storage', _storageUsed, Icons.storage),
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
            ],
          ),
        ),
        // Connection mode and hotspot sections removed - pure WiFi Direct only
      ],
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
          ListTile(
            title: Text(
              'Merge Duplicate Sessions',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Clean up and merge duplicate chat sessions',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.merge, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: _mergeDuplicateSessions,
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
            title: Text('Logout', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Sign out from the application',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            leading: Icon(Icons.logout, color: ResQLinkTheme.orange),
            trailing: Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _logout(false),
          ),
        ],
      ),
    );
  }
}
