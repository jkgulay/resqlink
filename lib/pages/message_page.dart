import 'package:flutter/material.dart';
import 'package:resqlink/pages/gps_page.dart';
import 'package:resqlink/services/messaging/message_sync_service.dart';
import '../services/p2p/p2p_main_service.dart';
import '../features/database/repositories/message_repository.dart';
import '../features/database/repositories/chat_repository.dart';
import '../../models/message_model.dart';
import '../../utils/resqlink_theme.dart';
import '../utils/responsive_utils.dart';
import '../widgets/message/chat_app_bar.dart';
import '../widgets/message/conversation_list.dart';
import '../widgets/message/chat_view.dart';
import '../widgets/message/message_input.dart';
import '../widgets/message/loading_view.dart';
import '../widgets/message/empty_chat_view.dart';
import '../widgets/message/emergency_dialog.dart';
import '../widgets/message/connection_banner.dart';
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
  // Removed local offline queue - using centralized MessageQueueService instead
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
  Timer? _loadConversationsDebounce;
  bool _isLoadingConversations = false;

  // Current user info - use consistent 'local' to match session generation across the app
  String get _currentUserId => 'local';
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
    _initializeQueueProcessing();
    _setupMessageRouterListener();
  }

  bool _conversationsEqual(List<MessageSummary> a, List<MessageSummary> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].endpointId != b[i].endpointId ||
          a[i].messageCount != b[i].messageCount ||
          a[i].unreadCount != b[i].unreadCount ||
          a[i].lastMessage?.timestamp != b[i].lastMessage?.timestamp) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _typingTimer?.cancel();
    _queueProcessingTimer?.cancel();
    _loadConversationsDebounce?.cancel();

    // Unregister MessageRouter listener
    if (_selectedEndpointId != null) {
      widget.p2pService.messageRouter.unregisterDeviceListener(_selectedEndpointId!);
    }

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

      // Note: onDeviceConnected is handled globally by home_page.dart
      // Don't override here to prevent duplicate session creation

      widget.p2pService.onDeviceDisconnected = (deviceId) {
        if (!mounted) return;
        _loadConversations();
        _showErrorMessage('Device disconnected');
      };

      widget.p2pService.addListener(_onP2PUpdate);
      // Note: Use event bus or message router for message handling instead of direct callback
      // widget.p2pService.onMessageReceived = _onMessageReceived;

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

  void _setupMessageRouterListener() {
    // Set up global listener for message updates
    widget.p2pService.messageRouter.setGlobalListener(_onRouterMessage);
    debugPrint('📱 MessagePage registered MessageRouter global listener');
  }

  void _onRouterMessage(dynamic message) {
    // Refresh conversations when any message is received
    if (mounted) {
      _loadConversations();

      // If we're in a specific conversation, add the message directly instead of full reload
      if (_isChatView && _selectedEndpointId != null && message is MessageModel) {
        // Check if this message is for the currently selected conversation
        if (message.endpointId == _selectedEndpointId) {
          // Check for duplicates before adding
          final alreadyExists = _selectedConversationMessages.any((m) =>
            m.messageId == message.messageId ||
            (m.timestamp == message.timestamp && m.fromUser == message.fromUser && m.message == message.message)
          );

          if (!alreadyExists) {
            setState(() {
              _selectedConversationMessages.add(message);
              // Sort by timestamp to maintain order
              _selectedConversationMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            });
            _scrollToBottom();
          }
        }
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

  void _initializeQueueProcessing() {
    _queueProcessingTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      if (widget.p2pService.isConnected) {
        // Process all queued messages using centralized service
        await widget.p2pService.messageQueueService.processAllQueues();
      }
    });
  }

  // Removed _processOfflineQueue - using centralized MessageQueueService

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) async {
    if (!mounted) return;

    for (var device in devices) {
      final deviceId = device['deviceAddress'];
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final isConnected = widget.p2pService.connectedDevices.containsKey(deviceId);

      if (isConnected) {
        await _createPersistentConversationForDevice(deviceId, deviceName);
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

  /// Create persistent conversation that survives page navigation and disconnection
  Future<void> _createPersistentConversationForDevice(String deviceId, String deviceName) async {
    if (!mounted) return;

    try {
      // First create the UI conversation placeholder
      _createConversationForDevice(deviceId, deviceName);

      // Then create persistent chat session in database
      await ChatRepository.createOrUpdate(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: _currentUserId,
      );

      debugPrint('✅ Created persistent conversation for $deviceName ($deviceId)');

      // Reload conversations to reflect the database changes
      await _loadConversations();

    } catch (e) {
      debugPrint('❌ Error creating persistent conversation: $e');
    }
  }

  Future<void> _loadConversations() async {
    if (!mounted || _isLoadingConversations) return;

    // Increased debounce to reduce database calls
    _loadConversationsDebounce?.cancel();
    _loadConversationsDebounce = Timer(const Duration(milliseconds: 1000), () async {
      await _loadConversationsInternal();
    });
  }

  Future<void> _loadConversationsInternal() async {
    if (!mounted || _isLoadingConversations) return;

    _isLoadingConversations = true;

    try {
      // Use smaller limits and shorter timeouts to prevent database locks
      final messages = await MessageRepository.getAllMessages(limit: 500).timeout(Duration(seconds: 2));
      final chatSessions = await ChatRepository.getAllSessions().timeout(Duration(seconds: 2));
      if (!mounted) return;

      final connectedDevices = widget.p2pService.connectedDevices;
      final discoveredDevices = widget.p2pService.discoveredResQLinkDevices;

      final Map<String, MessageSummary> conversationMap = {};

      // First, create conversations from stored chat sessions (ensures persistence)
      for (final session in chatSessions) {
        if (!mounted) return;

        final endpointId = session.deviceId;
        final deviceName = session.deviceName;

        conversationMap[endpointId] = MessageSummary(
          endpointId: endpointId,
          deviceName: deviceName,
          lastMessage: null,
          messageCount: 0,
          unreadCount: 0,
          isConnected: connectedDevices.containsKey(endpointId),
        );

        debugPrint('🗄️ Loaded persistent session: $deviceName ($endpointId)');
      }

      // Then, populate with actual message data
      for (final message in messages) {
        if (!mounted) return;

        final endpointId = message.endpointId;
        String deviceName = message.fromUser;

        // Use connected device name if available, otherwise use session name
        if (connectedDevices.containsKey(endpointId)) {
          deviceName = connectedDevices[endpointId]!.userName;
        } else if (conversationMap.containsKey(endpointId)) {
          deviceName = conversationMap[endpointId]!.deviceName;
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
          final endpointMessages = messages.where((m) => m.endpointId == endpointId).toList();
          final unreadCount = endpointMessages.where((m) => !m.synced && !m.isMe).length;

          if (message.dateTime.isAfter(currentSummary.lastMessage?.dateTime ?? DateTime(0))) {
            conversationMap[endpointId] = MessageSummary(
              endpointId: endpointId,
              deviceName: deviceName,
              lastMessage: message,
              messageCount: endpointMessages.length,
              unreadCount: unreadCount,
              isConnected: connectedDevices.containsKey(endpointId),
            );
          }
        }
      }

      if (mounted) {
        final newConversations = conversationMap.values.toList()
          ..sort((a, b) => (b.lastMessage?.dateTime ?? DateTime(0))
              .compareTo(a.lastMessage?.dateTime ?? DateTime(0)));

        // Only update state if data actually changed to prevent unnecessary rebuilds
        if (_conversations.length != newConversations.length ||
            !_conversationsEqual(_conversations, newConversations)) {
          setState(() {
            _conversations = newConversations;
            _isLoading = false;
          });
          debugPrint('✅ Updated ${_conversations.length} conversations (${connectedDevices.length} connected)');
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading conversations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Keep existing conversations on error
        });
      }
    } finally {
      _isLoadingConversations = false;
    }
  }

  Future<void> _loadMessagesForDevice(String endpointId) async {
    if (!mounted) return;

    try {
      final messages = await MessageRepository.getByEndpoint(endpointId);
      if (!mounted) return;

      setState(() {
        _selectedConversationMessages = messages;
      });

      _scrollToBottom();

      for (final message in messages.where((m) => !m.isMe && !m.synced)) {
        if (!mounted) return;

        if (message.id != null) {
          await MessageRepository.updateStatus(
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
      if (widget.p2pService.isConnected) {
        _loadConversations();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error in _onP2PUpdate: $e');
    }
  }



  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${_currentUserId.hashCode}';
  }

  Future<void> _sendMessage(String messageText, MessageType type) async {
    if (_selectedEndpointId == null) {
      _showErrorMessage('No conversation selected');
      return;
    }

    if (messageText.trim().isEmpty) {
      _showErrorMessage('Cannot send empty message');
      return;
    }

    try {
      final messageId = _generateMessageId();
      final timestamp = DateTime.now();
      final senderName = widget.p2pService.userName ?? 'Unknown User';

      // Check connection status
      final isConnected = widget.p2pService.connectedDevices.containsKey(_selectedEndpointId);
      final connectionInfo = isConnected ? 'connected' : 'disconnected (will queue)';

      debugPrint('📤 Sending message to $_selectedEndpointId ($connectionInfo): "$messageText"');

      // Create local database entry for sent message FIRST (for immediate UI update)
      final dbMessage = MessageModel(
        endpointId: _selectedEndpointId!,
        fromUser: senderName,
        message: messageText,
        isMe: true,
        isEmergency: type == MessageType.emergency || type == MessageType.sos,
        messageType: type,
        timestamp: timestamp.millisecondsSinceEpoch,
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
        messageId: messageId,
        type: type.name,
        status: isConnected ? MessageStatus.sent : MessageStatus.pending,
        deviceId: widget.p2pService.deviceId,
      );

      // Insert into local database FIRST for immediate UI update
      await MessageRepository.insert(dbMessage);

      // Update UI immediately to show the sent message (optimistic update)
      setState(() {
        _selectedConversationMessages.add(dbMessage);
      });
      _scrollToBottom();

      // Then send via P2P service (this might queue if not connected)
      await widget.p2pService.sendMessage(
        id: messageId,
        message: messageText,
        type: type,
        targetDeviceId: _selectedEndpointId, // CRITICAL: Include target device ID
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
        senderName: senderName, // CRITICAL: Include actual sender name
      );

      if (isConnected) {
        debugPrint('✅ Message sent immediately to connected device');
        _showSuccessMessage('Message sent');
      } else {
        debugPrint('📥 Message queued for later delivery');
        _showSuccessMessage('Message queued (device offline)');
      }

    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      _showErrorMessage('Failed to send message: ${e.toString()}');
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

      // Send location via P2P service instead of sync service for better delivery
      await widget.p2pService.sendMessage(
        message: locationText,
        type: MessageType.location,
        targetDeviceId: _selectedEndpointId!,
        latitude: widget.currentLocation!.latitude,
        longitude: widget.currentLocation!.longitude,
        senderName: widget.p2pService.userName ?? 'Unknown',
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
        // Use the updated _sendMessage method which now handles targeting properly
        await _sendMessage('🚨 Emergency SOS', MessageType.sos);
        if (mounted) {
          _showSuccessMessage('Emergency SOS sent to ${_selectedDeviceName ?? 'device'}');
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

    // Register MessageRouter listener for this specific device
    widget.p2pService.messageRouter.registerDeviceListener(
      deviceId,
      _onDeviceMessage,
    );
  }

  void _onDeviceMessage(dynamic message) {
    // Handle real-time messages for the selected device
    if (mounted && _selectedEndpointId != null) {
      _loadMessagesForDevice(_selectedEndpointId!);
    }
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
        body: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: ResponsiveUtils.isDesktop(context)
                  ? BoxConstraints(maxWidth: 1200)
                  : BoxConstraints(),
              child: _buildBody(),
            );
          },
        ),
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