import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wifi_direct_plugin/wifi_direct_plugin.dart';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import '../models/message_model.dart';
import '../services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

class P2PConnectionService with ChangeNotifier {
  static const String serviceType = "_resqlink._tcp";
  static const Duration messageExpiry = Duration(hours: 24);
  static const String emergencyPassword = "RESQLINK911";
  static const Duration autoConnectDelay = Duration(seconds: 5);
  static const int maxTtl = 5;

  // Connection state management
  bool _isDiscovering = false;
  bool _isDisposed = false;
  bool _isConnecting = false;
  DateTime? _lastDiscoveryTime;
  String? _preferredRole; // 'host' or 'client'

  // Device identity and role
  String? _deviceId;
  String? _userName;
  P2PRole _currentRole = P2PRole.none;

  // Singleton instance
  static P2PConnectionService? _instance;

  factory P2PConnectionService() {
    if (_instance == null || _instance!._isDisposed) {
      _instance = P2PConnectionService._internal();
    }
    return _instance!;
  }

  P2PConnectionService._internal();

  // Add reset method for clean recreation
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  // Network state
  final Map<String, ConnectedDevice> _connectedDevices = {};
  final Map<String, DeviceCredentials> _knownDevices = {};
  final Map<String, Map<String, dynamic>> _discoveredDevices = {};
  bool _isConnected = false;
  bool _isGroupOwner = false;
  String? _groupOwnerAddress;

  // Emergency mode with better control
  bool _emergencyMode = false;
  Timer? _autoConnectTimer;
  Timer? _discoveryTimer;
  Timer? _heartbeatTimer;

  // Emergency mode toggle with better control
  bool get emergencyMode => _emergencyMode;
  set emergencyMode(bool value) {
    if (_emergencyMode != value) {
      _emergencyMode = value;
      if (value) {
        _startEmergencyMode();
      } else {
        _stopEmergencyMode();
      }
      notifyListeners();
    }
  }

  // Message handling
  final Set<String> _processedMessageIds = {};
  final Map<String, List<PendingMessage>> _pendingMessages = {};
  final List<P2PMessage> _messageHistory = [];
  Timer? _messageCleanupTimer;
  Timer? _syncTimer;
  Timer? _reconnectTimer;

  // Stream subscriptions
  StreamSubscription? _peersChangeSubscription;
  StreamSubscription? _connectionChangeSubscription;
  StreamSubscription? _connectivitySubscription;

  // Connectivity
  bool _isOnline = false;

  // Callbacks
  Function(P2PMessage message)? onMessageReceived;
  Function(String deviceId, String userName)? onDeviceConnected;
  Function(String deviceId)? onDeviceDisconnected;
  Function(List<Map<String, dynamic>> devices)? onDevicesDiscovered;

  // Initialize service with role preference
  Future<bool> initialize(String userName, {String? preferredRole}) async {
    try {
      _userName = userName;
      _deviceId = _generateDeviceId(userName);
      _preferredRole = preferredRole;

      debugPrint(
        "🚀 Initializing P2P Service for: $_userName (ID: $_deviceId)",
      );

      // Initialize WiFi Direct
      bool success = await WifiDirectPlugin.initialize();
      if (!success) {
        debugPrint("❌ Failed to initialize WiFi Direct");
        return false;
      }

      // Setup WiFi Direct event listeners
      _setupWifiDirectListeners();

      // Start cleanup timers
      _startMessageCleanup();
      _startHeartbeat();
      _startReconnectTimer();

      // Monitor connectivity
      _monitorConnectivity();

      // Load known devices and pending messages
      await _loadKnownDevices();
      await _loadPendingMessages();

      debugPrint("✅ P2P Service initialized successfully");
      return true;
    } catch (e) {
      debugPrint("❌ P2P initialization error: $e");
      return false;
    }
  }

  // Enhanced WiFi Direct event listeners
  void _setupWifiDirectListeners() {
    // Peers discovered
    _peersChangeSubscription = WifiDirectPlugin.peersStream.listen((peers) {
      if (_isDisposed) return;

      debugPrint("📡 Discovered ${peers.length} peers");
      _discoveredDevices.clear();

      for (var peer in peers) {
        final deviceData = {
          'deviceName': peer.deviceName,
          'deviceAddress': peer.deviceAddress,
          'status': peer.status,
          'isAvailable': peer.status == 0, // 0 = Available
          'discoveredAt': DateTime.now().millisecondsSinceEpoch,
        };
        _discoveredDevices[peer.deviceAddress] = deviceData;

        debugPrint(
          "📱 Found device: ${peer.deviceName} (${peer.deviceAddress}) - Status: ${peer.status}",
        );
      }

      // Convert to list for callback
      final deviceList = _discoveredDevices.values.toList();
      onDevicesDiscovered?.call(deviceList);

      // Auto-connect logic only if emergency mode is on and not currently connecting
      if (_emergencyMode &&
          !_isConnecting &&
          !_isConnected &&
          deviceList.isNotEmpty) {
        _scheduleAutoConnect();
      }

      notifyListeners();
    });

    // Connection changes
    _connectionChangeSubscription = WifiDirectPlugin.connectionStream.listen((
      info,
    ) {
      if (_isDisposed) return;

      final wasConnected = _isConnected;
      _isConnected = info.isConnected;
      _isGroupOwner = info.isGroupOwner;
      _groupOwnerAddress = info.groupOwnerAddress;

      debugPrint(
        "🔗 Connection changed: connected=$_isConnected, isGroupOwner=$_isGroupOwner",
      );

      if (_isConnected && !wasConnected) {
        _handleConnectionEstablished();
      } else if (!_isConnected && wasConnected) {
        _handleConnectionLost();
      }

      _isConnecting = false;
      notifyListeners();
    });

    // Text message received
    WifiDirectPlugin.onTextReceived = (text) {
      if (_isDisposed) return;
      _handleIncomingText(text);
    };
  }

  // Smart auto-connect with role preference
  void _scheduleAutoConnect() {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = Timer(autoConnectDelay, () async {
      if (_isDisposed || _isConnecting || _isConnected) return;

      await _attemptSmartConnect();
    });
  }

  Future<void> _attemptSmartConnect() async {
    if (_discoveredDevices.isEmpty || _isConnecting) return;

    debugPrint("🤖 Attempting smart auto-connect...");

    // Sort devices by preference
    final availableDevices = _discoveredDevices.values
        .where((device) => device['isAvailable'] == true)
        .toList();

    if (availableDevices.isEmpty) {
      debugPrint("📍 No available devices, becoming host...");
      await _becomeHost();
      return;
    }

    // Prefer known devices first
    Map<String, dynamic>? targetDevice;

    for (var device in availableDevices) {
      if (_knownDevices.containsKey(device['deviceAddress'])) {
        targetDevice = device;
        break;
      }
    }

    // If no known devices, use role preference
    if (targetDevice == null) {
      if (_preferredRole == 'host' || availableDevices.length == 1) {
        debugPrint("📍 Preferred role is host, creating group...");
        await _becomeHost();
        return;
      } else {
        // Try to connect to first available device as client
        targetDevice = availableDevices.first;
      }
    }

    debugPrint("🔗 Auto-connecting to: ${targetDevice['deviceName']}");
    try {
      await connectToDevice(targetDevice);
    } catch (e) {
      debugPrint("❌ Auto-connect failed: $e, becoming host instead...");
      await Future.delayed(Duration(seconds: 2));
      if (!_isConnected && !_isConnecting) {
        await _becomeHost();
      }
    }
  }

  // Become host with better error handling
  Future<void> _becomeHost() async {
    if (_isConnecting || _isConnected) return;

    try {
      _isConnecting = true;
      _currentRole = P2PRole.host;

      debugPrint("👑 Becoming WiFi Direct host...");

      // Stop any ongoing discovery
      await WifiDirectPlugin.stopDiscovery();
      await Future.delayed(Duration(milliseconds: 500));

      bool success = await WifiDirectPlugin.startAsServer(
        "RESQLINK_$_userName",
      );

      if (success) {
        debugPrint("✅ Successfully created host group");
        notifyListeners();
      } else {
        debugPrint("❌ Failed to create host group");
        _currentRole = P2PRole.none;
        _isConnecting = false;
      }
    } catch (e) {
      debugPrint("❌ Error becoming host: $e");
      _currentRole = P2PRole.none;
      _isConnecting = false;
    }
  }

  // Cleanup and utilities
  String _generateDeviceId(String userName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = md5.convert(utf8.encode('$userName$timestamp')).toString();
    return hash.substring(0, 16);
  }

  // Check and request permissions
  Future<bool> checkAndRequestPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled");
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permission denied");
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permission permanently denied");
        return false;
      }

      return true;
    } catch (e) {
      debugPrint("Error checking permissions: $e");
      return false;
    }
  }

  // Emergency mode management
  void _startEmergencyMode() {
    debugPrint("🚨 Starting emergency mode...");

    // Start discovery if not connected
    if (!_isConnected && !_isDiscovering) {
      discoverDevices(force: true);
    }

    // Set up periodic discovery
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      if (!_isConnected && !_isDiscovering && !_isDisposed) {
        discoverDevices(force: true);
      }
    });
  }

  void _stopEmergencyMode() {
    debugPrint("✋ Stopping emergency mode...");

    _autoConnectTimer?.cancel();
    _discoveryTimer?.cancel();

    if (_isDiscovering) {
      _stopDiscovery();
    }
  }

  // Perform discovery scan using WiFi Direct
  Future<void> _performDiscoveryScan() async {
    if (_isDisposed) return;

    try {
      debugPrint("Starting WiFi Direct discovery scan...");

      // Clear old discoveries
      _discoveredDevices.clear();

      // Start WiFi Direct discovery
      bool success = await WifiDirectPlugin.startDiscovery();
      if (!success) {
        debugPrint("Failed to start discovery");
      } else {
        _isDiscovering = true;
        debugPrint("WiFi Direct discovery scan initiated");
      }
    } catch (e) {
      debugPrint("Discovery scan error: $e");
    }
  }

  // Create emergency group (become group owner)
  Future<void> createEmergencyGroup() async {
    try {
      if (_isConnected) {
        debugPrint('Cleaning up existing P2P connections...');
        await stopP2P();
        await Future.delayed(const Duration(seconds: 1));
      }

      debugPrint("Creating emergency WiFi Direct group...");

      _currentRole = P2PRole.host;
      _emergencyMode = true;

      bool success = await WifiDirectPlugin.startAsServer(
        "RESQLINK_$_userName",
      );
      if (!success) {
        debugPrint("Failed to start as server");
        return;
      }

      debugPrint("Emergency group created successfully");
      notifyListeners();
    } catch (e) {
      debugPrint('Error creating emergency group: $e');
      rethrow;
    }
  }

  // Enhanced device connection with better error handling
  Future<void> connectToDevice(Map<String, dynamic> deviceData) async {
    if (_isConnecting || _isConnected) {
      debugPrint("⚠️ Already connecting or connected");
      return;
    }

    try {
      _isConnecting = true;
      notifyListeners();

      final deviceAddress = deviceData['deviceAddress'] as String;
      final deviceName = deviceData['deviceName'] as String;

      debugPrint("🔗 Connecting to device: $deviceName ($deviceAddress)");

      // Stop discovery before connecting
      await WifiDirectPlugin.stopDiscovery();
      await Future.delayed(Duration(milliseconds: 500));

      bool success = await WifiDirectPlugin.connect(deviceAddress);

      if (success) {
        debugPrint("✅ Connection initiated successfully");
        _currentRole = P2PRole.client;

        // Save device credentials for future reconnection
        await _saveDeviceCredentials(
          deviceAddress,
          DeviceCredentials(
            deviceId: deviceAddress,
            ssid: deviceName,
            psk: emergencyPassword,
            isHost: false,
            lastSeen: DateTime.now(),
          ),
        );
      } else {
        debugPrint("❌ Failed to initiate connection");
        _isConnecting = false;
        throw Exception('Failed to connect to device');
      }
    } catch (e) {
      _isConnecting = false;
      notifyListeners();
      debugPrint("❌ Connection error: $e");
      rethrow;
    }
  }

  // Enhanced connection handling
  void _handleConnectionEstablished() {
    debugPrint(
      "🎉 P2P connection established! Role: ${_isGroupOwner ? 'Host' : 'Client'}",
    );

    _isConnecting = false;
    _currentRole = _isGroupOwner ? P2PRole.host : P2PRole.client;

    // Start heartbeat to maintain connection
    _startHeartbeat();

    // Send initial handshake
    _sendHandshake();

    notifyListeners();
  }

  void _handleConnectionLost() {
    debugPrint("💔 P2P connection lost");

    _connectedDevices.clear();
    _currentRole = P2PRole.none;
    _isConnecting = false;
    _stopHeartbeat();

    // In emergency mode, try to reconnect
    if (_emergencyMode && !_isDisposed) {
      Timer(Duration(seconds: 3), () {
        if (!_isConnected && !_isConnecting) {
          discoverDevices(force: true);
        }
      });
    }

    notifyListeners();
  }

  // Heartbeat to maintain connection
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isConnected && !_isDisposed) {
        _sendHeartbeat();
      } else {
        timer.cancel();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHandshake() {
    final handshake = {
      'type': 'handshake',
      'deviceId': _deviceId,
      'userName': _userName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'role': _currentRole.name,
    };

    _sendMessage(jsonEncode(handshake));
  }

  void _sendHeartbeat() {
    final heartbeat = {
      'type': 'heartbeat',
      'deviceId': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _sendMessage(jsonEncode(heartbeat));
  }

  Future<void> _sendMessage(String message) async {
    try {
      await WifiDirectPlugin.sendText(message);
    } catch (e) {
      debugPrint("❌ Error sending message: $e");
      rethrow;
    }
  }

  // Enhanced discovery with cooldown
  Future<void> discoverDevices({bool force = false}) async {
    final now = DateTime.now();

    // Cooldown period to prevent spam
    if (!force &&
        _lastDiscoveryTime != null &&
        now.difference(_lastDiscoveryTime!) < Duration(seconds: 5)) {
      debugPrint("⏳ Discovery cooldown active");
      return;
    }

    if (_isDiscovering) {
      debugPrint("⚠️ Discovery already in progress");
      return;
    }

    try {
      _isDiscovering = true;
      _lastDiscoveryTime = now;
      notifyListeners();

      debugPrint("🔍 Starting device discovery...");

      // Clear old discoveries
      _discoveredDevices.clear();

      bool success = await WifiDirectPlugin.startDiscovery();

      if (success) {
        debugPrint("✅ Discovery started successfully");

        // Auto-stop discovery after 30 seconds
        Timer(Duration(seconds: 30), () {
          if (_isDiscovering) {
            _stopDiscovery();
          }
        });
      } else {
        debugPrint("❌ Failed to start discovery");
        _isDiscovering = false;
      }
    } catch (e) {
      debugPrint("❌ Discovery error: $e");
      _isDiscovering = false;
    }

    notifyListeners();
  }

  Future<void> _stopDiscovery() async {
    if (!_isDiscovering) return;

    try {
      await WifiDirectPlugin.stopDiscovery();
      _isDiscovering = false;
      debugPrint("🛑 Discovery stopped");
    } catch (e) {
      debugPrint("❌ Error stopping discovery: $e");
    }

    notifyListeners();
  }

  // Enhanced message sending
  Future<void> sendMessage({
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to any device');
    }

    final enhancedMessage = _emergencyMode && type != MessageType.text
        ? "🚨 $message"
        : message;

    final p2pMessage = P2PMessage(
      id: _generateMessageId(),
      senderId: _deviceId!,
      senderName: _userName!,
      message: enhancedMessage,
      type: type,
      timestamp: DateTime.now(),
      ttl: maxTtl,
      targetDeviceId: targetDeviceId,
      latitude: latitude,
      longitude: longitude,
      routePath: [_deviceId!],
    );

    // Save to local database
    await _saveMessage(p2pMessage, true);

    // Mark as processed to avoid loops
    _processedMessageIds.add(p2pMessage.id);
    _messageHistory.add(p2pMessage);

    // Send to network
    final messageJson = jsonEncode({'type': 'message', ...p2pMessage.toJson()});

    await _sendMessage(messageJson);

    debugPrint("📤 Sent message: $enhancedMessage");
  }

  // Send emergency message templates
  Future<void> sendEmergencyTemplate(EmergencyTemplate template) async {
    String message = "";
    MessageType type = MessageType.emergency;

    switch (template) {
      case EmergencyTemplate.sos:
        message = "🆘 SOS - IMMEDIATE HELP NEEDED!";
        type = MessageType.sos;
      case EmergencyTemplate.trapped:
        message = "⚠️ I'M TRAPPED - Need rescue assistance";
        type = MessageType.emergency;
      case EmergencyTemplate.medical:
        message = "🏥 MEDICAL EMERGENCY - Need medical help";
        type = MessageType.emergency;
      case EmergencyTemplate.safe:
        message = "✅ I'M SAFE - No immediate danger";
        type = MessageType.text;
      case EmergencyTemplate.evacuating:
        message = "🏃 EVACUATING - Moving to safe location";
        type = MessageType.text;
    }

    // Get current location if available
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint("Could not get location: $e");
    }

    await sendMessage(
      message: message,
      type: type,
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
  }

  // Broadcast message to all connected devices
  Future<void> _broadcastMessage(P2PMessage message) async {
    // Decrease TTL
    final updatedMessage = message.copyWith(
      ttl: message.ttl - 1,
      routePath: [...message.routePath, _deviceId!],
    );

    if (updatedMessage.ttl <= 0) {
      debugPrint("Message TTL expired, dropping: ${message.id}");
      return;
    }

    final messageJson = jsonEncode(updatedMessage.toJson());

    try {
      await _sendMessage(messageJson);
    } catch (e) {
      debugPrint("Error broadcasting message: $e");
      // Queue for retry
      _queuePendingMessage(updatedMessage);
    }
  }

  // Enhanced message handling
  void _handleIncomingText(String text) {
    try {
      final json = jsonDecode(text);
      final messageType = json['type'] as String?;

      switch (messageType) {
        case 'handshake':
          _handleHandshake(json);
        case 'heartbeat':
          _handleHeartbeat(json);
        case 'message':
          _handleChatMessage(json);
        default:
          debugPrint("🤷 Unknown message type: $messageType");
      }
    } catch (e) {
      debugPrint("❌ Error handling incoming text: $e");
    }
  }

  void _handleHandshake(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    final userName = json['userName'] as String?;
    final role = json['role'] as String?;

    if (deviceId != null && userName != null) {
      debugPrint(
        "🤝 Received handshake from: $userName ($deviceId) - Role: $role",
      );

      _connectedDevices[deviceId] = ConnectedDevice(
        id: deviceId,
        name: userName,
        isHost: role == 'host',
        connectedAt: DateTime.now(),
      );

      onDeviceConnected?.call(deviceId, userName);
      notifyListeners();
    }
  }

  void _handleHeartbeat(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    if (deviceId != null && _connectedDevices.containsKey(deviceId)) {
      // Update last seen time
      debugPrint("💓 Heartbeat from: $deviceId");
    }
  }

  void _handleChatMessage(Map<String, dynamic> json) {
    try {
      final message = P2PMessage.fromJson(json);

      // Avoid processing our own messages
      if (message.senderId == _deviceId) return;

      // Check for duplicates
      if (_processedMessageIds.contains(message.id)) return;

      _processedMessageIds.add(message.id);
      _messageHistory.add(message);

      // Save to database
      _saveMessage(message, false);

      // Notify UI
      onMessageReceived?.call(message);

      debugPrint(
        "📨 Received message from ${message.senderName}: ${message.message}",
      );
    } catch (e) {
      debugPrint("❌ Error handling chat message: $e");
    }
  }

  // Save device credentials for reconnection
  Future<void> _saveDeviceCredentials(
    String deviceId,
    DeviceCredentials credentials,
  ) async {
    _knownDevices[deviceId] = credentials;
    await DatabaseService.saveDeviceCredentials(credentials);
  }

  // Load known devices from database
  Future<void> _loadKnownDevices() async {
    final devices = await DatabaseService.getKnownDevices();
    for (var device in devices) {
      _knownDevices[device.deviceId] = device;
    }
  }

  // Queue messages for offline devices
  void _queuePendingMessage(P2PMessage message) {
    for (var deviceId in _knownDevices.keys) {
      if (!_connectedDevices.containsKey(deviceId)) {
        _pendingMessages
            .putIfAbsent(deviceId, () => [])
            .add(
              PendingMessage(
                message: message,
                queuedAt: DateTime.now(),
                attempts: 0,
              ),
            );
      }
    }

    // Save to database
    DatabaseService.savePendingMessages(_pendingMessages);
  }

  // Load pending messages from database
  Future<void> _loadPendingMessages() async {
    try {
      final pending = await DatabaseService.getPendingMessages();

      // Group messages by endpoint ID since DatabaseService returns List<MessageModel>
      for (var message in pending) {
        final deviceId = message.endpointId;

        final p2pMessage = P2PMessage(
          id: message.messageId ?? _generateMessageId(),
          senderId: message.isMe
              ? _deviceId!
              : message.endpointId, // Fix: use correct sender
          senderName: message.fromUser,
          message: message.message,
          type: MessageType.values.firstWhere(
            (e) => e.name == message.type,
            orElse: () => MessageType.text,
          ),
          timestamp: message.dateTime,
          ttl: maxTtl,
          targetDeviceId: message.isMe
              ? message.endpointId
              : null, // Fix: add required parameter
          latitude: message.latitude,
          longitude: message.longitude,
          routePath: [_deviceId!],
        );

        _pendingMessages
            .putIfAbsent(deviceId, () => [])
            .add(
              PendingMessage(
                message: p2pMessage,
                queuedAt: message.dateTime,
                attempts: 0,
              ),
            );
      }

      debugPrint(
        'Loaded ${pending.length} pending messages for ${_pendingMessages.length} devices',
      );
    } catch (e) {
      debugPrint('Error loading pending messages: $e');
    }
  }

  // Auto-reconnect to known devices
  void _startReconnectTimer() {
    _reconnectTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_isDisposed) return;
      if (_isConnected) return;

      for (var device in _knownDevices.values) {
        if (DateTime.now().difference(device.lastSeen).inHours < 24) {
          try {
            await _performDiscoveryScan();
            await Future.delayed(Duration(seconds: 3));

            final targetDevice = _discoveredDevices.values.firstWhere(
              (d) => d['deviceAddress'] == device.deviceId,
              orElse: () => throw Exception("Device not found"),
            );

            await connectToDevice(targetDevice);
            break;
          } catch (e) {
            debugPrint("Failed to reconnect to ${device.deviceId}");
          }
        }
      }
    });
  }

  // Monitor connectivity for Firebase sync
  void _monitorConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      _isOnline = results.any((result) => result != ConnectivityResult.none);

      if (_isOnline) {
        await _syncToFirebase();
      }
    });
  }

  // Sync messages to Firebase when online
  Future<void> _syncToFirebase() async {
    if (!_isOnline) return;

    try {
      final unsyncedMessages = await DatabaseService.getUnsyncedMessages();
      for (var message in unsyncedMessages) {
        await FirebaseFirestore.instance
            .collection('emergency_messages')
            .add(message.toFirebaseJson());
        await DatabaseService.markMessageSynced(message.id as String);
      }
      debugPrint("Synced ${unsyncedMessages.length} messages to Firebase");
    } catch (e) {
      debugPrint("Firebase sync error: $e");
    }
  }

  // Cleanup old messages periodically
  void _startMessageCleanup() {
    _messageCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (_isDisposed) return;
      final cutoff = DateTime.now().subtract(messageExpiry);
      _processedMessageIds.removeWhere((id) {
        final timestamp = int.tryParse(id.split('-').last) ?? 0;
        return DateTime.fromMillisecondsSinceEpoch(timestamp).isBefore(cutoff);
      });
      _messageHistory.removeWhere((msg) => msg.timestamp.isBefore(cutoff));
      _pendingMessages.forEach((deviceId, messages) {
        messages.removeWhere((msg) => msg.isExpired());
      });
    });
  }

  // Save message to database
  Future<void> _saveMessage(P2PMessage message, bool isMe) async {
    try {
      final dbMessage = MessageModel(
        endpointId: isMe
            ? message.targetDeviceId ?? 'broadcast'
            : message.senderId,
        fromUser: message.senderName,
        message: message.message,
        isMe: isMe,
        isEmergency:
            message.type == MessageType.emergency ||
            message.type == MessageType.sos,
        timestamp: message.timestamp.millisecondsSinceEpoch,
        type: message.type.name,
        latitude: message.latitude,
        longitude: message.longitude,
        messageId: message.id,
        status: MessageStatus.delivered,
      );

      await DatabaseService.insertMessage(dbMessage);
    } catch (e) {
      debugPrint('❌ Error saving message to database: $e');
    }
  }

  // Generate unique message ID
  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return '$_deviceId-$random-$timestamp';
  }

  // Get device info with connection status
  Map<String, dynamic> getDeviceInfo(String deviceAddress) {
    final device = _discoveredDevices[deviceAddress];
    final connected = _connectedDevices[deviceAddress];

    return {
      'address': deviceAddress,
      'name': device?['deviceName'] ?? connected?.name ?? 'Unknown',
      'isConnected': connected != null,
      'isKnown': _knownDevices.containsKey(deviceAddress),
      'lastSeen': _knownDevices[deviceAddress]?.lastSeen,
      'isAvailable': device?['status'] == 0,
    };
  }

  // Check if should auto-reconnect to device
  bool shouldAutoReconnect(String deviceAddress) {
    final known = _knownDevices[deviceAddress];
    if (known == null) return false;
    final hoursSinceLastSeen = DateTime.now()
        .difference(known.lastSeen)
        .inHours;
    return hoursSinceLastSeen < 24;
  }

  // Connection info for UI
  Map<String, dynamic> getConnectionInfo() {
    return {
      'deviceId': _deviceId,
      'userName': _userName,
      'role': _currentRole.name,
      'isOnline': _isOnline,
      'isConnected': _isConnected,
      'isGroupOwner': _isGroupOwner,
      'connectedDevices': _connectedDevices.length,
      'knownDevices': _knownDevices.length,
      'discoveredDevices': _discoveredDevices.length,
      'isDiscovering': _isDiscovering,
      'isConnecting': _isConnecting,
      'emergencyMode': _emergencyMode,
    };
  }

  // Stop P2P operations
  Future<void> stopP2P() async {
    try {
      _autoConnectTimer?.cancel();
      _discoveryTimer?.cancel();
      await _peersChangeSubscription?.cancel();
      await _connectionChangeSubscription?.cancel();
      await WifiDirectPlugin.disconnect();
      WifiDirectPlugin.onTextReceived = null;
      _currentRole = P2PRole.none;
      _isConnected = false;
      _isGroupOwner = false;
      _groupOwnerAddress = null;
      _connectedDevices.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('Error in stopP2P: $e');
    }
  }

  // Disconnect from current P2P group
  Future<void> disconnect() async {
    try {
      await WifiDirectPlugin.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  // Sync pending messages for a specific device
  void syncPendingMessagesFor(String deviceId) async {
    final pending = _pendingMessages[deviceId] ?? [];
    for (var pendingMsg in pending) {
      if (pendingMsg.isExpired()) continue;
      try {
        await _broadcastMessage(pendingMsg.message);
        _pendingMessages[deviceId]?.remove(pendingMsg);
      } catch (e) {
        pendingMsg.attempts++;
        debugPrint("Failed to sync message: $e");
      }
    }
    if (_pendingMessages[deviceId]?.isEmpty ?? false) {
      _pendingMessages.remove(deviceId);
    }
    for (var deviceId in _connectedDevices.keys) {
      syncPendingMessagesFor(deviceId);
    }
  }

  // Cleanup
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    debugPrint("🗑️ Disposing P2P service...");

    // Cancel all timers
    _autoConnectTimer?.cancel();
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _messageCleanupTimer?.cancel();
    _syncTimer?.cancel();
    _reconnectTimer?.cancel();

    // Cancel subscriptions
    await _peersChangeSubscription?.cancel();
    await _connectionChangeSubscription?.cancel();
    await _connectivitySubscription?.cancel();

    // Stop WiFi Direct
    try {
      await WifiDirectPlugin.disconnect();
      WifiDirectPlugin.onTextReceived = null;
    } catch (e) {
      debugPrint("❌ Error during WiFi Direct cleanup: $e");
    }

    debugPrint("✅ P2P service disposed");
    super.dispose();
  }

  // Getters
  bool get isDiscovering => _isDiscovering;
  bool get isConnecting => _isConnecting;
  Map<String, ConnectedDevice> get connectedDevices =>
      Map.from(_connectedDevices);
  Map<String, DeviceCredentials> get knownDevices => Map.from(_knownDevices);
  Map<String, Map<String, dynamic>> get discoveredDevices =>
      Map.from(_discoveredDevices);
  List<P2PMessage> get messageHistory => List.from(_messageHistory);
  String? get deviceId => _deviceId;
  String? get userName => _userName;
  P2PRole get currentRole => _currentRole;
  bool get isOnline => _isOnline;
  bool get isConnected => _isConnected;
  bool get isGroupOwner => _isGroupOwner;
  String? get groupOwnerAddress => _groupOwnerAddress;
}

// Keep all your existing enums and classes...
enum P2PRole { none, host, client }
enum MessageType { text, emergency, location, sos, system, file }
enum EmergencyTemplate { sos, trapped, medical, safe, evacuating }

class P2PMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final MessageType type;
  final DateTime timestamp;
  final int ttl;
  final String? targetDeviceId;
  final double? latitude;
  final double? longitude;
  final List<String> routePath;
  final bool synced;

  P2PMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.ttl,
    this.targetDeviceId,
    this.latitude,
    this.longitude,
    required this.routePath,
    this.synced = false,
  });

  P2PMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? message,
    MessageType? type,
    DateTime? timestamp,
    int? ttl,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
    List<String>? routePath,
    bool? synced,
  }) {
    return P2PMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      ttl: ttl ?? this.ttl,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      routePath: routePath ?? this.routePath,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'type': type.index,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'ttl': ttl,
      'targetDeviceId': targetDeviceId,
      'latitude': latitude,
      'longitude': longitude,
      'routePath': routePath,
      'synced': synced,
    };
  }

  Map<String, dynamic> toFirebaseJson() {
    return {
      ...toJson(),
      'timestamp': FieldValue.serverTimestamp(),
      'deviceInfo': {
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
      },
    };
  }

  factory P2PMessage.fromJson(Map<String, dynamic> json) {
    return P2PMessage(
      id: json['id'],
      senderId: json['senderId'],
      senderName: json['senderName'],
      message: json['message'],
      type: MessageType.values[json['type']],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      ttl: json['ttl'],
      targetDeviceId: json['targetDeviceId'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      routePath: List<String>.from(json['routePath']),
      synced: json['synced'] ?? false,
    );
  }
}

class ConnectedDevice {
  final String id;
  final String name;
  final bool isHost;
  final DateTime connectedAt;

  ConnectedDevice({
    required this.id,
    required this.name,
    required this.isHost,
    required this.connectedAt,
  });
}

class DeviceCredentials {
  final String deviceId;
  final String ssid;
  final String psk;
  final bool isHost;
  final DateTime lastSeen;

  DeviceCredentials({
    required this.deviceId,
    required this.ssid,
    required this.psk,
    required this.isHost,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'ssid': ssid,
      'psk': psk,
      'isHost': isHost,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
    };
  }

  factory DeviceCredentials.fromJson(Map<String, dynamic> json) {
    return DeviceCredentials(
      deviceId: json['deviceId'],
      ssid: json['ssid'],
      psk: json['psk'],
      isHost: json['isHost'],
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen']),
    );
  }
}

class PendingMessage {
  final P2PMessage message;
  final DateTime queuedAt;
  int attempts;

  PendingMessage({
    required this.message,
    required this.queuedAt,
    this.attempts = 0,
  });

  bool isExpired() {
    return DateTime.now().difference(queuedAt) >
        P2PConnectionService.messageExpiry;
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message.toJson(),
      'queuedAt': queuedAt.millisecondsSinceEpoch,
      'attempts': attempts,
    };
  }

  factory PendingMessage.fromJson(Map<String, dynamic> json) {
    return PendingMessage(
      message: P2PMessage.fromJson(json['message']),
      queuedAt: DateTime.fromMillisecondsSinceEpoch(json['queuedAt']),
      attempts: json['attempts'] ?? 0,
    );
  }
}