import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/models/device_model.dart';
import 'package:resqlink/services/p2p/p2p_discovery_service.dart';
import '../../models/message_model.dart';
import 'wifi_direct_service.dart';
import 'p2p_base_service.dart';
import 'p2p_network_service.dart';
import '../../helpers/chat_navigation_helper.dart';
import '../../services/p2p/protocols/socket_protocol.dart';
import '../messaging/message_router.dart';


class P2PMainService extends P2PBaseService {
  // Service components
  late P2PNetworkService _networkService;
  late P2PDiscoveryService _discoveryService;
  WiFiDirectService? _wifiDirectService;

  late SocketProtocol _socketProtocol;
  late MessageRouter _messageRouter;

  // Enhanced state
  bool _isOnline = false;

  // Additional state for widget compatibility
  P2PConnectionMode _currentConnectionMode = P2PConnectionMode.none;
  bool _isConnecting = false;

  // Message tracing for debugging
  final List<String> _messageTrace = [];

  // Message deduplication at WiFi Direct level
  final Set<String> _processedMessages = {};
  final Map<String, DateTime> _messageTimestamps = {};
  static const Duration _messageDedupWindow = Duration(seconds: 5);

  // Debounce mechanism for connection state changes
  Timer? _connectionStateDebounceTimer;
  static const Duration _connectionStateDebounceDelay = Duration(
    milliseconds: 500,
  );

  // Debounce mechanism for peer updates
  Timer? _peerUpdateDebounceTimer;
  static const Duration _peerUpdateDebounceDelay = Duration(
    milliseconds: 1000,
  );


  final Set<String> _processingDevices = {};
  final Set<String> _handshakeResponsesSent = {};


  @override
  Future<bool> initialize(String userName, {String? preferredRole}) async {
    debugPrint('🚀 P2P Main Service initializing with userName: $userName');

    try {
      // Initialize base service first
      final baseSuccess = await super.initialize(
        userName,
        preferredRole: preferredRole,
      );
      if (!baseSuccess) {
        debugPrint('❌ Base service initialization failed');
        return false;
      }

      // Initialize service components
      _networkService = P2PNetworkService(this);
      _discoveryService = P2PDiscoveryService(this, _networkService);


      await _discoveryService.initialize();

      _wifiDirectService = WiFiDirectService.instance;

      await _wifiDirectService?.initialize();

      _socketProtocol = SocketProtocol();

      await _socketProtocol.forceCleanup();

      _socketProtocol.initialize(deviceId!, userName);

      _socketProtocol.onDeviceConnected = (deviceId, userName) {
        debugPrint(
          '🔗 Device connected via SocketProtocol: $userName ($deviceId)',
        );
        addConnectedDevice(deviceId, userName);
      };

      _messageRouter = MessageRouter();
      _messageRouter.setGlobalListener(_handleGlobalMessage);


      if (_wifiDirectService != null) {
        _setupWiFiDirectSync();

        _setupWiFiDirectMessageStream();
      }

      _addMessageTrace('Main service initialized with userName: $userName');
      debugPrint('✅ P2P Main Service initialized successfully');

      // Setup enhanced monitoring
      _setupEnhancedMonitoring();

      return true;
    } catch (e) {
      debugPrint('❌ P2P Main Service initialization failed: $e');
      _addMessageTrace('Service initialization failed: $e');
      return false;
    }
  }

  WiFiDirectService? get wifiDirectService => _wifiDirectService;

  /// Debounce connection state changes to prevent race conditions
  void _debounceConnectionStateChange(VoidCallback callback) {
    _connectionStateDebounceTimer?.cancel();
    _connectionStateDebounceTimer = Timer(
      _connectionStateDebounceDelay,
      callback,
    );
  }

  void _setupWiFiDirectMessageStream() {
    _wifiDirectService?.messageStream
        .listen((messageData) {
          debugPrint('📨 WiFi Direct message stream received: $messageData');

          final messageType = messageData['type'] as String?;
          if (messageType == 'message_received') {
            final message = messageData['message'] as String?;
            final from = messageData['from'] as String?;

            if (message != null && from != null) {

              final messageHash = '${from}_${message.hashCode}';

              _cleanupMessageDeduplication();

              final now = DateTime.now();
              final existingTimestamp = _messageTimestamps[messageHash];
              if (existingTimestamp != null) {
                final timeDiff = now.difference(existingTimestamp).inSeconds;
                if (timeDiff < 5) {
                  debugPrint(
                    '! Duplicate WiFi Direct message blocked: $messageHash',
                  );
                  return;
                }
              }

              // Mark as processed with current timestamp
              _processedMessages.add(messageHash);
              _messageTimestamps[messageHash] = now;

              _handleIncomingMessage(message, from);
            }
          }
        })
        .onError((error) {
          debugPrint('❌ WiFi Direct message stream error: $error');
        });

    debugPrint(
      '✅ WiFi Direct message stream listener setup complete with deduplication',
    );
  }

  void _setupWiFiDirectSync() {
    _wifiDirectService?.connectionStream.listen((connectionState) {
      debugPrint('🔗 WiFi Direct connection state changed: $connectionState');

      // Use a debounce mechanism to avoid rapid state changes
      _debounceConnectionStateChange(() {
        if (connectionState == WiFiDirectConnectionState.connected) {
          _currentConnectionMode = P2PConnectionMode.wifiDirect;
          updateConnectionStatus(true);
          _refreshConnectedPeers();
        } else if (connectionState == WiFiDirectConnectionState.disconnected) {
          if (_currentConnectionMode == P2PConnectionMode.wifiDirect) {
            _currentConnectionMode = P2PConnectionMode.none;
            updateConnectionStatus(false);
            _clearWiFiDirectDevices();
          }
        }
        notifyListeners();
      });
    });

    _wifiDirectService?.peersStream.listen((peers) {
      debugPrint('👥 WiFi Direct peers updated: ${peers.length} peers found');

      // Debounce peer updates to prevent excessive processing
      _peerUpdateDebounceTimer?.cancel();
      _peerUpdateDebounceTimer = Timer(_peerUpdateDebounceDelay, () {
        _updateDiscoveredPeersFromWiFiDirect(peers);
        _checkForNewConnectedPeers(peers);
        _triggerDevicesDiscoveredCallback();
        notifyListeners();
      });
    });

    _wifiDirectService?.stateStream.listen((state) {
      debugPrint('📡 WiFi Direct state update: $state');

      // Handle connection changes
      if (state['connectionChanged'] == true) {
        final connectionInfo = Map<String, dynamic>.from(
          state['connectionInfo'] as Map? ?? {},
        );
        _handleWiFiDirectConnectionChange(connectionInfo);
      }

      if (state['socketReady'] == true) {
        debugPrint('🔌 WiFi Direct socket communication ready');
        _addMessageTrace('WiFi Direct socket established');
      }

      if (state['socketEstablished'] == true) {
        final connectionInfo = Map<String, dynamic>.from(
          state['connectionInfo'] as Map? ?? {},
        );
        debugPrint('✅ Socket established: $connectionInfo');
        _handleSocketEstablished(connectionInfo);
      }

      if (state['existingConnection'] == true) {
        final connectionInfo = Map<String, dynamic>.from(
          state['connectionInfo'] as Map? ?? {},
        );
        debugPrint('🔗 Existing connection detected: $connectionInfo');
        _handleExistingConnection(connectionInfo);
      }

      // Message handling is now done ONLY via messageStream to prevent duplicates
      // Removed duplicate message processing from stateStream

      // Handle new socket events
      if (state['serverSocketReady'] == true) {
        final socketInfo = Map<String, dynamic>.from(
          state['socketInfo'] as Map? ?? {},
        );
        debugPrint('🔌 Server socket ready: $socketInfo');
        _addMessageTrace('Server socket ready on port ${socketInfo['port']}');
      }

      if (state['connectionError'] == true) {
        final error = state['error'] as String?;
        final details = state['details'] as String?;
        debugPrint('❌ Connection error: $error - $details');
        _addMessageTrace('Connection error: $error');

        // Try to recover from connection errors
        _handleConnectionError(error, details);
      }
    });
  }

  void _updateDiscoveredPeersFromWiFiDirect(List<WiFiDirectPeer> peers) {
    for (final peer in peers) {
      final deviceModel = DeviceModel(
        id: peer.deviceAddress,
        deviceId: peer.deviceAddress,
        userName: peer.deviceName,
        isHost: false,
        isOnline: true,
        createdAt: DateTime.now(),
        lastSeen: DateTime.now(),
        isConnected: peer.status == WiFiDirectPeerStatus.connected,
        discoveryMethod: 'wifi_direct',
        deviceAddress: peer.deviceAddress,
        messageCount: 0,
      );

      // Update or add to discovered devices
      final existingIndex = discoveredResQLinkDevices.indexWhere(
        (d) => d.deviceId == deviceModel.deviceId,
      );

      if (existingIndex >= 0) {
        discoveredResQLinkDevices[existingIndex] = deviceModel;
      } else {
        discoveredResQLinkDevices.add(deviceModel);
      }

      if (peer.status == WiFiDirectPeerStatus.connected) {
        debugPrint('➕ Adding connected WiFi Direct peer: ${peer.deviceName}');
        addConnectedDevice(peer.deviceAddress, peer.deviceName);
      }
    }
  }

  /// NEW METHOD: Check for newly connected peers
  void _checkForNewConnectedPeers(List<WiFiDirectPeer> peers) {
    for (final peer in peers) {
      if (peer.status == WiFiDirectPeerStatus.connected) {
        // Check if this peer is already in connected devices
        if (!connectedDevices.containsKey(peer.deviceAddress)) {
          debugPrint(
            '🆕 New WiFi Direct connection detected: ${peer.deviceName}',
          );
          addConnectedDevice(peer.deviceAddress, peer.deviceName);

          // DON'T trigger onDeviceConnected here - wait for socket/handshake completion
          // This prevents duplicate connection notifications from WiFi Direct peer discovery
          debugPrint(
            '⏳ Waiting for socket connection establishment with ${peer.deviceName}',
          );
        }
      }
    }
  }

  /// NEW METHOD: Handle WiFi Direct connection changes
  void _handleWiFiDirectConnectionChange(Map<String, dynamic> connectionInfo) {
    final isConnected = connectionInfo['isConnected'] as bool? ?? false;
    final groupFormed = connectionInfo['groupFormed'] as bool? ?? false;

    debugPrint(
      '🔄 WiFi Direct connection change: connected=$isConnected, groupFormed=$groupFormed',
    );

    if (isConnected && groupFormed) {
      _currentConnectionMode = P2PConnectionMode.wifiDirect;
      updateConnectionStatus(true);

      // Refresh peer list to get connected devices
      _refreshConnectedPeers();
    } else {
      if (_currentConnectionMode == P2PConnectionMode.wifiDirect) {
        _currentConnectionMode = P2PConnectionMode.none;
        updateConnectionStatus(false);
        _clearWiFiDirectDevices();
      }
    }

    notifyListeners();
  }

  Future<void> _refreshConnectedPeers() async {
    try {
      debugPrint('🔄 Refreshing connected WiFi Direct peers...');

      final peers = await _wifiDirectService?.getPeerList() ?? [];

      // Process connected peers
      for (final peerData in peers) {
        final deviceAddress = peerData['deviceAddress'] as String? ?? '';
        final deviceName =
            peerData['deviceName'] as String? ?? 'Unknown Device';
        final statusValue = peerData['status'];
        final statusInt = statusValue is int
            ? statusValue
            : int.tryParse(statusValue.toString()) ?? -1;

        // WiFi Direct status: 0 = connected, 1 = invited, 2 = failed, 3 = available, 4 = unavailable
        if (statusInt == 0 && deviceAddress.isNotEmpty) {
          debugPrint('✅ Found connected peer: $deviceName ($deviceAddress)');

          // Add to connected devices if not already there
          if (!connectedDevices.containsKey(deviceAddress)) {
            addConnectedDevice(deviceAddress, deviceName);
          }

          // Update discovered devices with connected status
          final existingIndex = discoveredResQLinkDevices.indexWhere(
            (d) => d.deviceId == deviceAddress,
          );

          if (existingIndex >= 0) {
            discoveredResQLinkDevices[existingIndex] =
                discoveredResQLinkDevices[existingIndex].copyWith(
                  isConnected: true,
                  lastSeen: DateTime.now(),
                );
          } else {
            // Add as new discovered device
            final deviceModel = DeviceModel(
              id: deviceAddress,
              deviceId: deviceAddress,
              userName: deviceName,
              isHost: false,
              isOnline: true,
              createdAt: DateTime.now(),
              lastSeen: DateTime.now(),
              isConnected: true,
              discoveryMethod: 'wifi_direct',
              deviceAddress: deviceAddress,
            );
            discoveredResQLinkDevices.add(deviceModel);
          }
        }
      }

      // Trigger callbacks
      _triggerDevicesDiscoveredCallback();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error refreshing connected peers: $e');
    }
  }

  /// NEW METHOD: Clear WiFi Direct devices on disconnection
  void _clearWiFiDirectDevices() {
    // Remove WiFi Direct devices from connected devices
    final wifiDirectDevices = connectedDevices.entries
        .where((entry) => entry.value.discoveryMethod == 'wifi_direct')
        .map((entry) => entry.key)
        .toList();

    for (final deviceId in wifiDirectDevices) {
      removeConnectedDevice(deviceId);
    }

    // Update discovered devices connection status
    for (int i = 0; i < discoveredResQLinkDevices.length; i++) {
      final device = discoveredResQLinkDevices[i];
      if (device.discoveryMethod == 'wifi_direct') {
        discoveredResQLinkDevices[i] = device.copyWith(isConnected: false);
      }
    }

    debugPrint('🧹 Cleared WiFi Direct devices from connected list');
  }

  /// Handle socket establishment with proper protocol initialization
  Future<void> _handleSocketEstablished(
    Map<String, dynamic> connectionInfo,
  ) async {
    final isGroupOwner = connectionInfo['isGroupOwner'] as bool? ?? false;
    final groupOwnerAddress =
        connectionInfo['groupOwnerAddress'] as String? ?? '';

    debugPrint(
      '🔌 Socket established - Group Owner: $isGroupOwner, Address: $groupOwnerAddress',
    );

    try {
      // Initialize socket protocol based on role
      if (isGroupOwner) {
        debugPrint('👑 Starting socket server as group owner');
        await _socketProtocol.startServer();
      } else if (groupOwnerAddress.isNotEmpty) {
        // Add this check to ensure we have a valid address
        debugPrint('📱 Connecting to socket server at: $groupOwnerAddress');
        await _socketProtocol.connectToServer(groupOwnerAddress);
      } else {
        debugPrint('⚠️ Cannot connect - no group owner address provided');
        _addMessageTrace('Socket connection failed: no group owner address');
        return;
      }

      // Update connection mode and status
      _currentConnectionMode = P2PConnectionMode.wifiDirect;
      updateConnectionStatus(true);

      _addMessageTrace(
        'Socket protocol initialized (Group Owner: $isGroupOwner)',
      );

      debugPrint('✅ Socket protocol fully established and ready');
    } catch (e) {
      debugPrint('❌ Socket protocol error: $e');
      _addMessageTrace('Socket protocol initialization failed: $e');
    }

    notifyListeners();
  }

  /// Handle existing connection detection
  void _handleExistingConnection(Map<String, dynamic> connectionInfo) {
    final isGroupOwner = connectionInfo['isGroupOwner'] as bool? ?? false;
    final groupOwnerAddress =
        connectionInfo['groupOwnerAddress'] as String? ?? '';

    debugPrint(
      '🔗 Existing connection - Group Owner: $isGroupOwner, Address: $groupOwnerAddress',
    );

    // Update connection mode and status
    _currentConnectionMode = P2PConnectionMode.wifiDirect;
    updateConnectionStatus(true);

    _addMessageTrace(
      'Existing WiFi Direct connection detected (Group Owner: $isGroupOwner)',
    );
    notifyListeners();
  }

  /// Handle incoming WiFi Direct messages with message router integration
  Future<void> _handleIncomingMessage(String message, String? from) async {
    try {
      debugPrint('📨 Processing WiFi Direct message: $message from: $from');

      // Parse message to check if it's a handshake
      try {
        final messageData = jsonDecode(message);
        final messageType = messageData['type'] as String?;

        if (messageType == 'handshake') {
          // Handle handshake directly to establish WiFi Direct connection
          final deviceId = messageData['deviceId'] as String?;
          final userName = messageData['userName'] as String?;
          final deviceName = messageData['deviceName'] as String?;

          if (deviceId != null) {
            // Prevent concurrent processing of the same device
            if (_processingDevices.contains(deviceId)) {
              debugPrint('⚠️ Handshake already being processed for device $deviceId');
              return;
            }

            debugPrint('🤝 Processing WiFi Direct handshake from $deviceId ($userName)');

            // Register device as connected for WiFi Direct (async, don't wait)
            _registerWiFiDirectDevice(deviceId, userName ?? 'Unknown', deviceName ?? 'Unknown Device', from);

            // Send handshake response (async, don't wait)
            _sendHandshakeResponse(deviceId, from);
            return;
          }
        }

        if (messageType == 'handshake_response') {
          // Handle handshake response
          final deviceId = messageData['deviceId'] as String?;
          final userName = messageData['userName'] as String?;
          final deviceName = messageData['deviceName'] as String?;

          if (deviceId != null) {
            // Prevent concurrent processing of the same device
            if (_processingDevices.contains(deviceId)) {
              debugPrint('⚠️ Handshake response already being processed for device $deviceId');
              return;
            }

            debugPrint('🤝 Processing WiFi Direct handshake response from $deviceId ($userName)');
            // Register device as connected (async, don't wait)
            _registerWiFiDirectDevice(deviceId, userName ?? 'Unknown', deviceName ?? 'Unknown Device', from);
            return;
          }
        }
      } catch (parseError) {
        // If not JSON or not a handshake, continue with normal processing
      }

      // Route through MessageRouter for non-handshake messages
      await _messageRouter.routeRawMessage(message, from ?? 'unknown');

      _addMessageTrace('WiFi Direct message routed successfully');
      debugPrint('✅ WiFi Direct message routed successfully via MessageRouter');
    } catch (e) {
      debugPrint('❌ Error routing message: $e');
      _addMessageTrace('Failed to route message: $e');

      // Fallback to direct processing if routing fails
      try {
        await _fallbackMessageProcessing(message, from);
      } catch (fallbackError) {
        debugPrint('❌ Fallback message processing also failed: $fallbackError');
      }
    }
  }

  /// Fallback message processing if router fails
  Future<void> _fallbackMessageProcessing(String message, String? from) async {
    final messageData = Map<String, dynamic>.from(json.decode(message));

    // Extract message details
    final messageText = messageData['message'] as String? ?? message;
    final senderName =
        messageData['senderName'] as String? ?? 'WiFi Direct User';
    final messageType = MessageType.values.firstWhere(
      (type) => type.name == messageData['messageType'],
      orElse: () => MessageType.text,
    );

    // Create message model
    final messageModel = MessageModel.createDirectMessage(
      fromUser: senderName,
      message: messageText,
      deviceId: messageData['deviceId'] ?? 'unknown',
      targetDeviceId: deviceId ?? 'unknown',
      type: messageType,
      isEmergency:
          messageType == MessageType.emergency ||
          messageType == MessageType.sos,
    );

    // Save to database
    await MessageRepository.insertMessage(messageModel);

    // Add to message history
    saveMessageToHistory(messageModel);

    debugPrint('✅ Fallback message processing completed');
  }

  Future<void> checkForExistingConnections() async {
    try {
      debugPrint('🔍 Checking for existing WiFi Direct connections...');

      // Check connection info
      final connectionInfo = await _wifiDirectService?.getConnectionInfo();

      if (connectionInfo != null && connectionInfo['groupFormed'] == true) {
        debugPrint('✅ Existing WiFi Direct connection found!');
        debugPrint('  - Group Owner: ${connectionInfo['isGroupOwner']}');
        debugPrint('  - Group Address: ${connectionInfo['groupOwnerAddress']}');

        _currentConnectionMode = P2PConnectionMode.wifiDirect;
        updateConnectionStatus(true);

        // CRITICAL FIX: Get and process peer list
        await _refreshConnectedPeers();

        // Establish socket if needed
        final socketEstablished = connectionInfo['socketEstablished'] ?? false;
        if (!socketEstablished) {
          debugPrint('🔌 Socket not established, creating now...');
          final success =
              await _wifiDirectService?.establishSocketConnection() ?? false;
          if (success) {
            debugPrint('✅ Socket connection established successfully');
            _addMessageTrace(
              'Socket connection established after system connection',
            );
          } else {
            debugPrint('❌ Failed to establish socket connection');
            _addMessageTrace('Socket establishment failed');
          }
        } else {
          debugPrint('✅ Socket already established');
        }

        notifyListeners();
      } else {
        debugPrint('ℹ️ No existing WiFi Direct connection found');
      }
    } catch (e) {
      debugPrint('❌ Error checking existing connections: $e');
      _addMessageTrace('Error checking connections: $e');
    }
  }

  /// Check for system-level WiFi Direct connections (call when returning from settings)
  Future<void> checkForSystemConnections() async {
    try {
      debugPrint('🔍 Checking for system-level connections...');
      await _wifiDirectService?.checkForSystemConnection();
    } catch (e) {
      debugPrint('❌ Error checking system connection: $e');
    }
  }

  /// Setup enhanced monitoring and verification
  void _setupEnhancedMonitoring() {

    // Check for system connections every 15 seconds
    Timer.periodic(Duration(seconds: 15), (_) {
      checkForSystemConnections();
    });
  }





  Future<bool> connectToDevice(Map<String, dynamic> device) async {
    try {
      debugPrint('🔗 Attempting to connect to device: ${device['deviceName']}');

      final connectionType = device['connectionType'] as String?;

      switch (connectionType) {
        case 'wifi_direct':
          return await _connectViaWifiDirect(device);
        case 'mdns':
        case 'mdns_enhanced':
          return await _connectViaMDNS(device);
        default:
          debugPrint('⚠️ Unknown connection type: $connectionType');
          return false;
      }
    } catch (e) {
      debugPrint('❌ Device connection failed: $e');
      return false;
    }
  }

  Future<bool> _connectViaWifiDirect(Map<String, dynamic> device) async {
    final deviceAddress = device['deviceAddress'] as String?;
    if (deviceAddress == null) return false;

    try {
      debugPrint('📡 Connecting via WiFi Direct to: $deviceAddress');

      // Use WiFiDirectService for actual connection
      final success =
          await _wifiDirectService?.connectToPeer(deviceAddress) ?? false;

      if (success) {
        // Update P2P service state
        _currentConnectionMode = P2PConnectionMode.wifiDirect;
        updateConnectionStatus(true);

        // Add device to connected devices
        final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
        addConnectedDevice(deviceAddress, deviceName);

        // CRITICAL FIX: Initialize socket protocol after WiFi Direct connection
        await _initializeSocketProtocolAfterConnection();

        debugPrint('✅ WiFi Direct connection successful');
        return true;
      } else {
        debugPrint('❌ WiFi Direct connection failed');
        return false;
      }
    } catch (e) {
      debugPrint('❌ WiFi Direct connection failed: $e');
      return false;
    }
  }


  Future<bool> _connectViaMDNS(Map<String, dynamic> device) async {
    debugPrint('📡 Connecting via mDNS to: ${device['deviceName']}');
    return true; // Placeholder
  }

  /// Force device to host role
  Future<void> forceHostRole() async {
    try {
      debugPrint('👑 Forcing host role...');
      setRole(P2PRole.host);
      _currentConnectionMode = P2PConnectionMode.wifiDirect;
      await discoverDevices(force: true);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to force host role: $e');
    }
  }

  /// Force device to client role
  Future<void> forceClientRole() async {
    try {
      debugPrint('📱 Forcing client role...');
      setRole(P2PRole.client);
      await discoverDevices(force: true);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to force client role: $e');
    }
  }

  Future<void> navigateToChat(
    BuildContext context,
    Map<String, dynamic> device,
  ) async {
    await ChatNavigationHelper.navigateToDeviceChat(
      context: context,
      device: device,
      p2pService: this,
    );
  }

  /// Clear forced role
  Future<void> clearForcedRole() async {
    try {
      debugPrint('🔄 Clearing forced role...');
      setRole(P2PRole.none);
      await discoverDevices(force: true);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to clear forced role: $e');
    }
  }

  /// Handle connection errors with recovery mechanisms
  Future<void> _handleConnectionError(String? error, String? details) async {
    debugPrint('🔧 Attempting to recover from connection error: $error');

    try {
      // Reset connection state
      if (_currentConnectionMode == P2PConnectionMode.wifiDirect) {
        _currentConnectionMode = P2PConnectionMode.none;
        updateConnectionStatus(false);
      }

      // Wait a moment before attempting recovery
      await Future.delayed(Duration(seconds: 2));

      // Try to establish new connections
      if (error?.contains('connect') == true ||
          error?.contains('socket') == true) {
        debugPrint('🔄 Retrying WiFi Direct connection...');
        await checkForExistingConnections();

        // If still not connected, try discovery
        if (!isConnected) {
          await discoverDevices(force: true);
        }
      }

      // Trigger fallback mechanisms if available
      if (!isConnected) {
        debugPrint('🔄 Triggering connection fallback...');
        // The fallback manager will handle alternative connection methods
      }
    } catch (e) {
      debugPrint('❌ Connection recovery failed: $e');
      _addMessageTrace('Connection recovery failed: $e');
    }
  }


  /// Get online status
  bool get isOnline => _isOnline;

  /// Get current connection mode
  P2PConnectionMode get currentConnectionMode => _currentConnectionMode;

  /// Get connection type as string
  String get connectionType {
    switch (_currentConnectionMode) {
      case P2PConnectionMode.wifiDirect:
        return 'wifi_direct';
      case P2PConnectionMode.client:
        return 'client';
      default:
        return 'none';
    }
  }


  /// Get connecting status
  bool get isConnecting => _isConnecting;

  /// Update online status
  void updateOnlineStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      debugPrint('🌐 Online status changed to: $online');
      notifyListeners();
    }
  }

  /// Send emergency template message
  Future<void> sendEmergencyTemplate(EmergencyTemplate template) async {
    String message;
    switch (template) {
      case EmergencyTemplate.sos:
        message = '🆘 SOS - Emergency assistance needed!';
      case EmergencyTemplate.trapped:
        message = '🚧 TRAPPED - Cannot move from current location!';
      case EmergencyTemplate.medical:
        message = '🏥 MEDICAL EMERGENCY - Immediate medical attention needed!';
      case EmergencyTemplate.safe:
        message = '✅ SAFE - I am safe and secure';
      case EmergencyTemplate.evacuating:
        message = '🏃 EVACUATING - Moving to safer location';
    }

    await sendMessage(
      message: message,
      type: MessageType.emergency,
      senderName: userName ?? 'Emergency User',
    );
  }

  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting from all connections...');

      // Stop network services
      _networkService.dispose();

      // Reset state
      _currentConnectionMode = P2PConnectionMode.none;
      _isConnecting = false;

      // Clear connected devices
      connectedDevices.clear();

      // Update connection status
      updateConnectionStatus(false);

      debugPrint('✅ Disconnected successfully');
    } catch (e) {
      debugPrint('❌ Disconnect failed: $e');
    }
  }

  /// Get connection information
  Map<String, dynamic> getConnectionInfo() {
    return {
      'deviceId': deviceId,
      'userName': userName,
      'role': currentRole.name,
      'isConnected': isConnected,
      'emergencyMode': emergencyMode,
      'connectedDevices': connectedDevices.length,
      'discoveredDevices': discoveredResQLinkDevices.length,
    };
  }

  /// Get enhanced connection info
  Map<String, dynamic> getEnhancedConnectionInfo() {
    final networkStatus = _networkService.getNetworkStatus();
    final discoveryStatus = _discoveryService.getDiscoveryStatus();

    return {
      ...getConnectionInfo(),
      'networkStatus': networkStatus,
      'discoveryStatus': discoveryStatus,
      'messageTrace': getMessageTrace(),
      'detailedStatus': getDetailedStatus(),
    };
  }

  Map<String, Map<String, dynamic>> get discoveredDevices {
    final deviceMap = <String, Map<String, dynamic>>{};

    // Add WiFi Direct peers with actual signal strength and connection status
    for (final peer in (_wifiDirectService?.discoveredPeers ?? <dynamic>[])) {
      final isConnected = peer.status == WiFiDirectPeerStatus.connected;

      // CRITICAL FIX: Use custom device name with priority:
      // 1. Handshake name (if connected)
      // 2. Service discovery name (DNS-SD broadcast - before connection)
      // 3. System WiFi Direct name (fallback)
      final connectedDevice = connectedDevices[peer.deviceAddress];
      final customNameFromDiscovery = _wifiDirectService?.getCustomName(peer.deviceAddress);
      final displayName = connectedDevice?.userName ??
                         customNameFromDiscovery ??
                         peer.deviceName;

      deviceMap[peer.deviceAddress] = {
        'deviceId': peer.deviceAddress,
        'deviceName': displayName, // Use custom name from handshake if available
        'deviceAddress': peer.deviceAddress,
        'connectionType': 'wifi_direct',
        'isAvailable':
            peer.status == WiFiDirectPeerStatus.available || isConnected,
        'signalLevel': peer.signalLevel ?? -50,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'isConnected': isConnected,
        'status': peer.status.toString(), // Add WiFi Direct status
        'isEmergency':
            displayName.toLowerCase().contains('resqlink') ||
            displayName.toLowerCase().contains('emergency'),
      };
    }

    // Add ResQLink devices from discovery service (don't overwrite WiFi Direct devices)
    for (final device in discoveredResQLinkDevices) {
      if (!deviceMap.containsKey(device.deviceId)) {
        deviceMap[device.deviceId] = {
          'deviceId': device.deviceId,
          'deviceName': device.userName,
          'deviceAddress': device.deviceAddress ?? device.deviceId,
          'connectionType': device.discoveryMethod ?? 'unknown',
          'isAvailable': !device.isConnected,
          'signalLevel': _calculateSignalStrength(device),
          'lastSeen': device.lastSeen.millisecondsSinceEpoch,
          'isConnected': device.isConnected,
          'isEmergency': device.userName.toLowerCase().contains('emergency'),
        };
      } else {
        // Merge information if device exists in both lists
        final existing = deviceMap[device.deviceId]!;
        deviceMap[device.deviceId] = {
          ...existing,
          'isConnected': device.isConnected || existing['isConnected'],
          'lastSeen': device.lastSeen.millisecondsSinceEpoch,
        };
      }
    }


    // Final step: Override device names with connected device names (real names from handshake)
    for (final connectedDevice in connectedDevices.values) {
      if (deviceMap.containsKey(connectedDevice.deviceId)) {
        deviceMap[connectedDevice.deviceId] = {
          ...deviceMap[connectedDevice.deviceId]!,
          'deviceName': connectedDevice
              .userName, // Use real name from connection handshake
          'isConnected': true,
          'isOnline': connectedDevice.isOnline,
        };
        debugPrint(
          '🔄 Updated device name from connection: ${connectedDevice.userName} (${connectedDevice.deviceId})',
        );
      }
    }

    return deviceMap;
  }

  /// Calculate signal strength for non-WiFi Direct devices
  int _calculateSignalStrength(DeviceModel device) {
    // Base signal strength on discovery method and recency
    final timeDiff = DateTime.now().difference(device.lastSeen).inMinutes;

    switch (device.discoveryMethod) {
      case 'mdns':
      case 'mdns_enhanced':
        return -45 - (timeDiff * 2); // Strong for local network
      case 'broadcast':
        return -55 - (timeDiff * 3); // Medium for broadcast
     
      default:
        return -70 - (timeDiff * 5); // Weak for unknown
    }
  }

  /// Trigger devices discovered callback
  void _triggerDevicesDiscoveredCallback() {
    if (onDevicesDiscovered != null) {
      final allDevices = discoveredDevices.values.toList();
      onDevicesDiscovered!(allDevices);
    }
  }


  Map<String, DeviceModel> get knownDevices {
    final knownMap = <String, DeviceModel>{};

    // Add discovered devices as known devices
    for (final device in discoveredResQLinkDevices) {
      knownMap[device.deviceId] = device;
    }

    // Add connected devices
    for (final device in connectedDevices.values) {
      knownMap[device.deviceId] = device;
    }

    return knownMap;
  }


  @override
  Future<void> discoverDevices({bool force = false}) async {
    try {
      debugPrint('🔍 Starting enhanced device discovery...');

      // Clear old devices if forcing discovery
      if (force) {
        discoveredResQLinkDevices.clear();
      }

      // Use WiFi Direct discovery
      await _wifiDirectService?.startDiscovery();

      // Also use existing discovery service
      await _discoveryService.discoverDevices(force: force);


      // Trigger callback with all discovered devices
      _triggerDevicesDiscoveredCallback();

      debugPrint(
        '✅ Enhanced device discovery completed - found ${discoveredDevices.length} devices',
      );
    } catch (e) {
      debugPrint('❌ Device discovery failed: $e');
    }
  }

  @override
  Future<void> sendMessage({
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
    String? senderName,
    String? id,
    int? ttl,
    List<String>? routePath,
  }) async {
    try {
      _addMessageTrace('Sending message: $message (type: ${type.name})');

      // Use actual userName from service
      final actualSenderName = userName ?? senderName ?? 'Unknown User';

      debugPrint('📤 Sending message: "$message" from: $actualSenderName');

      // Create message model
      final messageModel = targetDeviceId != null
          ? MessageModel.createDirectMessage(
              fromUser: actualSenderName,
              message: message,
              deviceId: deviceId!,
              targetDeviceId: targetDeviceId,
              type: type,
              isEmergency:
                  type == MessageType.emergency || type == MessageType.sos,
              latitude: latitude,
              longitude: longitude,
            )
          : MessageModel.createBroadcastMessage(
              fromUser: actualSenderName,
              message: message,
              deviceId: deviceId!,
              type: type,
              isEmergency:
                  type == MessageType.emergency || type == MessageType.sos,
              latitude: latitude,
              longitude: longitude,
            );

      // Save to database first
      await MessageRepository.insertMessage(messageModel);

      // Add to message history
      saveMessageToHistory(messageModel);

      // Create message JSON for network transmission
      final messageJson = jsonEncode({
        'type': 'message',
        'messageId': messageModel.messageId,
        'message': message,
        'senderName': actualSenderName,
        'deviceId': deviceId,
        'targetDeviceId': targetDeviceId,
        'messageType': type.name,
        'timestamp': messageModel.timestamp,
        'isEmergency': type == MessageType.emergency || type == MessageType.sos,
        'latitude': latitude,
        'longitude': longitude,
      });

      // Send immediately - message queue functionality removed
      if (!isConnected) {
        debugPrint('📥 Device not connected, message will not be queued');

        // Update status to failed instead of queuing
        await MessageRepository.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.failed,
        );

        _addMessageTrace('Message failed - device not connected');
        throw Exception('Device not connected');
      }

      bool success = false;

      final hasConnectedDevices = connectedDevices.isNotEmpty;

      if (hasConnectedDevices && _wifiDirectService != null) {
        // Send via WiFi Direct
        if (targetDeviceId != null) {
          // Send to specific device
          success = await _wifiDirectService!.sendMessage(messageJson);
        } else {
          // Broadcast to all WiFi Direct devices
          success = await _wifiDirectService!.sendMessage(messageJson);
        }
        debugPrint('📡 Message sent via WiFi Direct: $success');
      } else {
        // Fallback to socket protocol
        switch (_currentConnectionMode) {
          case P2PConnectionMode.wifiDirect:
            success = await _socketProtocol.sendMessage(
              messageJson,
              targetDeviceId,
            );

          default:
            success = await _socketProtocol.broadcastMessage(messageJson);
        }
      }

      if (success) {
        await MessageRepository.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.sent,
        );
        _addMessageTrace(
          'Message sent successfully: ${messageModel.messageId}',
        );
      } else {
        debugPrint('❌ Primary send failed, message queue disabled');

        // Update status to failed instead of queuing
        await MessageRepository.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.failed,
        );

        _addMessageTrace('Message send failed');
        throw Exception('Message send failed');
      }

      debugPrint('✅ Message processing completed');
    } catch (e) {
      _addMessageTrace('Message send failed: $e');
      debugPrint('❌ Message send failed: $e');
      rethrow;
    }
  }


  /// Initialize socket protocol after successful WiFi Direct connection
  Future<void> _initializeSocketProtocolAfterConnection() async {
    try {
      debugPrint(
        '🔌 Initializing socket protocol after WiFi Direct connection...',
      );

      // Get WiFi Direct connection info to determine role
      final connectionInfo = await _wifiDirectService?.getConnectionInfo();
      final isGroupOwner = connectionInfo?['isGroupOwner'] ?? false;
      final groupOwnerAddress = connectionInfo?['groupOwnerAddress'] ?? '';

      if (isGroupOwner) {
        debugPrint('👑 Starting socket server as group owner');
        await _socketProtocol.startServer();
      } else if (groupOwnerAddress.isNotEmpty) {
        debugPrint('📱 Connecting to socket server at: $groupOwnerAddress');
        await _socketProtocol.connectToServer(groupOwnerAddress);
      } else {
        debugPrint(
          '⚠️ Cannot determine socket connection - trying server mode',
        );
        await _socketProtocol.startServer();
      }

      debugPrint('✅ Socket protocol initialized successfully');
      _addMessageTrace(
        'Socket protocol initialized after WiFi Direct connection',
      );
    } catch (e) {
      debugPrint('❌ Socket protocol initialization failed: $e');
      _addMessageTrace('Socket protocol initialization error: $e');
    }
  }

  /// Clean up old message deduplication entries
  void _cleanupMessageDeduplication() {
    final cutoff = DateTime.now().subtract(_messageDedupWindow);
    final toRemove = <String>[];

    _messageTimestamps.forEach((messageHash, timestamp) {
      if (timestamp.isBefore(cutoff)) {
        toRemove.add(messageHash);
      }
    });

    for (final messageHash in toRemove) {
      _processedMessages.remove(messageHash);
      _messageTimestamps.remove(messageHash);
    }

    if (toRemove.isNotEmpty) {
      debugPrint('🧹 Cleaned up ${toRemove.length} old message entries from WiFi Direct deduplication');
    }

    // Also cleanup any stale processing entries (devices being processed for > 10 seconds)
    _processingDevices.removeWhere((deviceId) {
      // In practice, handshake processing should complete within seconds
      // This is a safety cleanup for any stuck entries
      return true; // For now, just clear old entries on each cleanup
    });

    // Clear handshake responses tracking periodically to allow re-handshaking if needed
    if (toRemove.isNotEmpty) {
      _handshakeResponsesSent.clear();
    }
  }

  /// Add message trace for debugging
  void _addMessageTrace(String trace) {
    final timestamp = DateTime.now().toIso8601String();
    _messageTrace.add('[$timestamp] $trace');

    // Keep only last 100 entries
    if (_messageTrace.length > 100) {
      _messageTrace.removeAt(0);
    }
  }

  /// Get message trace for debugging
  List<String> getMessageTrace() => List.from(_messageTrace);

  /// Register WiFi Direct device as connected
  Future<void> _registerWiFiDirectDevice(String deviceId, String userName, String deviceName, String? from) async {
    try {
      debugPrint('📱 Registering WiFi Direct device: $deviceId ($userName) from $from');

      // Use the base class method to add connected device (this handles deduplication)
      addConnectedDevice(deviceId, userName);

      // Also register with socket protocol for message sending
      if (from != null) {
        _socketProtocol.registerWiFiDirectDevice(deviceId, from);
      }

      debugPrint('✅ Successfully registered WiFi Direct device: $deviceId ($userName)');
      _addMessageTrace('Registered WiFi Direct device: $deviceId ($userName)');

      // Delay notification to prevent UI thread issues
      Future.microtask(() => notifyListeners());
    } catch (e) {
      debugPrint('❌ Error registering WiFi Direct device: $e');
      _addMessageTrace('Error registering WiFi Direct device: $e');
    }
  }

  /// Send handshake response via WiFi Direct
  Future<void> _sendHandshakeResponse(String targetDeviceId, String? address) async {
    try {
      final response = jsonEncode({
        'type': 'handshake_response',
        'deviceId': deviceId,
        'userName': userName,
        'deviceName': 'ResQLink Device',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'protocol_version': '1.0',
      });

      if (_wifiDirectService != null) {
        _wifiDirectService!.sendMessage(response); // Don't await, send immediately
        debugPrint('✅ Sent handshake response to $targetDeviceId');
        _addMessageTrace('Sent handshake response to $targetDeviceId');
      }
    } catch (e) {
      debugPrint('❌ Error sending handshake response: $e');
      _addMessageTrace('Error sending handshake response: $e');
    }
  }

  /// Get detailed service status
  String getDetailedStatus() {
    final networkStatus = _networkService.getNetworkStatus();
    final discoveryStatus = _discoveryService.getDiscoveryStatus();

    return '''
=== P2P Main Service Status ===
Device ID: $deviceId
User Name: $userName
Current Role: $currentRole
Emergency Mode: $emergencyMode
Connected Devices: ${connectedDevices.length}
Discovered Devices: ${discoveredResQLinkDevices.length}

Network Status:
- TCP Server: ${networkStatus['tcpServerActive']}
- HTTP Server: ${networkStatus['httpServerActive']}
- Connected Sockets: ${networkStatus['connectedSockets']}
- WebSocket Connections: ${networkStatus['webSocketConnections']}

Discovery Status:
- Discovery In Progress: ${discoveryStatus['discoveryInProgress']}
- WiFi Direct Available: ${discoveryStatus['wifiDirectAvailable']}
- Discovered Devices: ${discoveryStatus['discoveredDevices']}

Connection Status:
- Mode: WiFi Direct Only

Recent Message Traces:
${_messageTrace.take(5).join('\n')}
''';
  }

  /// Get available ResQLink networks - REMOVED
  List<Map<String, dynamic>> get availableNetworks {
    return [];
  }

  @override
  void dispose() async {
    debugPrint('🗑️ P2P Main Service disposing...');

    _connectionStateDebounceTimer?.cancel();
    _peerUpdateDebounceTimer?.cancel();

    _networkService.dispose();
    _discoveryService.dispose();
    // Message queue service disposal removed


    _messageTrace.clear();
    _processedMessages.clear();
    _messageTimestamps.clear();

    super.dispose();
  }

  /// Handle global messages from message router
  void _handleGlobalMessage(MessageModel message) {
    // Notify UI listeners
    onMessageReceived?.call(message);

    // Save to history
    saveMessageToHistory(message);

    notifyListeners();
  }

  @override
  String generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode;
    return 'msg_${timestamp}_${deviceId.hashCode}_$random';
  }

  /// Get message router for external access
  MessageRouter get messageRouter => _messageRouter;

  /// Get socket protocol for external access
  SocketProtocol get socketProtocol => _socketProtocol;

  /// Use ChatNavigationHelper statically for chat navigation

  // Message queue service getter removed

  /// Manually open WiFi Direct settings
  Future<void> openWiFiDirectSettings() async {
    await _wifiDirectService?.openWiFiDirectSettings();
  }
}

// Backwards compatibility typedef
typedef P2PConnectionService = P2PMainService;
