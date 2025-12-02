import 'package:flutter/material.dart';
import 'package:resqlink/utils/offline_fonts.dart';
import 'package:resqlink/features/database/repositories/chat_repository.dart';
import 'package:resqlink/features/database/repositories/location_repository.dart';
import 'package:resqlink/pages/landing_page.dart';
import 'package:resqlink/services/auth_service.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/features/database/repositories/system_repository.dart';
import 'package:resqlink/services/messaging/message_sync_service.dart';
import 'package:resqlink/services/p2p/p2p_main_service.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
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
          title: Text(
            title,
            style: OfflineFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          content: Text(
            content,
            style: OfflineFonts.poppins(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: OfflineFonts.poppins(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                confirmText,
                style: OfflineFonts.poppins(
                  color: isDangerous
                      ? ResQLinkTheme.primaryRed
                      : ResQLinkTheme.orange,
                  fontWeight: FontWeight.w700,
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
          style: OfflineFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<SettingsService>(
          builder: (context, settings, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                primaryColor: Color(0xFFFF6500),
                scaffoldBackgroundColor: Colors.black,
              ),
              child: Scaffold(
                backgroundColor: Colors.black,
                body: Container(
                  decoration: BoxDecoration(color: Colors.black),
                  child: CustomScrollView(
                    slivers: [
                      _buildStyledAppBar(),
                      SliverPadding(
                        padding: EdgeInsets.all(16),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildSectionHeader('Statistics'),
                            _buildStatisticsCard(),
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
                            SizedBox(height: 24),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Loading overlay
        if (_isLoading)
          Material(
            color: Colors.black.withValues(alpha: 0.7),
            child: Center(
              child: Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1E3E62).withValues(alpha: 0.95),
                      Color(0xFF0B192C).withValues(alpha: 0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Color(0xFFFF6500).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFF6500).withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFFFF6500),
                      strokeWidth: 3,
                    ),
                    SizedBox(width: 20),
                    Text(
                      'Logging out...',
                      style: OfflineFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  SliverAppBar _buildStyledAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: false,
      pinned: false,
      toolbarHeight: 0,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: ResponsiveSpacing.padding(context, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFF6500),
                  Color(0xFFFF6500).withValues(alpha: 0.5),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 12),
          Text(
            title,
            style: OfflineFonts.poppins(
              color: Colors.white,
              fontSize: ResponsiveHelper.getTitleSize(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3E62).withValues(alpha: 0.9),
            Color(0xFF0B192C).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: ResponsiveHelper.getCardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(0xFFFF6500).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.analytics,
                    color: Color(0xFFFF6500),
                    size: ResponsiveHelper.getIconSize(context),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.getContentSpacing(context)),
                Text(
                  'App Statistics',
                  style: OfflineFonts.poppins(
                    color: Colors.white,
                    fontSize: ResponsiveHelper.getTitleSize(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getSectionSpacing(context)),
            // Row 1: Messages, Sessions, Locations
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Messages',
                    '$_totalMessages',
                    Icons.message,
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Color(0xFFFF6500).withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Sessions',
                    '$_totalSessions',
                    Icons.chat_bubble,
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Color(0xFFFF6500).withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Locations',
                    '$_totalLocations',
                    Icons.location_on,
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
            Divider(
              color: Color(0xFFFF6500).withValues(alpha: 0.2),
              thickness: 1.5,
            ),
            SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
            // Row 2: Connections and Storage
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Connections',
                    '$_activeConnections',
                    Icons.devices,
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Color(0xFFFF6500).withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _buildStatItem('Storage', _storageUsed, Icons.storage),
                ),
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
        Icon(
          icon,
          color: Color(0xFFFF6500),
          size: ResponsiveHelper.getIconSize(context) * 0.8,
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: OfflineFonts.poppins(
            color: Colors.white,
            fontSize: ResponsiveHelper.getTitleSize(context),
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: OfflineFonts.poppins(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: ResponsiveHelper.getSubtitleSize(context) - 2,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildEnhancedSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
    bool? enabled,
  }) {
    final isEnabled = enabled ?? true;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.getCardPadding(context).left,
          vertical: 8,
        ),
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: value && isEnabled
                ? Color(0xFF1E3A5F).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: value && isEnabled
                ? Color(0xFF4A90E2)
                : Colors.white.withValues(alpha: 0.4),
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: OfflineFonts.poppins(
            color: isEnabled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.5),
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: OfflineFonts.poppins(
            color: isEnabled
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.3),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: isEnabled ? onChanged : null,
          activeColor: Color(0xFFFF6500),
          activeTrackColor: Color(0xFFFF6500).withValues(alpha: 0.5),
          inactiveThumbColor: Colors.white.withValues(alpha: 0.3),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  Widget _buildLocationSection(SettingsService settings) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3E62).withValues(alpha: 0.9),
            Color(0xFF0B192C).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildEnhancedSwitchTile(
            title: 'Location Sharing',
            subtitle: 'Allow app to share your location in messages',
            icon: Icons.location_on,
            value: settings.locationSharingEnabled,
            onChanged: _toggleLocationSharing,
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFFFF6500).withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.getCardPadding(context).left,
                vertical: 8,
              ),
              leading: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFFF6500).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.security, color: Color(0xFFFF6500), size: 24),
              ),
              title: Text(
                'Location Permissions',
                style: OfflineFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                'Manage location access for the app',
                style: OfflineFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Color(0xFFFF6500).withValues(alpha: 0.6),
              ),
              onTap: () async {
                await Geolocator.openAppSettings();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(SettingsService settings) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3E62).withValues(alpha: 0.9),
            Color(0xFF0B192C).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildEnhancedSwitchTile(
            title: 'Emergency Notifications',
            subtitle: 'Receive alerts for emergency messages',
            icon: Icons.emergency,
            value: settings.emergencyNotifications,
            onChanged: (value) async {
              await settings.setEmergencyNotifications(value);
            },
          ),
          _buildEnhancedSwitchTile(
            title: 'Sound Notifications',
            subtitle: 'Play sound for new messages',
            icon: Icons.volume_up,
            value: settings.soundNotifications && !settings.silentMode,
            onChanged: (value) async {
              if (!settings.silentMode) {
                await settings.setSoundNotifications(value);
              }
            },
            enabled: !settings.silentMode,
          ),
          _buildEnhancedSwitchTile(
            title: 'Vibration',
            subtitle: 'Vibrate for new messages',
            icon: Icons.vibration,
            value: settings.vibrationNotifications && !settings.silentMode,
            onChanged: (value) async {
              if (!settings.silentMode) {
                await settings.setVibrationNotifications(value);
              }
            },
            enabled: !settings.silentMode,
          ),
          _buildEnhancedSwitchTile(
            title: 'Silent Mode',
            subtitle: 'Disable all sounds and vibrations',
            icon: Icons.notifications_off,
            value: settings.silentMode,
            onChanged: (value) async {
              await settings.setSilentMode(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementSection(SettingsService settings) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3E62).withValues(alpha: 0.9),
            Color(0xFF0B192C).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.getCardPadding(context).left,
                vertical: 8,
              ),
              leading: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFFF6500).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.merge, color: Color(0xFFFF6500), size: 24),
              ),
              title: Text(
                'Merge Duplicate Sessions',
                style: OfflineFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                'Clean up and merge duplicate chat sessions',
                style: OfflineFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Color(0xFFFF6500).withValues(alpha: 0.6),
              ),
              onTap: _mergeDuplicateSessions,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFFFF6500).withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.getCardPadding(context).left,
                vertical: 8,
              ),
              leading: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.delete_forever,
                  color: Colors.red.shade400,
                  size: 24,
                ),
              ),
              title: Text(
                'Clear Chat History',
                style: OfflineFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                'Delete all messages from device',
                style: OfflineFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Colors.red.shade400.withValues(alpha: 0.6),
              ),
              onTap: _clearChatHistory,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3E62).withValues(alpha: 0.9),
            Color(0xFF0B192C).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.getCardPadding(context).left,
                vertical: 8,
              ),
              leading: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFFF6500).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.info, color: Color(0xFFFF6500), size: 24),
              ),
              title: Text(
                'About ResQLink',
                style: OfflineFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                'App version and information',
                style: OfflineFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Color(0xFFFF6500).withValues(alpha: 0.6),
              ),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'ResQLink',
                  applicationVersion: '1.0.0',
                  applicationIcon: Icon(
                    Icons.emergency,
                    size: 48,
                    color: Color(0xFFFF6500),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Offline emergency communication using Wi-Fi Direct and GPS.\n\n'
                        'Stay connected even when the internet is down.',
                        style: OfflineFonts.poppins(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.getCardPadding(context).left,
                vertical: 8,
              ),
              leading: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.logout, color: Colors.red.shade400, size: 24),
              ),
              title: Text(
                'Logout',
                style: OfflineFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                'Sign out from the application',
                style: OfflineFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Colors.red.shade400.withValues(alpha: 0.6),
              ),
              onTap: () => _logout(false),
            ),
          ),
        ],
      ),
    );
  }
}
