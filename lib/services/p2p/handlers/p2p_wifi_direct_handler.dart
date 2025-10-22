import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../wifi_direct_service.dart';
import '../p2p_base_service.dart';
import '../../../models/device_model.dart';
import '../managers/p2p_connection_manager.dart';
import '../protocols/socket_protocol.dart';

/// Handles WiFi Direct integration, events, and peer management
class P2PWiFiDirectHandler {
  final P2PBaseService _baseService;
  final P2PConnectionManager _connectionManager;
  final SocketProtocol _socketProtocol;
  WiFiDirectService? _wifiDirectService;

  // Callbacks
  void Function(List<WiFiDirectPeer>)? onPeersUpdated;
  void Function(String deviceId, String userName)? onDeviceRegistered;
  void Function(String message, String? from)? onMessageReceived;
  VoidCallback? onConnectionChanged;

  P2PWiFiDirectHandler(
    this._baseService,
    this._connectionManager,
    this._socketProtocol,
  );

  /// Initialize WiFi Direct service
  Future<void> initialize() async {
    try {
      _wifiDirectService = WiFiDirectService.instance;
      await _wifiDirectService?.initialize();

      // UUID-based system - no MAC address management needed
      debugPrint('✅ WiFiDirectHandler: Using UUID-based identification');

      _setupWiFiDirectStreams();
      debugPrint('✅ WiFi Direct handler initialized');
    } catch (e) {
      debugPrint('❌ WiFi Direct handler initialization failed: $e');
      rethrow;
    }
  }

  /// Get WiFi Direct service instance
  WiFiDirectService? get wifiDirectService => _wifiDirectService;

  /// Setup WiFi Direct event streams
  void _setupWiFiDirectStreams() {
    _setupConnectionStream();
    _setupPeersStream();
    _setupStateStream();
    _setupMessageStream();
  }

  /// Setup connection state stream
  void _setupConnectionStream() {
    _wifiDirectService?.connectionStream.listen((connectionState) {
      debugPrint('🔗 WiFi Direct connection state changed: $connectionState');

      _connectionManager.debounceConnectionStateChange(() {
        if (connectionState == WiFiDirectConnectionState.connected) {
          _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
          _refreshConnectedPeers();
        } else if (connectionState == WiFiDirectConnectionState.disconnected) {
          if (_connectionManager.currentConnectionMode == P2PConnectionMode.wifiDirect) {
            _connectionManager.setConnectionMode(P2PConnectionMode.none);
            _clearWiFiDirectDevices();
          }
        }
        onConnectionChanged?.call();
      });
    });
  }

  /// Setup peers discovery stream
  void _setupPeersStream() {
    _wifiDirectService?.peersStream.listen((peers) {
      debugPrint('👥 WiFi Direct peers updated: ${peers.length} peers found');

      _connectionManager.debouncePeerUpdate(() {
        _updateDiscoveredPeersFromWiFiDirect(peers);
        _checkForNewConnectedPeers(peers);
        onPeersUpdated?.call(peers);
      });
    });
  }

  /// Setup WiFi Direct state stream
  void _setupStateStream() {
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

      if (state['serverSocketReady'] == true) {
        final socketInfo = Map<String, dynamic>.from(
          state['socketInfo'] as Map? ?? {},
        );
        debugPrint('🔌 Server socket ready: $socketInfo');
      }

      if (state['connectionError'] == true) {
        final error = state['error'] as String?;
        final details = state['details'] as String?;
        debugPrint('❌ Connection error: $error - $details');
        _handleConnectionError(error, details);
      }
    });
  }

  /// Setup message stream (deduplication handled here)
  void _setupMessageStream() {
    _wifiDirectService?.messageStream.listen((messageData) {
      debugPrint('📨 WiFi Direct message stream received: $messageData');

      final messageType = messageData['type'] as String?;
      if (messageType == 'message_received') {
        final message = messageData['message'] as String?;
        final from = messageData['from'] as String?;

        if (message != null && from != null) {
          onMessageReceived?.call(message, from);
        }
      }
    }).onError((error) {
      debugPrint('❌ WiFi Direct message stream error: $error');
    });

    debugPrint('✅ WiFi Direct message stream listener setup complete');
  }

  /// Update discovered peers from WiFi Direct
  void _updateDiscoveredPeersFromWiFiDirect(List<WiFiDirectPeer> peers) {
    for (final peer in peers) {
      // CRITICAL: Use custom display name if available, otherwise fall back to system device name
      final customName = _wifiDirectService?.getCustomName(peer.deviceAddress);
      final displayName = customName ?? peer.deviceName;

      final deviceModel = DeviceModel(
        id: peer.deviceAddress,
        deviceId: peer.deviceAddress,
        userName: displayName,  // Use custom name if available
        isHost: false,
        isOnline: true,
        createdAt: DateTime.now(),
        lastSeen: DateTime.now(),
        isConnected: peer.status == WiFiDirectPeerStatus.connected,
        discoveryMethod: 'wifi_direct',
        deviceAddress: peer.deviceAddress,
        messageCount: 0,
      );

      // Update base service discovered devices
      final existingIndex = _baseService.discoveredResQLinkDevices.indexWhere(
        (d) => d.deviceId == deviceModel.deviceId,
      );

      if (existingIndex >= 0) {
        _baseService.discoveredResQLinkDevices[existingIndex] = deviceModel;
      } else {
        _baseService.discoveredResQLinkDevices.add(deviceModel);
      }

      // UUID-based system: DON'T register devices here with MAC address
      // Wait for socket handshake to exchange UUIDs first
      // The handshake handler will call addConnectedDevice() with the UUID
      if (peer.status == WiFiDirectPeerStatus.connected) {
        debugPrint('🔌 WiFi Direct peer connected: $displayName (${peer.deviceAddress})');
        debugPrint('⏳ Waiting for socket handshake to exchange UUIDs...');
      }
    }
  }

  /// Check for newly connected peers
  void _checkForNewConnectedPeers(List<WiFiDirectPeer> peers) {
    for (final peer in peers) {
      if (peer.status == WiFiDirectPeerStatus.connected) {
        // UUID-based system: Don't register with MAC address
        // Let the socket handshake exchange UUIDs first
        final customName = _wifiDirectService?.getCustomName(peer.deviceAddress);
        final displayName = customName ?? peer.deviceName;

        if (!_baseService.connectedDevices.containsKey(peer.deviceAddress)) {
          debugPrint('🆕 New WiFi Direct connection: $displayName (${peer.deviceAddress})');

          // Wait for socket/handshake completion
          debugPrint(
            '⏳ Waiting for socket connection establishment with ${peer.deviceName}',
          );
        } else {
          debugPrint('ℹ️ WiFi Direct peer already connected, preserving existing name: ${_baseService.connectedDevices[peer.deviceAddress]?.userName}');
        }
      }
    }
  }

  /// Handle WiFi Direct connection changes
  void _handleWiFiDirectConnectionChange(Map<String, dynamic> connectionInfo) {
    final isConnected = connectionInfo['isConnected'] as bool? ?? false;
    final groupFormed = connectionInfo['groupFormed'] as bool? ?? false;

    debugPrint(
      '🔄 WiFi Direct connection change: connected=$isConnected, groupFormed=$groupFormed',
    );

    if (isConnected && groupFormed) {
      _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
      _refreshConnectedPeers();

      // Automatically establish socket connection when group forms
      debugPrint('🔌 Group formed, establishing socket connection...');
      _wifiDirectService?.establishSocketConnection();
    } else {
      if (_connectionManager.currentConnectionMode == P2PConnectionMode.wifiDirect) {
        _connectionManager.setConnectionMode(P2PConnectionMode.none);
        _clearWiFiDirectDevices();
      }
    }

    onConnectionChanged?.call();
  }

  /// Refresh connected WiFi Direct peers
  Future<void> _refreshConnectedPeers() async {
    try {
      debugPrint('🔄 Refreshing connected WiFi Direct peers...');

      final peers = await _wifiDirectService?.getPeerList() ?? [];

      for (final peerData in peers) {
        final deviceAddress = peerData['deviceAddress'] as String? ?? '';
        final deviceName =
            peerData['deviceName'] as String? ?? 'Unknown Device';
        final statusValue = peerData['status'];
        final statusInt = statusValue is int
            ? statusValue
            : int.tryParse(statusValue.toString()) ?? -1;

        // WiFi Direct status: 0 = connected
        if (statusInt == 0 && deviceAddress.isNotEmpty) {
          // Use custom display name if available
          final customName = _wifiDirectService?.getCustomName(deviceAddress);
          final displayName = customName ?? deviceName;

          debugPrint('✅ Found connected peer: $displayName ($deviceAddress)');
          debugPrint('⏳ UUID-based system: Waiting for handshake to register device...');

          // Update discovered devices with connected status
          final existingIndex = _baseService.discoveredResQLinkDevices.indexWhere(
            (d) => d.deviceId == deviceAddress,
          );

          if (existingIndex >= 0) {
            _baseService.discoveredResQLinkDevices[existingIndex] =
                _baseService.discoveredResQLinkDevices[existingIndex].copyWith(
                  isConnected: true,
                  lastSeen: DateTime.now(),
                );
          } else {
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
            _baseService.discoveredResQLinkDevices.add(deviceModel);
          }
        }
      }

      onPeersUpdated?.call([]);
    } catch (e) {
      debugPrint('❌ Error refreshing connected peers: $e');
    }
  }

  /// Clear WiFi Direct devices on disconnection
  void _clearWiFiDirectDevices() {
    final wifiDirectDevices = _baseService.connectedDevices.entries
        .where((entry) => entry.value.discoveryMethod == 'wifi_direct')
        .map((entry) => entry.key)
        .toList();

    for (final deviceId in wifiDirectDevices) {
      _baseService.removeConnectedDevice(deviceId);
    }

    for (int i = 0; i < _baseService.discoveredResQLinkDevices.length; i++) {
      final device = _baseService.discoveredResQLinkDevices[i];
      if (device.discoveryMethod == 'wifi_direct') {
        _baseService.discoveredResQLinkDevices[i] = device.copyWith(isConnected: false);
      }
    }

    debugPrint('🧹 Cleared WiFi Direct devices from connected list');
  }

  /// Handle socket establishment
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
      if (isGroupOwner) {
        debugPrint('👑 Starting socket server as group owner');
        await _socketProtocol.startServer();
      } else if (groupOwnerAddress.isNotEmpty) {
        debugPrint('📱 Connecting to socket server at: $groupOwnerAddress');
        await _socketProtocol.connectToServer(groupOwnerAddress);
      } else {
        debugPrint('⚠️ Cannot connect - no group owner address provided');
        return;
      }

      _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
      debugPrint('✅ Socket protocol fully established and ready');
    } catch (e) {
      debugPrint('❌ Socket protocol error: $e');
      debugPrint('🔄 Reverting connection mode due to socket failure');

      // Revert connection state on socket protocol failure
      _connectionManager.setConnectionMode(P2PConnectionMode.none);

      // Schedule retry after delay
      Future.delayed(Duration(seconds: 2), () {
        debugPrint('🔄 Retrying socket establishment...');
        _handleSocketEstablished(connectionInfo);
      });
    }

    onConnectionChanged?.call();
  }

  /// Handle existing connection detection
  void _handleExistingConnection(Map<String, dynamic> connectionInfo) {
    final isGroupOwner = connectionInfo['isGroupOwner'] as bool? ?? false;
    final groupOwnerAddress =
        connectionInfo['groupOwnerAddress'] as String? ?? '';

    debugPrint(
      '🔗 Existing connection - Group Owner: $isGroupOwner, Address: $groupOwnerAddress',
    );

    _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
    onConnectionChanged?.call();
  }

  /// Handle connection errors
  void _handleConnectionError(String? error, String? details) {
    debugPrint('🔧 Handling connection error: $error - $details');

    if (_connectionManager.currentConnectionMode == P2PConnectionMode.wifiDirect) {
      _connectionManager.setConnectionMode(P2PConnectionMode.none);
    }
  }

  /// Check for existing WiFi Direct connections
  Future<void> checkForExistingConnections() async {
    try {
      debugPrint('🔍 Checking for existing WiFi Direct connections...');

      final connectionInfo = await _wifiDirectService?.getConnectionInfo();

      if (connectionInfo != null && connectionInfo['groupFormed'] == true) {
        debugPrint('✅ Existing WiFi Direct connection found!');
        debugPrint('  - Group Owner: ${connectionInfo['isGroupOwner']}');
        debugPrint('  - Group Address: ${connectionInfo['groupOwnerAddress']}');

        _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
        await _refreshConnectedPeers();

        final socketEstablished = connectionInfo['socketEstablished'] ?? false;
        if (!socketEstablished) {
          debugPrint('🔌 Socket not established, creating now...');
          final success =
              await _wifiDirectService?.establishSocketConnection() ?? false;
          if (success) {
            debugPrint('✅ Socket connection established successfully');
          } else {
            debugPrint('❌ Failed to establish socket connection');
          }
        } else {
          debugPrint('✅ Socket already established');
        }

        onConnectionChanged?.call();
      } else {
        debugPrint('ℹ️ No existing WiFi Direct connection found');
      }
    } catch (e) {
      debugPrint('❌ Error checking existing connections: $e');
    }
  }

  Future<void> checkForSystemConnections() async {
    try {
      debugPrint('🔍 Checking for system-level connections...');
      await _wifiDirectService?.checkForSystemConnection();
    } catch (e) {
      debugPrint('❌ Error checking system connection: $e');
    }
  }

  Future<bool> connectToPeer(String deviceAddress) async {
    try {
      debugPrint('📡 Connecting via WiFi Direct to: $deviceAddress');

      final success =
          await _wifiDirectService?.connectToPeer(deviceAddress) ?? false;

      if (success) {
        _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);
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

  /// Initialize socket protocol after successful WiFi Direct connection
  Future<void> _initializeSocketProtocolAfterConnection() async {
    try {
      debugPrint(
        '🔌 Initializing socket protocol after WiFi Direct connection...',
      );

      // Wait a moment for connection to stabilize
      await Future.delayed(Duration(milliseconds: 500));

      final connectionInfo = await _wifiDirectService?.getConnectionInfo();

      debugPrint('📋 Connection Info Received:');
      debugPrint('  - Full Info: $connectionInfo');
      debugPrint('  - Is Group Owner: ${connectionInfo?['isGroupOwner']}');
      debugPrint('  - Group Owner Address: ${connectionInfo?['groupOwnerAddress']}');

      final isGroupOwner = connectionInfo?['isGroupOwner'] ?? false;
      final groupOwnerAddress = connectionInfo?['groupOwnerAddress'] ?? '';

      if (isGroupOwner) {
        debugPrint('👑 I am the GROUP OWNER - Starting socket SERVER');
        await _socketProtocol.startServer();
      } else if (groupOwnerAddress.isNotEmpty) {
        debugPrint('📱 I am the CLIENT - Connecting to server at: $groupOwnerAddress');
        await _socketProtocol.connectToServer(groupOwnerAddress);
      } else {
        debugPrint(
          '⚠️ WARNING: Cannot determine group owner info!',
        );
        debugPrint('  - isGroupOwner: $isGroupOwner');
        debugPrint('  - groupOwnerAddress: "$groupOwnerAddress"');
        debugPrint('  - Defaulting to SERVER mode (may cause conflicts)');

        // Try to start server but log warning
        await _socketProtocol.startServer();
      }

      debugPrint('✅ Socket protocol initialized successfully');
    } catch (e) {
      debugPrint('❌ Socket protocol initialization failed: $e');
      debugPrint('🔄 Reverting connection mode due to socket initialization failure');

      // Revert connection state on socket protocol failure
      _connectionManager.setConnectionMode(P2PConnectionMode.none);
    }
  }

  /// Start WiFi Direct discovery
  Future<void> startDiscovery() async {
    try {
      await _wifiDirectService?.startDiscovery();
      debugPrint('🔍 WiFi Direct discovery started');
    } catch (e) {
      debugPrint('❌ Failed to start WiFi Direct discovery: $e');
    }
  }

  /// Stop WiFi Direct discovery
  Future<void> stopDiscovery() async {
    try {
      await _wifiDirectService?.stopDiscovery();
      debugPrint('🛑 WiFi Direct discovery stopped');
    } catch (e) {
      debugPrint('❌ Failed to stop WiFi Direct discovery: $e');
    }
  }

  /// Send handshake response via WiFi Direct
  Future<void> sendHandshakeResponse(
    String targetDeviceId,
    String? address,
  ) async {
    try {
      debugPrint('📤 Preparing handshake response to $targetDeviceId');

      // Get our UUID from base service
      final ourDeviceId = _baseService.deviceId;
      final ourUserName = _baseService.userName;

      if (ourDeviceId == null || ourUserName == null) {
        debugPrint('⚠️ Cannot send handshake response: Device not initialized');
        return;
      }

      debugPrint('   Our UUID: $ourDeviceId');
      debugPrint('   Peer UUID: $targetDeviceId');
      debugPrint('   Our userName: $ourUserName');

      final response = jsonEncode({
        'type': 'handshake_response',
        'deviceId': ourDeviceId,
        'displayName': ourUserName,
        'peerDeviceId': targetDeviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'protocol_version': '3.0',  // v3.0 = UUID-based

        // Legacy fields for backward compatibility
        'macAddress': ourDeviceId,
        'peerMacAddress': targetDeviceId,
        'userName': ourUserName,
        'deviceName': 'ResQLink Device',
      });

      if (_wifiDirectService != null) {
        _wifiDirectService!.sendMessage(response);
        debugPrint('✅ Sent handshake response to $targetDeviceId');
        _connectionManager.markHandshakeResponseSent(targetDeviceId);
      }
    } catch (e) {
      debugPrint('❌ Error sending handshake response: $e');
    }
  }

  /// Register WiFi Direct device as connected
  Future<void> registerWiFiDirectDevice(
    String deviceId,
    String userName,
    String deviceName,
    String? from,
  ) async {
    try {
      debugPrint(
        '📱 Registering WiFi Direct device: $deviceId ($userName) from $from',
      );

      // Try to resolve IP to MAC address from WiFi Direct peers
      String? macAddress;
      if (from != null && _wifiDirectService != null) {
        final ipMatch = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(from);
        if (ipMatch != null) {
          final ipAddress = ipMatch.group(1)!;

          // Look through WiFi Direct peers to find the one with this IP
          final peers = _wifiDirectService!.discoveredPeers;
          if (peers.isNotEmpty) {
            // For simplicity, if there's only one connected peer, use that MAC
            final connectedPeers = peers.where((p) =>
              p.status == WiFiDirectPeerStatus.connected ||
              p.status == WiFiDirectPeerStatus.invited
            ).toList();

            if (connectedPeers.length == 1) {
              macAddress = connectedPeers.first.deviceAddress;
              debugPrint('🔍 Resolved IP $ipAddress to MAC: $macAddress');
            }
          }
        }
      }

      _baseService.addConnectedDevice(deviceId, userName, macAddress: macAddress);

      if (from != null) {
        _socketProtocol.registerWiFiDirectDevice(deviceId, from);
      }

      debugPrint(
        '✅ Successfully registered WiFi Direct device: $deviceId ($userName)',
      );

      onDeviceRegistered?.call(deviceId, userName);
    } catch (e) {
      debugPrint('❌ Error registering WiFi Direct device: $e');
    }
  }

  /// Send message via WiFi Direct
  Future<bool> sendMessage(String message) async {
    try {
      if (_wifiDirectService != null) {
        return await _wifiDirectService!.sendMessage(message);
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error sending message via WiFi Direct: $e');
      return false;
    }
  }

  /// Get custom device name from WiFi Direct service
  String? getCustomDeviceName(String deviceAddress) {
    return _wifiDirectService?.getCustomName(deviceAddress);
  }

  /// Get discovered WiFi Direct peers
  List<dynamic> get discoveredPeers {
    return _wifiDirectService?.discoveredPeers ?? [];
  }

  /// Open WiFi Direct settings
  Future<void> openWiFiDirectSettings() async {
    await _wifiDirectService?.openWiFiDirectSettings();
  }

  /// Dispose and cleanup
  void dispose() {
    debugPrint('🗑️ WiFi Direct handler disposed');
  }
}
