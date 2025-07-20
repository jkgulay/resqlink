import 'package:flutter/material.dart';
import 'package:resqlink/gps_page.dart';
import '../services/p2p_services.dart';
import '../services/database_service.dart';
import '../models/message_model.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'dart:typed_data';

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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages();
    widget.p2pService.addListener(_onP2PUpdate);
    widget.p2pService.onMessageReceived = _onMessageReceived;

    // Refresh messages periodically
    _refreshTimer = Timer.periodic(Duration(seconds: 2), (_) {
      _loadMessages();
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
    }
  }

  void _onP2PUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onMessageReceived(P2PMessage message) {
    // Reload messages when new message received
    _loadMessages();

    // Show notification for emergency messages
    if (message.type == MessageType.emergency ||
        message.type == MessageType.sos) {
      _showEmergencyNotification(message);
    }
  }

  void _showEmergencyNotification(P2PMessage message) async {
    if (!mounted) return;

    // Show notification with sound and vibration
    await NotificationService.showEmergencyNotification(
      title: 'EMERGENCY from ${message.senderName}',
      body: message.message,
      playSound: true,
      vibrate: true,
    );

    // Check mounted before using context
    if (!mounted) return;

    // Also show SnackBar for in-app notification
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
                    'EMERGENCY from ${message.senderName}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(message.message),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            _scrollToBottom();
          },
        ),
      ),
    );
  }

  Future<void> _loadMessages() async {
    try {
      // Load all messages (group chat approach)
      final messages = await DatabaseService.getAllMessages();

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });

        // Scroll to bottom if new messages
        if (messages.length > _messages.length) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    // Send message to all connected devices
    await widget.p2pService.sendMessage(message: text, type: MessageType.text);

    // Reload messages
    await _loadMessages();
  }

  Future<void> _sendLocationMessage() async {
    if (widget.currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No location available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await widget.p2pService.sendMessage(
      message: '📍 Shared my location',
      type: MessageType.location,
      latitude: widget.currentLocation!.latitude,
      longitude: widget.currentLocation!.longitude,
    );

    await _loadMessages();
  }

  Future<void> _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Chat History?'),
        content: Text(
          'This will delete all messages from your device. Messages on other devices will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.clearAllData();
      await _loadMessages();

      // Check if widget is still mounted before using context
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Chat history cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.p2pService.connectedDevices.isNotEmpty;
    final connectedCount = widget.p2pService.connectedDevices.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Emergency Chat'),
            Text(
              isConnected
                  ? 'Connected to $connectedCount device${connectedCount > 1 ? 's' : ''}'
                  : 'No connection',
              style: TextStyle(
                fontSize: 12,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.p2pService.isOnline)
            Icon(Icons.cloud_done, color: Colors.green)
          else
            Icon(Icons.cloud_off, color: Colors.grey),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _clearChatHistory();
              } else if (value == 'info') {
                _showConnectionInfo();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 8),
                    Text('Connection Info'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20),
                    SizedBox(width: 8),
                    Text('Clear History'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Banner
          if (!isConnected)
            Container(
              padding: EdgeInsets.all(8),
              color: Colors.orange,
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
            ),

          // Messages List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final previousMessage = index > 0
                          ? _messages[index - 1]
                          : null;
                      final showDateHeader = _shouldShowDateHeader(
                        message,
                        previousMessage,
                      );

                      return Column(
                        children: [
                          if (showDateHeader)
                            _buildDateHeader(message.dateTime),
                          _buildMessageBubble(message),
                        ],
                      );
                    },
                  ),
          ),

          // Input Area
          _buildInputArea(isConnected),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            widget.p2pService.connectedDevices.isEmpty
                ? 'Connect to a device to start messaging'
                : 'Send a message to start the conversation',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  bool _shouldShowDateHeader(
    MessageModel message,
    MessageModel? previousMessage,
  ) {
    if (previousMessage == null) return true;

    final currentDate = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final previousDate = DateTime.fromMillisecondsSinceEpoch(
      previousMessage.timestamp,
    );

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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          dateText,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message) {
    final isMe = message.isMe;
    final hasLocation = message.hasLocation;

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
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  message.fromUser,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isEmergency
                    ? Colors.red
                    : message.type == 'location'
                    ? Colors.blue
                    : isMe
                    ? Theme.of(context).primaryColor
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(16).copyWith(
                  topLeft: isMe ? null : Radius.circular(4),
                  topRight: isMe ? Radius.circular(4) : null,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((255 * 0.1).toInt()),

                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.priority > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
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
                      color:
                          (message.isEmergency ||
                              message.type == 'location' ||
                              isMe)
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
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha((255 * 0.2).toInt()),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'View Location',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                              ),
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
                              (message.isEmergency ||
                                  message.type == 'location' ||
                                  isMe)
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
                              (message.isEmergency ||
                                  message.type == 'location' ||
                                  isMe)
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (widget.currentLocation != null)
              IconButton(
                icon: Icon(
                  Icons.location_on,
                  color: Theme.of(context).primaryColor,
                ),
                onPressed: _sendLocationMessage,
                tooltip: 'Share Location',
              ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: isConnected
                      ? 'Type a message...'
                      : 'Type a message (will save locally)...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _sendMessage,
                icon: Icon(Icons.send, color: Colors.white),
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
      builder: (context) => Container(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.person, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'From: ${message.fromUser}',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Coordinates: ${message.latitude!.toStringAsFixed(6)}, ${message.longitude!.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Time: ${_formatFullDateTime(message.dateTime)}',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(Icons.map),
                label: Text('Open in Maps'),
                onPressed: () {
                  // You can integrate with maps here
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Opening location in maps...')),
                  );
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
      builder: (context) => AlertDialog(
        title: Text('Connection Information'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                'Device ID',
                info['deviceId']?.substring(0, 8) ?? 'Unknown',
              ),
              _buildInfoRow('Role', info['role']?.toUpperCase() ?? 'NONE'),
              _buildInfoRow('Connected Devices', '${devices.length}'),
              _buildInfoRow(
                'Sync Status',
                info['isOnline'] == true ? 'Online' : 'Offline',
              ),
              _buildInfoRow(
                'Pending Messages',
                '${info['pendingMessages'] ?? 0}',
              ),
              _buildInfoRow(
                'Messages Processed',
                '${info['processedMessages'] ?? 0}',
              ),

              if (devices.isNotEmpty) ...[
                SizedBox(height: 16),
                Text(
                  'Connected Devices:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ...devices.entries.map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${entry.value.name} (${entry.key.substring(0, 8)})',
                      style: TextStyle(fontSize: 14),
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
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatFullDateTime(DateTime time) {
    return '${time.day}/${time.month}/${time.year} ${_formatTime(time)}';
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();

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
    required bool playSound,
    required bool vibrate,
  }) async {
    // Vibration pattern for emergency
    if (vibrate) {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(
          pattern: [0, 500, 200, 500, 200, 1000], // Emergency pattern
          intensities: [0, 255, 0, 255, 0, 255],
        );
      }
    }

    // Play emergency sound
    if (playSound) {
      try {
        await _audioPlayer.play(AssetSource('sounds/emergency_alert.mp3'));
      } catch (e) {
        print('Error playing sound: $e');
      }
    }

    // Show notification
  final androidDetails = AndroidNotificationDetails(
  'emergency_channel',
  'Emergency Alerts',
  channelDescription: 'Emergency notifications from nearby users',
  importance: Importance.max,
  priority: Priority.high,
  playSound: true,
  enableVibration: true,
  vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000]), // No const here
  styleInformation: const BigTextStyleInformation(''),
  color: const Color(0xFFFF0000),
  icon: '@drawable/ic_emergency',
);

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'emergency_alert.aiff',
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
  final String deviceId;
  final String deviceName;
  final MessageModel? lastMessage;
  final int messageCount;
  final int unreadCount;
  final bool isConnected;

  MessageSummary({
    required this.deviceId,
    required this.deviceName,
    this.lastMessage,
    required this.messageCount,
    required this.unreadCount,
    required this.isConnected,
  });
}
