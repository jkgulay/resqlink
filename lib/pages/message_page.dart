import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/pages/gps_page.dart';
import 'package:resqlink/services/message_sync_service.dart';
import 'package:resqlink/services/settings_service.dart';
import '../services/p2p/p2p_main_service.dart';
import '../../services/database_service.dart';
import '../../models/message_model.dart';
import '../../utils/resqlink_theme.dart';
import '../widgets/message/chat_app_bar.dart';
import '../widgets/message/conversation_list.dart';
import '../widgets/message/chat_view.dart';
import '../widgets/message/message_input.dart';
import '../widgets/message/loading_view.dart';
import '../widgets/message/empty_chat_view.dart';
import '../widgets/message/emergency_dialog.dart';
import '../widgets/message/connection_banner.dart';
import '../widgets/message/notification_service.dart';
import 'dart:async';

class MessagePage extends StatefulWidget {
  final P2PMainService p2pService;
  final LocationModel? currentLocation;

  const MessagePage({
    super.key,
    required this.p2pService,
    this.currentLocation,
  });

  @override
  State<MessagePage> createState() => _MessagePageState();

  static void selectDeviceFor(GlobalKey key, String deviceId, String deviceName) {
    final state = key.currentState;
    if (state != null && state is _MessagePageState) {
      state.selectDevice(deviceId, deviceName);
    }
  }
}

class _MessagePageState extends State<MessagePage> with WidgetsBindingObserver {
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Services
  final MessageSyncService _syncService = MessageSyncService();
  final List<Map<String, dynamic>> _offlineMessageQueue = [];
  Timer? _queueProcessingTimer;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _initializeOfflineQueue();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _typingTimer?.cancel();
    _queueProcessingTimer?.cancel();
    
    try {
      _syncService.dispose();
      widget.p2pService.removeListener(_onP2PUpdate);
      widget.p2pService.removeListener(_onP2PConnectionChanged);
    } catch (e) {
      debugPrint('Error disposing services: $e');
    }

    widget.p2pService.onMessageReceived = null;
    widget.p2pService.onDevicesDiscovered = null;
    super.dispose();
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

      widget.p2pService.addListener(_onP2PUpdate);
      widget.p2pService.onMessageReceived = _onMessageReceived;

      await _loadConversations();

      if (!mounted) return;

      _startAdaptiveRefresh();
    } catch (e) {
      debugPrint('❌ Error initializing MessagePage: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

  void _initializeOfflineQueue() {
    _queueProcessingTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (widget.p2pService.isConnected && _offlineMessageQueue.isNotEmpty) {
        _processOfflineQueue();
      }
    });
  }

  Future<void> _processOfflineQueue() async {
    if (!mounted || _offlineMessageQueue.isEmpty) return;

    debugPrint('📤 Processing ${_offlineMessageQueue.length} offline messages...');

    final messagesToProcess = List.from(_offlineMessageQueue);
    _offlineMessageQueue.clear();

    for (final queuedMessage in messagesToProcess) {
      try {
        await widget.p2pService.sendMessage(
          message: queuedMessage['text'],
          type: MessageType.values.firstWhere(
            (e) => e.name == queuedMessage['type'],
            orElse: () => MessageType.text,
          ),
          targetDeviceId: queuedMessage['targetId'],
          senderName: '',
        );

        debugPrint('✅ Offline message sent: ${queuedMessage['text']}');
      } catch (e) {
        debugPrint('❌ Failed to send offline message: $e');
        _offlineMessageQueue.add(queuedMessage);
      }
    }

    if (mounted && _offlineMessageQueue.isEmpty) {
      _showSuccessMessage('All offline messages sent!');
    }
  }

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) {
    if (!mounted) return;

    for (var device in devices) {
      final deviceId = device['deviceAddress'];
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final isConnected = widget.p2pService.connectedDevices.containsKey(deviceId);

      if (isConnected) {
        _createConversationForDevice(deviceId, deviceName);
      }
    }
  }

  void _createConversationForDevice(String deviceId, String deviceName) {
    if (!mounted) return;

    final existingConversation = _conversations.any((conv) => conv.endpointId == deviceId);

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
      final messages = await DatabaseService.getAllMessages().timeout(Duration(seconds: 10));
      if (!mounted) return;

      final connectedDevices = widget.p2pService.connectedDevices;
      final discoveredDevices = widget.p2pService.discoveredResQLinkDevices;

      final Map<String, MessageSummary> conversationMap = {};

      for (final message in messages) {
        if (!mounted) return;

        final endpointId = message.endpointId;
        String deviceName = message.fromUser;

        if (connectedDevices.containsKey(endpointId)) {
          deviceName = connectedDevices[endpointId]!.userName;
        } else {
          final discoveredDevice = discoveredDevices
              .where((d) => d.deviceId == endpointId)
              .firstOrNull;
          if (discoveredDevice != null) {
            deviceName = discoveredDevice.userName;
          }
        }

        if (!conversationMap.containsKey(endpointId)) {
          final endpointMessages = messages.where((m) => m.endpointId == endpointId).toList();
          final unreadCount = endpointMessages.where((m) => !m.synced && !m.isMe).length;

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
          if (message.dateTime.isAfter(currentSummary.lastMessage?.dateTime ?? DateTime(0))) {
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
            ..sort((a, b) => (b.lastMessage?.dateTime ?? DateTime(0))
                .compareTo(a.lastMessage?.dateTime ?? DateTime(0)));
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

  void _onMessageReceived(MessageModel message) async {
    if (!mounted) return;

    try {
      final messageId = message.messageId ?? 'unknown';
      final senderId = message.endpointId;

      final existingMessage = await DatabaseService.getMessageById(messageId);
      if (existingMessage != null) {
        debugPrint('⚠️ Duplicate message received: $messageId');
        return;
      }

      await DatabaseService.insertMessage(message);

      if (!mounted) return;

      await _batchUIUpdates(() async {
        await _loadConversations();

        if (message.messageType == MessageType.emergency ||
            message.messageType == MessageType.sos) {
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

  Future<void> _showEmergencyNotification(MessageModel message) async {
    if (!mounted) return;

    try {
      final settings = context.read<SettingsService>();

      if (!settings.emergencyNotifications) return;

      final playSound = settings.soundNotifications && !settings.silentMode;
      final vibrate = settings.vibrationNotifications && !settings.silentMode;

      await NotificationService.showEmergencyNotification(
        title: '${message.messageType.name.toUpperCase()} from ${message.fromUser}',
        body: message.message,
        playSound: playSound,
        vibrate: vibrate,
      );

      if (!mounted) return;

      String body = message.message;
      if (message.latitude != null && message.longitude != null) {
        body += '\nLocation: ${message.latitude!.toStringAsFixed(6)}, ${message.longitude!.toStringAsFixed(6)}';
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
                        '${message.messageType.name.toUpperCase()} from ${message.fromUser}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
              onPressed: () => _openConversation(message.endpointId, message.fromUser),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error showing emergency notification: $e');
    }
  }

  void _showInAppNotification(MessageModel message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: message.messageType == MessageType.emergency ||
                      message.messageType == MessageType.sos
                  ? ResQLinkTheme.primaryRed
                  : ResQLinkTheme.safeGreen,
              child: Icon(
                message.messageType == MessageType.emergency ||
                        message.messageType == MessageType.sos
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
                    'New message from ${message.fromUser}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
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
          onPressed: () => _openConversation(message.endpointId, message.fromUser),
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
        messageType: type,
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

    if (widget.currentLocation?.latitude == null || widget.currentLocation?.longitude == null) {
      if (mounted) {
        _showErrorMessage('Location not available. Please enable GPS.');
      }
      return;
    }

    try {
      final locationText =
          '📍 Location shared\nLat: ${widget.currentLocation!.latitude.toStringAsFixed(6)}\nLng: ${widget.currentLocation!.longitude.toStringAsFixed(6)}';

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
      final locationModel = LocationModel(
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
        timestamp: DateTime.now(),
        userId: widget.p2pService.deviceId,
        type: LocationType.normal,
        message: 'Shared via P2P',
      );

      await LocationService.insertLocation(locationModel);

      final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${widget.p2pService.deviceId?.hashCode ?? 0}';

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

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmergencyDialog(),
    );

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

  void selectDevice(String deviceId, String deviceName) {
    _openConversation(deviceId, deviceName);
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
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => ClearChatDialog(),
          );

          if (confirm == true && _selectedEndpointId != null) {
            await _loadMessagesForDevice(_selectedEndpointId!);
            _showSuccessMessage('Chat history cleared');
          }
        }
    }
  }

  Future<void> _reconnectToDevice(String deviceId) async {
    try {
      _showSuccessMessage('Attempting to reconnect...');

      await widget.p2pService.discoverDevices(force: true);
      await Future.delayed(Duration(seconds: 2));

      final devices = widget.p2pService.discoveredDevices;
      Map<String, dynamic>? targetDevice;

      if (devices.containsKey(deviceId)) {
        targetDevice = devices[deviceId];
      } else {
        for (final deviceData in devices.values) {
          if (deviceData['deviceId'] == deviceId || deviceData['endpointId'] == deviceId) {
            targetDevice = deviceData;
            break;
          }
        }
      }

      if (targetDevice != null && targetDevice.isNotEmpty) {
        final success = await widget.p2pService.connectToDevice(targetDevice);
        if (success) {
          _showSuccessMessage('Reconnected successfully!');
        } else {
          _showErrorMessage('Failed to reconnect. Try creating a new connection.');
        }
      } else {
        _showErrorMessage('Device not found. Try scanning again or create a new connection.');
      }
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
      _showErrorMessage('Reconnection failed. Try manual connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ResQLinkTheme.darkTheme,
      child: Scaffold(
        backgroundColor: ResQLinkTheme.backgroundDark,
        appBar: ChatAppBar(
          isChatView: _isChatView,
          selectedDeviceName: _selectedDeviceName,
          selectedEndpointId: _selectedEndpointId,
          p2pService: widget.p2pService,
          onBackPressed: () => setState(() {
            _isChatView = false;
            _selectedEndpointId = null;
            _selectedDeviceName = null;
            _selectedConversationMessages.clear();
          }),
          onMenuAction: _handleMenuAction,
          onReconnect: () => _selectedEndpointId != null 
              ? _reconnectToDevice(_selectedEndpointId!) 
              : null,
        ),
        body: _buildBody(),
        floatingActionButton: _buildFloatingActionButton(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return LoadingView();
    }

    return Column(
      children: [
        if (!widget.p2pService.isConnected) 
          ConnectionBanner(
            onScanPressed: () => widget.p2pService.discoverDevices(force: true),
          ),
        Expanded(
          child: _isChatView 
              ? ChatView(
                  messages: _selectedConversationMessages,
                  scrollController: _scrollController,
                )
              : _conversations.isEmpty
                  ? EmptyChatView(p2pService: widget.p2pService)
                  : ConversationList(
                      conversations: _conversations,
                      p2pService: widget.p2pService,
                      onConversationTap: _openConversation,
                      onRefresh: _loadConversations,
                    ),
        ),
        if (_isChatView) 
          MessageInput(
            controller: _messageController,
            onSendMessage: _sendMessage,
            onSendLocation: _sendLocationMessage,
            onSendLocationP2P: _sendLocationViaP2P,
            onSendEmergency: _sendEmergencyMessage,
            onTyping: _handleTyping,
            enabled: true,
          ),
      ],
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
        widget.p2pService.isDiscovering ? Icons.hourglass_empty : Icons.wifi_tethering,
        color: Colors.white,
      ),
    );
  }
}