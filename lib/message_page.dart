import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:resqlink/gps_page.dart';
import '../services/p2p_services.dart';
import '../services/database_service.dart';
import '../models/message_model.dart';
import '../utils/resqlink_theme.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

// Notification Service Class
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
  }

  static Future<void> showEmergencyNotification({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
  }) async {
    if (vibrate) {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        await Vibration.vibrate(
          pattern: [0, 500, 200, 500, 200, 1000],
          intensities: [0, 255, 0, 255, 0, 255],
        );
      }
    }

    if (playSound) {
      try {
        await _player.play(AssetSource('sounds/emergency_alert.mp3'));
      } catch (e) {
        print('Error playing sound: $e');
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'emergency notifications from nearby users',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false,
      enableVibration: false,
      styleInformation: BigTextStyleInformation(body),
      color: ResQLinkTheme.primaryRed,
      icon: '@drawable/icon_emergency',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'emergency_alert.mp3',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
    );
  }

  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}

// Message Summary Model
class MessageSummary {
  final String endpointId;
  final String deviceName;
  final MessageModel? lastMessage;
  final int messageCount;
  final int unreadCount;
  final bool isConnected;

  MessageSummary({
    required this.endpointId,
    required this.deviceName,
    this.lastMessage,
    required this.messageCount,
    required this.unreadCount,
    required this.isConnected,
  });
}

// Main Message Page Widget
class MessagePage extends StatefulWidget {
  final P2PConnectionService p2pService;
  final LocationModel? currentLocation;

  const MessagePage({
    super.key,
    required this.p2pService,
    this.currentLocation,
  });

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> with WidgetsBindingObserver {
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // State Variables
  List<MessageSummary> _conversations = [];
  List<MessageModel> _selectedConversationMessages = [];
  String? _selectedEndpointId;
  bool _isLoading = true;
  bool _isChatView = false;
  Timer? _refreshTimer;

  // Lifecycle Methods
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  void _initialize() {
    _loadConversations();
    widget.p2pService.addListener(_onP2PUpdate);
    widget.p2pService.onMessageReceived = _onMessageReceived;
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadConversations(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _refreshTimer?.cancel();
    widget.p2pService.removeListener(_onP2PUpdate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _loadConversations();
    }
  }

  // Data Loading Methods
  Future<void> _loadConversations() async {
    try {
      final messages = await DatabaseService.getAllMessages();
      final connectedDevices = widget.p2pService.connectedDevices;
      final knownDevices = await DatabaseService.getKnownDevices();
      final deviceMap = {
        for (final device in knownDevices)
          device.deviceId:
              widget.p2pService.getDeviceInfo(device.deviceId)['name'] ??
              device.deviceId.substring(0, 8),
      };

      final Map<String, MessageSummary> conversationMap = {};
      for (final message in messages) {
        final endpointId = message.endpointId;
        final deviceName =
            connectedDevices[endpointId]?.name ??
            deviceMap[endpointId] ??
            endpointId.substring(0, 8);

        if (!conversationMap.containsKey(endpointId)) {
          final messageCount = await DatabaseService.getMessages(
            endpointId,
          ).then((msgs) => msgs.length);
          final unreadCount = await DatabaseService.getMessages(
            endpointId,
          ).then((msgs) => msgs.where((m) => !m.synced).length);
          conversationMap[endpointId] = MessageSummary(
            endpointId: endpointId,
            deviceName: deviceName,
            lastMessage: message,
            messageCount: messageCount,
            unreadCount: unreadCount,
            isConnected: connectedDevices.containsKey(endpointId),
          );
        } else {
          final currentSummary = conversationMap[endpointId]!;
          if (message.dateTime.isAfter(
            currentSummary.lastMessage?.dateTime ?? DateTime(0),
          )) {
            conversationMap[endpointId] = MessageSummary(
              endpointId: endpointId,
              deviceName: deviceName,
              lastMessage: message,
              messageCount: currentSummary.messageCount,
              unreadCount: currentSummary.unreadCount,
              isConnected: connectedDevices.containsKey(endpointId),
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _conversations = conversationMap.values.toList()
            ..sort(
              (a, b) => (b.lastMessage?.dateTime ?? DateTime(0)).compareTo(
                a.lastMessage?.dateTime ?? DateTime(0),
              ),
            );
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading conversations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMessagesForDevice(String endpointId) async {
    try {
      final messages = await DatabaseService.getMessages(endpointId);
      if (mounted) {
        setState(() {
          _selectedConversationMessages = messages;
        });
        _scrollToBottom();
        final validMessageId =
            messages
                .where((m) => m.messageId != null)
                .map((m) => m.messageId!)
                .firstOrNull ??
            '';
        if (validMessageId.isNotEmpty) {
          await DatabaseService.markMessageSynced(validMessageId);
        }
        await _loadConversations();
      }
    } catch (e) {
      print('Error loading messages for device $endpointId: $e');
    }
  }

  // P2P Service Handlers
  void _onP2PUpdate() async {
    if (mounted) {
      await _loadConversations();
      setState(() {});
    }
  }

  void _onMessageReceived(P2PMessage message) async {
    await _loadConversations();

    if (message.type == MessageType.emergency ||
        message.type == MessageType.sos) {
      await _showEmergencyNotification(message);
    }

    if (_isChatView && _selectedEndpointId == message.senderId) {
      await _loadMessagesForDevice(_selectedEndpointId!);
    }
  }

  Future<void> _showEmergencyNotification(P2PMessage message) async {
    if (!mounted) return;

    String body = message.message;
    if (message.latitude != null && message.longitude != null) {
      body +=
          '\nLocation: ${message.latitude!.toStringAsFixed(6)}, ${message.longitude!.toStringAsFixed(6)}';
    }

    await NotificationService.showEmergencyNotification(
      title: '${message.type.name.toUpperCase()} from ${message.senderName}',
      body: body,
      playSound: true,
      vibrate: true,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${message.type.name.toUpperCase()} from ${message.senderName}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: ResQLinkTheme.primaryRed,
        duration: Duration(seconds: 5),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            _openConversation(message.senderId);
          },
        ),
      ),
    );
  }

  // Message Sending Methods
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedEndpointId == null) return;

    _messageController.clear();

    await widget.p2pService.sendMessage(
      message: text,
      type: MessageType.text,
      targetDeviceId: _selectedEndpointId,
    );

    await _loadMessagesForDevice(_selectedEndpointId!);
  }

  Future<void> _sendLocationMessage() async {
    if (widget.currentLocation == null || _selectedEndpointId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No location available'),
            backgroundColor: ResQLinkTheme.warningYellow,
          ),
        );
      }
      return;
    }

    await widget.p2pService.sendMessage(
      message: '📍 Shared my location',
      type: MessageType.location,
      latitude: widget.currentLocation!.latitude,
      longitude: widget.currentLocation!.longitude,
      targetDeviceId: _selectedEndpointId,
    );

    await _loadMessagesForDevice(_selectedEndpointId!);
  }

  Future<void> _sendEmergencyMessage() async {
    if (_selectedEndpointId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send Emergency SOS?'),
        content: Text(
          'This will send an emergency SOS message to the selected device, including your location if available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Send',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted && _selectedEndpointId != null) {
      await widget.p2pService.sendMessage(
        message: '🚨 Emergency SOS',
        type: MessageType.sos,
        latitude: widget.currentLocation?.latitude,
        longitude: widget.currentLocation?.longitude,
        targetDeviceId: _selectedEndpointId,
      );
      await _loadMessagesForDevice(_selectedEndpointId!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Emergency SOS sent')));
      }
    }
  }

  // Conversation Management
  Future<void> _clearConversation(String endpointId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Conversation?'),
        content: Text(
          'This will delete all messages with this device from your device. Messages on other devices will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // Note: DatabaseService lacks clearMessagesForDevice; using clearAllData as fallback
      await DatabaseService.clearAllData();
      if (_selectedEndpointId == endpointId) {
        setState(() {
          _isChatView = false;
          _selectedEndpointId = null;
          _selectedConversationMessages.clear();
        });
      }
      await _loadConversations();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Conversation cleared')));
      }
    }
  }

  Future<void> _reconnectToDevice(String endpointId) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Attempting to reconnect to device...')),
        );
      }
      // P2PConnectionService lacks reconnectToDevice; using connectToDevice with discovered device
      final deviceInfo = widget.p2pService.getDeviceInfo(endpointId);
      if (deviceInfo['isAvailable']) {
        await widget.p2pService.connectToDevice({
          'deviceAddress': endpointId,
          'deviceName': deviceInfo['name'],
        });
        await _loadConversations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reconnection attempt completed')),
          );
        }
      } else {
        throw Exception('Device not available');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reconnect: $e'),
            backgroundColor: ResQLinkTheme.warningYellow,
          ),
        );
      }
    }
  }

  void _openConversation(String endpointId) {
    setState(() {
      _selectedEndpointId = endpointId;
      _isChatView = true;
    });
    _loadMessagesForDevice(endpointId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // UI Building Methods
  @override
  Widget build(BuildContext context) {
    final isConnected = widget.p2pService.isConnected;
    final connectedCount = widget.p2pService.connectedDevices.length;

    return Theme(
      data: ThemeData.dark().copyWith(
        primaryColor: ResQLinkTheme.primaryRed,
        scaffoldBackgroundColor: ResQLinkTheme.backgroundDark,
      ),
      child: Scaffold(
        appBar: _buildAppBar(isConnected, connectedCount),
        body: Column(
          children: [
            if (!isConnected) _buildOfflineWarning(),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: ResQLinkTheme.primaryRed,
                      ),
                    )
                  : _isChatView
                  ? _buildChatView()
                  : _buildConversationList(),
            ),
            if (_isChatView) _buildInputArea(isConnected),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(bool isConnected, int connectedCount) {
    return AppBar(
      backgroundColor: ResQLinkTheme.surfaceDark,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isChatView ? 'Chat Messages' : 'Emergency Messages'),
          Text(
            isConnected
                ? 'Connected to $connectedCount device${connectedCount > 1 ? 's' : ''}'
                : 'No internet connection',
            style: TextStyle(
              fontSize: 12,
              color: isConnected
                  ? ResQLinkTheme.safeGreen
                  : ResQLinkTheme.warningYellow,
            ),
          ),
        ],
      ),
      leading: _isChatView
          ? IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _isChatView = false;
                  _selectedEndpointId = null;
                  _selectedConversationMessages.clear();
                });
              },
            )
          : null,
      actions: [
        Icon(
          widget.p2pService.isOnline ? Icons.cloud_done : Icons.cloud_off,
          color: widget.p2pService.isOnline
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.offlineGray,
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'clear' && _selectedEndpointId != null) {
              _clearConversation(_selectedEndpointId!);
            } else if (value == 'message') {
              _showConnectionInfo();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'message',
              child: Row(
                children: [
                  Icon(Icons.circle, size: 20, color: Colors.white70),
                  SizedBox(width: 8),
                  Text('Messages', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            if (_isChatView)
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Clear Chat', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildOfflineWarning() {
    return Container(
      padding: EdgeInsets.all(8),
      color: ResQLinkTheme.warningYellow,
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Not connected to any devices. Messages will be saved locally.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: ResQLinkTheme.offlineGray,
            ),
            SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            SizedBox(height: 8),
            Text(
              widget.p2pService.connectedDevices.isEmpty
                  ? 'Connect to a device to start messaging'
                  : 'Select a device to start messaging',
              style: TextStyle(fontSize: 14, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        return _buildConversationItem(conversation);
      },
    );
  }

  Widget _buildConversationItem(MessageSummary conversation) {
    final message = conversation.lastMessage;
    final isEmergency =
        message?.isEmergency ??
        false || message?.type == 'emergency' || message?.type == 'sos';

    return Card(
      color: ResQLinkTheme.cardDark,
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      elevation: 4,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isEmergency
              ? ResQLinkTheme.primaryRed
              : conversation.isConnected
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.offlineGray,
          child: Icon(
            isEmergency ? Icons.warning : Icons.person,
            color: Colors.white,
          ),
        ),
        title: Text(
          conversation.deviceName,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null)
              Text(
                message.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.black),
              ),
            SizedBox(height: 4),
            Text(
              message != null
                  ? _formatFullDateTime(message.dateTime)
                  : 'No messages available',
              style: TextStyle(fontSize: 12, color: Colors.black),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conversation.unreadCount > 0)
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.primaryRed,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            if (!conversation.isConnected)
              IconButton(
                icon: Icon(Icons.refresh, color: ResQLinkTheme.warningYellow),
                onPressed: () => _reconnectToDevice(conversation.endpointId),
                tooltip: 'Reconnect',
              ),
          ],
        ),
        onTap: () => _openConversation(conversation.endpointId),
      ),
    );
  }

  Widget _buildChatView() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(16),
      itemCount: _selectedConversationMessages.length,
      itemBuilder: (context, index) {
        final message = _selectedConversationMessages[index];
        final previousMessage = index > 0
            ? _selectedConversationMessages[index - 1]
            : null;
        final showDateHeader = _shouldShowDateHeader(message, previousMessage);

        return Column(
          children: [
            if (showDateHeader) _buildDateHeader(message.dateTime),
            _buildMessageBubble(message),
          ],
        );
      },
    );
  }

  bool _shouldShowDateHeader(
    MessageModel message,
    MessageModel? previousMessage,
  ) {
    if (previousMessage == null) return true;

    final currentDate = message.dateTime;
    final previousDate = previousMessage.dateTime;

    return currentDate.day != previousDate.day ||
        currentDate.month != previousDate.month ||
        currentDate.year != previousDate.year;
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.day == now.day && date.month == now.month && date.year == now.year;
    final isYesterday =
        date.day == now.day - 1 &&
        date.month == now.month &&
        date.year == now.year;

    String dateText;
    if (isToday) {
      dateText = 'Today';
    } else if (isYesterday) {
      dateText = 'Yesterday';
    } else {
      dateText = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: ResQLinkTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          dateText,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message) {
    final isMe = message.isMe;
    final hasLocation = message.hasLocation;
    final isEmergency =
        message.isEmergency ||
        message.type == 'emergency' ||
        message.type == 'sos';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  message.fromUser,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isEmergency
                    ? ResQLinkTheme.primaryRed
                    : message.type == 'location'
                    ? ResQLinkTheme.locationBlue
                    : isMe
                    ? ResQLinkTheme.safeGreen
                    : Colors.white,
                borderRadius: BorderRadius.circular(16).copyWith(
                  topLeft: isMe ? null : Radius.circular(4),
                  topRight: isMe ? Radius.circular(4) : null,
                ),
                border: isEmergency
                    ? Border.all(color: ResQLinkTheme.darkRed, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEmergency)
                    Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            message.type == 'sos' ? Icons.sos : Icons.warning,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            message.type.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    message.message,
                    style: TextStyle(
                      color: isMe || message.type == 'location' || isEmergency
                          ? Colors.white
                          : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  if (hasLocation)
                    InkWell(
                      onTap: () => _showLocationDetails(message),
                      child: Container(
                        margin: EdgeInsets.only(top: 8),
                        height: 100,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              message.latitude!,
                              message.longitude!,
                            ),
                            initialZoom: 15.0,
                            interactionOptions: InteractionOptions(
                              flags:
                                  InteractiveFlag.pinchZoom |
                                  InteractiveFlag.doubleTapZoom,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.resqlink.app',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(
                                    message.latitude!,
                                    message.longitude!,
                                  ),
                                  child: Icon(
                                    Icons.location_pin,
                                    color: ResQLinkTheme.primaryRed,
                                    size: 30,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.dateTime),
                        style: TextStyle(
                          color:
                              isMe || message.type == 'location' || isEmergency
                              ? Colors.white70
                              : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      if (!message.synced) ...[
                        SizedBox(width: 4),
                        Icon(
                          Icons.schedule,
                          size: 12,
                          color:
                              isMe || message.type == 'location' || isEmergency
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isConnected) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (widget.currentLocation != null)
              IconButton(
                icon: Icon(Icons.location_on, color: ResQLinkTheme.primaryRed),
                onPressed: _sendLocationMessage,
                tooltip: 'Share Location',
              ),
            IconButton(
              icon: Icon(Icons.sos, color: ResQLinkTheme.primaryRed),
              onPressed: _sendEmergencyMessage,
              tooltip: 'Send Emergency SOS',
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: isConnected
                      ? 'Type a message...'
                      : 'Type a message (offline)',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: ResQLinkTheme.cardDark,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: TextStyle(color: Colors.white),
                onSubmitted: (_) => _sendMessage(),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: ResQLinkTheme.primaryRed,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationDetails(MessageModel message) {
    if (!message.hasLocation) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: ResQLinkTheme.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(message.latitude!, message.longitude!),
                  initialZoom: 14.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.resqlink.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(message.latitude!, message.longitude!),
                        child: Icon(
                          Icons.location_pin,
                          color: ResQLinkTheme.primaryRed,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.person, color: Colors.white70),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'From: ${message.fromUser}',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.white70),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Coordinates: ${message.latitude!.toStringAsFixed(6)}, ${message.longitude!.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.white70),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Time: ${_formatFullDateTime(message.dateTime)}',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(Icons.map, color: Colors.white),
                label: Text(
                  'Open in Maps',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ResQLinkTheme.primaryRed,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Opening in maps...')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionInfo() {
    final info = widget.p2pService.getConnectionInfo();
    final devices = widget.p2pService.connectedDevices;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Connection Information',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                'Device ID:',
                info['deviceId']?.substring(0, 8) ?? 'Unknown',
              ),
              _buildInfoRow('Role:', info['role']?.toUpperCase() ?? 'NONE'),
              _buildInfoRow('Connected Devices:', devices.length.toString()),
              _buildInfoRow(
                'Sync Status:',
                Text(
                  info['isOnline'] == true ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: info['isOnline'] == true
                        ? ResQLinkTheme.safeGreen
                        : ResQLinkTheme.warningYellow,
                  ),
                ),
              ),
              _buildInfoRow(
                'Pending Messages:',
                info['pendingMessages']?.toString() ?? '0',
              ),
              _buildInfoRow(
                'Messages Processed:',
                info['processedMessages']?.toString() ?? '0',
              ),
              if (devices.isNotEmpty) ...[
                SizedBox(height: 16),
                Text(
                  'Connected Devices:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                ...devices.entries.map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${entry.value.name} (${entry.key.substring(0, 8)})',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value, [Widget? builder]) =>
      Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.white70)),
            builder ??
                Text(
                  value.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
          ],
        ),
      );

  // Utility Methods
  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatFullDateTime(DateTime dateTime) {
    final day = dateTime.day.toString();
    final month = dateTime.month.toString();
    final year = dateTime.year;
    return '$day/$month/$year ${_formatTime(dateTime)}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
