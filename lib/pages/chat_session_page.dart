import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/chat_session_model.dart';
import '../models/message_model.dart';
import '../features/database/repositories/chat_repository.dart';
import '../features/database/repositories/message_repository.dart';
import '../services/p2p/p2p_main_service.dart';
import '../services/location_state_service.dart';
import '../utils/resqlink_theme.dart';
import '../utils/responsive_utils.dart';
import '../widgets/message/chat_view.dart';
import '../widgets/message/message_input.dart';
import '../widgets/message/loading_view.dart';
import '../pages/gps_page.dart';

class ChatSessionPage extends StatefulWidget {
  final String sessionId;
  final String deviceName;
  final P2PMainService p2pService;
  final String deviceId;

  const ChatSessionPage({
    super.key,
    required this.sessionId,
    required this.deviceName,
    required this.p2pService,
    required this.deviceId,
  });

  @override
  State<ChatSessionPage> createState() => _ChatSessionPageState();
}

class _ChatSessionPageState extends State<ChatSessionPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LocationStateService _locationStateService = LocationStateService();

  ChatSession? _chatSession;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isMeshReachable = false;
  int _meshHopCount = 0; // Hop count for mesh relay
  Timer? _refreshTimer;
  Timer? _typingTimer;
  bool _isTyping = false;
  String? _listenerDeviceId; // Device ID registered with MessageRouter
  String? _sessionDeviceId; // Canonical device identifier for this chat
  int _queuedMessageCount = 0; // Track queued messages for this device
  bool _isP2PListenerAttached = false;

  LocationModel? get _currentLocation => _locationStateService.currentLocation;

  bool get _hasMeshRelay => !_isConnected && _isMeshReachable;

  bool get _canSendMessages => _isConnected || _isMeshReachable;

  String get _connectionStatusLabel => _isConnected
      ? 'Direct link'
      : _hasMeshRelay
      ? 'Relay via mesh ($_meshHopCount ${_meshHopCount == 1 ? 'hop' : 'hops'})'
      : _chatSession?.lastSeenText ?? 'Offline';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.p2pService.addListener(_handleP2PStateChanged);
    _isP2PListenerAttached = true;
    _sessionDeviceId = _safeTrim(widget.deviceId);

    // Immediate connectivity check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshConnectivityState();
      }
    });

    _initialize();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_isP2PListenerAttached) {
      widget.p2pService.removeListener(_handleP2PStateChanged);
      _isP2PListenerAttached = false;
    }

    // Unregister MessageRouter listener
    if (_listenerDeviceId != null) {
      widget.p2pService.messageRouter.unregisterDeviceListener(
        _listenerDeviceId!,
      );
      _listenerDeviceId = null;
    }

    // Clear global P2P listener
    widget.p2pService.onMessageReceived = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChatData();
      _startPeriodicRefresh();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    }
  }

  Future<void> _initialize() async {
    await _loadChatData();
    _setupMessageListener();
    _setupMessageRouterListener();
    _markMessagesAsRead();
    _startPeriodicRefresh();
    _startMeshMonitoring();
  }

  void _startMeshMonitoring() {
    // Monitor mesh registry every 2 seconds for real-time updates
    Timer.periodic(Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final deviceId = _effectiveDeviceId;
      if (deviceId == null) return;

      // Check if device is in mesh registry
      final inMesh = widget.p2pService.meshDevices.containsKey(deviceId);

      // If device appeared in mesh and we thought it was offline, update immediately
      if (inMesh && !_isMeshReachable) {
        debugPrint(
          '🔔 MESH CONNECTIVITY DETECTED! Device $deviceId now reachable via mesh',
        );
        _refreshConnectivityState();
      }
    });
  }

  void _setupMessageListener() {
    // Note: Use event bus or message router for message handling to prevent conflicts
    // widget.p2pService.onMessageReceived = _onMessageReceived;
  }

  void _setupMessageRouterListener() {
    final targetDeviceId = _effectiveDeviceId;
    if (targetDeviceId == null) {
      debugPrint(
        '⚠️ Unable to register MessageRouter listener - missing device ID for ${widget.sessionId}',
      );
      return;
    }

    if (_listenerDeviceId == targetDeviceId) {
      return; // Already registered for this device
    }

    // Unregister old listener if the device identity changed
    if (_listenerDeviceId != null && _listenerDeviceId != targetDeviceId) {
      widget.p2pService.messageRouter.unregisterDeviceListener(
        _listenerDeviceId!,
      );
    }

    _listenerDeviceId = targetDeviceId;
    widget.p2pService.messageRouter.registerDeviceListener(
      targetDeviceId,
      _onRouterMessage,
    );

    debugPrint(
      '📱 Registered MessageRouter listener for device: $targetDeviceId',
    );
  }

  String? _safeTrim(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _resolveCanonicalDeviceId(String? value) {
    final trimmed = _safeTrim(value);
    if (trimmed == null) return null;
    return widget.p2pService.resolveDeviceIdentifier(trimmed) ?? trimmed;
  }

  void _refreshConnectivityState() {
    if (!mounted) return;
    final deviceId = _effectiveDeviceId;
    if (deviceId == null) {
      debugPrint('⚠️ _refreshConnectivityState: No effective device ID');
      return;
    }

    debugPrint(
      '🔄 Refreshing connectivity for device: $deviceId (${widget.deviceName})',
    );
    final direct = widget.p2pService.isDeviceDirectlyConnected(deviceId);
    final reachable = widget.p2pService.isDeviceReachable(deviceId);
    final hopCount = widget.p2pService.meshDeviceHopCount[deviceId] ?? 0;
    final inMeshRegistry = widget.p2pService.meshDevices.containsKey(deviceId);

    debugPrint(
      '   Direct: $direct, Reachable: $reachable, InMesh: $inMeshRegistry, Hops: $hopCount',
    );
    debugPrint(
      '   Current state - Connected: $_isConnected, MeshReachable: $_isMeshReachable, HopCount: $_meshHopCount',
    );

    if (_isConnected != direct ||
        _isMeshReachable != reachable ||
        _meshHopCount != hopCount) {
      debugPrint('   ⚡ State changed! Updating UI...');
      setState(() {
        _isConnected = direct;
        _isMeshReachable = reachable;
        _meshHopCount = hopCount;
      });
    } else {
      debugPrint('   ℹ️ No change in connectivity state');
    }
  }

  String? _deriveDeviceIdFromSession(ChatSession session) {
    const prefix = 'chat_';
    if (session.id.startsWith(prefix) && session.id.length > prefix.length) {
      return _safeTrim(session.id.substring(prefix.length));
    }
    return null;
  }

  String? _lookupSessionDeviceId(ChatSession session) {
    final metadataDeviceId = session.metadata?['deviceId']?.toString();
    final candidates = [
      session.deviceId,
      session.deviceAddress,
      metadataDeviceId,
      _deriveDeviceIdFromSession(session),
    ];

    for (final candidate in candidates) {
      final trimmed = _safeTrim(candidate);
      if (trimmed != null && trimmed != 'unknown') {
        return trimmed;
      }
    }
    return null;
  }

  String? get _effectiveDeviceId {
    final candidates = <String?>[
      _sessionDeviceId,
      if (_chatSession != null) _lookupSessionDeviceId(_chatSession!),
      widget.deviceId,
    ];

    for (final candidate in candidates) {
      final resolved = _resolveCanonicalDeviceId(candidate);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  void _handleP2PStateChanged() {
    if (!mounted) return;
    debugPrint(
      '📡 P2P state changed - refreshing connectivity for ${widget.deviceName}',
    );
    _refreshConnectivityState();

    // Double refresh after short delay to catch async mesh registry updates
    Future.delayed(Duration(milliseconds: 200)).then((_) {
      if (mounted) _refreshConnectivityState();
    });
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: 3), (_) {
      if (mounted) {
        _loadChatData();
        _refreshConnectivityState();
      }
    });
  }

  Future<void> _loadChatData() async {
    if (!mounted) return;

    try {
      final session = await ChatRepository.getSession(widget.sessionId);
      final messages = await ChatRepository.getSessionMessages(
        widget.sessionId,
      );
      final resolvedDeviceId = session != null
          ? _lookupSessionDeviceId(session)
          : _effectiveDeviceId;
      final canonicalDeviceId = _resolveCanonicalDeviceId(
        resolvedDeviceId ?? widget.deviceId,
      );
      final reachable =
          canonicalDeviceId != null &&
          widget.p2pService.isDeviceReachable(canonicalDeviceId);
      final directConnected =
          canonicalDeviceId != null &&
          widget.p2pService.isDeviceDirectlyConnected(canonicalDeviceId);

      if (session != null &&
          canonicalDeviceId != null &&
          session.metadata?['deviceId'] != canonicalDeviceId) {
        await ChatRepository.updateMetadata(
          sessionId: widget.sessionId,
          values: {'deviceId': canonicalDeviceId},
        );
      }

      if (mounted) {
        setState(() {
          _chatSession = session;
          _messages = messages;
          _isLoading = false;
          _isConnected = directConnected;
          _isMeshReachable = reachable;
          _sessionDeviceId =
              canonicalDeviceId ??
              _sessionDeviceId ??
              _resolveCanonicalDeviceId(widget.deviceId);
        });

        _setupMessageRouterListener();

        _refreshConnectivityState();
        // Update queued message count
        _updateQueuedMessageCount();
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('❌ Error loading chat data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    await ChatRepository.markSessionMessagesAsRead(widget.sessionId);
  }

  /// Handle messages from MessageRouter (real-time)
  void _onRouterMessage(MessageModel message) async {
    if (!mounted) return;
    final sessionDeviceId = _effectiveDeviceId;
    if (sessionDeviceId == null) {
      debugPrint(
        '⚠️ ChatSessionPage missing effective device ID; skipping message',
      );
      return;
    }

    if (!_shouldAttachMessageToSession(message, sessionDeviceId)) {
      debugPrint(
        'ℹ️ Message ignored for session ${widget.sessionId} (not targeted)',
      );
      return;
    }

    // Format debug log based on message type
    String logMessage;
    if (message.messageType == MessageType.voice) {
      logMessage =
          '📨 ChatSession received voice message from ${message.fromUser}';
    } else if (message.messageType == MessageType.location) {
      logMessage = '📨 ChatSession received location from ${message.fromUser}';
    } else {
      logMessage =
          '📨 ChatSession received message from ${message.fromUser}: ${message.message}';
    }
    debugPrint(logMessage);

    // Update message with chat session ID or corrected endpoint for broadcast copies
    MessageModel messageToAdd = message;
    final needsSessionBinding = message.chatSessionId != widget.sessionId;
    final needsEndpointCorrection =
        message.endpointId == 'broadcast' || message.endpointId == 'unknown';

    if (needsSessionBinding || needsEndpointCorrection) {
      final updatedEndpoint = needsEndpointCorrection
          ? sessionDeviceId
          : message.endpointId;

      messageToAdd = message.copyWith(
        chatSessionId: widget.sessionId,
        endpointId: updatedEndpoint,
      );
      await MessageRepository.insert(messageToAdd);
    }

    // Check if message is not already in our current messages list (avoid duplicates)
    final alreadyExists = _messages.any(
      (m) =>
          m.messageId == messageToAdd.messageId ||
          (m.timestamp == messageToAdd.timestamp &&
              m.fromUser == messageToAdd.fromUser &&
              m.message == messageToAdd.message),
    );

    if (!alreadyExists) {
      // Add message directly to UI instead of reloading everything
      setState(() {
        _messages.add(messageToAdd);
        // Sort by timestamp to maintain order
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });

      // Scroll to bottom to show new message
      _scrollToBottom();
    }

    // Mark messages as read
    await _markMessagesAsRead();

    // Record heartbeat so session shows as online
    await _recordSessionConnection();

    // Refresh connectivity state after receiving message
    debugPrint(
      '✅ Message received from ${message.fromUser} - device IS reachable, refreshing status',
    );
    _refreshConnectivityState();

    // Double refresh to ensure UI updates
    Future.delayed(Duration(milliseconds: 100)).then((_) {
      if (mounted) _refreshConnectivityState();
    });

    // Update queued message count
    _updateQueuedMessageCount();
  }

  bool _shouldAttachMessageToSession(
    MessageModel message,
    String sessionDeviceId,
  ) {
    final isBroadcastMessage = _isBroadcastMessage(message);

    if (isBroadcastMessage) {
      // Sender should see their own broadcasts in every open chat, receivers only if target matches
      if (message.isMe) {
        return true;
      }
      return message.endpointId == sessionDeviceId ||
          message.targetDeviceId == sessionDeviceId ||
          message.deviceId == sessionDeviceId;
    }

    return message.endpointId == sessionDeviceId ||
        message.targetDeviceId == sessionDeviceId ||
        message.deviceId == sessionDeviceId;
  }

  bool _isBroadcastMessage(MessageModel message) {
    return message.endpointId == 'broadcast' ||
        message.targetDeviceId == 'broadcast' ||
        message.endpointId == 'unknown';
  }

  /// Update queued message count for this device - DISABLED
  void _updateQueuedMessageCount() {
    final deviceId = _effectiveDeviceId;
    if (deviceId != null && mounted) {
      // Message queue functionality removed
      setState(() {
        _queuedMessageCount = 0; // Always 0 since queue is disabled
      });
    }
  }

  Future<void> _recordSessionConnection() async {
    try {
      final connectionType = _isConnected
          ? ConnectionType.wifiDirect
          : ConnectionType.unknown;
      await ChatRepository.updateConnection(
        sessionId: widget.sessionId,
        connectionType: connectionType,
        connectionTime: DateTime.now(),
      );
    } catch (e) {
      debugPrint(
        '⚠️ Failed to update connection metadata for ${widget.sessionId}: $e',
      );
    }
  }

  void _updateLocalMessageStatus(String messageId, MessageStatus status) {
    final index = _messages.indexWhere((m) => m.messageId == messageId);
    if (index == -1) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(status: status);
    });
  }

  Future<void> _sendMessage(String messageText, MessageType type) async {
    if (_chatSession == null || messageText.trim().isEmpty) return;

    final targetDeviceId = _effectiveDeviceId;
    if (targetDeviceId == null) {
      debugPrint(
        '❌ Unable to send message - missing device ID for session ${widget.sessionId}',
      );
      _showSnackBar(
        'Missing device identifier. Please reopen or recreate this chat.',
        isError: true,
      );
      return;
    }

    try {
      final messageId = MessageModel.generateMessageId(
        widget.p2pService.deviceId ?? 'unknown',
      );
      final timestamp = DateTime.now();

      // CRITICAL: Use the stable session ID from the widget (MAC address-based)
      // DO NOT regenerate from display names - that causes duplicate sessions!
      String chatSessionId = widget.sessionId;

      // Check reachability BEFORE creating message (for correct initial status)
      final isReachable = widget.p2pService.isDeviceReachable(targetDeviceId);
      final initialStatus = isReachable
          ? MessageStatus.pending
          : MessageStatus.failed;

      // Create message with chat session ID
      final message = MessageModel(
        messageId: messageId,
        endpointId: targetDeviceId,
        fromUser: widget.p2pService.userName ?? 'You',
        message: messageText.trim(),
        isMe: true,
        isEmergency: type == MessageType.emergency || type == MessageType.sos,
        timestamp: timestamp.millisecondsSinceEpoch,
        messageType: type,
        type: type.name,
        status: initialStatus,
        chatSessionId: chatSessionId,
        connectionType: widget.p2pService.connectionType,
        deviceId: null,
      );

      // Save message to database
      await MessageRepository.insert(message);

      // Update UI immediately with the new message (optimistic update)
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
      _messageController.clear();

      if (!isReachable) {
        // Already set to failed status above, just show error
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isMeshReachable = false;
          });
        }
        _showSnackBar('Device unreachable - message failed', isError: true);
        return;
      }

      try {
        await widget.p2pService.sendMessage(
          message: messageText.trim(),
          type: type,
          targetDeviceId: targetDeviceId,
          senderName: widget.p2pService.userName ?? 'You',
        );

        await MessageRepository.updateStatus(messageId, MessageStatus.sent);
        _updateLocalMessageStatus(messageId, MessageStatus.sent);

        debugPrint(
          '✅ Message sent successfully - device IS reachable, refreshing status',
        );
        _refreshConnectivityState();

        // Double refresh to ensure UI updates
        Future.delayed(Duration(milliseconds: 100)).then((_) {
          if (mounted) _refreshConnectivityState();
        });
      } catch (e) {
        debugPrint('❌ Error sending P2P message: $e');
        await MessageRepository.updateStatus(messageId, MessageStatus.failed);
        _updateLocalMessageStatus(messageId, MessageStatus.failed);
      }
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      _showSnackBar('Failed to send message', isError: true);
    }
  }

  Future<void> _sendLocationMessage() async {
    if (_chatSession == null) return;

    final targetDeviceId = _effectiveDeviceId;
    if (targetDeviceId == null) {
      debugPrint(
        '❌ Unable to send location - missing device ID for session ${widget.sessionId}',
      );
      _showSnackBar(
        'Missing device identifier. Please reopen or recreate this chat.',
        isError: true,
      );
      return;
    }

    // Show loading
    _showSnackBar('Getting GPS location...', isError: false);

    // Get fresh GPS location
    await _locationStateService.refreshLocation();

    // If still no location, try to get current position directly
    if (_currentLocation == null) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );

        final freshLocation = LocationModel(
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
          userId: widget.p2pService.deviceId ?? 'unknown',
          type: LocationType.normal,
          accuracy: position.accuracy,
        );

        _locationStateService.updateCurrentLocation(freshLocation);
      } catch (e) {
        debugPrint('❌ Error getting current position: $e');
        _showSnackBar(
          'Location not available. Please enable GPS.',
          isError: true,
        );
        return;
      }
    }

    if (_currentLocation == null) {
      _showSnackBar(
        'Location not available. Please enable GPS.',
        isError: true,
      );
      return;
    }

    try {
      final locationText =
          '📍 Location shared\nLat: ${_currentLocation!.latitude.toStringAsFixed(6)}\nLng: ${_currentLocation!.longitude.toStringAsFixed(6)}';

      // Save location to database
      await LocationService.insertLocation(_currentLocation!);

      // Create message with location data
      final messageId = MessageModel.generateMessageId(
        widget.p2pService.deviceId ?? 'unknown',
      );
      final timestamp = DateTime.now();

      // Check reachability BEFORE creating message
      final isReachable = widget.p2pService.isDeviceReachable(targetDeviceId);
      final initialStatus = isReachable
          ? MessageStatus.pending
          : MessageStatus.failed;

      final message = MessageModel(
        messageId: messageId,
        endpointId: targetDeviceId,
        fromUser: widget.p2pService.userName ?? 'You',
        message: locationText,
        isMe: true,
        isEmergency: false,
        timestamp: timestamp.millisecondsSinceEpoch,
        messageType: MessageType.location,
        type: MessageType.location.name,
        status: initialStatus,
        chatSessionId: widget.sessionId,
        connectionType: widget.p2pService.connectionType,
        deviceId: widget.p2pService.deviceId,
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
      );

      // Save to database
      await MessageRepository.insert(message);

      // Update UI immediately
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
      _messageController.clear();

      if (isReachable) {
        try {
          await widget.p2pService.sendMessage(
            id: messageId,
            message: locationText,
            type: MessageType.location,
            targetDeviceId: targetDeviceId,
            senderName: widget.p2pService.userName ?? 'You',
            latitude: _currentLocation!.latitude,
            longitude: _currentLocation!.longitude,
          );

          await MessageRepository.updateStatus(messageId, MessageStatus.sent);

          // Update the message in UI to show sent status
          final updatedMessage = message.copyWith(status: MessageStatus.sent);
          setState(() {
            final index = _messages.indexWhere((m) => m.messageId == messageId);
            if (index != -1) {
              _messages[index] = updatedMessage;
            }
          });

          _refreshConnectivityState();
          _showSnackBar('Location shared successfully', isError: false);
        } catch (e) {
          debugPrint('❌ Error sending P2P message: $e');
          await MessageRepository.updateStatus(messageId, MessageStatus.failed);
          _showSnackBar('Failed to send location', isError: true);
        }
      } else {
        _showSnackBar('Location queued (device offline)', isError: false);
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isMeshReachable = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending location: $e');
      _showSnackBar('Failed to send location', isError: true);
    }
  }

  Future<void> _reconnectToDevice() async {
    if (_chatSession == null) return;

    final targetDeviceId = _effectiveDeviceId;
    if (targetDeviceId == null) {
      _showSnackBar(
        'Missing device identifier, cannot reconnect.',
        isError: true,
      );
      return;
    }

    try {
      _showSnackBar('Attempting to reconnect...', isError: false);

      await widget.p2pService.discoverDevices(force: true);
      await Future.delayed(Duration(seconds: 2));

      final devices = widget.p2pService.discoveredDevices;
      Map<String, dynamic>? targetDevice;

      if (devices.containsKey(targetDeviceId)) {
        targetDevice = devices[targetDeviceId];
      } else {
        for (final deviceData in devices.values) {
          if (deviceData['deviceId'] == targetDeviceId ||
              deviceData['endpointId'] == targetDeviceId) {
            targetDevice = deviceData;
            break;
          }
        }
      }

      if (targetDevice != null && targetDevice.isNotEmpty) {
        final success = await widget.p2pService.connectToDevice(targetDevice);
        if (success) {
          await ChatRepository.updateSessionConnection(
            sessionId: widget.sessionId,
            connectionType: ConnectionType.wifiDirect,
            connectionTime: DateTime.now(),
          );
          await _loadChatData();
          _showSnackBar('Reconnected successfully!', isError: false);
          _refreshConnectivityState();
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

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;

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

  void _handleTyping(String text) {
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

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
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
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: true,
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
                child: _buildBody(),
              ),
            );
          },
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;
    final statusText = _connectionStatusLabel;

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
      leading: Container(
        margin: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Color(0xFFFF6500).withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
        ),
      ),
      title: Row(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _isConnected
                  ? LinearGradient(
                      colors: [
                        ResQLinkTheme.safeGreen,
                        ResQLinkTheme.safeGreen.withValues(alpha: 0.7),
                      ],
                    )
                  : _hasMeshRelay
                  ? LinearGradient(
                      colors: [
                        Colors.orange,
                        Colors.orange.withValues(alpha: 0.7),
                      ],
                    )
                  : LinearGradient(
                      colors: [Colors.grey.shade700, Colors.grey.shade800],
                    ),
              boxShadow: [
                BoxShadow(
                  color: _isConnected
                      ? ResQLinkTheme.safeGreen.withValues(alpha: 0.4)
                      : _hasMeshRelay
                      ? Colors.orange.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.transparent,
              child: Text(
                widget.deviceName.isNotEmpty
                    ? widget.deviceName[0].toUpperCase()
                    : 'D',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.deviceName,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isConnected
                            ? ResQLinkTheme.safeGreen
                            : _hasMeshRelay
                            ? Colors.orange
                            : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: (_isConnected || _hasMeshRelay)
                            ? [
                                BoxShadow(
                                  color:
                                      (_isConnected
                                              ? ResQLinkTheme.safeGreen
                                              : Colors.orange)
                                          .withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        statusText,
                        style: GoogleFonts.poppins(
                          color: _isConnected
                              ? ResQLinkTheme.safeGreen
                              : _hasMeshRelay
                              ? Colors.orange
                              : Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_queuedMessageCount > 0)
            Container(
              margin: EdgeInsets.only(left: 8),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange, Colors.deepOrange],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Text(
                '$_queuedMessageCount',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (!_isConnected && !_isMeshReachable)
          Container(
            margin: EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.orange),
              onPressed: _reconnectToDevice,
              tooltip: 'Reconnect',
            ),
          ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.white),
          color: Color(0xFF1E3E62),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Color(0xFFFF6500).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          onSelected: (value) async {
            switch (value) {
              case 'device_info':
                _showDeviceInfo();
              case 'clear_chat':
                _showClearChatDialog();
              case 'block_device':
                _showBlockDeviceDialog();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'device_info',
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Device Info',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Clear Chat',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'block_device',
              child: Row(
                children: [
                  Icon(Icons.block, color: ResQLinkTheme.primaryRed, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Block Device',
                    style: GoogleFonts.poppins(
                      color: ResQLinkTheme.primaryRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return LoadingView();
    }

    return Column(
      children: [
        if ((!_isConnected && !_isMeshReachable) ||
            _hasMeshRelay ||
            _queuedMessageCount > 0)
          _buildOfflineBanner(),
        Expanded(
          child: ChatView(
            messages: _messages,
            scrollController: _scrollController,
          ),
        ),
        MessageInput(
          controller: _messageController,
          onSendMessage: _sendMessage,
          onSendLocation: _sendLocationMessage,
          onTyping: _handleTyping,
          enabled: _canSendMessages,
        ),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    final isOffline = !_isConnected && !_isMeshReachable;
    final hasQueuedMessages = _queuedMessageCount > 0;
    final hasRelay = _hasMeshRelay;

    String bannerText;
    IconData bannerIcon;
    Color bannerColor;

    if (hasRelay && hasQueuedMessages) {
      bannerText =
          'Mesh relay active - $_queuedMessageCount messages queued for transfer';
      bannerIcon = Icons.device_hub;
      bannerColor = ResQLinkTheme.warningYellow;
    } else if (hasRelay) {
      bannerText = 'Mesh relay active - delivery may be slower';
      bannerIcon = Icons.device_hub;
      bannerColor = ResQLinkTheme.warningYellow;
    } else if (isOffline && hasQueuedMessages) {
      bannerText = 'Device offline - $_queuedMessageCount messages queued';
      bannerIcon = Icons.wifi_off;
      bannerColor = ResQLinkTheme.primaryRed;
    } else if (isOffline) {
      bannerText = 'Device offline - messages will be queued';
      bannerIcon = Icons.wifi_off;
      bannerColor = ResQLinkTheme.primaryRed;
    } else if (hasQueuedMessages) {
      bannerText = '$_queuedMessageCount messages pending delivery';
      bannerIcon = Icons.schedule;
      bannerColor = Colors.orange;
    } else {
      bannerText = 'Device offline - messages will be queued';
      bannerIcon = Icons.wifi_off;
      bannerColor = ResQLinkTheme.primaryRed;
    }

    return Container(
      margin: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            bannerColor.withValues(alpha: 0.2),
            bannerColor.withValues(alpha: 0.1),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bannerColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bannerColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(bannerIcon, color: bannerColor, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                bannerText,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceInfo() {
    if (_chatSession == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Device Information',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name', _chatSession!.deviceName),
            _buildInfoRow(
              'Device ID',
              _effectiveDeviceId ?? _chatSession!.deviceId,
            ),
            _buildInfoRow('Status', _connectionStatusLabel),
            if (_chatSession!.lastConnectionType != null)
              _buildInfoRow(
                'Last Connection',
                _chatSession!.lastConnectionType!.displayName,
              ),
            _buildInfoRow('Messages', _chatSession!.messageCount.toString()),
            _buildInfoRow('Created', _formatDate(_chatSession!.createdAt)),
            if (_chatSession!.lastConnectionAt != null)
              _buildInfoRow(
                'Last Seen',
                _formatDate(_chatSession!.lastConnectionAt!),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
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
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w400,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Clear Chat History',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Are you sure you want to clear all messages in this chat? This action cannot be undone.',
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop();
              await ChatRepository.deleteSession(widget.sessionId);
              if (mounted) {
                navigator.pop();
              }
            },
            child: Text(
              'Clear',
              style: GoogleFonts.poppins(
                color: ResQLinkTheme.primaryRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Block Device',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Are you sure you want to block this device? You will no longer receive messages from this device.',
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop();
              // Implement device blocking logic here
              await ChatRepository.archiveSession(widget.sessionId);
              if (mounted) {
                navigator.pop();
              }
            },
            child: Text(
              'Block',
              style: GoogleFonts.poppins(
                color: ResQLinkTheme.primaryRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
