import 'package:flutter/material.dart';
import 'package:flutter_p2p_plus/flutter_p2p_plus.dart';
import 'package:flutter_p2p_plus/protos/protos.pb.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
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
/// - Pure WiFi Direct discovery (no BLE dependency)
class P2PConnectionService with ChangeNotifier {
  static const String serviceType = "_resqlink._tcp";
  static const int defaultPort = 8888;
  static const int maxTtl = 5; // Maximum hops
  static const Duration messageExpiry = Duration(hours: 24);
  static const String emergencyPassword = "RESQLINK911"; // Predefined password
  static const Duration autoConnectDelay = Duration(seconds: 3);
  static const int minSignalStrength = -80; // dBm threshold

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
  final Map<String, Map<String, dynamic>> _discoveredDevices =
      {}; // Store device data as Map
  bool _isConnected = false; // Simple boolean for connection state
  bool _isGroupOwner = false; // Simple boolean for group owner state
  String? _groupOwnerAddress; // Store group owner address

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
  StreamSubscription? _stateChangeSubscription;
  StreamSubscription? _connectionChangeSubscription;
  StreamSubscription? _peersChangeSubscription;
  StreamSubscription? _deviceChangeSubscription;
  StreamSubscription? _discoveryChangeSubscription;
  StreamSubscription? _connectivitySubscription;

  // WiFi P2P socket for communication
  P2pSocket? _socket;
  bool _isHost = false;

  // Connectivity
  bool _isOnline = false;

  // Permission handling state
  bool _isRequestingPermissions = false;

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

      // Setup WiFi P2P event listeners
      _setupWifiP2PListeners();

      // Register to native events
      FlutterP2pPlus.register();

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

  // Setup WiFi P2P event listeners
  void _setupWifiP2PListeners() {
    // WiFi state changes
    _stateChangeSubscription = FlutterP2pPlus.wifiEvents.stateChange?.listen((
      change,
    ) {
      debugPrint("WiFi P2P state changed: ${change.isEnabled}");
      notifyListeners();
    });

    // Connection changes
    _connectionChangeSubscription = FlutterP2pPlus.wifiEvents.connectionChange
        ?.listen((change) {
          _isConnected = change.networkInfo.isConnected;
          _isGroupOwner = change.wifiP2pInfo.isGroupOwner;
          _groupOwnerAddress = change.wifiP2pInfo.groupOwnerAddress;
          _isHost = _isGroupOwner;

          debugPrint(
            "Connection changed: connected=$_isConnected, isHost=$_isHost",
          );

          if (_isConnected) {
            _handleConnectionEstablished();
          } else {
            _handleConnectionLost();
          }

          notifyListeners();
        });

    // Peers discovered
    _peersChangeSubscription = FlutterP2pPlus.wifiEvents.peersChange?.listen((
      change,
    ) {
      _discoveredDevices.clear();
      for (var device in change.devices) {
        final deviceData = {
          'deviceName': device.deviceName,
          'deviceAddress': device.deviceAddress,
          'status': device.status,
        };
        _discoveredDevices[device.deviceAddress] = deviceData;
      }

      debugPrint("Discovered ${change.devices.length} devices");

      // Convert to list of maps for callback
      final deviceList = _discoveredDevices.values.toList();
      onDevicesDiscovered?.call(deviceList);

      // Auto-connect in emergency mode
      if (_emergencyMode && _autoConnectEnabled && !_isConnected) {
        _attemptAutoConnect();
      }

      notifyListeners();
    });

    // This device changes
    _deviceChangeSubscription = FlutterP2pPlus.wifiEvents.thisDeviceChange
        ?.listen((change) {
          debugPrint("This device changed: ${change.deviceName}");
          notifyListeners();
        });

    // Discovery state changes
    _discoveryChangeSubscription = FlutterP2pPlus.wifiEvents.discoveryChange
        ?.listen((change) {
          _isDiscovering = change.isDiscovering;
          debugPrint("Discovery state changed: $_isDiscovering");
          notifyListeners();
        });
  }

  // Generate unique device ID
  String _generateDeviceId(String userName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = md5.convert(utf8.encode('$userName$timestamp')).toString();
    return hash.substring(0, 16);
  }

  // Check and request permissions
  Future<bool> checkAndRequestPermissions() async {
    if (_isRequestingPermissions) {
      debugPrint("Permission request already in progress");
      return false;
    }

    _isRequestingPermissions = true;

    try {
      // Check location permission
      final locationPermissionGranted =
          await FlutterP2pPlus.isLocationPermissionGranted();
      if (locationPermissionGranted != null && !locationPermissionGranted) {
        await FlutterP2pPlus.requestLocationPermission();

        // Verify permission was granted
        final permissionGrantedAfterRequest =
            await FlutterP2pPlus.isLocationPermissionGranted();
        if (permissionGrantedAfterRequest == null ||
            !permissionGrantedAfterRequest) {
          _isRequestingPermissions = false;
          return false;
        }
      }

      _isRequestingPermissions = false;
      return true;
    } catch (e) {
      debugPrint("Error requesting permissions: $e");
      _isRequestingPermissions = false;
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
    if (!(_isConnected)) {
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
      if (!(_isConnected)) {
        await _performDiscoveryScan();
      }
    });

    // Start immediate scan
    await _performDiscoveryScan();
  }

  // Perform discovery scan using pure WiFi Direct
  Future<void> _performDiscoveryScan() async {
    try {
      debugPrint("Starting WiFi Direct discovery scan...");

      // Clear old discoveries
      _discoveredDevices.clear();

      // Start WiFi P2P discovery
      await FlutterP2pPlus.discoverDevices();

      debugPrint("WiFi Direct discovery scan initiated");
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
      // Ensure complete cleanup before creating new group
      if (_isConnected) {
        debugPrint('Cleaning up existing P2P connections...');
        await stopP2P();
        await Future.delayed(const Duration(seconds: 1));
      }

      debugPrint("Creating emergency WiFi Direct group...");

      // Remove any existing group first
      try {
        await FlutterP2pPlus.removeGroup();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Ignore errors if no group exists
      }

      _currentRole = P2PRole.host;
      _emergencyMode = true;

      // Start accepting connections on default port
      await _startSocketServer();

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

      // Use the actual device from the discovered devices instead of creating a new one
      final deviceAddress = deviceData['deviceAddress'];

      // Find the actual device object from the events
      WifiP2pDevice? actualDevice;

      // We need to trigger discovery again to get the actual device objects
      await FlutterP2pPlus.discoverDevices();

      // Wait a moment for discovery to complete
      await Future.delayed(const Duration(seconds: 2));

      // For now, we'll use connect with the device address directly
      // This is a workaround since we need the actual device object
      try {
        // Connect using device address - this may need adjustment based on actual API
        await FlutterP2pPlus.connect(deviceAddress as WifiP2pDevice);
      } catch (e) {
        // If direct connection fails, try creating device object
        debugPrint("Direct connection failed, trying alternative approach: $e");
        throw Exception('Connection method needs API adjustment');
      }

      // Save device credentials for future reconnection
      _saveDeviceCredentials(
        deviceData['deviceAddress'],
        DeviceCredentials(
          deviceId: deviceData['deviceAddress'],
          ssid: deviceData['deviceName'], // Using device name as identifier
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
    debugPrint("P2P connection established, isHost: $_isHost");

    if (_isHost) {
      // As group owner, start server socket
      await _startSocketServer();
    } else {
      // As client, connect to group owner
      await _connectToHost();
    }

    // Setup emergency authentication and messaging
    _setupEmergencyMessaging();
  }

  // Handle connection lost
  void _handleConnectionLost() {
    debugPrint("P2P connection lost");

    try {
      _socket?.writeString("DISCONNECT");
    } catch (e) {
      // Ignore socket errors during disconnect
    }
    _socket = null;
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

  // Start socket server (for group owner)
  Future<void> _startSocketServer() async {
    try {
      _socket = await FlutterP2pPlus.openHostPort(defaultPort);

      // Listen for incoming data
      _socket!.inputStream.listen((data) {
        _handleIncomingData(data);
      });

      // Accept connections
      await FlutterP2pPlus.acceptPort(defaultPort);

      debugPrint("Socket server started on port $defaultPort");
    } catch (e) {
      debugPrint("Error starting socket server: $e");
    }
  }

  // Connect to host (for client)
  Future<void> _connectToHost() async {
    try {
      if (_groupOwnerAddress == null) {
        throw Exception("No group owner address available");
      }

      _socket = await FlutterP2pPlus.connectToHost(
        _groupOwnerAddress!,
        defaultPort,
        timeout: 10000,
      );

      // Listen for incoming data
      _socket!.inputStream.listen((data) {
        _handleIncomingData(data);
      });

      debugPrint("Connected to host socket");
    } catch (e) {
      debugPrint("Error connecting to host: $e");
    }
  }

  // Handle incoming socket data
  void _handleIncomingData(dynamic data) {
    try {
      String buffer = "";
      final message = String.fromCharCodes(data.data);
      buffer += message;

      if (data.dataAvailable == 0) {
        debugPrint("Received complete data: $buffer");
        _handleIncomingText(buffer);
        buffer = "";
      }
    } catch (e) {
      debugPrint("Error handling incoming data: $e");
    }
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

    _sendSocketMessage(jsonEncode(deviceInfo));

    // Start periodic heartbeat
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (_socket == null) {
        timer.cancel();
        return;
      }

      final heartbeat = {
        'type': 'heartbeat',
        'deviceId': _deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      _sendSocketMessage(jsonEncode(heartbeat));
    });
  }

  // Send message through socket
  Future<void> _sendSocketMessage(String message) async {
    try {
      if (_socket != null) {
        await _socket!.writeString(message);
      }
    } catch (e) {
      debugPrint("Error sending socket message: $e");
    }
  }

  // Discover devices (start WiFi Direct discovery)
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
      await _sendSocketMessage(messageJson);
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
        isHost: false, // Will be updated based on connection role
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
    // Find offline devices
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
    final pending = await DatabaseService.getPendingMessages();
    for (var entry in pending) {
      _pendingMessages[entry.key] = entry.value;
    }
  }

  // ✅ This is good!
  void _startBackgroundDiscovery() {
    Timer.periodic(Duration(minutes: 1), (timer) async {
      if (!_isConnected && _knownDevices.isNotEmpty) {
        // Try to discover known devices
        await _performDiscoveryScan();
      }
    });
  }

  // Auto-reconnect to known devices
  void _startReconnectTimer() {
    _reconnectTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_isConnected) return;

      // Try to reconnect to known devices
      for (var device in _knownDevices.values) {
        if (DateTime.now().difference(device.lastSeen).inHours < 24) {
          try {
            // Try to find and connect to this device
            await _performDiscoveryScan();

            // Wait for discovery results
            await Future.delayed(Duration(seconds: 3));

            final targetDevice = _discoveredDevices.values.firstWhere(
              (d) => d['deviceAddress'] == device.deviceId,
              orElse: () => throw Exception("Device not found"),
            );

            await connectToDevice(targetDevice);
            break; // Connected successfully
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
      // Get unsynced messages from database
      final unsyncedMessages = await DatabaseService.getUnsyncedMessages();

      for (var message in unsyncedMessages) {
        await FirebaseFirestore.instance
            .collection('emergency_messages')
            .add(message.toFirebaseJson());

        // Mark as synced
        await DatabaseService.markMessageSynced(message.id);
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

      // Clean processed message IDs
      _processedMessageIds.removeWhere((id) {
        final timestamp = int.tryParse(id.split('-').last) ?? 0;
        return DateTime.fromMillisecondsSinceEpoch(timestamp).isBefore(cutoff);
      });

      // Clean message history
      _messageHistory.removeWhere((msg) => msg.timestamp.isBefore(cutoff));

      // Clean expired pending messages
      _pendingMessages.forEach((deviceId, messages) {
        messages.removeWhere((msg) => msg.isExpired());
      });
    });
  }

  // Save message to database
  Future<void> _saveMessage(P2PMessage message, bool isMe) async {
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
      latitude: message.latitude ?? 0.0,
      longitude: message.longitude,
      messageId: message.id,
    );

    await DatabaseService.insertMessage(dbMessage);
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
      'isAvailable': device?['status'] == 0, // 0 = AVAILABLE in WifiP2pDevice
    };
  }

  // Check if should auto-reconnect to device
  bool shouldAutoReconnect(String deviceAddress) {
    final known = _knownDevices[deviceAddress];
    if (known == null) return false;

    // Auto-reconnect if seen in last 24 hours
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
      'isHost': _isHost,
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
      // Cancel timers first
      _autoConnectTimer?.cancel();
      _discoveryTimer?.cancel();

      // Cancel subscriptions
      await Future.wait(
        [
          _stateChangeSubscription?.cancel() ?? Future.value(),
          _connectionChangeSubscription?.cancel() ?? Future.value(),
          _peersChangeSubscription?.cancel() ?? Future.value(),
          _deviceChangeSubscription?.cancel() ?? Future.value(),
          _discoveryChangeSubscription?.cancel() ?? Future.value(),
        ].cast<Future<void>>(),
      );

      // Close socket safely
      try {
        _socket?.writeString("DISCONNECT");
      } catch (e) {
        // Ignore socket errors during disconnect
      }
      _socket = null;

      // Remove P2P group if we're the owner
      if (_isHost) {
        try {
          await FlutterP2pPlus.removeGroup();
        } catch (e) {
          debugPrint('Error removing group: $e');
        }
      }

      // Unregister from native events
      FlutterP2pPlus.unregister();

      // Reset state
      _currentRole = P2PRole.none;
      _isConnected = false;
      _isGroupOwner = false;
      _groupOwnerAddress = null;
      _connectedDevices.clear();
      _isHost = false;

      notifyListeners();
    } catch (e) {
      debugPrint('Error in stopP2P: $e');
      // Don't rethrow - prevent app crash
    }
  }

  // Disconnect from current P2P group
  Future<void> disconnect() async {
    try {
      await FlutterP2pPlus.removeGroup();
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  // Sync pending messages for a specific device
  void _syncPendingMessagesFor(String deviceId) async {
    final pending = _pendingMessages[deviceId] ?? [];

    for (var pendingMsg in pending) {
      if (pendingMsg.isExpired()) continue;

      try {
        await _broadcastMessage(pendingMsg.message);
        // Remove from pending after successful send
        _pendingMessages[deviceId]?.remove(pendingMsg);
      } catch (e) {
        pendingMsg.attempts++;
        debugPrint("Failed to sync message: $e");
      }
    }

    // Clean up
    if (_pendingMessages[deviceId]?.isEmpty ?? false) {
      _pendingMessages.remove(deviceId);
    }

    // Sync pending messages when device connects
    for (var deviceId in _connectedDevices.keys) {
      _syncPendingMessagesFor(deviceId);
    }
  }

  // Get current location for emergency beacon
  Map<String, double>? _getCurrentLocation() {
    // This should be integrated with your location service
    // Placeholder for now
    return null;
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
  bool get isHost => _isHost;
  String? get groupOwnerAddress => _groupOwnerAddress;
}

// Enums and Models
enum P2PRole { none, host, client }

enum MessageType { text, emergency, location, sos, system, file }

// Emergency message templates
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
