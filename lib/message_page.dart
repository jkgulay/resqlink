import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:resqlink/gps_page.dart';
import 'package:resqlink/services/message_sync_service.dart';
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

  // Services
  final MessageSyncService _syncService = MessageSyncService();

  // State Variables
  List<MessageSummary> _conversations = [];
  List<MessageModel> _selectedConversationMessages = [];
  String? _selectedEndpointId;
  bool _isLoading = true;
  bool _isChatView = false;
  Timer? _refreshTimer;
  StreamSubscription? _p2pSubscription;

  // Lifecycle Methods
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  void _initialize() {
    _syncService.initialize();
    _loadConversations();

    // Setup P2P listener with proper cleanup
    _p2pSubscription = widget.p2pService.messageHistory.isNotEmpty
        ? Stream.periodic(
            const Duration(seconds: 1),
          ).listen((_) => _onP2PUpdate())
        : null;

    widget.p2pService.addListener(_onP2PUpdate);
    widget.p2pService.onMessageReceived = _onMessageReceived;

    // Refresh conversations every 10 seconds, but only if mounted
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadConversations();
      }
    });
  }

  @override
  void dispose() {
    debugPrint('🗑️ MessagePage disposing...');

    // Cancel all timers and subscriptions FIRST
    _refreshTimer?.cancel();
    _refreshTimer = null;

    _p2pSubscription?.cancel();
    _p2pSubscription = null;

    // Remove listeners
    widget.p2pService.removeListener(_onP2PUpdate);
    widget.p2pService.onMessageReceived = null;

    // Dispose controllers
    _messageController.dispose();
    _scrollController.dispose();

    // Dispose services
    _syncService.dispose();

    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    debugPrint('✅ MessagePage disposed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed && mounted) {
      await _loadConversations();
    }
  }

  // Data Loading Methods
  Future<void> _loadConversations() async {
    if (!mounted) return;

    try {
      final messages = await DatabaseService.getAllMessages();
      final connectedDevices = widget.p2pService.connectedDevices;
      final knownDevices = await DatabaseService.getKnownDevices();

      final deviceMap = {
        for (final device in knownDevices)
          device.deviceId: device.deviceId.substring(0, 8), // Fallback name
      };

      final Map<String, MessageSummary> conversationMap = {};

      for (final message in messages) {
        final endpointId = message.endpointId;
        final deviceName =
            connectedDevices[endpointId]?.name ??
            deviceMap[endpointId] ??
            endpointId.substring(0, 8);

        if (!conversationMap.containsKey(endpointId)) {
          final endpointMessages = messages
              .where((m) => m.endpointId == endpointId)
              .toList();
          final unreadCount = endpointMessages
              .where((m) => !m.synced && !m.isMe)
              .length;

          conversationMap[endpointId] = MessageSummary(
            endpointId: endpointId,
            deviceName: deviceName,
            lastMessage: message,
            messageCount: endpointMessages.length,
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
              deviceName: currentSummary.deviceName,
              lastMessage: message,
              messageCount: currentSummary.messageCount,
              unreadCount: currentSummary.unreadCount,
              isConnected: currentSummary.isConnected,
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
      debugPrint('❌ Error loading conversations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMessagesForDevice(String endpointId) async {
    if (!mounted) return;

    try {
      final messages = await DatabaseService.getMessages(endpointId);
      if (mounted) {
        setState(() {
          _selectedConversationMessages = messages;
        });
        _scrollToBottom();

        // Mark messages as read
        for (final message in messages.where((m) => !m.isMe && !m.synced)) {
          if (message.messageId != null) {
            await DatabaseService.updateMessageStatus(
              message.messageId!,
              MessageStatus.delivered,
            );
          }
        }

        await _loadConversations();
      }
    } catch (e) {
      debugPrint('❌ Error loading messages for device $endpointId: $e');
    }
  }

  // P2P Service Handlers
  void _onP2PUpdate() async {
    if (mounted) {
      await _loadConversations();
      if (mounted) setState(() {});
    }
  }

  void _onMessageReceived(P2PMessage message) async {
    if (!mounted) return;

    // Save received message to database
    final messageModel = MessageModel(
      endpointId: message.senderId,
      fromUser: message.senderName,
      message: message.message,
      isMe: false,
      isEmergency:
          message.type == MessageType.emergency ||
          message.type == MessageType.sos,
      timestamp: message.timestamp.millisecondsSinceEpoch,
      latitude: message.latitude,
      longitude: message.longitude,
      messageId: message.id,
      type: message.type.name,
      status: MessageStatus.delivered,
    );

    await DatabaseService.insertMessage(messageModel);
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

    if (mounted) {
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
  }

  // Message Sending Methods
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedEndpointId == null || !mounted) return;

    _messageController.clear();

    try {
      // Remove the unused messageId variable since we don't need it here
      await _syncService.sendMessage(
        endpointId: _selectedEndpointId!,
        message: text,
        fromUser: widget.p2pService.userName ?? 'Unknown',
        isEmergency: false,
        messageType: MessageType.text,
        p2pService: widget.p2pService,
      );

      if (mounted) {
        await _loadMessagesForDevice(_selectedEndpointId!);
      }
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendLocationMessage() async {
    if (widget.currentLocation == null ||
        _selectedEndpointId == null ||
        !mounted) {
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

    try {
      await _syncService.sendMessage(
        endpointId: _selectedEndpointId!,
        message: '📍 Shared my location',
        fromUser: widget.p2pService.userName ?? 'Unknown',
        isEmergency: false,
        messageType: MessageType.location,
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
        p2pService: widget.p2pService,
      );

      if (mounted) {
        await _loadMessagesForDevice(_selectedEndpointId!);
      }
    } catch (e) {
      debugPrint('❌ Error sending location: $e');
    }
  }

  Future<void> _sendEmergencyMessage() async {
    if (_selectedEndpointId == null || !mounted) return;

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

    // Add mounted check after async dialog operation
    if (confirm == true && mounted && _selectedEndpointId != null) {
      try {
        await _syncService.sendMessage(
          endpointId: _selectedEndpointId!,
          message: '🚨 Emergency SOS',
          fromUser: widget.p2pService.userName ?? 'Unknown',
          isEmergency: true,
          messageType: MessageType.sos,
          latitude: widget.currentLocation?.latitude,
          longitude: widget.currentLocation?.longitude,
          p2pService: widget.p2pService,
        );

        // Add mounted check before using context after async operation
        if (mounted) {
          await _loadMessagesForDevice(_selectedEndpointId!);

          // Add another mounted check before using ScaffoldMessenger
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Emergency SOS sent')));
          }
        }
      } catch (e) {
        debugPrint('❌ Error sending emergency message: $e');

        // Add mounted check before showing error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send emergency SOS: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _openConversation(String endpointId) {
    if (!mounted) return;
    setState(() {
      _selectedEndpointId = endpointId;
      _isChatView = true;
    });
    _loadMessagesForDevice(endpointId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
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
                if (mounted) {
                  setState(() {
                    _isChatView = false;
                    _selectedEndpointId = null;
                    _selectedConversationMessages.clear();
                  });
                }
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
            if (message != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      message.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  SizedBox(width: 8),
                  _buildMessageStatusIcon(message.status),
                ],
              ),
              SizedBox(height: 4),
            ],
            Text(
              message != null
                  ? _formatFullDateTime(message.dateTime)
                  : 'No messages available',
              style: TextStyle(fontSize: 12, color: Colors.white54),
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
          ],
        ),
        onTap: () => _openConversation(conversation.endpointId),
      ),
    );
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return Icon(Icons.schedule, size: 16, color: Colors.orange);
      case MessageStatus.sent:
        return Icon(Icons.check, size: 16, color: Colors.blue);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 16, color: Colors.green);
      case MessageStatus.failed:
        return Icon(Icons.error, size: 16, color: Colors.red);
      case MessageStatus.synced:
        return Icon(Icons.cloud_done, size: 16, color: Colors.green);
      // Remove the default case since all enum values are covered
    }
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
            color: Colors.white70,
            fontSize: 12,
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
                        mainAxisSize: MainAxisSize.min,
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
                      if (isMe) ...[
                        SizedBox(width: 4),
                        _buildMessageStatusIcon(message.status),
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
