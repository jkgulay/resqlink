import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:resqlink/models/device_model.dart';
import 'package:resqlink/services/p2p/p2p_discovery_service.dart';
import '../../models/message_model.dart';
import 'wifi_direct_service.dart';
import 'p2p_base_service.dart';
import 'p2p_network_service.dart';
import '../../helpers/chat_navigation_helper.dart';
import 'protocols/socket_protocol.dart';
import '../messaging/message_router.dart';
import 'managers/p2p_connection_manager.dart';
import 'handlers/p2p_wifi_direct_handler.dart';
import 'handlers/p2p_message_handler.dart';
import 'managers/p2p_device_manager.dart';
import 'monitoring/connection_quality_monitor.dart';
import 'monitoring/reconnection_manager.dart';
import 'monitoring/device_prioritization.dart';
import 'monitoring/timeout_manager.dart';
import 'managers/identifier_resolver.dart';

class P2PMainService extends P2PBaseService {
  // Core service components
  late P2PNetworkService _networkService;
  late P2PDiscoveryService _discoveryService;
  late SocketProtocol _socketProtocol;
  late MessageRouter _messageRouter;

  // Specialized managers and handlers
  late P2PConnectionManager _connectionManager;
  late P2PWiFiDirectHandler _wifiDirectHandler;
  late P2PMessageHandler _messageHandler;
  late P2PDeviceManager _deviceManager;
  late IdentifierResolver _identifierResolver;

  // Enhanced monitoring and management
  late ConnectionQualityMonitor _qualityMonitor;
  late ReconnectionManager _reconnectionManager;
  late DevicePrioritization _devicePrioritization;
  late TimeoutManager _timeoutManager;

  Timer? _monitoringTimer;
  Timer? _pingTimer;

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

      // Initialize core components
      await _initializeCoreComponents();

      // Initialize specialized managers and handlers
      await _initializeManagers();

      // Setup connections and callbacks
      _setupConnectionsAndCallbacks();

      // Setup enhanced monitoring
      _setupEnhancedMonitoring();

      debugPrint('✅ P2P Main Service initialized successfully');
      return true;
    } catch (e) {
      debugPrint('❌ P2P Main Service initialization failed: $e');
      return false;
    }
  }

  /// Initialize core service components
  Future<void> _initializeCoreComponents() async {
    // Identifier resolver (UUID-based system)
    _identifierResolver = IdentifierResolver();

    // Network and discovery services
    _networkService = P2PNetworkService(this);
    _discoveryService = P2PDiscoveryService(this);
    await _discoveryService.initialize();

    // Socket protocol (UUID-based)
    _socketProtocol = SocketProtocol();
    await _socketProtocol.forceCleanup();
    _socketProtocol.initialize(deviceId!, userName!);

    // Message router
    _messageRouter = MessageRouter();

    // CRITICAL FIX: Register IdentifierResolver with MessageRouter
    // This allows MessageRouter to resolve display names to MAC addresses
    _messageRouter.setIdentifierResolver(_identifierResolver);
    debugPrint('✅ IdentifierResolver registered with MessageRouter');

    // Register P2P service for mesh device registry updates
    _messageRouter.setP2PService(this);
    debugPrint(
      '✅ P2PBaseService registered with MessageRouter for mesh updates',
    );

    debugPrint('✅ Core components initialized');
  }

  /// Initialize specialized managers and handlers
  Future<void> _initializeManagers() async {
    // Connection manager
    _connectionManager = P2PConnectionManager(this);

    // WiFi Direct handler
    _wifiDirectHandler = P2PWiFiDirectHandler(
      this,
      _connectionManager,
      _socketProtocol,
    );
    await _wifiDirectHandler.initialize();

    // Message handler
    _messageHandler = P2PMessageHandler(
      this,
      _messageRouter,
      _socketProtocol,
      _wifiDirectHandler,
    );

    // Device manager
    _deviceManager = P2PDeviceManager(this, _connectionManager);
    _deviceManager.setWiFiDirectService(_wifiDirectHandler.wifiDirectService);

    // Enhanced monitoring and management
    _qualityMonitor = ConnectionQualityMonitor();
    _reconnectionManager = ReconnectionManager(
      maxReconnectionAttempts: emergencyMode ? 10 : 5,
      initialDelay: Duration(seconds: emergencyMode ? 1 : 2),
    );
    _devicePrioritization = DevicePrioritization();
    _timeoutManager = TimeoutManager(
      config: emergencyMode ? TimeoutConfig.emergency() : TimeoutConfig(),
    );

    debugPrint('✅ Managers and handlers initialized');
  }

  /// Setup connections and callbacks between components
  void _setupConnectionsAndCallbacks() {
    // UUID-based system - no MAC address updates needed

    // Socket protocol callbacks
    _socketProtocol.onDeviceConnected = (deviceId, userName) {
      debugPrint(
        '🔗 Device connected via SocketProtocol: $userName ($deviceId)',
      );
      addConnectedDevice(deviceId, userName);
      _broadcastGroupRoster();
    };

    _socketProtocol.onDeviceSocketDisconnected = (deviceId) {
      removeConnectedDevice(deviceId);
      _broadcastGroupRoster();
    };

    _socketProtocol.onGroupStateReceived = (devices) {
      applyGroupRoster(devices);
    };
    _socketProtocol.onPongReceived = (deviceId, sequence) {
      _qualityMonitor.recordPingReceived(deviceId, sequence);
    };

    // WiFi Direct handler callbacks
    _wifiDirectHandler.onMessageReceived = (message, from) {
      _messageHandler.handleIncomingMessage(message, from);
    };

    _wifiDirectHandler.onConnectionChanged = () {
      notifyListeners();
    };

    _wifiDirectHandler.onPeersUpdated = (peers) {
      _deviceManager.triggerDevicesDiscoveredCallback();
      notifyListeners();
    };

    _wifiDirectHandler.onDeviceRegistered = (deviceId, userName) {
      // Delay notification to prevent UI thread issues
      Future.microtask(() => notifyListeners());
    };

    // Connection manager callbacks
    _connectionManager.onConnectionStateChanged = () {
      notifyListeners();
    };

    _connectionManager.onPeerListUpdated = () {
      notifyListeners();
    };

    // Message handler callbacks
    _messageHandler.onMessageProcessed = (message) {
      notifyListeners();
    };

    // Device manager callbacks
    _deviceManager.onDevicesDiscovered = (devices) {
      if (onDevicesDiscovered != null) {
        onDevicesDiscovered!(devices);
      }
    };

    // Quality monitor callbacks
    _qualityMonitor.onQualityChanged = (deviceId, quality) {
      debugPrint(
        '📊 Quality changed for $deviceId: ${quality.level.name} (RTT: ${quality.rtt.toStringAsFixed(1)}ms)',
      );
    };

    _qualityMonitor.onConnectionDegraded = (deviceId) {
      debugPrint(
        '⚠️ Connection degraded for $deviceId, considering reconnection',
      );
      // Optionally trigger reconnection for degraded connections
    };

    // Reconnection manager callbacks
    _reconnectionManager.onReconnectAttempt = (deviceId, deviceInfo) async {
      debugPrint('🔄 Attempting to reconnect to $deviceId');
      return await connectToDevice(deviceInfo);
    };

    _reconnectionManager.onReconnectionSuccess = (deviceId) {
      debugPrint('✅ Successfully reconnected to $deviceId');
    };

    _reconnectionManager.onReconnectionFailed = (deviceId) {
      debugPrint('❌ Failed to reconnect to $deviceId after maximum attempts');
    };

    // Timeout manager callbacks
    _timeoutManager.onTimeout = (id, operation) {
      debugPrint('⏰ ${operation.name} timeout: $id');
    };

    debugPrint('✅ Connections and callbacks setup complete');
  }

  /// Setup enhanced monitoring and verification
  void _setupEnhancedMonitoring() {
    // Start connection quality monitoring
    _qualityMonitor.startMonitoring();

    // Broadcast group roster IMMEDIATELY if we're the group owner
    // This ensures clients have topology info right away
    _broadcastGroupRoster();
    debugPrint('📣 Initial group roster broadcast sent');

    // Check for system connections every 15 seconds
    _monitoringTimer = Timer.periodic(Duration(seconds: 15), (_) {
      checkForSystemConnections();
      // Broadcast group roster periodically if we're the group owner
      // This ensures all clients know about mesh topology
      _broadcastGroupRoster();
    });

    // Send pings to connected devices every 10 seconds for RTT tracking
    _pingTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _sendPingToConnectedDevices();
    });

    debugPrint('✅ Enhanced monitoring started with immediate roster broadcast');
  }

  /// Send ping messages to all connected devices for quality monitoring
  void _sendPingToConnectedDevices() async {
    // Don't send pings if not fully connected with socket protocol
    if (connectedDevices.isEmpty || !_socketProtocol.isConnected) {
      return;
    }

    for (final entry in connectedDevices.entries) {
      final deviceId = entry.key;

      try {
        final pingMessage = _qualityMonitor.generatePingMessage(deviceId);
        _qualityMonitor.recordPingSent(deviceId);

        // Send directly via socket protocol (not through message handler)
        final success = await _socketProtocol.sendMessage(
          jsonEncode(pingMessage),
          deviceId,
        );

        if (!success) {
          _qualityMonitor.recordPacketTimeout(deviceId);
        }
      } catch (e) {
        _qualityMonitor.recordPacketTimeout(deviceId);
        // Don't log ping timeouts as errors - they're expected for quality monitoring
      }
    }
  }

  // ============================================================================
  // Public API Methods - Delegates to specialized managers/handlers
  // ============================================================================

  /// Get WiFi Direct service instance
  WiFiDirectService? get wifiDirectService =>
      _wifiDirectHandler.wifiDirectService;

  /// Get online status
  bool get isOnline => _connectionManager.isOnline;

  /// Get current connection mode
  P2PConnectionMode get currentConnectionMode =>
      _connectionManager.currentConnectionMode;

  /// Get connection type as string
  String get connectionType => _connectionManager.connectionType;

  /// Get connecting status
  bool get isConnecting => _connectionManager.isConnecting;

  /// Update online status
  void updateOnlineStatus(bool online) {
    _connectionManager.updateOnlineStatus(online);
  }

  /// Get discovered devices
  Map<String, Map<String, dynamic>> get discoveredDevices {
    return _deviceManager.discoveredDevices;
  }

  /// Get known devices
  Map<String, DeviceModel> get knownDevices {
    return _deviceManager.knownDevices;
  }

  /// Discover devices with timeout and prioritization
  @override
  Future<void> discoverDevices({bool force = false}) async {
    try {
      debugPrint('🔍 Starting enhanced device discovery...');

      if (force) {
        _deviceManager.clearDiscoveredDevices();
      }

      // Wrap discovery with timeout
      await _timeoutManager.withTimeout(
        timeoutType: TimeoutOperation.discovery,
        operation: () async {
          // Use WiFi Direct discovery
          await _wifiDirectHandler.startDiscovery();

          // Also use existing discovery service
          await _discoveryService.discoverDevices(force: force);
        },
      );

      // Trigger callback with all discovered devices
      _deviceManager.triggerDevicesDiscoveredCallback();

      debugPrint(
        '✅ Enhanced device discovery completed - found ${discoveredDevices.length} devices',
      );
    } catch (e) {
      debugPrint('❌ Device discovery failed: $e');
    }
  }

  /// Connect to a device with timeout and quality tracking
  Future<bool> connectToDevice(Map<String, dynamic> device) async {
    final deviceId =
        device['deviceId'] as String? ?? device['deviceAddress'] as String?;
    if (deviceId == null) {
      debugPrint('❌ Cannot connect: device ID not found');
      return false;
    }

    try {
      // Wrap connection with timeout
      final success = await _timeoutManager.withTimeout(
        timeoutType: TimeoutOperation.connection,
        operation: () async {
          return await _deviceManager.connectToDevice(device);
        },
      );

      if (success) {
        // Start tracking connection quality for this device
        final signalLevel = device['signalLevel'] as int? ?? -70;
        _qualityMonitor.updateSignalStrength(deviceId, signalLevel);
        debugPrint('✅ Connected to $deviceId, monitoring quality');
      }

      return success;
    } on TimeoutException {
      debugPrint('⏰ Connection to $deviceId timed out');
      return false;
    } catch (e) {
      debugPrint('❌ Connection to $deviceId failed: $e');
      return false;
    }
  }

  /// Get prioritized list of devices to connect to
  List<String> getPrioritizedDevices() {
    final deviceFactors = <String, DevicePriorityFactors>{};

    for (final entry in discoveredDevices.entries) {
      final device = entry.value;
      final deviceId = entry.key;

      final factors = DevicePriorityFactors(
        isEmergency: device['isEmergency'] as bool? ?? false,
        signalStrength: device['signalLevel'] as int? ?? -70,
        rtt: _qualityMonitor.getAverageRtt(deviceId),
        packetLoss: _qualityMonitor.getDeviceQuality(deviceId)?.packetLoss,
        connectionQuality: _qualityMonitor.getDeviceQuality(deviceId)?.level,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
          device['lastSeen'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
        isPreviouslyConnected: knownDevices.containsKey(deviceId),
        messageCount: knownDevices[deviceId]?.messageCount ?? 0,
      );

      deviceFactors[deviceId] = factors;
    }

    return _devicePrioritization
        .prioritizeDevices(deviceFactors)
        .map((p) => p.deviceId)
        .toList();
  }

  /// Connect to best available device based on priority
  Future<bool> connectToBestDevice() async {
    final prioritized = getPrioritizedDevices();
    if (prioritized.isEmpty) {
      debugPrint('❌ No devices available to connect');
      return false;
    }

    final bestDeviceId = prioritized.first;
    final device = discoveredDevices[bestDeviceId];
    if (device == null) {
      debugPrint('❌ Best device not found');
      return false;
    }

    debugPrint('🎯 Connecting to best device: $bestDeviceId');
    return await connectToDevice(device);
  }

  /// Send a message
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
    await _messageHandler.sendMessage(
      message: message,
      type: type,
      targetDeviceId: targetDeviceId,
      latitude: latitude,
      longitude: longitude,
      senderName: senderName,
      id: id,
      ttl: ttl,
      routePath: routePath,
    );
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

  /// Check for existing WiFi Direct connections
  Future<void> checkForExistingConnections() async {
    await _wifiDirectHandler.checkForExistingConnections();
  }

  /// Check for system-level WiFi Direct connections
  Future<void> checkForSystemConnections() async {
    await _wifiDirectHandler.checkForSystemConnections();
  }

  Future<void> forceHostRole() async {
    try {
      debugPrint('👑 Forcing host role...');
      setRole(P2PRole.host);
      _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to force host role: $e');
    }
  }

  Future<void> forceClientRole() async {
    try {
      debugPrint('📱 Forcing client role...');
      setRole(P2PRole.client);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to force client role: $e');
    }
  }

  /// Clear forced role
  Future<void> clearForcedRole() async {
    try {
      debugPrint('🔄 Clearing forced role...');
      setRole(P2PRole.none);
      // Don't call discoverDevices here
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to clear forced role: $e');
    }
  }

  /// Navigate to chat
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

  /// Disconnect from all connections
  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting from all connections...');

      // Stop reconnection attempts
      _reconnectionManager.stopAll();

      // Stop network services
      _networkService.dispose();

      // Reset connection manager
      _connectionManager.reset();

      // Clear connected devices
      connectedDevices.clear();

      // Clear quality monitoring for disconnected devices
      _qualityMonitor.clearAll();

      debugPrint('✅ Disconnected successfully');
    } catch (e) {
      debugPrint('❌ Disconnect failed: $e');
    }
  }

  /// Handle device disconnection with optional reconnection
  Future<void> handleDeviceDisconnection(
    String deviceId,
    Map<String, dynamic>? deviceInfo,
  ) async {
    debugPrint('📡 Device $deviceId disconnected');

    // Check if we should attempt reconnection
    final quality = _qualityMonitor.getDeviceQuality(deviceId);
    final wasHealthy = quality?.isHealthy ?? true;

    if (wasHealthy && deviceInfo != null && !emergencyMode) {
      // Device had good connection quality, attempt reconnection
      debugPrint('🔄 Starting automatic reconnection for $deviceId');
      _reconnectionManager.startReconnection(deviceId, deviceInfo);
    } else if (emergencyMode && deviceInfo != null) {
      // In emergency mode, always try to reconnect
      debugPrint('🚨 Emergency mode: forcing reconnection for $deviceId');
      _reconnectionManager.startReconnection(deviceId, deviceInfo);
    }
  }

  /// Get connection information with quality metrics
  Map<String, dynamic> getConnectionInfo() {
    final baseInfo = {
      'deviceId': deviceId,
      'userName': userName,
      'role': currentRole.name,
      'isConnected': isConnected,
      'emergencyMode': emergencyMode,
      'connectedDevices': connectedDevices.length,
      'discoveredDevices': discoveredResQLinkDevices.length,
    };

    final connectionInfo = _connectionManager.getConnectionInfo();

    return {...baseInfo, ...connectionInfo};
  }

  /// Get enhanced connection info with quality and reconnection stats
  Map<String, dynamic> getEnhancedConnectionInfo() {
    final networkStatus = _networkService.getNetworkStatus();
    final discoveryStatus = _discoveryService.getDiscoveryStatus();

    return {
      ...getConnectionInfo(),
      'networkStatus': networkStatus,
      'discoveryStatus': discoveryStatus,
      'messageTrace': _messageHandler.getMessageTrace(),
      'detailedStatus': getDetailedStatus(),
      'deviceStats': _deviceManager.getDeviceStats(),
      'qualityStats': _qualityMonitor.getStatistics(),
      'reconnectionStats': _reconnectionManager.getStatistics(),
      'timeoutStats': _timeoutManager.getStatistics(),
    };
  }

  /// Get connection quality for a specific device
  ConnectionQuality? getDeviceQuality(String deviceId) {
    return _qualityMonitor.getDeviceQuality(deviceId);
  }

  /// Get all device qualities
  Map<String, ConnectionQuality> getAllDeviceQualities() {
    return _qualityMonitor.getAllQualities();
  }

  /// Check if reconnecting to a device
  bool isReconnecting(String deviceId) {
    return _reconnectionManager.isReconnecting(deviceId);
  }

  /// Get list of devices currently reconnecting
  List<String> getReconnectingDevices() {
    return _reconnectionManager.getReconnectingDevices();
  }

  /// Manually trigger reconnection for a device
  void triggerReconnection(String deviceId, Map<String, dynamic> deviceInfo) {
    _reconnectionManager.startReconnection(deviceId, deviceInfo);
  }

  /// Stop reconnection for a device
  void stopReconnection(String deviceId) {
    _reconnectionManager.stopReconnection(deviceId);
  }

  /// Update all device references when MAC address changes
  // UUID-based system - device IDs never change, so this method is not needed

  /// Get detailed service status
  String getDetailedStatus() {
    final networkStatus = _networkService.getNetworkStatus();
    final discoveryStatus = _discoveryService.getDiscoveryStatus();
    final connectionInfo = _connectionManager.getConnectionInfo();
    final deviceStats = _deviceManager.getDeviceStats();

    return '''
=== P2P Main Service Status ===
Device ID: $deviceId
User Name: $userName
Current Role: $currentRole
Emergency Mode: $emergencyMode

Connection Info:
${connectionInfo.entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}

Device Stats:
${deviceStats.entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}

Network Status:
- TCP Server: ${networkStatus['tcpServerActive']}
- HTTP Server: ${networkStatus['httpServerActive']}
- Connected Sockets: ${networkStatus['connectedSockets']}
- WebSocket Connections: ${networkStatus['webSocketConnections']}

Discovery Status:
- Discovery In Progress: ${discoveryStatus['discoveryInProgress']}
- WiFi Direct Available: ${discoveryStatus['wifiDirectAvailable']}
- Discovered Devices: ${discoveryStatus['discoveredDevices']}

Recent Message Traces:
${_messageHandler.getMessageTrace().take(5).join('\n')}
''';
  }

  /// Get message router for external access
  MessageRouter get messageRouter => _messageHandler.messageRouter;

  /// Get socket protocol for external access
  SocketProtocol get socketProtocol => _socketProtocol;

  Future<void> _broadcastGroupRoster() async {
    if (!_socketProtocol.isServer) return;

    // ═══════════════════════════════════════════════════════════════
    // GROUP ROSTER BROADCAST
    // The group owner (Device 1) broadcasts the list of all connected
    // devices to all clients. This allows Device 2 and Device 3 to know
    // about each other even though they're not directly connected.
    //
    // Flow:
    // 1. Device 1 (group owner) sees Device 2 and Device 3 directly
    // 2. Device 1 broadcasts roster: [Device 1 (host), Device 2, Device 3]
    // 3. Device 3 receives roster → adds Device 2 to mesh registry (1 hop)
    // 4. Device 2 receives roster → adds Device 3 to mesh registry (1 hop)
    // 5. Now Device 2 and Device 3 know they can communicate via Device 1
    // ═══════════════════════════════════════════════════════════════

    final roster = <Map<String, dynamic>>[];
    if (deviceId != null && userName != null) {
      roster.add({'deviceId': deviceId, 'userName': userName, 'isHost': true});
    }

    connectedDevices.forEach((uuid, device) {
      roster.add({
        'deviceId': uuid,
        'userName': device.userName,
        'isHost': device.isHost,
      });
    });

    if (roster.isEmpty) {
      debugPrint('📣 No devices to broadcast in roster - skipping');
      return;
    }

    debugPrint(
      '📣 ═══════════════════════════════════════════════════════════',
    );
    debugPrint('📣 BROADCASTING GROUP ROSTER (${roster.length} devices):');
    for (final device in roster) {
      debugPrint(
        '   - ${device['userName']} (${device['deviceId']}) ${device['isHost'] == true ? "[HOST]" : "[CLIENT]"}',
      );
    }
    debugPrint(
      '📣 ═══════════════════════════════════════════════════════════',
    );

    await _socketProtocol.broadcastSystemMessage({
      'type': 'group_state',
      'devices': roster,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    debugPrint(
      '📣 Group roster broadcast sent to ${_socketProtocol.connectedDeviceCount} connected clients',
    );
  }

  /// Open WiFi Direct settings
  Future<void> openWiFiDirectSettings() async {
    await _wifiDirectHandler.openWiFiDirectSettings();
  }

  @override
  String generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode;
    return 'msg_${timestamp}_${deviceId.hashCode}_$random';
  }

  /// Get identifier resolver for external access
  IdentifierResolver get identifierResolver => _identifierResolver;

  /// Register device with identifier resolver (UUID + display name)
  void registerDevice(String deviceId, String displayName) {
    _identifierResolver.registerDevice(deviceId, displayName);
  }

  @override
  void dispose() {
    debugPrint('🗑️ P2P Main Service disposing...');

    // Cancel timers
    _monitoringTimer?.cancel();
    _pingTimer?.cancel();

    // Dispose monitoring and management components
    _qualityMonitor.dispose();
    _reconnectionManager.dispose();
    _timeoutManager.dispose();

    // Dispose managers and handlers
    _connectionManager.dispose();
    _wifiDirectHandler.dispose();
    _messageHandler.dispose();
    _deviceManager.dispose();

    // Dispose core services
    _networkService.dispose();
    _discoveryService.dispose();

    super.dispose();

    debugPrint('✅ P2P Main Service disposed completely');
  }
}

typedef P2PConnectionService = P2PMainService;
