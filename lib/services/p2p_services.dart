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

/// P2P Connection Service Architecture:
/// - Dynamic Host/Client roles based on network topology
/// - Multi-hop message forwarding with TTL
/// - Store-and-forward for offline devices
/// - Automatic message deduplication
/// - Firebase sync when online
/// - Pure WiFi Direct discovery using wifi_direct_plugin
class P2PConnectionService with ChangeNotifier {
  static const String serviceType = "_resqlink._tcp";
  static const Duration messageExpiry = Duration(hours: 24);
  static const String emergencyPassword = "RESQLINK911"; // Predefined password
  static const Duration autoConnectDelay = Duration(seconds: 3);
  static const int maxTtl = 5; // Maximum hops

  // Field to track discovery state
  bool _isDiscovering = false;

  // Getter for isDiscovering
  bool get isDiscovering => _isDiscovering;

  // Singleton instance
  static final P2PConnectionService _instance =
      P2PConnectionService._internal();
  factory P2PConnectionService() => _instance;
  P2PConnectionService._internal();

  // Device identity and role
  String? _deviceId;
  String? _userName;
  P2PRole _currentRole = P2PRole.none;

  // Network state
  final Map<String, ConnectedDevice> _connectedDevices = {};
  final Map<String, DeviceCredentials> _knownDevices = {};
  final Map<String, Map<String, dynamic>> _discoveredDevices = {};
  bool _isConnected = false;
  bool _isGroupOwner = false;
  String? _groupOwnerAddress;

  // Emergency mode
  bool _emergencyMode = false;
  bool _autoConnectEnabled = true;
  Timer? _autoConnectTimer;
  Timer? _discoveryTimer;

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

  // Emergency mode toggle
  bool get emergencyMode => _emergencyMode;
  set emergencyMode(bool value) {
    _emergencyMode = value;
    if (value) {
      _startEmergencyMode();
    } else {
      _stopEmergencyMode();
    }
    notifyListeners();
  }

  // Initialize service
  Future<bool> initialize(String userName) async {
    try {
      _userName = userName;
      _deviceId = _generateDeviceId(userName);

      // Initialize WiFi Direct
      bool success = await WifiDirectPlugin.initialize();
      if (!success) {
        debugPrint("Failed to initialize WiFi Direct");
        return false;
      }

      // Setup WiFi Direct event listeners
      _setupWifiDirectListeners();

      // Start cleanup timers
      _startMessageCleanup();
      _startReconnectTimer();

      // Monitor connectivity
      _monitorConnectivity();

      // Load known devices and pending messages
      await _loadKnownDevices();
      await _loadPendingMessages();

      // Start discovery in background
      _startBackgroundDiscovery();

      return true;
    } catch (e) {
      debugPrint("P2P initialization error: $e");
      return false;
    }
  }

  // Setup WiFi Direct event listeners
  void _setupWifiDirectListeners() {
    // Peers discovered
    _peersChangeSubscription = WifiDirectPlugin.peersStream.listen((peers) {
      _discoveredDevices.clear();
      for (var peer in peers) {
        final deviceData = {
          'deviceName': peer.deviceName,
          'deviceAddress': peer.deviceAddress,
          'status': peer.status,
        };
        _discoveredDevices[peer.deviceAddress] = deviceData;
      }

      debugPrint("Discovered ${peers.length} devices");

      // Convert to list of maps for callback
      final deviceList = _discoveredDevices.values.toList();
      onDevicesDiscovered?.call(deviceList);

      // Auto-connect in emergency mode
      if (_emergencyMode && _autoConnectEnabled && !_isConnected) {
        _attemptAutoConnect();
      }

      notifyListeners();
    });

    // Connection changes
    _connectionChangeSubscription = WifiDirectPlugin.connectionStream.listen((
      info,
    ) {
      _isConnected = info.isConnected;
      _isGroupOwner = info.isGroupOwner;
      _groupOwnerAddress = info.groupOwnerAddress;

      debugPrint(
        "Connection changed: connected=$_isConnected, isGroupOwner=$_isGroupOwner",
      );

      if (_isConnected) {
        _handleConnectionEstablished();
      } else {
        _handleConnectionLost();
      }

      notifyListeners();
    });

    // Text message received
    WifiDirectPlugin.onTextReceived = (text) {
      _handleIncomingText(text);
    };
  }

  // Generate unique device ID
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

  void _startEmergencyMode() async {
    debugPrint("Starting emergency mode...");

    // Enable all services
    await checkAndRequestPermissions();

    // Start aggressive discovery
    _startAggressiveDiscovery();

    // Auto-create or join groups
    if (!_isConnected) {
      _autoConnectTimer = Timer(autoConnectDelay, () {
        _attemptAutoConnect();
      });
    }
  }

  void _stopEmergencyMode() {
    debugPrint("Stopping emergency mode...");
    _autoConnectTimer?.cancel();
    _discoveryTimer?.cancel();
  }

  void _startAggressiveDiscovery() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      if (!_isConnected) {
        await _performDiscoveryScan();
      }
    });

    // Start immediate scan
    await _performDiscoveryScan();
  }

  // Perform discovery scan using WiFi Direct
  Future<void> _performDiscoveryScan() async {
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

  Future<void> _attemptAutoConnect() async {
    if (_discoveredDevices.isEmpty) {
      // No devices found, create own group
      debugPrint("No devices found, creating emergency group...");
      await createEmergencyGroup();
      return;
    }

    // Find best device to connect to
    Map<String, dynamic>? bestDevice;

    for (var device in _discoveredDevices.values) {
      // Prioritize known devices
      if (_knownDevices.containsKey(device['deviceAddress'])) {
        bestDevice = device;
        break;
      }

      // Otherwise, choose devices with RESQLINK in name or any available device
      if (device['deviceName'].toString().contains("RESQLINK") ||
          bestDevice == null) {
        bestDevice = device;
      }
    }

    if (bestDevice != null) {
      debugPrint("Auto-connecting to ${bestDevice['deviceName']}...");
      try {
        await connectToDevice(bestDevice);
      } catch (e) {
        debugPrint("Auto-connect failed: $e");
        // Fallback: create own group
        await createEmergencyGroup();
      }
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

  // Connect to discovered device
  Future<void> connectToDevice(Map<String, dynamic> deviceData) async {
    try {
      debugPrint("Connecting to device: ${deviceData['deviceName']}");

      final deviceAddress = deviceData['deviceAddress'];
      bool success = await WifiDirectPlugin.connect(deviceAddress);
      if (!success) {
        throw Exception("Failed to connect to device");
      }

      // Save device credentials for future reconnection
      _saveDeviceCredentials(
        deviceAddress,
        DeviceCredentials(
          deviceId: deviceAddress,
          ssid: deviceData['deviceName'],
          psk: emergencyPassword,
          isHost: false,
          lastSeen: DateTime.now(),
        ),
      );

      _currentRole = P2PRole.client;
      debugPrint("Connected to device successfully");
    } catch (e) {
      debugPrint('Failed to connect to device: $e');
      throw Exception('Failed to connect to device: $e');
    }
  }

  // Handle connection established
  void _handleConnectionEstablished() async {
    debugPrint("P2P connection established, isGroupOwner: $_isGroupOwner");

    // Setup emergency authentication and messaging
    _setupEmergencyMessaging();
  }

  // Handle connection lost
  void _handleConnectionLost() {
    debugPrint("P2P connection lost");

    _connectedDevices.clear();
    _currentRole = P2PRole.none;

    // In emergency mode, try to reconnect or create new group
    if (_emergencyMode) {
      Timer(Duration(seconds: 5), () {
        _attemptAutoConnect();
      });
    }

    notifyListeners();
  }

  // Setup emergency messaging
  void _setupEmergencyMessaging() {
    // Send device info to establish identity
    final deviceInfo = {
      'type': 'device_info',
      'deviceId': _deviceId,
      'userName': _userName,
      'emergency': _emergencyMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _sendMessage(jsonEncode(deviceInfo));

    // Start periodic heartbeat
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (!_isConnected) {
        timer.cancel();
        return;
      }

      final heartbeat = {
        'type': 'heartbeat',
        'deviceId': _deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      _sendMessage(jsonEncode(heartbeat));
    });
  }

  // Send message through WiFi Direct
  Future<void> _sendMessage(String message) async {
    try {
      await WifiDirectPlugin.sendText(message);
    } catch (e) {
      debugPrint("Error sending message: $e");
    }
  }

  // Discover devices
  Future<void> discoverDevices() async {
    await _performDiscoveryScan();
  }

  // Send message with multi-hop support
  Future<void> sendMessage({
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
  }) async {
    // Add emergency indicator to message if in emergency mode
    final enhancedMessage = _emergencyMode ? "🚨 $message" : message;

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
    await _broadcastMessage(p2pMessage);

    // Notify UI
    onMessageReceived?.call(p2pMessage);
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

  // Handle incoming text messages
  void _handleIncomingText(String text) {
    try {
      final json = jsonDecode(text);

      // Handle special message types
      if (json['type'] == 'device_info') {
        _handleDeviceInfo(json);
        return;
      } else if (json['type'] == 'heartbeat') {
        _handleHeartbeat(json);
        return;
      }

      final message = P2PMessage.fromJson(json);

      // Check if already processed (avoid loops)
      if (_processedMessageIds.contains(message.id)) {
        debugPrint("Duplicate message ignored: ${message.id}");
        return;
      }

      // Check if device is in route path (avoid loops)
      if (message.routePath.contains(_deviceId)) {
        debugPrint("Message already routed through this device: ${message.id}");
        return;
      }

      // Mark as processed
      _processedMessageIds.add(message.id);
      _messageHistory.add(message);

      // Save to database
      _saveMessage(message, false);

      // Check if message is for this device
      if (message.targetDeviceId == null ||
          message.targetDeviceId == _deviceId) {
        // Message is for us
        onMessageReceived?.call(message);
      }

      // Forward if TTL > 0 (multi-hop relay)
      if (message.ttl > 0) {
        _broadcastMessage(message);
      }
    } catch (e) {
      debugPrint("Error handling message: $e");
    }
  }

  // Handle device info messages
  void _handleDeviceInfo(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    final userName = json['userName'] as String?;

    if (deviceId != null && userName != null) {
      _connectedDevices[deviceId] = ConnectedDevice(
        id: deviceId,
        name: userName,
        isHost: false,
        connectedAt: DateTime.now(),
      );

      onDeviceConnected?.call(deviceId, userName);
      notifyListeners();
    }
  }

  // Handle heartbeat messages
  void _handleHeartbeat(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    if (deviceId != null && _connectedDevices.containsKey(deviceId)) {
      // Update last seen time
      debugPrint("Heartbeat received from $deviceId");
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

  void _startBackgroundDiscovery() {
    Timer.periodic(Duration(minutes: 1), (timer) async {
      if (!_isConnected && _knownDevices.isNotEmpty) {
        await _performDiscoveryScan();
      }
    });
  }

  // Auto-reconnect to known devices
  void _startReconnectTimer() {
    _reconnectTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
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
        endpointId: message.senderId,
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
        messageId:
            message.id, // Fix: use message.id instead of undefined getter
        status: MessageStatus.delivered, // Add the required status field
      );

      await DatabaseService.insertMessage(dbMessage);
    } catch (e) {
      debugPrint('Error saving message to database: $e');
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

  // Get connection info
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
      'pendingMessages': _pendingMessages.values
          .expand((messages) => messages)
          .length,
      'processedMessages': _processedMessageIds.length,
      'groupOwnerAddress': _groupOwnerAddress,
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

  // Dispose service
  @override
  Future<void> dispose() async {
    await stopP2P();
    _messageCleanupTimer?.cancel();
    _syncTimer?.cancel();
    _reconnectTimer?.cancel();
    await _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Getters
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

// Enums and Models
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
