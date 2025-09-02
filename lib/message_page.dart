import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  // Services (aligned with home page service usage)
  final MessageSyncService _syncService = MessageSyncService();
  final MessageAcknowledgmentService _ackService =
      MessageAcknowledgmentService();
  final SignalMonitoringService _signalService = SignalMonitoringService();
  final EmergencyRecoveryService _recoveryService = EmergencyRecoveryService();

  // State Variables (consistent with home page patterns)
  List<MessageSummary> _conversations = [];
  List<MessageModel> _selectedConversationMessages = [];
  String? _selectedEndpointId;
  String? _selectedDeviceName;
  bool _isLoading = true;
  bool _isChatView = false;
  bool _isTyping = false;
  Timer? _refreshTimer;
  Timer? _typingTimer;
  StreamSubscription? _p2pSubscription;

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

      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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
  void dispose() {
    debugPrint('🗑️ MessagePage disposing...');

    _refreshTimer?.cancel();
    _refreshTimer = null;
    _typingTimer?.cancel();
    _typingTimer = null;
    _p2pSubscription?.cancel();
    _p2pSubscription = null;

    widget.p2pService.removeListener(_onP2PUpdate);
    widget.p2pService.onMessageReceived = null;

    _messageController.dispose();
    _scrollController.dispose();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed && mounted) {
      try {
        await _loadConversations();
      } catch (e) {
        debugPrint('❌ Error in didChangeAppLifecycleState: $e');
      }
    }
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;

    try {
      final messages = await DatabaseService.getAllMessages();
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
    if (!mounted) return; // ✅ Guard against disposed state

    try {
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

      if (!mounted) return;

      await _loadConversations();

      if (!mounted) return;

      if (message.type == MessageType.emergency ||
          message.type == MessageType.sos) {
        await _showEmergencyNotification(message);
      }

      if (!mounted) return;

      if (_isChatView && _selectedEndpointId == message.senderId) {
        await _loadMessagesForDevice(_selectedEndpointId!);
      } else {
        _showInAppNotification(message);
      }
    } catch (e) {
      debugPrint('❌ Error in _onMessageReceived: $e');
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

      if (!mounted) return; // ✅ Check after notification

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
                SizedBox(width: ResponsiveSpacing.sm(context)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ResponsiveTextWidget(
                        '${message.type.name.toUpperCase()} from ${message.senderName}',
                        styleBuilder: (context) =>
                            ResponsiveText.bodyLarge(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                        maxLines: 1,
                      ),
                      ResponsiveTextWidget(
                        body,
                        styleBuilder: (context) => ResponsiveText.bodyMedium(
                          context,
                        ).copyWith(color: Colors.white),
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
            SizedBox(width: ResponsiveSpacing.sm(context)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ResponsiveTextWidget(
                    'New message from ${message.senderName}',
                    styleBuilder: (context) =>
                        ResponsiveText.bodyMedium(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                    maxLines: 1,
                  ),
                  ResponsiveTextWidget(
                    message.message,
                    styleBuilder: (context) => ResponsiveText.bodySmall(
                      context,
                    ).copyWith(color: Colors.white70),
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

  // ✅ Message actions aligned with home page patterns
  Future<void> _sendMessage() async {
    if (!mounted) return;

    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedEndpointId == null) return;

    _messageController.clear();

    try {
      await _ackService.sendMessageWithAck(
        widget.p2pService,
        message: text,
        type: MessageType.text,
        targetDeviceId: _selectedEndpointId!,
      );

      if (mounted) {
        await _loadMessagesForDevice(_selectedEndpointId!);
        _showSuccessMessage('Message sent');
      }
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        _showErrorMessage('Failed to send message');
      }
    }
  }

  Future<void> _sendLocationMessage() async {
    if (widget.currentLocation == null ||
        _selectedEndpointId == null ||
        !mounted) {
      if (mounted) {
        _showErrorMessage('No location available');
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
        _showSuccessMessage('Location shared');
      }
    } catch (e) {
      debugPrint('❌ Error sending location: $e');
      if (mounted) {
        _showErrorMessage('Failed to share location');
      }
    }
  }

  Future<void> _sendEmergencyMessage() async {
    if (_selectedEndpointId == null || !mounted) return;

    final confirm = await _showEmergencyConfirmDialog();

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

        if (mounted) {
          await _loadMessagesForDevice(_selectedEndpointId!);
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

  // ✅ UI Helper methods aligned with home page
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
            SizedBox(width: ResponsiveSpacing.sm(context)),
            ResponsiveTextWidget(
              message,
              styleBuilder: (context) => ResponsiveText.bodyMedium(
                context,
              ).copyWith(color: Colors.white),
            ),
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
            SizedBox(width: ResponsiveSpacing.sm(context)),
            Expanded(
              child: ResponsiveTextWidget(
                message,
                styleBuilder: (context) => ResponsiveText.bodyMedium(
                  context,
                ).copyWith(color: Colors.white),
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
      builder: (context) => ResponsiveWidget(
        mobile: _buildMobileEmergencyDialog(),
        tablet: _buildTabletEmergencyDialog(),
      ),
    );
  }

  Widget _buildMobileEmergencyDialog() {
    return AlertDialog(
      backgroundColor: ResQLinkTheme.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 24),
          SizedBox(width: ResponsiveSpacing.sm(context)),
          ResponsiveTextWidget(
            'Send Emergency SOS?',
            styleBuilder: (context) =>
                ResponsiveText.heading3(context).copyWith(color: Colors.white),
          ),
        ],
      ),
      content: ResponsiveTextWidget(
        'This will send an emergency SOS message to the selected device, including your location if available.',
        styleBuilder: (context) =>
            ResponsiveText.bodyMedium(context).copyWith(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: ResponsiveTextWidget(
            'Cancel',
            styleBuilder: (context) =>
                ResponsiveText.button(context).copyWith(color: Colors.white70),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ResQLinkTheme.primaryRed,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: ResponsiveTextWidget(
            'Send SOS',
            styleBuilder: (context) =>
                ResponsiveText.button(context).copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletEmergencyDialog() {
    return Dialog(
      backgroundColor: ResQLinkTheme.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: ResponsiveSpacing.padding(
          context,
          all: ResponsiveSpacing.lg(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: ResponsiveSpacing.padding(
                    context,
                    all: ResponsiveSpacing.sm(context),
                  ),
                  decoration: BoxDecoration(
                    color: ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning,
                    color: ResQLinkTheme.primaryRed,
                    size: 32,
                  ),
                ),
                SizedBox(width: ResponsiveSpacing.md(context)),
                Expanded(
                  child: ResponsiveTextWidget(
                    'Send Emergency SOS?',
                    styleBuilder: (context) => ResponsiveText.heading2(
                      context,
                    ).copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveSpacing.lg(context)),
            ResponsiveTextWidget(
              'This will send an emergency SOS message to the selected device, including your location if available. This action should only be used in real emergencies.',
              styleBuilder: (context) => ResponsiveText.bodyLarge(
                context,
              ).copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveSpacing.xl(context)),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: ResponsiveSpacing.padding(
                        context,
                        vertical: ResponsiveSpacing.md(context),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: ResponsiveTextWidget(
                      'Cancel',
                      styleBuilder: (context) => ResponsiveText.button(
                        context,
                      ).copyWith(color: Colors.white70),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveSpacing.md(context)),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ResQLinkTheme.primaryRed,
                      padding: ResponsiveSpacing.padding(
                        context,
                        vertical: ResponsiveSpacing.md(context),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: ResponsiveTextWidget(
                      'Send SOS',
                      styleBuilder: (context) => ResponsiveText.button(
                        context,
                      ).copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
          await widget.p2pService.createEmergencyGroup();
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
        title: ResponsiveTextWidget(
          'Clear Chat History?',
          styleBuilder: (context) =>
              ResponsiveText.heading3(context).copyWith(color: Colors.white),
        ),
        content: ResponsiveTextWidget(
          'This will permanently delete all messages in this conversation.',
          styleBuilder: (context) => ResponsiveText.bodyMedium(
            context,
          ).copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: ResponsiveTextWidget(
              'Cancel',
              styleBuilder: (context) => ResponsiveText.button(
                context,
              ).copyWith(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.primaryRed,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: ResponsiveTextWidget(
              'Clear',
              styleBuilder: (context) =>
                  ResponsiveText.button(context).copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && _selectedEndpointId != null) {
      await _loadMessagesForDevice(_selectedEndpointId!);
      _showSuccessMessage('Chat history cleared');
    }
  }

  // ✅ Responsive UI Building Methods aligned with home page
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ResQLinkTheme.darkTheme,
      child: Scaffold(
        backgroundColor: ResQLinkTheme.backgroundDark,
        appBar: _buildResponsiveAppBar(),
        body: _buildResponsiveBody(),
        floatingActionButton: _buildResponsiveFloatingActionButton(),
      ),
    );
  }

  PreferredSizeWidget _buildResponsiveAppBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;

    return AppBar(
      elevation: 2,
      shadowColor: Colors.black26,
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      toolbarHeight: isNarrowScreen ? 56 : 64,
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
      title: _buildResponsiveAppBarTitle(isNarrowScreen),
      actions: _buildResponsiveAppBarActions(isNarrowScreen),
    );
  }

  Widget _buildResponsiveAppBarTitle(bool isNarrowScreen) {
    if (_isChatView) {
      return ResponsiveWidget(
        mobile: _buildMobileChatTitle(isNarrowScreen),
        tablet: _buildTabletChatTitle(isNarrowScreen),
      );
    }

    return ResponsiveWidget(
      mobile: _buildMobileMessagesTitle(isNarrowScreen),
      tablet: _buildTabletMessagesTitle(isNarrowScreen),
    );
  }

  Widget _buildMobileChatTitle(bool isNarrowScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveTextWidget(
          _selectedDeviceName ?? 'Unknown Device',
          styleBuilder: (context) => ResponsiveText.bodyLarge(
            context,
          ).copyWith(fontWeight: FontWeight.w600, color: Colors.white),
          maxLines: 1,
        ),
        ResponsiveTextWidget(
          widget.p2pService.connectedDevices.containsKey(_selectedEndpointId)
              ? 'Connected'
              : 'Offline',
          styleBuilder: (context) => ResponsiveText.caption(context).copyWith(
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

  Widget _buildTabletChatTitle(bool isNarrowScreen) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor:
              widget.p2pService.connectedDevices.containsKey(
                _selectedEndpointId,
              )
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.offlineGray,
          child: Icon(Icons.person, color: Colors.white, size: 20),
        ),
        SizedBox(width: ResponsiveSpacing.md(context)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ResponsiveTextWidget(
                _selectedDeviceName ?? 'Unknown Device',
                styleBuilder: (context) => ResponsiveText.heading3(
                  context,
                ).copyWith(color: Colors.white),
                maxLines: 1,
              ),
              ResponsiveTextWidget(
                widget.p2pService.connectedDevices.containsKey(
                      _selectedEndpointId,
                    )
                    ? 'Connected • Online'
                    : 'Offline • Last seen unknown',
                styleBuilder: (context) =>
                    ResponsiveText.bodySmall(context).copyWith(
                      color:
                          widget.p2pService.connectedDevices.containsKey(
                            _selectedEndpointId,
                          )
                          ? ResQLinkTheme.safeGreen
                          : ResQLinkTheme.offlineGray,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileMessagesTitle(bool isNarrowScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveTextWidget(
          'Messages',
          styleBuilder: (context) =>
              ResponsiveText.heading3(context).copyWith(color: Colors.white),
        ),
        ResponsiveTextWidget(
          widget.p2pService.isConnected
              ? '${widget.p2pService.connectedDevices.length} connected'
              : 'No connection',
          styleBuilder: (context) => ResponsiveText.caption(context).copyWith(
            color: widget.p2pService.isConnected
                ? ResQLinkTheme.safeGreen
                : ResQLinkTheme.warningYellow,
          ),
        ),
      ],
    );
  }

  Widget _buildTabletMessagesTitle(bool isNarrowScreen) {
    return Row(
      children: [
        Container(
          padding: ResponsiveSpacing.padding(
            context,
            all: ResponsiveSpacing.sm(context),
          ),
          decoration: BoxDecoration(
            color: ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.chat_bubble_outline,
            color: ResQLinkTheme.primaryRed,
            size: 24,
          ),
        ),
        SizedBox(width: ResponsiveSpacing.md(context)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ResponsiveTextWidget(
                'Emergency Messages',
                styleBuilder: (context) => ResponsiveText.heading2(
                  context,
                ).copyWith(color: Colors.white),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.p2pService.isConnected
                          ? ResQLinkTheme.safeGreen
                          : ResQLinkTheme.warningYellow,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: ResponsiveSpacing.xs(context)),
                  ResponsiveTextWidget(
                    widget.p2pService.isConnected
                        ? '${widget.p2pService.connectedDevices.length} devices connected'
                        : 'No connection',
                    styleBuilder: (context) =>
                        ResponsiveText.bodySmall(context).copyWith(
                          color: widget.p2pService.isConnected
                              ? ResQLinkTheme.safeGreen
                              : ResQLinkTheme.warningYellow,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildResponsiveAppBarActions(bool isNarrowScreen) {
    final actions = <Widget>[];

    // Connection status indicator - aligned with home page
    actions.add(
      Container(
        margin: ResponsiveSpacing.padding(
          context,
          right: ResponsiveSpacing.xs(context),
        ),
        padding: ResponsiveSpacing.padding(
          context,
          horizontal: ResponsiveSpacing.sm(context),
          vertical: ResponsiveSpacing.xs(context),
        ),
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
            SizedBox(width: ResponsiveSpacing.xs(context)),
            ResponsiveTextWidget(
              '${widget.p2pService.connectedDevices.length}',
              styleBuilder: (context) => ResponsiveText.caption(
                context,
              ).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    // Options menu
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
                SizedBox(width: ResponsiveSpacing.sm(context)),
                ResponsiveTextWidget(
                  'Scan for Devices',
                  styleBuilder: (context) => ResponsiveText.bodyMedium(
                    context,
                  ).copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'create_group',
            child: Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.white70, size: 20),
                SizedBox(width: ResponsiveSpacing.sm(context)),
                ResponsiveTextWidget(
                  'Create Group',
                  styleBuilder: (context) => ResponsiveText.bodyMedium(
                    context,
                  ).copyWith(color: Colors.white),
                ),
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
                  SizedBox(width: ResponsiveSpacing.sm(context)),
                  ResponsiveTextWidget(
                    'Clear Chat',
                    styleBuilder: (context) => ResponsiveText.bodyMedium(
                      context,
                    ).copyWith(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return actions;
  }

  Widget _buildResponsiveBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: ResQLinkTheme.primaryRed),
            SizedBox(height: ResponsiveSpacing.md(context)),
            ResponsiveTextWidget(
              'Loading messages...',
              styleBuilder: (context) => ResponsiveText.bodyMedium(
                context,
              ).copyWith(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return ResponsiveWidget(
      mobile: _buildMobileBody(),
      tablet: _buildTabletBody(),
    );
  }

  Widget _buildMobileBody() {
    return Column(
      children: [
        if (!widget.p2pService.isConnected) _buildMobileConnectionBanner(),
        Expanded(
          child: _isChatView
              ? _buildMobileChatView()
              : _buildMobileConversationList(),
        ),
        if (_isChatView) _buildMobileMessageInput(),
      ],
    );
  }

  Widget _buildTabletBody() {
    return Row(
      children: [
        // Conversation list sidebar
        Container(
          width: 350,
          decoration: BoxDecoration(
            color: ResQLinkTheme.surfaceDark,
            border: Border(
              right: BorderSide(color: ResQLinkTheme.cardDark, width: 1),
            ),
          ),
          child: Column(
            children: [
              if (!widget.p2pService.isConnected)
                _buildTabletConnectionBanner(),
              Expanded(child: _buildTabletConversationList()),
            ],
          ),
        ),

        // Chat area
        Expanded(
          child: _isChatView
              ? Column(
                  children: [
                    Expanded(child: _buildTabletChatView()),
                    _buildTabletMessageInput(),
                  ],
                )
              : _buildTabletEmptyState(),
        ),
      ],
    );
  }

  Widget _buildMobileConnectionBanner() {
    return Container(
      width: double.infinity,
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.sm(context),
      ),
      color: ResQLinkTheme.warningYellow.withValues(alpha: 0.9),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 20),
          SizedBox(width: ResponsiveSpacing.sm(context)),
          Expanded(
            child: ResponsiveTextWidget(
              'Not connected to any devices. Messages will be saved locally.',
              styleBuilder: (context) => ResponsiveText.bodySmall(
                context,
              ).copyWith(color: Colors.white),
              maxLines: 2,
            ),
          ),
          TextButton(
            onPressed: () => widget.p2pService.discoverDevices(force: true),
            child: ResponsiveTextWidget(
              'SCAN',
              styleBuilder: (context) => ResponsiveText.button(
                context,
              ).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletConnectionBanner() {
    return Container(
      width: double.infinity,
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.md(context),
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.warningYellow.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: ResQLinkTheme.warningYellow, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wifi_off,
                color: ResQLinkTheme.warningYellow,
                size: 24,
              ),
              SizedBox(width: ResponsiveSpacing.sm(context)),
              ResponsiveTextWidget(
                'No Connection',
                styleBuilder: (context) => ResponsiveText.heading3(
                  context,
                ).copyWith(color: ResQLinkTheme.warningYellow),
              ),
            ],
          ),
          SizedBox(height: ResponsiveSpacing.xs(context)),
          ResponsiveTextWidget(
            'Messages will be saved locally until connection is restored.',
            styleBuilder: (context) => ResponsiveText.bodySmall(
              context,
            ).copyWith(color: Colors.white70),
          ),
          SizedBox(height: ResponsiveSpacing.sm(context)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(Icons.search, size: 18),
              label: ResponsiveTextWidget(
                'Scan for Devices',
                styleBuilder: (context) => ResponsiveText.button(context),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ResQLinkTheme.primaryRed,
                padding: ResponsiveSpacing.padding(
                  context,
                  vertical: ResponsiveSpacing.sm(context),
                ),
              ),
              onPressed: () => widget.p2pService.discoverDevices(force: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildResponsiveFloatingActionButton() {
    if (_isChatView || widget.p2pService.isConnected) return null;

    return ResponsiveWidget(
      mobile: FloatingActionButton(
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
      ),
      tablet: FloatingActionButton.extended(
        backgroundColor: ResQLinkTheme.primaryRed,
        onPressed: widget.p2pService.isDiscovering
            ? null
            : () async {
                await widget.p2pService.discoverDevices(force: true);
                if (mounted) {
                  _showSuccessMessage('Scanning for nearby devices...');
                }
              },
        icon: Icon(
          widget.p2pService.isDiscovering
              ? Icons.hourglass_empty
              : Icons.wifi_tethering,
          color: Colors.white,
        ),
        label: ResponsiveTextWidget(
          widget.p2pService.isDiscovering ? 'Scanning...' : 'Scan Devices',
          styleBuilder: (context) =>
              ResponsiveText.button(context).copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildMobileConversationList() {
    if (_conversations.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildMobileConnectionControls(),
            SizedBox(height: ResponsiveSpacing.xl(context)),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: ResQLinkTheme.offlineGray,
                  ),
                  SizedBox(height: ResponsiveSpacing.md(context)),
                  ResponsiveTextWidget(
                    'No messages yet',
                    styleBuilder: (context) => ResponsiveText.heading3(
                      context,
                    ).copyWith(color: Colors.white),
                  ),
                  SizedBox(height: ResponsiveSpacing.sm(context)),
                  ResponsiveTextWidget(
                    widget.p2pService.connectedDevices.isEmpty
                        ? 'Connect to a device to start messaging'
                        : 'Select a device to start messaging',
                    styleBuilder: (context) => ResponsiveText.bodyMedium(
                      context,
                    ).copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Compact connection status
        SizedBox(
          height: 100,
          child: SingleChildScrollView(
            child: _buildMobileConnectionStatusSummary(),
          ),
        ),
        // Conversations list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadConversations,
            color: ResQLinkTheme.primaryRed,
            backgroundColor: ResQLinkTheme.surfaceDark,
            child: ListView.builder(
              padding: ResponsiveSpacing.padding(
                context,
                all: ResponsiveSpacing.md(context),
              ),
              itemCount: _conversations.length,
              itemBuilder: (context, index) =>
                  _buildMobileConversationCard(_conversations[index]),
            ),
          ),
        ),
      ],
    );
  }

  // ✅ Tablet Conversation List
  Widget _buildTabletConversationList() {
    return Column(
      children: [
        // Header
        Container(
          padding: ResponsiveSpacing.padding(
            context,
            all: ResponsiveSpacing.md(context),
          ),
          decoration: BoxDecoration(
            color: ResQLinkTheme.cardDark,
            border: Border(
              bottom: BorderSide(
                color: ResQLinkTheme.offlineGray.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: ResQLinkTheme.primaryRed,
                size: 20,
              ),
              SizedBox(width: ResponsiveSpacing.sm(context)),
              ResponsiveTextWidget(
                'Conversations',
                styleBuilder: (context) => ResponsiveText.heading3(
                  context,
                ).copyWith(color: Colors.white),
              ),
              Spacer(),
              Container(
                padding: ResponsiveSpacing.padding(
                  context,
                  horizontal: ResponsiveSpacing.sm(context),
                  vertical: ResponsiveSpacing.xs(context),
                ),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ResponsiveTextWidget(
                  '${_conversations.length}',
                  styleBuilder: (context) =>
                      ResponsiveText.caption(context).copyWith(
                        color: ResQLinkTheme.primaryRed,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
        ),

        // Conversations
        if (_conversations.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: ResQLinkTheme.offlineGray,
                  ),
                  SizedBox(height: ResponsiveSpacing.md(context)),
                  ResponsiveTextWidget(
                    'No conversations yet',
                    styleBuilder: (context) => ResponsiveText.bodyLarge(
                      context,
                    ).copyWith(color: Colors.white70),
                  ),
                  SizedBox(height: ResponsiveSpacing.sm(context)),
                  ResponsiveTextWidget(
                    'Connect to devices to start messaging',
                    styleBuilder: (context) => ResponsiveText.bodySmall(
                      context,
                    ).copyWith(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadConversations,
              color: ResQLinkTheme.primaryRed,
              backgroundColor: ResQLinkTheme.surfaceDark,
              child: ListView.builder(
                padding: ResponsiveSpacing.padding(
                  context,
                  all: ResponsiveSpacing.sm(context),
                ),
                itemCount: _conversations.length,
                itemBuilder: (context, index) =>
                    _buildTabletConversationCard(_conversations[index]),
              ),
            ),
          ),
      ],
    );
  }

  // ✅ Mobile Connection Status Summary
  Widget _buildMobileConnectionStatusSummary() {
    final isConnected = widget.p2pService.isConnected;
    final connectionInfo = widget.p2pService.getConnectionInfo();

    return Container(
      margin: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.sm(context),
      ),
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.sm(context),
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? ResQLinkTheme.safeGreen
              : ResQLinkTheme.warningYellow,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: ResponsiveSpacing.padding(
                  context,
                  all: ResponsiveSpacing.xs(context),
                ),
                decoration: BoxDecoration(
                  color:
                      (isConnected
                              ? ResQLinkTheme.safeGreen
                              : ResQLinkTheme.warningYellow)
                          .withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected
                      ? ResQLinkTheme.safeGreen
                      : ResQLinkTheme.warningYellow,
                  size: 16,
                ),
              ),
              SizedBox(width: ResponsiveSpacing.sm(context)),
              Expanded(
                child: ResponsiveTextWidget(
                  isConnected ? 'Connected' : 'Offline',
                  styleBuilder: (context) =>
                      ResponsiveText.bodyMedium(context).copyWith(
                        color: isConnected
                            ? ResQLinkTheme.safeGreen
                            : ResQLinkTheme.warningYellow,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (!isConnected)
                TextButton(
                  onPressed: () =>
                      widget.p2pService.discoverDevices(force: true),
                  style: TextButton.styleFrom(
                    padding: ResponsiveSpacing.padding(
                      context,
                      horizontal: ResponsiveSpacing.sm(context),
                      vertical: ResponsiveSpacing.xs(context),
                    ),
                  ),
                  child: ResponsiveTextWidget(
                    'SCAN',
                    styleBuilder: (context) =>
                        ResponsiveText.caption(context).copyWith(
                          color: ResQLinkTheme.primaryRed,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
            ],
          ),
          if (isConnected) ...[
            SizedBox(height: ResponsiveSpacing.xs(context)),
            Row(
              children: [
                _buildMobileQuickStatusItem(
                  '${connectionInfo['connectedDevices'] ?? 0}',
                  'Connected',
                  ResQLinkTheme.safeGreen,
                ),
                Spacer(),
                _buildMobileQuickStatusItem(
                  connectionInfo['role']?.toString().toUpperCase() ?? 'NONE',
                  'Role',
                  Colors.blue,
                ),
                Spacer(),
                _buildMobileQuickStatusItem(
                  '${widget.p2pService.discoveredDevices.length}',
                  'Available',
                  Colors.orange,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileQuickStatusItem(String value, String label, Color color) {
    return Column(
      children: [
        ResponsiveTextWidget(
          value,
          styleBuilder: (context) => ResponsiveText.bodySmall(
            context,
          ).copyWith(color: color, fontWeight: FontWeight.bold),
        ),
        ResponsiveTextWidget(
          label,
          styleBuilder: (context) =>
              ResponsiveText.caption(context).copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  // ✅ Mobile Connection Controls
  Widget _buildMobileConnectionControls() {
    final connectionInfo = widget.p2pService.getConnectionInfo();
    final isConnected = widget.p2pService.isConnected;
    final discoveredDevices = widget.p2pService.discoveredDevices;

    return Container(
      margin: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.md(context),
      ),
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.md(context),
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wifi_tethering,
                color: isConnected
                    ? ResQLinkTheme.safeGreen
                    : ResQLinkTheme.warningYellow,
                size: 20,
              ),
              SizedBox(width: ResponsiveSpacing.sm(context)),
              ResponsiveTextWidget(
                'Network Status',
                styleBuilder: (context) => ResponsiveText.heading3(
                  context,
                ).copyWith(color: Colors.white),
              ),
            ],
          ),
          SizedBox(height: ResponsiveSpacing.md(context)),

          // Status indicators
          _buildMobileStatusRow(
            'Status',
            isConnected ? 'Connected' : 'Disconnected',
            isConnected ? ResQLinkTheme.safeGreen : ResQLinkTheme.warningYellow,
          ),
          _buildMobileStatusRow(
            'Role',
            connectionInfo['role']?.toString().toUpperCase() ?? 'NONE',
            isConnected ? ResQLinkTheme.safeGreen : Colors.grey,
          ),
          _buildMobileStatusRow(
            'Connected Devices',
            '${connectionInfo['connectedDevices'] ?? 0}',
            Colors.blue,
          ),
          _buildMobileStatusRow(
            'Available Devices',
            '${discoveredDevices.length}',
            Colors.orange,
          ),

          SizedBox(height: ResponsiveSpacing.md(context)),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.search, size: 18),
                  label: ResponsiveTextWidget(
                    'Scan',
                    styleBuilder: (context) => ResponsiveText.button(context),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ResQLinkTheme.primaryRed,
                    padding: ResponsiveSpacing.padding(
                      context,
                      vertical: ResponsiveSpacing.sm(context),
                    ),
                  ),
                  onPressed: widget.p2pService.isDiscovering
                      ? null
                      : () async {
                          await widget.p2pService.discoverDevices(force: true);
                          if (mounted) {
                            _showSuccessMessage('Scanning for devices...');
                          }
                        },
                ),
              ),
              SizedBox(width: ResponsiveSpacing.sm(context)),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(
                    isConnected ? Icons.group_add : Icons.wifi_tethering,
                    size: 18,
                  ),
                  label: ResponsiveTextWidget(
                    isConnected ? 'Host' : 'Create',
                    styleBuilder: (context) => ResponsiveText.button(context),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ResQLinkTheme.safeGreen,
                    padding: ResponsiveSpacing.padding(
                      context,
                      vertical: ResponsiveSpacing.sm(context),
                    ),
                  ),
                  onPressed: () => _handleMenuAction('create_group'),
                ),
              ),
            ],
          ),

          // Available devices
          if (discoveredDevices.isNotEmpty) ...[
            SizedBox(height: ResponsiveSpacing.md(context)),
            ResponsiveTextWidget(
              'Available Devices',
              styleBuilder: (context) => ResponsiveText.bodyLarge(
                context,
              ).copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: ResponsiveSpacing.sm(context)),
            ...discoveredDevices.entries.map(
              (entry) => _buildMobileDeviceItem(entry.value),
            ),
          ],
        ],
      ),
    );
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

  Widget _buildMobileStatusRow(String label, String value, Color color) {
    return Padding(
      padding: ResponsiveSpacing.padding(
        context,
        vertical: ResponsiveSpacing.xs(context),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: ResponsiveSpacing.sm(context)),
          ResponsiveTextWidget(
            '$label: ',
            styleBuilder: (context) => ResponsiveText.bodySmall(
              context,
            ).copyWith(color: Colors.white70),
          ),
          ResponsiveTextWidget(
            value,
            styleBuilder: (context) => ResponsiveText.bodySmall(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDeviceItem(Map<String, dynamic> device) {
    return Container(
      margin: ResponsiveSpacing.padding(
        context,
        vertical: ResponsiveSpacing.xs(context),
      ),
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.sm(context),
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: device['isAvailable']
                ? ResQLinkTheme.safeGreen
                : Colors.grey,
            child: Icon(Icons.devices, size: 14, color: Colors.white),
          ),
          SizedBox(width: ResponsiveSpacing.sm(context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResponsiveTextWidget(
                  device['deviceName'] ?? 'Unknown Device',
                  styleBuilder: (context) => ResponsiveText.bodySmall(
                    context,
                  ).copyWith(color: Colors.white, fontWeight: FontWeight.w500),
                  maxLines: 1,
                ),
                ResponsiveTextWidget(
                  device['deviceAddress'] ?? '',
                  styleBuilder: (context) => ResponsiveText.caption(
                    context,
                  ).copyWith(color: Colors.white54),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          if (device['isAvailable'])
            ElevatedButton(
              onPressed: () async {
                try {
                  await widget.p2pService.connectToDevice(device);
                  if (mounted) {
                    _showSuccessMessage('Connected to ${device['deviceName']}');
                  }
                } catch (e) {
                  if (mounted) {
                    _showErrorMessage('Connection failed');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ResQLinkTheme.primaryRed,
                padding: ResponsiveSpacing.padding(
                  context,
                  horizontal: ResponsiveSpacing.sm(context),
                  vertical: ResponsiveSpacing.xs(context),
                ),
              ),
              child: ResponsiveTextWidget(
                'Connect',
                styleBuilder: (context) => ResponsiveText.caption(
                  context,
                ).copyWith(color: Colors.white),
              ),
            )
          else
            ResponsiveTextWidget(
              'Unavailable',
              styleBuilder: (context) =>
                  ResponsiveText.caption(context).copyWith(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  // ✅ Conversation Cards
  Widget _buildMobileConversationCard(MessageSummary conversation) {
    final message = conversation.lastMessage;
    final isEmergency = message?.isEmergency ?? false;

    return Container(
      margin: ResponsiveSpacing.padding(
        context,
        bottom: ResponsiveSpacing.sm(context),
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergency ? ResQLinkTheme.primaryRed : Colors.transparent,
          width: isEmergency ? 2 : 0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
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
            padding: ResponsiveSpacing.padding(
              context,
              all: ResponsiveSpacing.md(context),
            ),
            child: Row(
              children: [
                // Avatar with status
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isEmergency
                          ? ResQLinkTheme.primaryRed
                          : conversation.isConnected
                          ? ResQLinkTheme.safeGreen
                          : ResQLinkTheme.offlineGray,
                      child: Icon(
                        isEmergency ? Icons.warning : Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    if (conversation.isConnected)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: ResQLinkTheme.safeGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ResQLinkTheme.cardDark,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                SizedBox(width: ResponsiveSpacing.md(context)),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ResponsiveTextWidget(
                              conversation.deviceName,
                              styleBuilder: (context) =>
                                  ResponsiveText.bodyLarge(context).copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                              maxLines: 1,
                            ),
                          ),
                          if (message != null)
                            ResponsiveTextWidget(
                              _formatRelativeTime(message.dateTime),
                              styleBuilder: (context) => ResponsiveText.caption(
                                context,
                              ).copyWith(color: Colors.white54),
                            ),
                        ],
                      ),

                      SizedBox(height: ResponsiveSpacing.xs(context)),

                      if (message != null) ...[
                        Row(
                          children: [
                            if (message.isMe) ...[
                              Icon(
                                Icons.reply,
                                size: 14,
                                color: Colors.white54,
                              ),
                              SizedBox(width: ResponsiveSpacing.xs(context)),
                            ],
                            Expanded(
                              child: ResponsiveTextWidget(
                                isEmergency
                                    ? '🚨 ${message.message}'
                                    : message.message,
                                styleBuilder: (context) =>
                                    ResponsiveText.bodyMedium(
                                      context,
                                    ).copyWith(color: Colors.white70),
                                maxLines: 1,
                              ),
                            ),
                            SizedBox(width: ResponsiveSpacing.sm(context)),
                            _buildMessageStatusIcon(message.status),
                          ],
                        ),
                      ] else ...[
                        ResponsiveTextWidget(
                          'No messages yet',
                          styleBuilder: (context) =>
                              ResponsiveText.bodySmall(context).copyWith(
                                color: Colors.white54,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(width: ResponsiveSpacing.sm(context)),

                // Unread badge
                if (conversation.unreadCount > 0)
                  Container(
                    padding: ResponsiveSpacing.padding(
                      context,
                      horizontal: ResponsiveSpacing.sm(context),
                      vertical: ResponsiveSpacing.xs(context),
                    ),
                    decoration: BoxDecoration(
                      color: ResQLinkTheme.primaryRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ResponsiveTextWidget(
                      '${conversation.unreadCount}',
                      styleBuilder: (context) =>
                          ResponsiveText.caption(context).copyWith(
                            color: Colors.white,
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

  Widget _buildTabletConversationCard(MessageSummary conversation) {
    final message = conversation.lastMessage;
    final isEmergency = message?.isEmergency ?? false;
    final isSelected = _selectedEndpointId == conversation.endpointId;

    return Container(
      margin: ResponsiveSpacing.padding(
        context,
        bottom: ResponsiveSpacing.xs(context),
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? ResQLinkTheme.primaryRed.withValues(alpha: 0.1)
            : ResQLinkTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? ResQLinkTheme.primaryRed
              : isEmergency
              ? ResQLinkTheme.primaryRed.withValues(alpha: 0.5)
              : Colors.transparent,
          width: isSelected
              ? 2
              : isEmergency
              ? 1
              : 0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openConversation(
            conversation.endpointId,
            conversation.deviceName,
          ),
          child: Padding(
            padding: ResponsiveSpacing.padding(
              context,
              all: ResponsiveSpacing.sm(context),
            ),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isEmergency
                          ? ResQLinkTheme.primaryRed
                          : conversation.isConnected
                          ? ResQLinkTheme.safeGreen
                          : ResQLinkTheme.offlineGray,
                      child: Icon(
                        isEmergency ? Icons.warning : Icons.person,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    if (conversation.isConnected)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: ResQLinkTheme.safeGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ResQLinkTheme.cardDark,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                SizedBox(width: ResponsiveSpacing.sm(context)),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ResponsiveTextWidget(
                        conversation.deviceName,
                        styleBuilder: (context) =>
                            ResponsiveText.bodyMedium(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                        maxLines: 1,
                      ),
                      if (message != null) ...[
                        SizedBox(height: ResponsiveSpacing.xs(context)),
                        ResponsiveTextWidget(
                          isEmergency
                              ? '🚨 ${message.message}'
                              : message.message,
                          styleBuilder: (context) => ResponsiveText.bodySmall(
                            context,
                          ).copyWith(color: Colors.white70),
                          maxLines: 1,
                        ),
                        SizedBox(height: ResponsiveSpacing.xs(context)),
                        Row(
                          children: [
                            ResponsiveTextWidget(
                              _formatRelativeTime(message.dateTime),
                              styleBuilder: (context) => ResponsiveText.caption(
                                context,
                              ).copyWith(color: Colors.white54),
                            ),
                            Spacer(),
                            _buildMessageStatusIcon(message.status),
                          ],
                        ),
                      ] else ...[
                        ResponsiveTextWidget(
                          'No messages',
                          styleBuilder: (context) =>
                              ResponsiveText.caption(context).copyWith(
                                color: Colors.white54,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Unread badge
                if (conversation.unreadCount > 0) ...[
                  SizedBox(width: ResponsiveSpacing.xs(context)),
                  Container(
                    padding: ResponsiveSpacing.padding(
                      context,
                      all: ResponsiveSpacing.xs(context),
                    ),
                    decoration: BoxDecoration(
                      color: ResQLinkTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                    child: ResponsiveTextWidget(
                      '${conversation.unreadCount}',
                      styleBuilder: (context) =>
                          ResponsiveText.caption(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Chat Views
  Widget _buildMobileChatView() {
    return ListView.builder(
      controller: _scrollController,
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.md(context),
      ),
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
            _buildResponsiveMessageBubble(message, isMobile: true),
          ],
        );
      },
    );
  }

  Widget _buildTabletChatView() {
    if (_selectedConversationMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: ResQLinkTheme.offlineGray,
            ),
            SizedBox(height: ResponsiveSpacing.md(context)),
            ResponsiveTextWidget(
              'No messages in this conversation',
              styleBuilder: (context) => ResponsiveText.heading3(
                context,
              ).copyWith(color: Colors.white70),
            ),
            SizedBox(height: ResponsiveSpacing.sm(context)),
            ResponsiveTextWidget(
              'Start typing to send the first message',
              styleBuilder: (context) => ResponsiveText.bodyMedium(
                context,
              ).copyWith(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.lg(context),
      ),
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
            _buildResponsiveMessageBubble(message, isMobile: false),
          ],
        );
      },
    );
  }

  Widget _buildTabletEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 96,
            color: ResQLinkTheme.offlineGray,
          ),
          SizedBox(height: ResponsiveSpacing.lg(context)),
          ResponsiveTextWidget(
            'Select a conversation',
            styleBuilder: (context) =>
                ResponsiveText.heading2(context).copyWith(color: Colors.white),
          ),
          SizedBox(height: ResponsiveSpacing.sm(context)),
          ResponsiveTextWidget(
            'Choose a conversation from the sidebar to start messaging',
            styleBuilder: (context) => ResponsiveText.bodyLarge(
              context,
            ).copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveSpacing.xl(context)),
          if (_conversations.isEmpty)
            Column(
              children: [
                ResponsiveTextWidget(
                  'No conversations available',
                  styleBuilder: (context) => ResponsiveText.bodyLarge(
                    context,
                  ).copyWith(color: Colors.white54),
                ),
                SizedBox(height: ResponsiveSpacing.md(context)),
                ElevatedButton.icon(
                  icon: Icon(Icons.search),
                  label: ResponsiveTextWidget(
                    'Scan for Devices',
                    styleBuilder: (context) => ResponsiveText.button(context),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ResQLinkTheme.primaryRed,
                    padding: ResponsiveSpacing.padding(
                      context,
                      horizontal: ResponsiveSpacing.lg(context),
                      vertical: ResponsiveSpacing.md(context),
                    ),
                  ),
                  onPressed: () async {
                    await widget.p2pService.discoverDevices(force: true);
                    if (mounted) {
                      _showSuccessMessage('Scanning for nearby devices...');
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ✅ Message Input Areas
  Widget _buildMobileMessageInput() {
    return Container(
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.md(context),
      ),
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
            // Quick actions row
            Row(
              children: [
                _buildQuickActionButton(
                  icon: Icons.location_on,
                  color: ResQLinkTheme.locationBlue,
                  onPressed: _sendLocationMessage,
                  tooltip: 'Share Location',
                ),
                SizedBox(width: ResponsiveSpacing.sm(context)),
                _buildQuickActionButton(
                  icon: Icons.sos,
                  color: ResQLinkTheme.primaryRed,
                  onPressed: _sendEmergencyMessage,
                  tooltip: 'Emergency SOS',
                ),
                Spacer(),
                if (_isTyping)
                  ResponsiveTextWidget(
                    'Typing...',
                    styleBuilder: (context) => ResponsiveText.caption(
                      context,
                    ).copyWith(color: Colors.white54),
                  ),
              ],
            ),
            SizedBox(height: ResponsiveSpacing.sm(context)),
            // Input row
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: ResQLinkTheme.cardDark,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: widget.p2pService.isConnected
                            ? 'Type a message...'
                            : 'Type a message (offline)',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: ResponsiveSpacing.padding(
                          context,
                          horizontal: ResponsiveSpacing.lg(context),
                          vertical: ResponsiveSpacing.sm(context),
                        ),
                      ),
                      style: ResponsiveText.bodyMedium(
                        context,
                      ).copyWith(color: Colors.white),
                      onChanged: _handleTyping,
                      onSubmitted: (_) => _sendMessage(),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      minLines: 1,
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveSpacing.sm(context)),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [ResQLinkTheme.primaryRed, ResQLinkTheme.darkRed],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: _sendMessage,
                    splashRadius: 24,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletMessageInput() {
    return Container(
      padding: ResponsiveSpacing.padding(
        context,
        all: ResponsiveSpacing.lg(context),
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark,
        border: Border(
          top: BorderSide(color: ResQLinkTheme.cardDark, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Quick actions
          Row(
            children: [
              _buildQuickActionButton(
                icon: Icons.location_on,
                color: ResQLinkTheme.locationBlue,
                onPressed: _sendLocationMessage,
                tooltip: 'Share Location',
              ),
              SizedBox(width: ResponsiveSpacing.md(context)),
              _buildQuickActionButton(
                icon: Icons.sos,
                color: ResQLinkTheme.primaryRed,
                onPressed: _sendEmergencyMessage,
                tooltip: 'Emergency SOS',
              ),
              Spacer(),
              if (_isTyping)
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ResQLinkTheme.primaryRed,
                      ),
                    ),
                    SizedBox(width: ResponsiveSpacing.sm(context)),
                    ResponsiveTextWidget(
                      'Typing...',
                      styleBuilder: (context) => ResponsiveText.bodySmall(
                        context,
                      ).copyWith(color: Colors.white54),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: ResponsiveSpacing.md(context)),
          // Input area
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: ResQLinkTheme.cardDark,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: widget.p2pService.isConnected
                          ? 'Type a message...'
                          : 'Type a message (will be sent when connected)',
                      hintStyle: ResponsiveText.bodyMedium(
                        context,
                      ).copyWith(color: Colors.white54),
                      border: InputBorder.none,
                      contentPadding: ResponsiveSpacing.padding(
                        context,
                        horizontal: ResponsiveSpacing.lg(context),
                        vertical: ResponsiveSpacing.md(context),
                      ),
                    ),
                    style: ResponsiveText.bodyLarge(
                      context,
                    ).copyWith(color: Colors.white),
                    onChanged: _handleTyping,
                    onSubmitted: (_) => _sendMessage(),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 5,
                    minLines: 1,
                  ),
                ),
              ),
              SizedBox(width: ResponsiveSpacing.md(context)),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [ResQLinkTheme.primaryRed, ResQLinkTheme.darkRed],
                  ),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.send_rounded, color: Colors.white, size: 24),
                  onPressed: _sendMessage,
                  splashRadius: 28,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ Helper Widgets
  Widget _buildQuickActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: IconButton(
          icon: Icon(icon, color: color, size: 20),
          onPressed: onPressed,
          splashRadius: 20,
        ),
      ),
    );
  }

  Widget _buildResponsiveMessageBubble(
    MessageModel message, {
    required bool isMobile,
  }) {
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
          maxWidth:
              MediaQuery.of(context).size.width * (isMobile ? 0.75 : 0.65),
        ),
        margin: ResponsiveSpacing.padding(
          context,
          vertical: ResponsiveSpacing.xs(context),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: ResponsiveSpacing.padding(
                  context,
                  left: ResponsiveSpacing.sm(context),
                  bottom: ResponsiveSpacing.xs(context),
                ),
                child: ResponsiveTextWidget(
                  message.fromUser,
                  styleBuilder: (context) =>
                      ResponsiveText.caption(context).copyWith(
                        color: Colors.white60,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),

            Container(
              padding: ResponsiveSpacing.padding(
                context,
                all: ResponsiveSpacing.md(context),
              ),
              decoration: BoxDecoration(
                gradient: _getMessageGradient(isMe, isEmergency, message.type),
                borderRadius: BorderRadius.circular(isMobile ? 16 : 20)
                    .copyWith(
                      topLeft: isMe ? null : Radius.circular(isMobile ? 4 : 6),
                      topRight: isMe ? Radius.circular(isMobile ? 4 : 6) : null,
                    ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEmergency) _buildEmergencyHeader(message.type),

                  ResponsiveTextWidget(
                    message.message,
                    styleBuilder: (context) =>
                        (isMobile
                                ? ResponsiveText.bodyMedium(context)
                                : ResponsiveText.bodyLarge(context))
                            .copyWith(color: Colors.white, height: 1.4),
                  ),

                  if (hasLocation) ...[
                    SizedBox(height: ResponsiveSpacing.sm(context)),
                    _buildLocationPreview(message),
                  ],

                  SizedBox(height: ResponsiveSpacing.xs(context)),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ResponsiveTextWidget(
                        _formatTime(message.dateTime),
                        styleBuilder: (context) => ResponsiveText.caption(
                          context,
                        ).copyWith(color: Colors.white70),
                      ),
                      if (isMe) ...[
                        SizedBox(width: ResponsiveSpacing.xs(context)),
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
      padding: ResponsiveSpacing.padding(
        context,
        bottom: ResponsiveSpacing.sm(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type == 'sos' ? Icons.sos : Icons.warning,
            color: Colors.white,
            size: 16,
          ),
          SizedBox(width: ResponsiveSpacing.xs(context)),
          ResponsiveTextWidget(
            type.toUpperCase(),
            styleBuilder: (context) => ResponsiveText.caption(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPreview(MessageModel message) {
    return InkWell(
      onTap: () => _showLocationDetails(message),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(message.latitude!, message.longitude!),
            initialZoom: 15.0,
            interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.resqlink.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(message.latitude!, message.longitude!),
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
    );
  }

  LinearGradient _getMessageGradient(bool isMe, bool isEmergency, String type) {
    if (isEmergency) {
      return LinearGradient(
        colors: [ResQLinkTheme.primaryRed, ResQLinkTheme.darkRed],
      );
    }

    if (type == 'location') {
      return LinearGradient(
        colors: [ResQLinkTheme.locationBlue, Colors.blue.shade700],
      );
    }

    if (isMe) {
      return LinearGradient(
        colors: [ResQLinkTheme.safeGreen, Colors.green.shade700],
      );
    }

    return LinearGradient(
      colors: [ResQLinkTheme.cardDark, Colors.grey.shade800],
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
      padding: ResponsiveSpacing.padding(
        context,
        vertical: ResponsiveSpacing.md(context),
      ),
      child: Center(
        child: Container(
          padding: ResponsiveSpacing.padding(
            context,
            horizontal: ResponsiveSpacing.sm(context),
            vertical: ResponsiveSpacing.xs(context),
          ),
          decoration: BoxDecoration(
            color: ResQLinkTheme.cardDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ResponsiveTextWidget(
            dateText,
            styleBuilder: (context) => ResponsiveText.caption(
              context,
            ).copyWith(color: Colors.white70, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showLocationDetails(MessageModel message) {
    if (message.latitude == null || message.longitude == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: ResQLinkTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          padding: ResponsiveSpacing.padding(
            context,
            all: ResponsiveSpacing.md(context),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, color: ResQLinkTheme.locationBlue),
                  SizedBox(width: ResponsiveSpacing.sm(context)),
                  ResponsiveTextWidget(
                    'Location Details',
                    styleBuilder: (context) => ResponsiveText.heading3(
                      context,
                    ).copyWith(color: Colors.white),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: ResponsiveSpacing.md(context)),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                      message.latitude!,
                      message.longitude!,
                    ),
                    initialZoom: 15.0,
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
              SizedBox(height: ResponsiveSpacing.md(context)),
              Container(
                padding: ResponsiveSpacing.padding(
                  context,
                  all: ResponsiveSpacing.sm(context),
                ),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ResponsiveTextWidget(
                      'Coordinates',
                      styleBuilder: (context) =>
                          ResponsiveText.bodyLarge(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    SizedBox(height: ResponsiveSpacing.xs(context)),
                    ResponsiveTextWidget(
                      'Lat: ${message.latitude!.toStringAsFixed(6)}',
                      styleBuilder: (context) => ResponsiveText.bodyMedium(
                        context,
                      ).copyWith(color: Colors.white70),
                    ),
                    ResponsiveTextWidget(
                      'Lng: ${message.longitude!.toStringAsFixed(6)}',
                      styleBuilder: (context) => ResponsiveText.bodyMedium(
                        context,
                      ).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
