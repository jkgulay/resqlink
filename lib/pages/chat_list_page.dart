import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_session_model.dart';
import '../features/database/repositories/chat_repository.dart';
import '../services/p2p/p2p_main_service.dart';
import '../utils/resqlink_theme.dart';
import '../utils/responsive_utils.dart';
import '../utils/responsive_helper.dart';
import '../widgets/message/empty_chat_view.dart';
import '../widgets/message/loading_view.dart';
import 'message_page.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChatSessions();
    _startPeriodicRefresh();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
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

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
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
      if (mounted) {
        setState(() {
          _chatSessions = sessions;
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

  List<ChatSessionSummary> get _filteredSessions {
    if (_searchQuery.isEmpty) return _chatSessions;

    return _chatSessions.where((session) {
      return session.deviceName.toLowerCase().contains(_searchQuery) ||
          session.deviceId.toLowerCase().contains(_searchQuery) ||
          (session.lastMessage?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  Future<void> _openChat(ChatSessionSummary session) async {
    if (widget.onChatSelected != null) {
      widget.onChatSelected!(session.sessionId, session.deviceName);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagePage(p2pService: widget.p2pService),
        ),
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
      backgroundColor: ResQLinkTheme.backgroundDark,
      appBar: AppBar(
        title: Text(
          'Chats',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: ResQLinkTheme.cardDark,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              setState(() {
                _searchController.clear();
                _searchQuery = '';
              });
            },
          ),
          IconButton(icon: Icon(Icons.refresh), onPressed: _loadChatSessions),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: ResponsiveUtils.isDesktop(context)
                ? BoxConstraints(maxWidth: 1200)
                : BoxConstraints(),
            child: Column(
              children: [
                _buildSearchBar(),
                _buildConnectionStatus(),
                Expanded(child: _buildChatList()),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: ResponsiveHelper.getCardPadding(context),
      margin: ResponsiveHelper.getCardMargins(context),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search chats...',
          hintStyle: TextStyle(color: Colors.white60),
          prefixIcon: Icon(Icons.search, color: Colors.white60),
          filled: true,
          fillColor: ResQLinkTheme.cardDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.getResponsiveSpacing(context, 16),
            vertical: ResponsiveUtils.getResponsiveSpacing(context, 12)
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (!widget.p2pService.isConnected) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveUtils.getResponsiveSpacing(context, 16),
          vertical: ResponsiveUtils.getResponsiveSpacing(context, 8)
        ),
        child: Card(
          color: ResQLinkTheme.primaryRed.withValues(alpha: 0.1),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveUtils.getResponsiveSpacing(context, 12)),
            child: Row(
              children: [
                Icon(Icons.wifi_off, color: ResQLinkTheme.primaryRed, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No active connections. Scan for devices to start chatting.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      widget.p2pService.discoverDevices(force: true),
                  child: Text(
                    'SCAN',
                    style: TextStyle(color: ResQLinkTheme.primaryRed),
                  ),
                ),
              ],
            ),
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

    final filteredSessions = _filteredSessions;

    if (filteredSessions.isEmpty) {
      return _searchQuery.isNotEmpty
          ? _buildNoSearchResults()
          : EmptyChatView(p2pService: widget.p2pService);
    }

    return RefreshIndicator(
      onRefresh: _loadChatSessions,
      color: ResQLinkTheme.primaryRed,
      child: ResponsiveUtils.isDesktop(context)
          ? _buildDesktopChatList(filteredSessions)
          : ListView.builder(
              padding: ResponsiveHelper.getCardMargins(context),
              itemCount: filteredSessions.length,
              itemBuilder: (context, index) {
                final session = filteredSessions[index];
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

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.white30),
          SizedBox(height: 16),
          Text(
            'No chats found',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try searching with different keywords',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildChatListItem(ChatSessionSummary session) {
    return Card(
      margin: ResponsiveHelper.getCardMargins(context),
      color: ResQLinkTheme.cardDark,
      child: InkWell(
        onTap: () => _openChat(session),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: ResponsiveHelper.getCardPadding(context),
          child: Row(
            children: [
              _buildAvatar(session),
              SizedBox(width: 12),
              Expanded(child: _buildChatInfo(session)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildTimestamp(session),
                  SizedBox(height: 4),
                  _buildBadges(session),
                ],
              ),
              _buildOptionsMenu(session),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ChatSessionSummary session) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: session.isOnline
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.primaryRed.withValues(alpha: 0.3),
          child: Text(
            session.deviceName.isNotEmpty
                ? session.deviceName[0].toUpperCase()
                : 'D',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        if (session.isOnline)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: ResQLinkTheme.safeGreen,
                shape: BoxShape.circle,
                border: Border.all(color: ResQLinkTheme.cardDark, width: 2),
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
              child: Text(
                session.deviceName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (session.connectionType != null) ...[
              SizedBox(width: 4),
              Icon(
                session.connectionType == ConnectionType.wifiDirect
                    ? Icons.wifi
                    : Icons.wifi_tethering,
                size: 16,
                color: session.isOnline
                    ? ResQLinkTheme.safeGreen
                    : Colors.white30,
              ),
            ],
          ],
        ),
        SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                session.lastMessage ?? 'No messages yet',
                style: TextStyle(
                  color: session.lastMessage != null
                      ? Colors.white70
                      : Colors.white30,
                  fontSize: 14,
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
}
