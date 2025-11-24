import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:resqlink/utils/offline_fonts.dart';
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
import '../widgets/message/connection_banner.dart';
import '../widgets/message/emergency_dialog.dart';
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

  static void selectDeviceFor(
    GlobalKey key,
    String deviceId,
    String deviceName,
  ) {
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
  // Message queue processing removed

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

  // Connectivity status tracking (for chat view)
  bool _isConnected = false;
  bool _isMeshReachable = false;
  int _meshHopCount = 0; // Hop count for mesh relay
  Timer? _meshMonitoringTimer;
  Timer? _connectivityRefreshTimer;

  // Current user info - use consistent 'local' to match session generation across the app
  String get _currentUserId => 'local';
  LocationModel? get _currentLocation => widget.currentLocation;

  // Track devices for which we've already created sessions to prevent duplicates
  final Set<String> _processedDeviceIds = {};

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
    // Queue processing initialization removed
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
    _meshMonitoringTimer?.cancel();
    _connectivityRefreshTimer?.cancel();
    // Queue processing timer removal - no longer needed
    _loadConversationsDebounce?.cancel();

    // Unregister MessageRouter listener
    if (_selectedEndpointId != null) {
      widget.p2pService.messageRouter.unregisterDeviceListener(
        _selectedEndpointId!,
      );
    }

    try {
      _syncService.dispose();
      widget.p2pService.removeListener(_onP2PUpdate);
      widget.p2pService.removeListener(_onP2PConnectionChanged);
      widget.p2pService.removeListener(_handleP2PStateChanged);
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
      widget.p2pService.addListener(_handleP2PStateChanged);
      // Note: Use event bus or message router for message handling instead of direct callback
      // widget.p2pService.onMessageReceived = _onMessageReceived;

      await _loadConversations();

      if (!mounted) return;

      _startAdaptiveRefresh();
      _startMeshMonitoring();
      _startPeriodicConnectivityRefresh();

      // Initial connectivity check after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedEndpointId != null) {
          _refreshConnectivityState();
        }
      });
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
    // Optimized message handling to reduce database calls
    if (mounted && message is MessageModel) {
      // If we're in a specific conversation, handle it directly
      if (_isChatView && _selectedEndpointId != null) {
        // Check if this message is for the currently selected conversation
        if (message.endpointId == _selectedEndpointId) {
          // Enhanced duplicate check with multiple criteria
          final alreadyExists = _selectedConversationMessages.any(
            (m) =>
                m.messageId == message.messageId ||
                (m.timestamp == message.timestamp &&
                    m.fromUser == message.fromUser &&
                    m.message == message.message &&
                    m.endpointId == message.endpointId),
          );

          if (!alreadyExists) {
            setState(() {
              _selectedConversationMessages.add(message);
              // Sort by timestamp to maintain chronological order (oldest first, newest at bottom)
              _selectedConversationMessages.sort(
                (a, b) => a.timestamp.compareTo(b.timestamp),
              );
              debugPrint(
                '📨 Added incoming message to conversation. Total messages: ${_selectedConversationMessages.length}',
              );
              debugPrint(
                '🕙 Last message timestamp: ${_selectedConversationMessages.last.timestamp}',
              );
            });
            _scrollToBottom();
            debugPrint(
              '✅ Added message to conversation without database reload',
            );

            // Message received proves device is reachable - refresh connectivity
            debugPrint(
              '✅ Message received - device IS reachable, refreshing status',
            );
            _refreshConnectivityState();
            Future.delayed(Duration(milliseconds: 100)).then((_) {
              if (mounted) _refreshConnectivityState();
            });
          } else {
            debugPrint('⚠️ Duplicate message blocked in conversation view');
          }
        }
      }

      // Only refresh conversations if we're not in chat view or every 10th message
      // This reduces database load significantly
      if (!_isChatView || DateTime.now().millisecond % 10 == 0) {
        _loadConversations();
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
    if (_isChatView && _selectedEndpointId != null) {
      _refreshConnectivityState();
    }
    setState(() {});
  }

  void _handleP2PStateChanged() {
    if (!mounted) return;
    if (_isChatView && _selectedEndpointId != null) {
      debugPrint(
        '📡 P2P state changed - refreshing connectivity for $_selectedDeviceName',
      );
      _refreshConnectivityState();
      // Double-refresh with delay to catch async updates
      Future.delayed(Duration(milliseconds: 200)).then((_) {
        if (mounted) _refreshConnectivityState();
      });
    }
  }

  void _refreshConnectivityState() {
    if (!mounted || _selectedEndpointId == null) return;

    final deviceId = _selectedEndpointId!;
    debugPrint(
      '🔄 Refreshing connectivity for device: $deviceId ($_selectedDeviceName)',
    );

    final direct = widget.p2pService.isDeviceDirectlyConnected(deviceId);
    final reachable = widget.p2pService.isDeviceReachable(deviceId);
    final hopCount = widget.p2pService.meshDeviceHopCount[deviceId] ?? 0;
    final inMeshRegistry = widget.p2pService.meshDevices.containsKey(deviceId);

    debugPrint(
      '   Direct: $direct, Reachable: $reachable, InMesh: $inMeshRegistry, Hops: $hopCount',
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
    }
  }

  void _startMeshMonitoring() {
    _meshMonitoringTimer?.cancel();
    _meshMonitoringTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (!_isChatView || _selectedEndpointId == null) return;

      final deviceId = _selectedEndpointId!;
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

  void _startPeriodicConnectivityRefresh() {
    _connectivityRefreshTimer?.cancel();
    _connectivityRefreshTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_isChatView && _selectedEndpointId != null) {
        _refreshConnectivityState();
      }
    });
  }

  // Message queue processing methods removed

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) async {
    if (!mounted) return;

    // Note: Session creation is now handled by home_page.dart via onDeviceConnected
    // This method now only handles UI updates for the message page
    for (var device in devices) {
      final deviceId = device['deviceAddress'];
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final isConnected = widget.p2pService.connectedDevices.containsKey(
        deviceId,
      );

      // Only create UI conversation placeholder if connected
      if (isConnected && !_processedDeviceIds.contains(deviceId)) {
        _processedDeviceIds.add(deviceId);
        _createConversationForDevice(deviceId, deviceName);
        debugPrint(
          '✅ Created UI conversation placeholder for $deviceName ($deviceId)',
        );
      }
    }
  }

  void _createConversationForDevice(String deviceId, String deviceName) {
    if (!mounted) return;

    final existingConversation = _conversations.any(
      (conv) => conv.endpointId == deviceId,
    );

    if (!existingConversation) {
      final isDirectlyConnected = widget.p2pService.connectedDevices
          .containsKey(deviceId);
      final isMeshReachable =
          !isDirectlyConnected &&
          widget.p2pService.meshDevices.containsKey(deviceId);
      final hopCount = widget.p2pService.meshDeviceHopCount[deviceId] ?? 0;

      final newConversation = MessageSummary(
        endpointId: deviceId,
        deviceName: deviceName,
        lastMessage: null,
        messageCount: 0,
        unreadCount: 0,
        isConnected: isDirectlyConnected,
        isMeshReachable: isMeshReachable,
        meshHopCount: hopCount,
      );

      setState(() {
        _conversations.insert(0, newConversation);
      });

      debugPrint('✅ Created conversation placeholder for $deviceName');
    }
  }

  // Persistent conversation creation is now handled by home_page.dart to prevent duplicates

  Future<void> _loadConversations() async {
    if (!mounted || _isLoadingConversations) return;

    // Increased debounce to reduce database calls
    _loadConversationsDebounce?.cancel();
    _loadConversationsDebounce = Timer(
      const Duration(milliseconds: 1000),
      () async {
        await _loadConversationsInternal();
      },
    );
  }

  Future<void> _loadConversationsInternal() async {
    if (!mounted || _isLoadingConversations) return;

    _isLoadingConversations = true;

    try {
      // Use smaller limits and shorter timeouts to prevent database locks
      final messages = await MessageRepository.getAllMessages(
        limit: 500,
      ).timeout(Duration(seconds: 2));
      final chatSessions = await ChatRepository.getAllSessions().timeout(
        Duration(seconds: 2),
      );
      if (!mounted) return;

      final connectedDevices = widget.p2pService.connectedDevices;
      final discoveredDevices = widget.p2pService.discoveredResQLinkDevices;

      final Map<String, MessageSummary> conversationMap = {};

      // First, create conversations from stored chat sessions (ensures persistence)
      for (final session in chatSessions) {
        if (!mounted) return;

        final endpointId = session.deviceId;
        final deviceName = session.deviceName;

        // Only check for better names if we already have a session, otherwise just add it
        if (conversationMap.containsKey(endpointId)) {
          final existing = conversationMap[endpointId]!;
          // Simple check: only replace if new name is clearly better (avoid heavy scoring)
          if (_isSimpleNameBetter(deviceName, existing.deviceName)) {
            final isDirectlyConnected = connectedDevices.containsKey(
              endpointId,
            );
            final isMeshReachable =
                !isDirectlyConnected &&
                widget.p2pService.meshDevices.containsKey(endpointId);
            final hopCount =
                widget.p2pService.meshDeviceHopCount[endpointId] ?? 0;

            conversationMap[endpointId] = MessageSummary(
              endpointId: endpointId,
              deviceName: deviceName,
              lastMessage: null,
              messageCount: 0,
              unreadCount: 0,
              isConnected: isDirectlyConnected,
              isMeshReachable: isMeshReachable,
              meshHopCount: hopCount,
            );
            debugPrint(
              '🔄 Updated session name: $deviceName (was: ${existing.deviceName})',
            );
          }
        } else {
          final isDirectlyConnected = connectedDevices.containsKey(endpointId);
          final isMeshReachable =
              !isDirectlyConnected &&
              widget.p2pService.meshDevices.containsKey(endpointId);
          final hopCount =
              widget.p2pService.meshDeviceHopCount[endpointId] ?? 0;

          conversationMap[endpointId] = MessageSummary(
            endpointId: endpointId,
            deviceName: deviceName,
            lastMessage: null,
            messageCount: 0,
            unreadCount: 0,
            isConnected: isDirectlyConnected,
            isMeshReachable: isMeshReachable,
            meshHopCount: hopCount,
          );
          debugPrint(
            '🗄️ Loaded persistent session: $deviceName ($endpointId)',
          );
        }
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
          final endpointMessages = messages
              .where((m) => m.endpointId == endpointId)
              .toList();
          final unreadCount = endpointMessages
              .where((m) => !m.synced && !m.isMe)
              .length;

          final isDirectlyConnected = connectedDevices.containsKey(endpointId);
          final isMeshReachable =
              !isDirectlyConnected &&
              widget.p2pService.meshDevices.containsKey(endpointId);
          final hopCount =
              widget.p2pService.meshDeviceHopCount[endpointId] ?? 0;

          conversationMap[endpointId] = MessageSummary(
            endpointId: endpointId,
            deviceName: deviceName,
            lastMessage: message,
            messageCount: endpointMessages.length,
            unreadCount: unreadCount,
            isConnected: isDirectlyConnected,
            isMeshReachable: isMeshReachable,
            meshHopCount: hopCount,
          );
        } else {
          final currentSummary = conversationMap[endpointId]!;
          final endpointMessages = messages
              .where((m) => m.endpointId == endpointId)
              .toList();
          final unreadCount = endpointMessages
              .where((m) => !m.synced && !m.isMe)
              .length;

          // Check if we should update the conversation based on message time or better device name
          final shouldUpdateTime = message.dateTime.isAfter(
            currentSummary.lastMessage?.dateTime ?? DateTime(0),
          );
          final shouldUpdateName = _isDisplayNameBetter(
            deviceName,
            currentSummary.deviceName,
          );

          if (shouldUpdateTime || shouldUpdateName) {
            // Use the better device name if updating due to name priority
            final bestDeviceName = shouldUpdateName
                ? deviceName
                : currentSummary.deviceName;

            final isDirectlyConnected = connectedDevices.containsKey(
              endpointId,
            );
            final isMeshReachable =
                !isDirectlyConnected &&
                widget.p2pService.meshDevices.containsKey(endpointId);
            final hopCount =
                widget.p2pService.meshDeviceHopCount[endpointId] ?? 0;

            conversationMap[endpointId] = MessageSummary(
              endpointId: endpointId,
              deviceName: bestDeviceName,
              lastMessage: shouldUpdateTime
                  ? message
                  : currentSummary.lastMessage,
              messageCount: endpointMessages.length,
              unreadCount: unreadCount,
              isConnected: isDirectlyConnected,
              isMeshReachable: isMeshReachable,
              meshHopCount: hopCount,
            );

            if (shouldUpdateName) {
              debugPrint(
                '🔄 Updated conversation name: $bestDeviceName (was: ${currentSummary.deviceName})',
              );
            }
          }
        }
      }

      if (mounted) {
        final newConversations = conversationMap.values.toList()
          ..sort(
            (a, b) => (b.lastMessage?.dateTime ?? DateTime(0)).compareTo(
              a.lastMessage?.dateTime ?? DateTime(0),
            ),
          );

        // Only update state if data actually changed to prevent unnecessary rebuilds
        if (_conversations.length != newConversations.length ||
            !_conversationsEqual(_conversations, newConversations)) {
          setState(() {
            _conversations = newConversations;
            _isLoading = false;
          });
          debugPrint(
            '✅ Updated ${_conversations.length} conversations (${connectedDevices.length} connected)',
          );
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
        // Ensure messages are sorted chronologically (oldest first, newest at bottom)
        _selectedConversationMessages = messages;
        _selectedConversationMessages.sort(
          (a, b) => a.timestamp.compareTo(b.timestamp),
        );
      });

      // Scroll to bottom to show latest messages
      _scrollToBottomImmediate();

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

  /// Get the quality score of a display name (higher is better)
  /// Priority: Real names > Device names > Generic device IDs > Empty
  int _getNameScore(String name) {
    if (name.isEmpty) return 0;

    // Generic device IDs (like device_xxxxx, User_xxxxx)
    if (name.startsWith('device_') || name.startsWith('User_')) {
      return 1;
    }

    // Device model names (often contain brand/model info)
    if (name.contains('HONOR') ||
        name.contains('Samsung') ||
        name.toLowerCase().contains('phone') ||
        name.toLowerCase().contains('tablet')) {
      return 2;
    }

    // Real human names (assume names without special chars/numbers are real names)
    if (RegExp(r'^[a-zA-Z\s]+$').hasMatch(name) && name.length <= 30) {
      return 3;
    }

    // Default score for other names
    return 2;
  }

  /// Determine if a display name is better than another
  bool _isDisplayNameBetter(String newName, String currentName) {
    final newScore = _getNameScore(newName);
    final currentScore = _getNameScore(currentName);
    return newScore > currentScore;
  }

  /// Simple name comparison for performance (avoids heavy scoring during session loading)
  bool _isSimpleNameBetter(String newName, String currentName) {
    // Quick checks for obvious improvements
    if (currentName.startsWith('device_') || currentName.startsWith('User_')) {
      return !newName.startsWith('device_') && !newName.startsWith('User_');
    }
    return false; // Don't replace if not obviously better
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
      // Check both direct connection AND mesh reachability
      final isConnected = widget.p2pService.connectedDevices.containsKey(
        _selectedEndpointId,
      );
      final isReachable = widget.p2pService.isDeviceReachable(
        _selectedEndpointId!,
      );
      final connectionInfo = isReachable
          ? (isConnected ? 'directly connected' : 'mesh reachable')
          : 'unreachable (will queue)';

      debugPrint(
        '📤 Sending message to $_selectedEndpointId ($connectionInfo): "$messageText"',
      );

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
        status: isReachable ? MessageStatus.pending : MessageStatus.failed,
        deviceId: widget.p2pService.deviceId,
      );

      // Insert into local database FIRST for immediate UI update
      await MessageRepository.insert(dbMessage);

      // Update UI immediately to show the sent message (optimistic update)
      setState(() {
        _selectedConversationMessages.add(dbMessage);
        // Sort by timestamp to maintain chronological order
        _selectedConversationMessages.sort(
          (a, b) => a.timestamp.compareTo(b.timestamp),
        );
        debugPrint(
          '💬 Added sent message to conversation. Total messages: ${_selectedConversationMessages.length}',
        );
        debugPrint(
          '🕙 Last message timestamp: ${_selectedConversationMessages.last.timestamp}',
        );
      });
      // Immediate scroll for sent messages
      _scrollToBottomImmediate();

      // Then send via P2P service (this might queue if not connected)
      await widget.p2pService.sendMessage(
        id: messageId,
        message: messageText,
        type: type,
        targetDeviceId:
            _selectedEndpointId, // CRITICAL: Include target device ID
        latitude: _currentLocation?.latitude,
        longitude: _currentLocation?.longitude,
        senderName: senderName, // CRITICAL: Include actual sender name
      );

      if (isReachable) {
        // Update status to sent after successful transmission
        await MessageRepository.updateStatus(messageId, MessageStatus.sent);
        if (mounted) {
          setState(() {
            final index = _selectedConversationMessages.indexWhere(
              (m) => m.messageId == messageId,
            );
            if (index != -1) {
              _selectedConversationMessages[index] = dbMessage.copyWith(
                status: MessageStatus.sent,
              );
            }
          });
        }

        debugPrint(
          '✅ Message sent successfully to ${isConnected ? "directly connected" : "mesh-reachable"} device',
        );
        _showSuccessMessage(
          isConnected ? 'Message sent' : 'Message sent via mesh',
        );

        // Message sent successfully proves device is reachable - refresh connectivity
        _refreshConnectivityState();
        Future.delayed(Duration(milliseconds: 100)).then((_) {
          if (mounted) _refreshConnectivityState();
        });
      } else {
        debugPrint('📥 Message failed - device unreachable');
        _showErrorMessage('Device unreachable - message failed');
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

    // Show loading message
    if (mounted) {
      _showSuccessMessage('Getting GPS location...');
    }

    // Get fresh GPS position
    double? latitude;
    double? longitude;

    // Try to get current GPS position
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      latitude = position.latitude;
      longitude = position.longitude;
    } catch (e) {
      debugPrint('❌ Error getting GPS position: $e');
      if (mounted) {
        _showErrorMessage('Location not available. Please enable GPS.');
      }
      return;
    }

    try {
      final locationText =
          '📍 Location shared\nLat: ${latitude.toStringAsFixed(6)}\nLng: ${longitude.toStringAsFixed(6)}';

      final locationModel = LocationModel(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        userId: widget.p2pService.deviceId,
        type: LocationType.normal,
        message: 'Shared via sync service',
      );

      await LocationService.insertLocation(locationModel);

      final messageId = _generateMessageId();
      final timestamp = DateTime.now();
      final senderName = widget.p2pService.userName ?? 'Unknown User';
      final isConnected = widget.p2pService.connectedDevices.containsKey(
        _selectedEndpointId,
      );
      final isReachable = widget.p2pService.isDeviceReachable(
        _selectedEndpointId!,
      );

      final dbMessage = MessageModel(
        endpointId: _selectedEndpointId!,
        fromUser: senderName,
        message: locationText,
        isMe: true,
        isEmergency: false,
        messageType: MessageType.location,
        timestamp: timestamp.millisecondsSinceEpoch,
        latitude: latitude,
        longitude: longitude,
        messageId: messageId,
        type: MessageType.location.name,
        status: isReachable ? MessageStatus.pending : MessageStatus.failed,
        deviceId: widget.p2pService.deviceId,
      );

      await MessageRepository.insert(dbMessage);

      if (mounted) {
        setState(() {
          _selectedConversationMessages.add(dbMessage);
          _selectedConversationMessages.sort(
            (a, b) => a.timestamp.compareTo(b.timestamp),
          );
        });
        _scrollToBottomImmediate();
      }

      await widget.p2pService.sendMessage(
        id: messageId,
        message: locationText,
        type: MessageType.location,
        targetDeviceId: _selectedEndpointId!,
        latitude: latitude,
        longitude: longitude,
        senderName: senderName,
      );

      if (mounted) {
        if (isReachable) {
          // Update status to sent after successful transmission
          await MessageRepository.updateStatus(messageId, MessageStatus.sent);
          setState(() {
            final index = _selectedConversationMessages.indexWhere(
              (m) => m.messageId == messageId,
            );
            if (index != -1) {
              _selectedConversationMessages[index] = dbMessage.copyWith(
                status: MessageStatus.sent,
              );
            }
          });
          _showSuccessMessage(
            isConnected
                ? 'Location shared successfully'
                : 'Location shared via mesh',
          );
        } else {
          _showSuccessMessage('Device unreachable - location failed');
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending location: $e');
      if (mounted) {
        _showErrorMessage('Failed to share location');
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
    _refreshSelectedDeviceName(endpointId);

    // Refresh connectivity state when opening conversation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshConnectivityState();
        // Double-refresh to catch async updates
        Future.delayed(Duration(milliseconds: 100)).then((_) {
          if (mounted) _refreshConnectivityState();
        });
      }
    });
  }

  Future<void> _refreshSelectedDeviceName(String deviceId) async {
    try {
      final session = await ChatRepository.getSessionByDeviceId(deviceId);
      if (!mounted) return;
      if (session != null && session.deviceName.isNotEmpty) {
        setState(() {
          _selectedDeviceName = session.deviceName;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh selected device name: $e');
    }
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

    // Use multiple frame callbacks to ensure reliable scrolling after UI updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        // Schedule another frame callback to ensure layout is complete
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
    });
  }

  void _scrollToBottomImmediate() {
    if (!mounted) return;

    // Immediate scroll for sent messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);

        // Also schedule an animated scroll to ensure we're at the very bottom
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
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
            Text(
              message,
              style: OfflineFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
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
            SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: OfflineFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
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
      case 'clear_chat':
        if (_selectedEndpointId != null && mounted) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => ClearChatDialog(),
          );

          if (confirm == true && _selectedEndpointId != null) {
            try {
              await MessageRepository.deleteMessagesForEndpoint(
                _selectedEndpointId!,
              );

              if (mounted) {
                setState(() {
                  _selectedConversationMessages.clear();
                });
                _showSuccessMessage('Chat history cleared');
              }
            } catch (e) {
              if (mounted) {
                _showErrorMessage('Failed to clear chat history: $e');
              }
            }
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
          if (deviceData['deviceId'] == deviceId ||
              deviceData['endpointId'] == deviceId) {
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
          _showErrorMessage(
            'Failed to reconnect. Try creating a new connection.',
          );
        }
      } else {
        _showErrorMessage(
          'Device not found. Try scanning again or create a new connection.',
        );
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
          isConnected: _isConnected,
          isMeshReachable: _isMeshReachable,
          meshHopCount: _meshHopCount,
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
        widget.p2pService.isDiscovering
            ? Icons.hourglass_empty
            : Icons.wifi_tethering,
        color: Colors.white,
      ),
    );
  }
}
