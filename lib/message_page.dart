import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/gps_page.dart';
import 'package:resqlink/services/message_sync_service.dart';
import 'package:resqlink/services/settings_service.dart';
import 'services/p2p_service.dart';
import '../services/database_service.dart';
import '../models/message_model.dart';
import '../utils/resqlink_theme.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../services/message_ack_service.dart';
import '../services/signal_monitoring_service.dart';
import '../services/emergency_recovery_service.dart';

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
      if (hasVibrator == true) {
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
        debugPrint('Error playing sound: $e');
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
  final MessageAcknowledgmentService _ackService =
      MessageAcknowledgmentService();
  final SignalMonitoringService _signalService = SignalMonitoringService();
  final EmergencyRecoveryService _recoveryService = EmergencyRecoveryService();

  // State Variables
  List<MessageSummary> _conversations = [];
  List<MessageModel> _selectedConversationMessages = [];
  String? _selectedEndpointId;
  String? _selectedDeviceName;
  bool _isLoading = true;
  bool _isChatView = false;
  bool _isTyping = false;
  Timer? _refreshTimer;
  Timer? _typingTimer;

  // Current user info
  String get _currentUserId => widget.p2pService.deviceId ?? 'unknown';
  LocationModel? get _currentLocation => widget.currentLocation;

  Duration get _refreshInterval {
    if (!widget.p2pService.isConnected) return Duration(minutes: 1);
    if (widget.p2pService.emergencyMode) return Duration(seconds: 10);
    return Duration(seconds: 30);
  }

  void _startAdaptiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (mounted) {
        _loadConversations();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  void _initialize() async {
    if (!mounted) return;

    try {
      await _syncService.initialize();
      if (!mounted) return;

      widget.p2pService.addListener(_onP2PConnectionChanged);
      widget.p2pService.onDevicesDiscovered = _onDevicesDiscovered;
      widget.p2pService.onDeviceConnected = (deviceId, userName) {
        if (!mounted) return;
        _createConversationForDevice(deviceId, userName);
        _showSuccessMessage('Connected to $userName');
      };

      widget.p2pService.onDeviceDisconnected = (deviceId) {
        if (!mounted) return;
        _loadConversations();
        _showErrorMessage('Device disconnected');
      };

      _ackService.initialize(widget.p2pService);
      _signalService.startMonitoring(widget.p2pService);
      _recoveryService.initialize(widget.p2pService, _signalService);

      if (widget.p2pService.emergencyMode) {
        _recoveryService.startEmergencyRecovery();
      }

      widget.p2pService.addListener(_onP2PUpdate);
      widget.p2pService.onMessageReceived = _onMessageReceived;

      await _loadConversations();

      if (!mounted) return;

      Timer.periodic(Duration(seconds: 5), (_) {
        if (mounted) {
          _loadConversations();
        }
      });

      _refreshTimer = Timer.periodic(Duration(seconds: 5), (_) {
        if (mounted) {
          _loadConversations();
        }
      });
    } catch (e) {
      debugPrint('❌ Error initializing MessagePage: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    debugPrint('🗑️ MessagePage disposing...');

    _refreshTimer?.cancel();
    _refreshTimer = null;

    _typingTimer?.cancel();
    _typingTimer = null;

    try {
      _syncService.dispose();
      _signalService.dispose();
      _recoveryService.dispose();
      _ackService.dispose();
    } catch (e) {
      debugPrint('Error disposing services: $e');
    }

    try {
      widget.p2pService.removeListener(_onP2PUpdate);
      widget.p2pService.removeListener(_onP2PConnectionChanged);
    } catch (e) {
      debugPrint('Error removing listeners: $e');
    }

    widget.p2pService.onMessageReceived = null;
    widget.p2pService.onDevicesDiscovered = null;

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        _startAdaptiveRefresh();
        if (mounted) await _loadConversations();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _refreshTimer?.cancel();
      case AppLifecycleState.detached:
        dispose();
      case AppLifecycleState.hidden:
        _refreshTimer?.cancel();
    }
  }

  void _onP2PConnectionChanged() {
    if (!mounted) return;
    _loadConversations();
    setState(() {});
  }

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) {
    if (!mounted) return;

    for (var device in devices) {
      final deviceId = device['deviceAddress'];
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final isConnected = widget.p2pService.connectedDevices.containsKey(
        deviceId,
      );

      if (isConnected) {
        _createConversationForDevice(deviceId, deviceName);
      }
    }
  }

  void _createConversationForDevice(String deviceId, String deviceName) {
    if (!mounted) return;

    final existingConversation = _conversations.any(
      (conv) => conv.endpointId == deviceId,
    );

    if (!existingConversation) {
      final newConversation = MessageSummary(
        endpointId: deviceId,
        deviceName: deviceName,
        lastMessage: null,
        messageCount: 0,
        unreadCount: 0,
        isConnected: true,
      );

      setState(() {
        _conversations.insert(0, newConversation);
      });

      debugPrint('✅ Created conversation placeholder for $deviceName');
    }
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;

    try {
      final messages = await DatabaseService.getAllMessages().timeout(
        Duration(seconds: 10),
      );
      if (!mounted) return;

      final connectedDevices = widget.p2pService.connectedDevices;
      final discoveredDevices = widget.p2pService.discoveredDevices;

      final Map<String, MessageSummary> conversationMap = {};

      for (final message in messages) {
        if (!mounted) return;

        final endpointId = message.endpointId;
        String deviceName = message.fromUser;

        if (connectedDevices.containsKey(endpointId)) {
          deviceName = connectedDevices[endpointId]!.name;
        } else if (discoveredDevices.containsKey(endpointId)) {
          deviceName =
              discoveredDevices[endpointId]!['deviceName'] ?? deviceName;
        }

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
              deviceName: deviceName,
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
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMessagesForDevice(String endpointId) async {
    if (!mounted) return;

    try {
      final messages = await DatabaseService.getMessages(endpointId);
      if (!mounted) return;

      setState(() {
        _selectedConversationMessages = messages;
      });

      _scrollToBottom();

      for (final message in messages.where((m) => !m.isMe && !m.synced)) {
        if (!mounted) return;

        if (message.messageId != null) {
          await DatabaseService.updateMessageStatus(
            message.messageId!,
            MessageStatus.delivered,
          );
        }
      }

      if (mounted) {
        await _loadConversations();
      }
    } catch (e) {
      debugPrint('❌ Error loading messages for device $endpointId: $e');
    }
  }

  void _onP2PUpdate() async {
    if (!mounted) return;

    try {
      await _loadConversations();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error in _onP2PUpdate: $e');
    }
  }

  void _onMessageReceived(P2PMessage message) async {
    if (!mounted) return;

    try {
      final messageId = message.id;
      final senderId = message.senderId;
      final senderName = message.senderName;

      final messageModel = MessageModel(
        endpointId: senderId,
        fromUser: senderName,
        message: message.message,
        isMe: false,
        isEmergency:
            message.type == MessageType.emergency ||
            message.type == MessageType.sos,
        timestamp: message.timestamp.millisecondsSinceEpoch,
        latitude: message.latitude,
        longitude: message.longitude,
        messageId: messageId,
        type: message.type.name,
        status: MessageStatus.delivered,
      );

      final existingMessage = await DatabaseService.getMessageById(messageId);
      if (existingMessage != null) {
        debugPrint('⚠️ Duplicate message received: $messageId');
        return;
      }

      await DatabaseService.insertMessage(messageModel);

      if (!mounted) return;

      await _batchUIUpdates(() async {
        await _loadConversations();

        if (message.type == MessageType.emergency ||
            message.type == MessageType.sos) {
          await _showEmergencyNotification(message);
        }

        if (_isChatView && _selectedEndpointId == senderId) {
          await _loadMessagesForDevice(_selectedEndpointId!);
        } else {
          _showInAppNotification(message);
        }
      });
    } catch (e) {
      debugPrint('❌ Error in _onMessageReceived: $e');
      if (mounted) {
        _showErrorMessage('Failed to process received message');
      }
    }
  }

  Future<void> _batchUIUpdates(Future<void> Function() updates) async {
    try {
      await updates();
    } catch (e) {
      debugPrint('❌ Error in batch UI updates: $e');
    }
  }

  Future<void> _showEmergencyNotification(P2PMessage message) async {
    if (!mounted) return;

    try {
      final settings = context.read<SettingsService>();

      if (!settings.emergencyNotifications) return;

      final playSound = settings.soundNotifications && !settings.silentMode;
      final vibrate = settings.vibrationNotifications && !settings.silentMode;

      await NotificationService.showEmergencyNotification(
        title: '${message.type.name.toUpperCase()} from ${message.senderName}',
        body: message.message,
        playSound: playSound,
        vibrate: vibrate,
      );

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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                      ),
                      Text(
                        body,
                        style: TextStyle(color: Colors.white),
                        maxLines: 2,
                      ),
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
              onPressed: () =>
                  _openConversation(message.senderId, message.senderName),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error showing emergency notification: $e');
    }
  }

  void _showInAppNotification(P2PMessage message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor:
                  message.type == MessageType.emergency ||
                      message.type == MessageType.sos
                  ? ResQLinkTheme.primaryRed
                  : ResQLinkTheme.safeGreen,
              child: Icon(
                message.type == MessageType.emergency ||
                        message.type == MessageType.sos
                    ? Icons.warning
                    : Icons.message,
                color: Colors.white,
                size: 16,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New message from ${message.senderName}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                  ),
                  Text(
                    message.message,
                    style: TextStyle(color: Colors.white70),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: ResQLinkTheme.cardDark,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: ResQLinkTheme.primaryRed,
          onPressed: () =>
              _openConversation(message.senderId, message.senderName),
        ),
      ),
    );
  }

  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${_currentUserId.hashCode}';
  }

  Future<void> _sendMessage(String messageText, MessageType type) async {
    try {
      final messageId = _generateMessageId();
      final timestamp = DateTime.now();

      await widget.p2pService.sendMessage(
        message: messageText,
        type: type,
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
        senderName: '',
      );

      final dbMessage = MessageModel(
        endpointId: _selectedEndpointId ?? 'broadcast',
        fromUser: widget.p2pService.userName ?? 'Unknown',
        message: messageText,
        isMe: true,
        isEmergency: type == MessageType.emergency || type == MessageType.sos,
        timestamp: timestamp.millisecondsSinceEpoch,
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
        messageId: messageId,
        type: type.name,
        status: MessageStatus.sent,
      );

      await DatabaseService.insertMessage(dbMessage);
      await _loadMessagesForDevice(_selectedEndpointId!);
    } catch (e) {
      debugPrint('Error sending message: $e');
      _showErrorMessage('Failed to send message');
    }
  }

  Future<void> _sendLocationMessage() async {
    if (_selectedEndpointId == null || !mounted) {
      if (mounted) {
        _showErrorMessage('No conversation selected');
      }
      return;
    }

    if (widget.currentLocation?.latitude == null ||
        widget.currentLocation?.longitude == null) {
      if (mounted) {
        _showErrorMessage('Location not available. Please enable GPS.');
      }
      return;
    }

    try {
      final locationText =
          '📍 Location shared\nLat: ${widget.currentLocation!.latitude.toStringAsFixed(6)}\nLng: ${widget.currentLocation!.longitude.toStringAsFixed(6)}';

      // ENHANCED: Save location to your existing database first
      final locationModel = LocationModel(
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
        timestamp: DateTime.now(),
        userId: widget.p2pService.deviceId,
        type: LocationType.normal,
        message: 'Shared via sync service',
      );

      await LocationService.insertLocation(locationModel);

      await _syncService.sendMessage(
        endpointId: _selectedEndpointId!,
        message: locationText,
        fromUser: widget.p2pService.userName ?? 'Unknown',
        isEmergency: false,
        messageType: MessageType.location,
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
        p2pService: widget.p2pService,
      );

      if (mounted) {
        await _loadMessagesForDevice(_selectedEndpointId!);
        _showSuccessMessage('Location shared successfully');
      }
    } catch (e) {
      debugPrint('❌ Error sending location: $e');
      if (mounted) {
        _showErrorMessage('Failed to share location');
      }
    }
  }

  Future<void> _sendLocationViaP2P() async {
    if (_selectedEndpointId == null || !mounted) {
      if (mounted) {
        _showErrorMessage('No conversation selected');
      }
      return;
    }

    if (widget.currentLocation == null) {
      if (mounted) {
        _showErrorMessage('Location not available. Please enable GPS.');
      }
      return;
    }

    try {
      // ENHANCED: Save to your existing database first
      final locationModel = LocationModel(
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
        timestamp: DateTime.now(),
        userId: widget.p2pService.deviceId,
        type: LocationType.normal,
        message: 'Shared via P2P',
      );

      await LocationService.insertLocation(locationModel);

      // Generate proper message ID
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_${widget.p2pService.deviceId?.hashCode ?? 0}';

      await widget.p2pService.sendMessage(
        id: messageId,
        senderName: widget.p2pService.userName ?? 'Unknown',
        message: '📍 Shared my location',
        type: MessageType.location,
        ttl: 5,
        routePath: [],
        targetDeviceId: _selectedEndpointId,
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
      );

      if (mounted) {
        await _loadMessagesForDevice(_selectedEndpointId!);
        _showSuccessMessage('Location shared via P2P');
      }
    } catch (e) {
      debugPrint('❌ Error sending location via P2P: $e');
      if (mounted) {
        _showErrorMessage('Failed to share location via P2P');
      }
    }
  }

  Future<void> _sendEmergencyMessage() async {
    if (_selectedEndpointId == null || !mounted) return;

    final confirm = await _showEmergencyConfirmDialog();

    if (confirm == true && mounted && _selectedEndpointId != null) {
      try {
        await _sendMessage('🚨 Emergency SOS', MessageType.sos);
        if (mounted) {
          _showSuccessMessage('Emergency SOS sent');
        }
      } catch (e) {
        debugPrint('❌ Error sending emergency message: $e');
        if (mounted) {
          _showErrorMessage('Failed to send emergency SOS');
        }
      }
    }
  }

  void _openConversation(String endpointId, [String? deviceName]) {
    if (!mounted) return;
    setState(() {
      _selectedEndpointId = endpointId;
      _selectedDeviceName = deviceName;
      _isChatView = true;
    });
    _loadMessagesForDevice(endpointId);
  }

  void _scrollToBottom() {
    if (!mounted) return;

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

  void _handleTyping(String text) {
    if (!mounted) return;

    if (!_isTyping && mounted) {
      setState(() => _isTyping = true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isTyping = false);
      }
    });
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(message, style: TextStyle(color: Colors.white)),
          ],
        ),
        backgroundColor: ResQLinkTheme.safeGreen,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white),
                maxLines: 2,
              ),
            ),
          ],
        ),
        backgroundColor: ResQLinkTheme.primaryRed,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<bool?> _showEmergencyConfirmDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildEmergencyDialog(),
    );
  }

  Widget _buildEmergencyDialog() {
    return AlertDialog(
      backgroundColor: ResQLinkTheme.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 24),
          SizedBox(width: 8),
          Text('Send Emergency SOS?', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Text(
        'This will send an emergency SOS message to the selected device, including your location if available.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ResQLinkTheme.primaryRed,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Send SOS', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  void _handleMenuAction(String action) async {
    if (!mounted) return;

    switch (action) {
      case 'scan':
        try {
          await widget.p2pService.discoverDevices(force: true);
          if (mounted) {
            _showSuccessMessage('Scanning for nearby devices...');
          }
        } catch (e) {
          if (mounted) {
            _showErrorMessage('Failed to start scan');
          }
        }
      case 'create_group':
        try {
          await widget.p2pService.createEmergencyHotspot();
          if (mounted) {
            _showSuccessMessage('Emergency group created');
          }
        } catch (e) {
          if (mounted) {
            _showErrorMessage('Failed to create group');
          }
        }
      case 'clear_chat':
        if (_selectedEndpointId != null && mounted) {
          await _showClearChatConfirmDialog();
        }
    }
  }

  Future<void> _showClearChatConfirmDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Clear Chat History?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will permanently delete all messages in this conversation.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.primaryRed,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && _selectedEndpointId != null) {
      await _loadMessagesForDevice(_selectedEndpointId!);
      _showSuccessMessage('Chat history cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ResQLinkTheme.darkTheme,
      child: Scaffold(
        backgroundColor: ResQLinkTheme.backgroundDark,
        appBar: _buildAppBar(),
        body: _buildBody(),
        floatingActionButton: _buildFloatingActionButton(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 2,
      shadowColor: Colors.black26,
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B192C), Color(0xFF1E3A5F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: _isChatView
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => setState(() {
                _isChatView = false;
                _selectedEndpointId = null;
                _selectedDeviceName = null;
                _selectedConversationMessages.clear();
              }),
            )
          : null,
      title: _buildAppBarTitle(),
      actions: _buildAppBarActions(),
    );
  }

  Widget _buildAppBarTitle() {
    if (_isChatView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedDeviceName ?? 'Unknown Device',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            maxLines: 1,
          ),
          Text(
            widget.p2pService.connectedDevices.containsKey(_selectedEndpointId)
                ? 'Connected'
                : 'Offline',
            style: TextStyle(
              fontSize: 12,
              color:
                  widget.p2pService.connectedDevices.containsKey(
                    _selectedEndpointId,
                  )
                  ? ResQLinkTheme.safeGreen
                  : ResQLinkTheme.warningYellow,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Messages', style: TextStyle(color: Colors.white)),
        Text(
          widget.p2pService.isConnected
              ? '${widget.p2pService.connectedDevices.length} connected'
              : 'No connection',
          style: TextStyle(
            fontSize: 12,
            color: widget.p2pService.isConnected
                ? ResQLinkTheme.safeGreen
                : ResQLinkTheme.warningYellow,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions() {
    final actions = <Widget>[];

    actions.add(
      Container(
        margin: EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.p2pService.isConnected
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.warningYellow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.p2pService.isConnected ? Icons.wifi : Icons.wifi_off,
              size: 14,
              color: Colors.white,
            ),
            SizedBox(width: 4),
            Text(
              widget.p2pService.currentRole == P2PRole.host
                  ? 'HOST'
                  : widget.p2pService.currentRole == P2PRole.client
                  ? 'CLIENT'
                  : 'OFF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );

    actions.add(
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: Colors.white),
        onSelected: _handleMenuAction,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'scan',
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text('Scan for Devices', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'create_group',
            child: Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text('Create Group', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          if (_isChatView) ...[
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Clear Chat', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return actions;
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: ResQLinkTheme.primaryRed),
            SizedBox(height: 16),
            Text(
              'Loading messages...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (!widget.p2pService.isConnected) _buildConnectionBanner(),
        Expanded(
          child: _isChatView ? _buildChatView() : _buildConversationList(),
        ),
        if (_isChatView) _buildMessageInput(),
      ],
    );
  }

  Widget _buildConnectionBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      color: ResQLinkTheme.warningYellow.withValues(alpha: 0.9),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Not connected to any devices. Messages will be saved locally.',
              style: TextStyle(color: Colors.white),
              maxLines: 2,
            ),
          ),
          TextButton(
            onPressed: () => widget.p2pService.discoverDevices(force: true),
            child: Text(
              'SCAN',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    if (_isChatView || widget.p2pService.isConnected) return null;

    return FloatingActionButton(
      backgroundColor: ResQLinkTheme.primaryRed,
      onPressed: widget.p2pService.isDiscovering
          ? null
          : () async {
              await widget.p2pService.discoverDevices(force: true);
              if (mounted) {
                _showSuccessMessage('Scanning for nearby devices...');
              }
            },
      child: Icon(
        widget.p2pService.isDiscovering
            ? Icons.hourglass_empty
            : Icons.wifi_tethering,
        color: Colors.white,
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
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: ResQLinkTheme.primaryRed,
      backgroundColor: ResQLinkTheme.surfaceDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _conversations.length,
        itemBuilder: (context, index) =>
            _buildConversationCard(_conversations[index]),
      ),
    );
  }

  Widget _buildConversationCard(MessageSummary conversation) {
    final message = conversation.lastMessage;
    final isEmergency = message?.isEmergency ?? false;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ResQLinkTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergency ? ResQLinkTheme.primaryRed : Colors.transparent,
          width: isEmergency ? 2 : 0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openConversation(
            conversation.endpointId,
            conversation.deviceName,
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: conversation.isConnected
                          ? ResQLinkTheme.safeGreen
                          : ResQLinkTheme.offlineGray,
                      radius: 24,
                      child: Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                    if (conversation.isConnected)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: ResQLinkTheme.safeGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.deviceName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (message != null)
                            Text(
                              _formatRelativeTime(message.dateTime),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                        ],
                      ),
                      if (message != null) ...[
                        SizedBox(height: 4),
                        Text(
                          message.message,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                if (conversation.unreadCount > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ResQLinkTheme.primaryRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${conversation.unreadCount}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
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

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.day == now.day && date.month == now.month && date.year == now.year;
    final isYesterday = date.difference(now).inDays == -1;

    String dateText;
    if (isToday) {
      dateText = 'Today';
    } else if (isYesterday) {
      dateText = 'Yesterday';
    } else {
      dateText = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateText,
            style: TextStyle(color: Colors.white70, fontSize: 12),
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
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        margin: EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (isEmergency) _buildEmergencyHeader(message.type),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: _getMessageGradient(isMe, isEmergency, message.type),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.message,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  if (hasLocation) ...[
                    SizedBox(height: 8),
                    _buildLocationPreview(message),
                  ],
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.dateTime),
                        style: TextStyle(color: Colors.white70, fontSize: 12),
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

  Widget _buildEmergencyHeader(String type) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 16),
          SizedBox(width: 4),
          Text(
            type.toUpperCase(),
            style: TextStyle(
              color: ResQLinkTheme.primaryRed,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPreview(MessageModel message) {
    return InkWell(
      onTap: () => _showLocationDetails(message),
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              'Location shared',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _getMessageGradient(bool isMe, bool isEmergency, String type) {
    if (isEmergency) {
      return LinearGradient(
        colors: [ResQLinkTheme.primaryRed, Colors.red.shade700],
      );
    }

    if (type == 'location') {
      return LinearGradient(colors: [Colors.blue, Colors.blue.shade700]);
    }

    if (isMe) {
      return LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF0B192C)]);
    }

    return LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade800]);
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    IconData icon;
    Color color;

    switch (status) {
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.white70;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = ResQLinkTheme.safeGreen;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = ResQLinkTheme.primaryRed;
      case MessageStatus.pending:
      default:
        icon = Icons.schedule;
        color = Colors.white54;
    }

    return Icon(icon, size: 14, color: color);
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.location_on, color: Colors.blue),
                  onPressed: _sendLocationMessage,
                  tooltip: 'Share Location',
                ),
                IconButton(
                  icon: Icon(Icons.my_location, color: Colors.green),
                  onPressed: _sendLocationViaP2P,
                  tooltip: 'Share via P2P',
                ),
                IconButton(
                  icon: Icon(Icons.warning, color: ResQLinkTheme.primaryRed),
                  onPressed: _sendEmergencyMessage,
                  tooltip: 'Send Emergency',
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _handleTyping,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: ResQLinkTheme.cardDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(color: Colors.white),
                    maxLines: null,
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: ResQLinkTheme.primaryRed,
                  onPressed: () {
                    final text = _messageController.text.trim();
                    if (text.isNotEmpty) {
                      _sendMessage(text, MessageType.text);
                      _messageController.clear();
                    }
                  },
                  child: Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';

    return '${dateTime.day}/${dateTime.month}';
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

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    return '$displayHour:$minute $period';
  }

  void _showLocationDetails(MessageModel message) {
    if (message.latitude == null || message.longitude == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text('Location Details', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Latitude: ${message.latitude!.toStringAsFixed(6)}',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              'Longitude: ${message.longitude!.toStringAsFixed(6)}',
              style: TextStyle(color: Colors.white70),
            ),
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
}
