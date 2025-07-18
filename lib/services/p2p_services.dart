import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/message_model.dart';
import '../services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// P2P Connection Service Architecture:
/// - Dynamic Host/Client roles based on network topology
/// - Multi-hop message forwarding with TTL
/// - Store-and-forward for offline devices
/// - Automatic message deduplication
/// - Firebase sync when online
class P2PConnectionService with ChangeNotifier {
  static const String serviceType = "_resqlink._tcp";
  static const int defaultPort = 8888;
  static const int maxTtl = 5; // Maximum hops
  static const Duration messageExpiry = Duration(hours: 24);
  static const String serviceUuid = "resqlink-emergency-p2p";

  // Singleton instance
  static final P2PConnectionService _instance =
      P2PConnectionService._internal();
  factory P2PConnectionService() => _instance;
  P2PConnectionService._internal();

  // P2P instances
  FlutterP2pHost? _hostInstance;
  FlutterP2pClient? _clientInstance;

  // Device identity and role
  String? _deviceId;
  String? _userName;
  P2PRole _currentRole = P2PRole.none;

  // Network state
  final Map<String, ConnectedDevice> _connectedDevices = {};
  final Map<String, DeviceCredentials> _knownDevices = {}; // For reconnection
  HotspotHostState? _hostState;
  HotspotClientState? _clientState;

  // Message handling
  final Set<String> _processedMessageIds = {};
  final Map<String, List<PendingMessage>> _pendingMessages = {};
  final List<P2PMessage> _messageHistory = [];
  Timer? _messageCleanupTimer;
  Timer? _syncTimer;
  Timer? _reconnectTimer;

  // Stream subscriptions
  StreamSubscription? _hostStateSubscription;
  StreamSubscription? _clientStateSubscription;
  StreamSubscription? _clientListSubscription;
  StreamSubscription? _receivedTextsSubscription;
  StreamSubscription? _connectivitySubscription;

  // Connectivity
  bool _isOnline = false;

  // Callbacks
  Function(P2PMessage message)? onMessageReceived;
  Function(String deviceId, String userName)? onDeviceConnected;
  Function(String deviceId)? onDeviceDisconnected;

  // Initialize service
  Future<bool> initialize(String userName) async {
    try {
      _userName = userName;
      _deviceId = _generateDeviceId(userName);

      // Start cleanup timers
      _startMessageCleanup();
      _startReconnectTimer();

      // Monitor connectivity
      _monitorConnectivity();

      // Load known devices and pending messages
      await _loadKnownDevices();
      await _loadPendingMessages();

      return true;
    } catch (e) {
      print("P2P initialization error: $e");
      return false;
    }
  }

  // Generate unique device ID
  String _generateDeviceId(String userName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = md5.convert(utf8.encode('$userName$timestamp')).toString();
    return hash.substring(0, 16);
  }

  // Permission handling state
  bool _isRequestingPermissions = false;

  // Check and request permissions
  Future<bool> checkAndRequestPermissions() async {
    // Prevent multiple simultaneous permission requests
    if (_isRequestingPermissions) {
      print("Permission request already in progress");
      return false;
    }

    _isRequestingPermissions = true;

    try {
      final p2p = _hostInstance ?? _clientInstance ?? FlutterP2pHost();

      // Check all permissions first
      bool hasStorage = await p2p.checkStoragePermission();
      bool hasP2P = await p2p.checkP2pPermissions();
      bool hasBluetooth = await p2p.checkBluetoothPermissions();

      // Request only missing permissions
      if (!hasStorage) {
        if (!await p2p.askStoragePermission()) {
          _isRequestingPermissions = false;
          return false;
        }
      }

      if (!hasP2P) {
        if (!await p2p.askP2pPermissions()) {
          _isRequestingPermissions = false;
          return false;
        }
      }

      if (!hasBluetooth) {
        if (!await p2p.askBluetoothPermissions()) {
          _isRequestingPermissions = false;
          return false;
        }
      }

      _isRequestingPermissions = false;
      return true;
    } catch (e) {
      print("Error requesting permissions: $e");
      _isRequestingPermissions = false;
      return false;
    }
  }

  // Enable required services
  Future<bool> enableServices() async {
    final p2p = _hostInstance ?? _clientInstance ?? FlutterP2pHost();

    // WiFi
    if (!await p2p.checkWifiEnabled()) {
      await p2p.enableWifiServices();
    }

    // Location
    if (!await p2p.checkLocationEnabled()) {
      await p2p.enableLocationServices();
    }

    // Bluetooth
    if (!await p2p.checkBluetoothEnabled()) {
      await p2p.enableBluetoothServices();
    }

    return true;
  }

  // Create emergency group (become host)
  Future<void> createEmergencyGroup() async {
    if (_currentRole != P2PRole.none) {
      await stopP2P();
    }

    _hostInstance = FlutterP2pHost();
    await _hostInstance!.initialize();

    // Setup host listeners
    _setupHostListeners();

    // Create group with BLE advertising
    final state = await _hostInstance!.createGroup(
      advertise: true,
      timeout: const Duration(seconds: 30),
    );

    if (state.isActive) {
      _currentRole = P2PRole.host;
      _hostState = state;

      // Save credentials for reconnection
      if (state.ssid != null && state.preSharedKey != null) {
        _saveDeviceCredentials(
          _deviceId!,
          DeviceCredentials(
            deviceId: _deviceId!,
            ssid: state.ssid!,
            psk: state.preSharedKey!,
            isHost: true,
            lastSeen: DateTime.now(),
          ),
        );
      }

      notifyListeners();
    } else {
      throw Exception('Failed to create group: ${state.failureReason}');
    }
  }

  // Discover and join groups (become client)
  Future<void> discoverGroups() async {
    if (_currentRole != P2PRole.none) {
      await stopP2P();
    }

    _clientInstance = FlutterP2pClient();
    await _clientInstance!.initialize();

    // Setup client listeners
    _setupClientListeners();

    _currentRole = P2PRole.client;
    notifyListeners();
  }

  Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(
    Function(List<BleDiscoveredDevice> devices) onDevicesFound,
  ) async {
    if (_clientInstance == null) {
      throw Exception('Client not initialized');
    }

    // Removed the nonexistent serviceUuid parameter
    return await _clientInstance!.startScan(onDevicesFound);
  }

  // Connect to discovered device
  Future<void> connectToDevice(BleDiscoveredDevice device) async {
    if (_clientInstance == null) {
      throw Exception('Client not initialized');
    }

    await _clientInstance!.connectWithDevice(
      device,
      timeout: const Duration(seconds: 30),
    );
  }

  // Connect with known credentials
  Future<void> connectWithCredentials(String ssid, String preSharedKey) async {
    if (_clientInstance == null) {
      await discoverGroups();
    }

    await _clientInstance!.connectWithCredentials(
      ssid,
      preSharedKey,
      timeout: const Duration(seconds: 30),
    );
  }

  // Send message with multi-hop support
  Future<void> sendMessage({
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
  }) async {
    final p2pMessage = P2PMessage(
      id: _generateMessageId(),
      senderId: _deviceId!,
      senderName: _userName!,
      message: message,
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

  // Broadcast message to all connected devices
  Future<void> _broadcastMessage(P2PMessage message) async {
    // Decrease TTL
    final updatedMessage = message.copyWith(
      ttl: message.ttl - 1,
      routePath: [...message.routePath, _deviceId!],
    );

    if (updatedMessage.ttl <= 0) {
      print("Message TTL expired, dropping: ${message.id}");
      return;
    }

    final messageJson = jsonEncode(updatedMessage.toJson());

    try {
      if (_currentRole == P2PRole.host && _hostInstance != null) {
        // Host broadcasts to all clients
        await _hostInstance!.broadcastText(messageJson);
      } else if (_currentRole == P2PRole.client && _clientInstance != null) {
        // Client sends to host (which will relay to others)
        await _clientInstance!.broadcastText(messageJson);
      }
    } catch (e) {
      print("Error broadcasting message: $e");
      // Queue for retry
      _queuePendingMessage(updatedMessage);
    }
  }

  // Handle incoming text messages
  void _handleIncomingText(String text) {
    try {
      final json = jsonDecode(text);
      final message = P2PMessage.fromJson(json);

      // Check if already processed (avoid loops)
      if (_processedMessageIds.contains(message.id)) {
        print("Duplicate message ignored: ${message.id}");
        return;
      }

      // Check if device is in route path (avoid loops)
      if (message.routePath.contains(_deviceId)) {
        print("Message already routed through this device: ${message.id}");
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
      print("Error handling message: $e");
    }
  }

  // Setup host listeners
  void _setupHostListeners() {
    if (_hostInstance == null) return;

    // Host state changes
    _hostStateSubscription = _hostInstance!.streamHotspotState().listen((
      state,
    ) {
      _hostState = state;

      if (state.isActive && state.ssid != null && state.preSharedKey != null) {
        // Broadcast group info periodically
        _broadcastGroupInfo();
      }

      notifyListeners();
    });

    // Client list updates
    _clientListSubscription = _hostInstance!.streamClientList().listen((
      clients,
    ) {
      _updateConnectedDevices(clients);
    });

    // Received messages
    _receivedTextsSubscription = _hostInstance!.streamReceivedTexts().listen((
      text,
    ) {
      _handleIncomingText(text);
    });
  }

  // Setup client listeners
  void _setupClientListeners() {
    if (_clientInstance == null) return;

    // Client state changes
    _clientStateSubscription = _clientInstance!.streamHotspotState().listen((
      state,
    ) {
      _clientState = state;

      if (state.isActive && state.hostSsid != null) {
        // Save host credentials for reconnection
        _saveHostCredentials(state.hostSsid!);
      }

      notifyListeners();
    });

    // Participant list updates
    _clientListSubscription = _clientInstance!.streamClientList().listen((
      clients,
    ) {
      _updateConnectedDevices(clients);
    });

    // Received messages
    _receivedTextsSubscription = _clientInstance!.streamReceivedTexts().listen((
      text,
    ) {
      _handleIncomingText(text);
    });
  }

  // Update connected devices list
  void _updateConnectedDevices(List<P2pClientInfo> clients) {
    _connectedDevices.clear();

    for (var client in clients) {
      _connectedDevices[client.id] = ConnectedDevice(
        id: client.id,
        name: client.username,
        isHost: client.isHost,
        connectedAt: DateTime.now(),
      );

      // Sync pending messages for this device
      _syncPendingMessagesFor(client.id);
    }

    notifyListeners();
  }

  // Save device credentials for reconnection
  Future<void> _saveDeviceCredentials(
    String deviceId,
    DeviceCredentials credentials,
  ) async {
    _knownDevices[deviceId] = credentials;
    await DatabaseService.saveDeviceCredentials(credentials);
  }

  // Save host credentials for reconnection
  Future<void> _saveHostCredentials(String ssid) async {
    // Extract device ID from SSID if possible
    // For now, just save the SSID
    final credentials = DeviceCredentials(
      deviceId: ssid,
      ssid: ssid,
      psk: '',
      isHost: true,
      lastSeen: DateTime.now(),
    );

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

  // Sync pending messages for a specific device
  Future<void> _syncPendingMessagesFor(String deviceId) async {
    final pending = _pendingMessages[deviceId] ?? [];

    for (var pendingMsg in pending) {
      if (pendingMsg.isExpired()) continue;

      try {
        await _broadcastMessage(pendingMsg.message);

        // Remove from pending after successful send
        _pendingMessages[deviceId]?.remove(pendingMsg);
      } catch (e) {
        pendingMsg.attempts++;
        print("Failed to sync message: $e");
      }
    }

    // Clean up
    if (_pendingMessages[deviceId]?.isEmpty ?? false) {
      _pendingMessages.remove(deviceId);
    }
  }

  // Load pending messages from database
  Future<void> _loadPendingMessages() async {
    final pending = await DatabaseService.getPendingMessages();
    for (var entry in pending) {
      _pendingMessages[entry.key] = entry.value;
      // Ensure entry has the correct properties
    }
  }

  // Broadcast group info (for hosts)
  void _broadcastGroupInfo() {
    if (_currentRole != P2PRole.host || _hostState == null) return;

    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_currentRole != P2PRole.host) {
        timer.cancel();
        return;
      }

      final groupInfo = {
        'type': 'group_info',
        'deviceId': _deviceId,
        'userName': _userName,
        'ssid': _hostState!.ssid,
        'psk': _hostState!.preSharedKey,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      _hostInstance?.broadcastText(jsonEncode(groupInfo));
    });
  }

  // Auto-reconnect to known devices
  void _startReconnectTimer() {
    _reconnectTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_currentRole != P2PRole.none) return;

      // Try to reconnect to known hosts
      for (var device in _knownDevices.values) {
        if (device.isHost &&
            DateTime.now().difference(device.lastSeen).inHours < 24) {
          try {
            await connectWithCredentials(device.ssid, device.psk);
            break; // Connected successfully
          } catch (e) {
            print("Failed to reconnect to ${device.ssid}");
          }
        }
      }
    });
  }

  // Monitor connectivity for Firebase sync
  void _monitorConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      _isOnline = result != ConnectivityResult.none;

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

      print("Synced ${unsyncedMessages.length} messages to Firebase");
    } catch (e) {
      print("Firebase sync error: $e");
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
    );

    await DatabaseService.insertMessage(dbMessage);
  }

  // Generate unique message ID
  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return '$_deviceId-$random-$timestamp';
  }

  // Get connection info
  Map<String, dynamic> getConnectionInfo() {
    return {
      'deviceId': _deviceId,
      'userName': _userName,
      'role': _currentRole.name,
      'isOnline': _isOnline,
      'connectedDevices': _connectedDevices.length,
      'knownDevices': _knownDevices.length,
      'pendingMessages': _pendingMessages.values
          .expand((messages) => messages)
          .length,
      'processedMessages': _processedMessageIds.length,
      'hostInfo': _hostState != null
          ? {'ssid': _hostState!.ssid, 'isActive': _hostState!.isActive}
          : null,
      'clientInfo': _clientState != null
          ? {
              'hostSsid': _clientState!.hostSsid,
              'isActive': _clientState!.isActive,
            }
          : null,
    };
  }

  // Stop P2P operations
  Future<void> stopP2P() async {
    // Cancel subscriptions
    await _hostStateSubscription?.cancel();
    await _clientStateSubscription?.cancel();
    await _clientListSubscription?.cancel();
    await _receivedTextsSubscription?.cancel();

    // Stop host
    if (_hostInstance != null) {
      await _hostInstance!.removeGroup();
      await _hostInstance!.dispose();
      _hostInstance = null;
    }

    // Stop client
    if (_clientInstance != null) {
      await _clientInstance!.disconnect();
      await _clientInstance!.dispose();
      _clientInstance = null;
    }

    _currentRole = P2PRole.none;
    _connectedDevices.clear();

    notifyListeners();
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
  List<P2PMessage> get messageHistory => List.from(_messageHistory);
  String? get deviceId => _deviceId;
  String? get userName => _userName;
  P2PRole get currentRole => _currentRole;
  bool get isOnline => _isOnline;
  HotspotHostState? get hostState => _hostState;
  HotspotClientState? get clientState => _clientState;
}

// Enums and Models
enum P2PRole { none, host, client }

enum MessageType { text, emergency, location, sos, system, file }

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
