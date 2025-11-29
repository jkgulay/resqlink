import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_session_model.dart';
import '../features/database/repositories/chat_repository.dart';
import '../services/p2p/p2p_main_service.dart';
import 'package:resqlink/helpers/chat_navigation_helper.dart';
import '../utils/resqlink_theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/responsive_helper.dart';
import '../widgets/message/empty_chat_view.dart';
import '../widgets/message/loading_view.dart';
import 'dart:async';

class ChatListPage extends StatefulWidget {
  final P2PMainService p2pService;
  final Function(String sessionId, String deviceName)? onChatSelected;

  const ChatListPage({
    super.key,
    required this.p2pService,
    this.onChatSelected,
  });

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with WidgetsBindingObserver {
  List<ChatSessionSummary> _chatSessions = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChatSessions();
    _startPeriodicRefresh();
    _setupMessageRouterListener();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChatSessions();
      _startPeriodicRefresh();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    }
  }

  void _setupMessageRouterListener() {
    // Set up global listener to refresh chat list when new messages arrive
    widget.p2pService.messageRouter.setGlobalListener(_onGlobalMessage);
    debugPrint('📱 ChatListPage registered MessageRouter global listener');
  }

  void _onGlobalMessage(dynamic message) {
    // Refresh chat sessions when any message is received
    if (mounted) {
      _loadChatSessions();
    }
  }

  /// Get queue statistics for display - DISABLED
  Map<String, dynamic> _getQueueStatistics() {
    // Message queue service removed - return empty stats
    return {
      'totalQueued': 0,
      'totalSent': 0,
      'totalFailed': 0,
      'currentQueueSize': 0,
      'queuesByDevice': <String, int>{},
    };
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (mounted) {
        _loadChatSessions();
      }
    });
  }

  Future<void> _loadChatSessions() async {
    if (!mounted) return;

    try {
      final sessions = await ChatRepository.getChatSessions();
      final connectedDevices = widget.p2pService.connectedDevices;
      final discoveredDevices = widget.p2pService.discoveredResQLinkDevices;

      final updatedSessions = sessions.map((session) {
        String updatedName = session.deviceName;
        // Check connected devices first for the most accurate name
        if (connectedDevices.containsKey(session.deviceId)) {
          updatedName = connectedDevices[session.deviceId]!.userName;
        } else {
          // Fallback to discovered devices
          try {
            final discovered = discoveredDevices.firstWhere(
              (d) => d.deviceId == session.deviceId,
            );
            updatedName = discovered.userName;
          } catch (e) {
            // Device not found in discovered list, keep existing name
          }
        }
        return session.copyWith(deviceName: updatedName);
      }).toList();

      if (mounted) {
        setState(() {
          _chatSessions = updatedSessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading chat sessions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openChat(ChatSessionSummary session) async {
    if (widget.onChatSelected != null) {
      widget.onChatSelected!(session.sessionId, session.deviceName);
    } else {
      // Use ChatNavigationHelper for proper session management
      await ChatNavigationHelper.navigateToSession(
        context: context,
        sessionId: session.sessionId,
        deviceName: session.deviceName,
        deviceId: session.deviceId,
        p2pService: widget.p2pService,
      );
    }

    // Mark messages as read
    await ChatRepository.markSessionMessagesAsRead(session.sessionId);
    _loadChatSessions();
  }

  Future<void> _deleteChat(ChatSessionSummary session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text('Delete Chat', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete the chat with ${session.deviceName}? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ChatRepository.deleteSession(session.sessionId);
      _loadChatSessions();
      _showSnackBar('Chat deleted', isError: false);
    }
  }

  Future<void> _reconnectToDevice(ChatSessionSummary session) async {
    try {
      _showSnackBar('Attempting to reconnect to ${session.deviceName}...');

      await widget.p2pService.discoverDevices(force: true);
      await Future.delayed(Duration(seconds: 2));

      final devices = widget.p2pService.discoveredDevices;
      Map<String, dynamic>? targetDevice;

      if (devices.containsKey(session.deviceId)) {
        targetDevice = devices[session.deviceId];
      } else {
        for (final deviceData in devices.values) {
          if (deviceData['deviceId'] == session.deviceId ||
              deviceData['endpointId'] == session.deviceId) {
            targetDevice = deviceData;
            break;
          }
        }
      }

      if (targetDevice != null && targetDevice.isNotEmpty) {
        final success = await widget.p2pService.connectToDevice(targetDevice);
        if (success) {
          await ChatRepository.updateSessionConnection(
            sessionId: session.sessionId,
            connectionType: ConnectionType.wifiDirect,
            connectionTime: DateTime.now(),
          );
          _loadChatSessions();
          _showSnackBar(
            'Reconnected to ${session.deviceName}!',
            isError: false,
          );
        } else {
          _showSnackBar('Failed to reconnect. Try creating a new connection.');
        }
      } else {
        _showSnackBar('Device not found. Try scanning again.');
      }
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
      _showSnackBar('Reconnection failed. Try manual connection.');
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: isError
            ? ResQLinkTheme.primaryRed
            : ResQLinkTheme.safeGreen,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0B192C),
      extendBodyBehindAppBar: false,
      appBar: _buildStyledAppBar(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C),
              Color(0xFF1E3E62).withValues(alpha: 0.8),
              Color(0xFF0B192C),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: ResponsiveUtils.isDesktop(context)
                    ? BoxConstraints(maxWidth: 1200)
                    : BoxConstraints(),
                child: Column(
                  children: [
                    _buildConnectionStatus(),
                    Expanded(child: _buildChatList()),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  PreferredSizeWidget _buildStyledAppBar(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;
    final queueStats = _getQueueStatistics();
    final totalQueued = queueStats['totalQueued'] as int? ?? 0;

    return AppBar(
      elevation: 8,
      shadowColor: Colors.black45,
      backgroundColor: Colors.transparent,
      toolbarHeight: isNarrow ? 56.0 : 64.0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B192C), Color(0xFF1E3E62), Color(0xFF2A5278)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0xFFFF6500).withValues(alpha: 0.2),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            color: Color(0xFFFF6500),
            size: ResponsiveHelper.getIconSize(context, narrow: 24),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Messages',
                  style: ResponsiveText.heading3(context).copyWith(
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Color(0xFFFF6500).withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                if (!isNarrow && _chatSessions.isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    '${_chatSessions.length} conversation${_chatSessions.length != 1 ? 's' : ''}',
                    style: ResponsiveText.caption(
                      context,
                    ).copyWith(color: Colors.white60, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (totalQueued > 0)
            Container(
              margin: EdgeInsets.only(left: 8),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange, Colors.deepOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    '$totalQueued',
                    style: ResponsiveText.caption(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        Container(
          margin: EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Color(0xFFFF6500).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.refresh, color: Color(0xFFFF6500)),
            onPressed: _loadChatSessions,
            tooltip: 'Refresh chats',
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    if (!widget.p2pService.isConnected) {
      return Container(
        margin: EdgeInsets.all(ResponsiveHelper.getContentSpacing(context)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
              ResQLinkTheme.primaryRed.withValues(alpha: 0.1),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ResQLinkTheme.primaryRed.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: ResponsiveHelper.getCardPadding(context),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.wifi_off,
                  color: ResQLinkTheme.primaryRed,
                  size: ResponsiveHelper.getIconSize(context, narrow: 24),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Active Connections',
                      style: ResponsiveText.bodyLarge(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Connect to devices to start messaging',
                      style: ResponsiveText.bodySmall(
                        context,
                      ).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox.shrink();
  }

  Widget _buildChatList() {
    if (_isLoading) {
      return LoadingView();
    }

    if (_chatSessions.isEmpty) {
      return EmptyChatView(p2pService: widget.p2pService);
    }

    return RefreshIndicator(
      onRefresh: _loadChatSessions,
      color: ResQLinkTheme.primaryRed,
      child: ResponsiveUtils.isDesktop(context)
          ? _buildDesktopChatList(_chatSessions)
          : ListView.builder(
              padding: ResponsiveHelper.getCardMargins(context),
              itemCount: _chatSessions.length,
              itemBuilder: (context, index) {
                final session = _chatSessions[index];
                return _buildChatListItem(session);
              },
            ),
    );
  }

  Widget _buildDesktopChatList(List<ChatSessionSummary> sessions) {
    return Padding(
      padding: ResponsiveHelper.getCardMargins(context),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: ResponsiveUtils.isDesktop(context) ? 2 : 1,
          crossAxisSpacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
          mainAxisSpacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
          childAspectRatio: 4.0,
        ),
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          return _buildChatListItem(session);
        },
      ),
    );
  }

  Widget _buildChatListItem(ChatSessionSummary session) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.getCardMargins(context).horizontal / 2,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3E62).withValues(alpha: 0.6),
            Color(0xFF0B192C).withValues(alpha: 0.4),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: session.isOnline
              ? Color(0xFFFF6500).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: session.isOnline
                ? Color(0xFFFF6500).withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChat(session),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                _buildAvatar(session),
                SizedBox(width: 16),
                Expanded(child: _buildChatInfo(session)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildTimestamp(session),
                    SizedBox(height: 8),
                    _buildBadges(session),
                  ],
                ),
                SizedBox(width: 8),
                _buildOptionsMenu(session),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ChatSessionSummary session) {
    return Stack(
      children: [
        FutureBuilder<String>(
          future: _getDisplayName(session.deviceName),
          builder: (context, snapshot) {
            final displayName = snapshot.data ?? session.deviceName;
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: session.isOnline
                    ? LinearGradient(
                        colors: [
                          ResQLinkTheme.safeGreen,
                          ResQLinkTheme.safeGreen.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [Colors.grey.shade700, Colors.grey.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: session.isOnline
                        ? ResQLinkTheme.safeGreen.withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.transparent,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'D',
                  style: ResponsiveText.heading3(
                    context,
                  ).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        ),
        if (session.isOnline)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ResQLinkTheme.safeGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFF0B192C), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: ResQLinkTheme.safeGreen.withValues(alpha: 0.6),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatInfo(ChatSessionSummary session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: _getDisplayName(session.deviceName),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? session.deviceName,
                    style: ResponsiveText.bodyLarge(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ),
            if (session.connectionType != null) ...[
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: session.isOnline
                      ? ResQLinkTheme.safeGreen.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      session.connectionType == ConnectionType.wifiDirect
                          ? Icons.wifi
                          : Icons.wifi_tethering,
                      size: 12,
                      color: session.isOnline
                          ? ResQLinkTheme.safeGreen
                          : Colors.white38,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                session.lastMessage ?? 'No messages yet',
                style: ResponsiveText.bodySmall(context).copyWith(
                  color: session.lastMessage != null
                      ? Colors.white70
                      : Colors.white38,
                  fontStyle: session.lastMessage == null
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 2),
        Text(
          session.connectionStatusText,
          style: TextStyle(
            color: session.isOnline ? ResQLinkTheme.safeGreen : Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTimestamp(ChatSessionSummary session) {
    return Text(
      session.timeDisplay,
      style: TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  Widget _buildBadges(ChatSessionSummary session) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (session.unreadCount > 0)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ResQLinkTheme.primaryRed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              session.unreadCount > 99 ? '99+' : session.unreadCount.toString(),
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionsMenu(ChatSessionSummary session) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.white60),
      color: ResQLinkTheme.cardDark,
      onSelected: (value) async {
        switch (value) {
          case 'reconnect':
            await _reconnectToDevice(session);
          case 'delete':
            await _deleteChat(session);
          case 'info':
            _showDeviceInfo(session);
        }
      },
      itemBuilder: (context) => [
        if (!session.isOnline)
          PopupMenuItem(
            value: 'reconnect',
            child: Row(
              children: [
                Icon(Icons.refresh, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text('Reconnect', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Text('Device Info', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: ResQLinkTheme.primaryRed,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Delete Chat',
                style: TextStyle(color: ResQLinkTheme.primaryRed),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeviceInfo(ChatSessionSummary session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Device Information',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name', session.deviceName),
            _buildInfoRow('Device ID', session.deviceId),
            _buildInfoRow('Status', session.connectionStatusText),
            if (session.connectionType != null)
              _buildInfoRow('Connection', session.connectionType!.displayName),
            if (session.lastMessageTime != null)
              _buildInfoRow('Last Message', session.timeDisplay),
            _buildInfoRow('Unread Messages', session.unreadCount.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    return FloatingActionButton(
      backgroundColor: ResQLinkTheme.primaryRed,
      onPressed: widget.p2pService.isDiscovering
          ? null
          : () async {
              HapticFeedback.lightImpact();
              await widget.p2pService.discoverDevices(force: true);
              _showSnackBar('Scanning for nearby devices...', isError: false);
            },
      child: Icon(
        widget.p2pService.isDiscovering
            ? Icons.hourglass_empty
            : Icons.wifi_tethering,
        color: Colors.white,
      ),
    );
  }

  Future<String> _getDisplayName([String? fallbackDeviceName]) async {
    // Return the device's name directly - this is for displaying OTHER devices in chat list
    return fallbackDeviceName ?? 'Unknown User';
  }
}
