import 'package:flutter/material.dart';
import 'package:resqlink/gps_page.dart';
import 'package:resqlink/services/database_service.dart';
import 'package:resqlink/models/message_model.dart';
import 'home_page.dart';

// Responsive utility class
class ResponsiveUtils {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  static bool isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.height < 600;

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSize * 0.85;
    if (width > tabletBreakpoint) return baseSize * 1.15;
    if (width > mobileBreakpoint) return baseSize * 1.05;
    return baseSize;
  }

  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSpacing * 0.8;
    if (width > tabletBreakpoint) return baseSpacing * 1.5;
    if (width > mobileBreakpoint) return baseSpacing * 1.2;
    return baseSpacing;
  }

  static EdgeInsets getResponsivePadding(
    BuildContext context, {
    double? horizontal,
    double? vertical,
  }) {
    final size = MediaQuery.of(context).size;
    final baseHorizontal = horizontal ?? (size.width * 0.04);
    final baseVertical = vertical ?? (size.height * 0.02);

    if (isDesktop(context)) {
      return EdgeInsets.symmetric(
        horizontal: baseHorizontal * 1.5,
        vertical: baseVertical * 1.5,
      );
    } else if (isTablet(context)) {
      return EdgeInsets.symmetric(
        horizontal: baseHorizontal * 1.2,
        vertical: baseVertical * 1.2,
      );
    } else {
      return EdgeInsets.symmetric(
        horizontal: baseHorizontal,
        vertical: baseVertical,
      );
    }
  }

  static double getMaxChatWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return width * 0.7;
    if (isTablet(context)) return width * 0.85;
    return width;
  }

  static double getMessageBubbleMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return width * 0.5;
    if (isTablet(context)) return width * 0.65;
    return width * 0.75;
  }

  static double getAvatarSize(BuildContext context) {
    if (isDesktop(context)) return 50;
    if (isTablet(context)) return 45;
    return 40;
  }

  static double getListTileHeight(BuildContext context) {
    if (isDesktop(context)) return 80;
    if (isTablet(context)) return 75;
    return 70;
  }
}

class MessagePage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;
  final LocationModel? currentLocation;

  const MessagePage({
    super.key,
    required this.wifiDirectService,
    this.currentLocation,
  });

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  @override
  void initState() {
    super.initState();
    widget.wifiDirectService.addListener(_update);
  }

  @override
  void dispose() {
    widget.wifiDirectService.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final connectedDevices = widget.wifiDirectService.connectedDevices;
    final discoveredDevices = widget.wifiDirectService.discoveredDevices;

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: ResponsiveUtils.getMaxChatWidth(context),
          child: FutureBuilder<List<MessageModel>>(
            future: _loadAllMessages(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        16,
                      ),
                    ),
                  ),
                );
              }

              final messages = snapshot.data ?? [];
              if (messages.isEmpty && connectedDevices.isEmpty) {
                return _buildEmptyState(context);
              }

              // Group messages by endpoint
              final grouped = <String, List<MessageModel>>{};
              for (var m in messages) {
                grouped.putIfAbsent(m.endpointId, () => []).add(m);
              }

              // Add discovered devices that aren't in message history
              for (var endpoint in discoveredDevices.keys) {
                if (!grouped.containsKey(endpoint)) {
                  grouped[endpoint] = [];
                }
              }

              return _buildMessageList(
                context,
                grouped,
                connectedDevices,
                discoveredDevices,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: ResponsiveUtils.getResponsiveFontSize(context, 64),
            color: Colors.grey,
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 16)),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 18),
              color: Colors.grey,
            ),
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 8)),
          Text(
            'Connect to nearby devices to start messaging',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 24)),
          ElevatedButton.icon(
            icon: Icon(Icons.wifi_tethering),
            label: Text('Find Nearby Devices'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NearbyDevicesPage(
                    wifiDirectService: widget.wifiDirectService,
                    currentLocation: widget.currentLocation,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    Map<String, List<MessageModel>> grouped,
    Map<String, String> connectedDevices,
    Map<String, String> discoveredDevices,
  ) {
    final sortedEndpoints = grouped.keys.toList()
      ..sort((a, b) {
        // Sort by last message time, with empty conversations at bottom
        final aMessages = grouped[a]!;
        final bMessages = grouped[b]!;
        if (aMessages.isEmpty && bMessages.isEmpty) return 0;
        if (aMessages.isEmpty) return 1;
        if (bMessages.isEmpty) return -1;
        return bMessages.last.timestamp.compareTo(aMessages.last.timestamp);
      });

    return Column(
      children: [
        // Header with connection status
        Container(
          padding: ResponsiveUtils.getResponsivePadding(context),
          child: Row(
            children: [
              Icon(
                Icons.wifi_tethering,
                color: connectedDevices.isNotEmpty
                    ? Colors.green
                    : Colors.orange,
              ),
              SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 8)),
              Text(
                'Connected: ${connectedDevices.length} | Available: ${discoveredDevices.length}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Spacer(),
              TextButton.icon(
                icon: Icon(Icons.search),
                label: Text('Find Devices'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NearbyDevicesPage(
                        wifiDirectService: widget.wifiDirectService,
                        currentLocation: widget.currentLocation,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Divider(),
        Expanded(
          child: ListView.separated(
            padding: ResponsiveUtils.getResponsivePadding(
              context,
              horizontal: 12,
              vertical: 8,
            ),
            itemCount: sortedEndpoints.length,
            separatorBuilder: (context, index) => SizedBox(
              height: ResponsiveUtils.getResponsiveSpacing(context, 4),
            ),
            itemBuilder: (context, index) {
              final endpointId = sortedEndpoints[index];
              final history = grouped[endpointId]!;
              final userName =
                  connectedDevices[endpointId] ??
                  discoveredDevices[endpointId] ??
                  (history.isNotEmpty ? history.last.fromUser : 'Unknown User');
              final isConnected = connectedDevices.containsKey(endpointId);
              final isDiscovered = discoveredDevices.containsKey(endpointId);

              return _buildMessageTile(
                context,
                endpointId,
                userName,
                history.isNotEmpty ? history.last : null,
                isConnected,
                isDiscovered,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMessageTile(
    BuildContext context,
    String endpointId,
    String userName,
    MessageModel? lastMessage,
    bool isConnected,
    bool isDiscovered,
  ) {
    final avatarSize = ResponsiveUtils.getAvatarSize(context);
    final tileHeight = ResponsiveUtils.getListTileHeight(context);

    return Container(
      height: tileHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: ResponsiveUtils.getResponsivePadding(
          context,
          horizontal: 16,
          vertical: 8,
        ),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: avatarSize / 2,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                userName[0].toUpperCase(),
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            if (isConnected)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                userName,
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (lastMessage != null)
              Text(
                _formatTimestamp(lastMessage.timestamp),
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 4)),
            if (lastMessage != null)
              Row(
                children: [
                  if (lastMessage.isEmergency) ...[
                    Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: ResponsiveUtils.getResponsiveFontSize(context, 16),
                    ),
                    SizedBox(
                      width: ResponsiveUtils.getResponsiveSpacing(context, 4),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      lastMessage.message,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(
                          context,
                          14,
                        ),
                        color: lastMessage.isEmergency
                            ? Colors.red
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                isConnected
                    ? 'Connected - Tap to chat'
                    : isDiscovered
                    ? 'Available - Tap to connect'
                    : 'Offline - Tap to view history',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                  color: isConnected ? Colors.green : Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        trailing: isConnected
            ? Icon(
                Icons.chat_bubble,
                color: Theme.of(context).colorScheme.primary,
                size: ResponsiveUtils.getResponsiveFontSize(context, 20),
              )
            : isDiscovered
            ? ElevatedButton(
                onPressed: () async {
                  await widget.wifiDirectService.connectToDevice(endpointId);
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Text('Connect'),
              )
            : Icon(
                Icons.history,
                color: Colors.grey,
                size: ResponsiveUtils.getResponsiveFontSize(context, 20),
              ),
        onTap: () {
          if (isConnected || lastMessage != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ChatScreen(
                  endpointId: endpointId,
                  userName: userName,
                  wifiDirectService: widget.wifiDirectService,
                  currentLocation: widget.currentLocation,
                ),
              ),
            );
          } else if (isDiscovered) {
            // Connect first, then open chat
            widget.wifiDirectService.connectToDevice(endpointId).then((_) {
              if (context.mounted) {
                // Changed from 'mounted' to 'context.mounted'
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ChatScreen(
                      endpointId: endpointId,
                      userName: userName,
                      wifiDirectService: widget.wifiDirectService,
                      currentLocation: widget.currentLocation,
                    ),
                  ),
                );
              }
            });
          }
        },
      ),
    );
  }

  Future<List<MessageModel>> _loadAllMessages() async {
    try {
      final db = await DatabaseService.database;
      final result = await db.query('messages', orderBy: 'timestamp DESC');
      return result.map((e) => MessageModel.fromMap(e)).toList();
    } catch (e) {
      print('Error loading messages: $e');
      return [];
    }
  }

  String _formatTimestamp(int timestampMs) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'now';
    }
  }
}

class _ChatScreen extends StatefulWidget {
  final String endpointId;
  final String userName;
  final WiFiDirectService wifiDirectService;
  final LocationModel? currentLocation;

  const _ChatScreen({
    required this.endpointId,
    required this.userName,
    required this.wifiDirectService,
    this.currentLocation,
  });

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<MessageModel> _messages = [];
  LocationModel? _currentLocation;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.currentLocation;
    _loadMessages();
    _loadLatestLocation();
    widget.wifiDirectService.addListener(_onMessage);
  }

  void _onMessage() => _loadMessages();

  Future<void> _loadLatestLocation() async {
    try {
      final location = await LocationService.getLastKnownLocation();
      if (mounted && location != null) {
        setState(() {
          _currentLocation = location;
        });
      }
    } catch (e) {
      print('Error loading location: $e');
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await DatabaseService.getMessages(widget.endpointId);
    if (mounted) {
      setState(() => _messages = msgs);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    await widget.wifiDirectService.sendMessage(widget.endpointId, text);
    await _loadMessages();
  }

  Future<void> _sendLocation() async {
    if (_currentLocation == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No location available to share'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await widget.wifiDirectService.sendLocation(
      widget.endpointId,
      _currentLocation!,
    );
    await _loadMessages();
  }

  Future<void> _sendEmergencyMessage() async {
    await widget.wifiDirectService.broadcastEmergency(
      'EMERGENCY ASSISTANCE NEEDED!',
      _currentLocation?.latitude,
      _currentLocation?.longitude,
    );
    await _loadMessages();
  }

  @override
  void dispose() {
    widget.wifiDirectService.removeListener(_onMessage);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.wifiDirectService.connectedDevices.containsKey(
      widget.endpointId,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    widget.userName[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        14,
                      ),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (isConnected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.userName,
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        18,
                      ),
                    ),
                  ),
                  Text(
                    isConnected ? 'Connected' : 'Not connected',
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        12,
                      ),
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (isConnected) ...[
            IconButton(
              icon: Icon(Icons.location_on),
              onPressed: _currentLocation != null ? _sendLocation : null,
              tooltip: 'Share Location',
            ),
            IconButton(
              icon: Icon(Icons.emergency, color: Colors.red),
              onPressed: _sendEmergencyMessage,
              tooltip: 'Send Emergency',
            ),
          ],
        ],
      ),
      body: Center(
        child: SizedBox(
          width: ResponsiveUtils.getMaxChatWidth(context),
          child: Column(
            children: [
              if (!isConnected)
                Container(
                  padding: EdgeInsets.all(8),
                  color: Colors.orange.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Not connected. Messages will be sent when connection is restored.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.wifiDirectService.connectToDevice(
                            widget.endpointId,
                          );
                        },
                        child: Text('Connect'),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildMessagesList()),
              _buildMessageInput(isConnected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: ResponsiveUtils.getResponsiveFontSize(context, 48),
              color: Colors.grey,
            ),
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 16)),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                color: Colors.grey,
              ),
            ),
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 8)),
            Text(
              'Start a conversation with ${widget.userName}',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: ResponsiveUtils.getResponsivePadding(
        context,
        horizontal: 16,
        vertical: 8,
      ),
      itemCount: _messages.length,
      itemBuilder: (_, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(MessageModel msg) {
    final isMe = msg.isMe;
    final maxWidth = ResponsiveUtils.getMessageBubbleMaxWidth(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: EdgeInsets.symmetric(
          vertical: ResponsiveUtils.getResponsiveSpacing(context, 4),
          horizontal: ResponsiveUtils.getResponsiveSpacing(context, 8),
        ),
        padding: ResponsiveUtils.getResponsivePadding(
          context,
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: msg.isEmergency
              ? Colors.red.shade600
              : msg.type == 'location'
              ? Colors.blue.shade700
              : isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(
            ResponsiveUtils.getResponsiveSpacing(context, 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isEmergency) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning, color: Colors.white, size: 16),
                  SizedBox(
                    width: ResponsiveUtils.getResponsiveSpacing(context, 4),
                  ),
                  Text(
                    'EMERGENCY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        12,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 4),
              ),
            ],
            if (msg.type == 'location' &&
                msg.latitude != 0.0 &&
                msg.longitude != 0.0) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, color: Colors.white, size: 16),
                  SizedBox(
                    width: ResponsiveUtils.getResponsiveSpacing(context, 4),
                  ),
                  Text(
                    'Location Shared',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        12,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 4),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GpsPage(
                        userId: 'viewer',
                        // Add initial coordinates support in GpsPage if needed
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Lat: ${msg.latitude.toStringAsFixed(4)}, '
                          'Lon: ${msg.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: ResponsiveUtils.getResponsiveFontSize(
                              context,
                              12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              Text(
                msg.message,
                style: TextStyle(
                  color: (isMe || msg.isEmergency || msg.type == 'location')
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                ),
              ),
            if (ResponsiveUtils.isTablet(context) ||
                ResponsiveUtils.isDesktop(context)) ...[
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 4),
              ),
              Text(
                _formatTimestamp(msg.timestamp),
                style: TextStyle(
                  color:
                      ((isMe || msg.isEmergency || msg.type == 'location')
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant)
                          .withValues(alpha: 0.7),
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(bool isConnected) {
    return Container(
      padding: ResponsiveUtils.getResponsivePadding(
        context,
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (isConnected && _currentLocation != null)
              IconButton(
                icon: Icon(
                  Icons.location_on,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _sendLocation,
                tooltip: 'Share Location',
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: isConnected,
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                ),
                decoration: InputDecoration(
                  hintText: isConnected
                      ? 'Type message...'
                      : 'Connect to send messages',
                  hintStyle: TextStyle(
                    fontSize: ResponsiveUtils.getResponsiveFontSize(
                      context,
                      16,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  contentPadding: ResponsiveUtils.getResponsivePadding(
                    context,
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: isConnected ? (_) => _sendMessage() : null,
                maxLines: ResponsiveUtils.isDesktop(context) ? 3 : 1,
              ),
            ),
            SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 8)),
            Container(
              decoration: BoxDecoration(
                color: isConnected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: isConnected ? _sendMessage : null,
                icon: Icon(
                  Icons.send,
                  color: Colors.white,
                  size: ResponsiveUtils.getResponsiveFontSize(context, 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(int timestampMs) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'now';
    }
  }
}
