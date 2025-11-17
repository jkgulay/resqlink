import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../models/message_model.dart';
import '../../models/device_model.dart';
import '../temporary_identity_service.dart';
import '../identity_service.dart';

/// Base P2P service with core functionality
abstract class P2PBaseService with ChangeNotifier {
  // Constants
  static const String resqlinkPrefix = "ResQLink_";
  static const String emergencyPassword = "resqlink911";
  static const int defaultPort = 8080;
  static const int tcpPort = 8888;
  static const Duration messageExpiry = Duration(hours: 24);
  static const int maxTtl = 5;

  // Core state
  String? _deviceId;
  String? _userName;
  P2PRole _currentRole = P2PRole.none;
  bool _isConnected = false;
  bool _isDiscovering = false;
  bool _emergencyMode = false;
  bool _isDisposed = false;

  // Collections
  final Map<String, DeviceModel> _connectedDevices = {};
  final List<DeviceModel> _discoveredResQLinkDevices = [];
  final Set<String> _processedMessageIds = {};
  final List<MessageModel> _messageHistory = [];
  final Map<String, String> _macToUuidMapping = {}; // MAC -> UUID mapping

  // Mesh network device registry - tracks ALL devices seen in the network
  final Map<String, DeviceModel> _meshDeviceRegistry =
      {}; // UUID -> DeviceModel
  final Map<String, DateTime> _meshDeviceLastSeen =
      {}; // UUID -> Last seen timestamp
  final Map<String, int> _meshDeviceHopCount =
      {}; // UUID -> Number of hops away

  // Timers
  Timer? _keepAliveTimer;
  Timer? _connectionWatchdog;
  Timer? _messageCleanupTimer;

  // Stream subscriptions
  StreamSubscription? _connectivitySubscription;

  // Callbacks
  Function(MessageModel message)? onMessageReceived;
  Function(String deviceId, String userName)? onDeviceConnected;
  Function(String deviceId)? onDeviceDisconnected;
  Function(List<Map<String, dynamic>> devices)? onDevicesDiscovered;

  // Getters
  String? get deviceId => _deviceId;
  String? get userName => _userName;
  P2PRole get currentRole => _currentRole;
  bool get isConnected => _isConnected;
  bool get isDiscovering => _isDiscovering;
  bool get emergencyMode => _emergencyMode;
  bool get isDisposed => _isDisposed;

  Map<String, DeviceModel> get connectedDevices => Map.from(_connectedDevices);
  List<DeviceModel> get discoveredResQLinkDevices =>
      List.from(_discoveredResQLinkDevices);
  List<MessageModel> get messageHistory => List.from(_messageHistory);

  /// Get all devices known in the mesh network (including multi-hop)
  Map<String, DeviceModel> get meshDevices => Map.from(_meshDeviceRegistry);

  /// Get devices reachable via multi-hop (sorted by hop count)
  List<Map<String, dynamic>> get reachableDevices {
    final devices = <Map<String, dynamic>>[];
    for (final entry in _meshDeviceRegistry.entries) {
      final deviceId = entry.key;
      final device = entry.value;
      final hopCount = _meshDeviceHopCount[deviceId] ?? 99;
      final lastSeen = _meshDeviceLastSeen[deviceId];
      final isStale =
          lastSeen != null && DateTime.now().difference(lastSeen).inMinutes > 5;

      if (!isStale) {
        devices.add({
          'deviceId': deviceId,
          'deviceName': device.userName,
          'hopCount': hopCount,
          'isDirect': hopCount == 0,
          'isMultiHop': hopCount > 0,
          'lastSeen': lastSeen?.millisecondsSinceEpoch ?? 0,
        });
      }
    }

    // Sort by hop count (direct connections first)
    devices.sort((a, b) => a['hopCount'].compareTo(b['hopCount']));
    return devices;
  }

  /// Get UUID for a given MAC address
  String? getUuidForMac(String macAddress) => _macToUuidMapping[macAddress];

  // Emergency mode setter
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

  /// Initialize the service
  Future<bool> initialize(String userName, {String? preferredRole}) async {
    debugPrint('🚀 P2P Base Service initializing with userName: $userName');

    try {
      // Get UUID from IdentityService
      final identity = IdentityService();
      _deviceId = await identity.getDeviceId();

      // Save display name to IdentityService
      _userName = userName;
      await identity.setDisplayName(userName);

      if (preferredRole != null) {
        _currentRole = _parseRole(preferredRole);
      }

      // Check permissions
      await checkAndRequestPermissions();

      // Monitor connectivity
      _monitorConnectivity();

      // Start cleanup timer
      _startMessageCleanup();

      debugPrint(
        '✅ P2P Base Service initialized - UUID: $_deviceId, DisplayName: $_userName',
      );
      return true;
    } catch (e) {
      debugPrint('❌ P2P Base Service initialization failed: $e');
      return false;
    }
  }

  /// Update device ID (called when UUID needs to be refreshed)
  void updateDeviceId(String newDeviceId) {
    final oldDeviceId = _deviceId;
    _deviceId = newDeviceId;
    debugPrint(
      '🔄 Base service device ID updated: $oldDeviceId → $newDeviceId',
    );
  }

  /// Parse role string to enum
  P2PRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'host':
        return P2PRole.host;
      case 'client':
        return P2PRole.client;
      default:
        return P2PRole.none;
    }
  }

  /// Set device role (protected method for subclasses)
  void setRole(P2PRole role) {
    if (_currentRole != role) {
      _currentRole = role;
      debugPrint('🎭 Role changed to: ${role.name}');
      notifyListeners();
    }
  }

  /// Check and request required permissions
  Future<bool> checkAndRequestPermissions() async {
    try {
      final permissions = [Permission.location, Permission.nearbyWifiDevices];

      bool allGranted = true;
      for (final permission in permissions) {
        var status = await permission.status;
        if (status.isPermanentlyDenied) {
          debugPrint(
            '❌ Permission permanently denied: $permission. Please open settings to grant.',
          );
          await openAppSettings();
          allGranted = false;
        } else if (!status.isGranted) {
          final result = await permission.request();
          if (result != PermissionStatus.granted) {
            debugPrint('❌ Permission denied: $permission');
            allGranted = false;
          }
        }
      }

      return allGranted;
    } catch (e) {
      debugPrint('❌ Permission check failed: $e');
      return false;
    }
  }

  /// Monitor connectivity changes
  void _monitorConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final hasConnection = results.any(
        (result) => result != ConnectivityResult.none,
      );
      debugPrint('📶 Connectivity changed: $hasConnection');
      _onConnectivityChanged(hasConnection);
    });
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(bool hasConnection) {
    // Override in subclasses
  }

  /// Start message cleanup timer
  void _startMessageCleanup() {
    _messageCleanupTimer = Timer.periodic(Duration(minutes: 30), (_) {
      _cleanupOldMessages();
    });
  }

  /// Clean up old messages
  void _cleanupOldMessages() {
    final cutoff = DateTime.now().subtract(messageExpiry);
    final cutoffTimestamp = cutoff.millisecondsSinceEpoch;

    _messageHistory.removeWhere(
      (message) => message.timestamp < cutoffTimestamp,
    );
    _processedMessageIds.removeWhere((messageId) {
      // Remove processed IDs that are older than cutoff
      // This requires checking against message history
      return !_messageHistory.any((msg) => msg.messageId == messageId);
    });

    debugPrint(
      '🧹 Cleaned up old messages. History: ${_messageHistory.length}, Processed IDs: ${_processedMessageIds.length}',
    );
  }

  /// Generate unique message ID
  String generateMessageId() {
    return MessageModel.generateMessageId(_deviceId!);
  }

  /// Save message to history
  void saveMessageToHistory(MessageModel message) {
    if (message.messageId != null) {
      _processedMessageIds.add(message.messageId!);
    }
    _messageHistory.add(message);

    // Keep only recent messages in memory
    if (_messageHistory.length > 1000) {
      _messageHistory.removeAt(0);
    }
  }

  /// Check if message was already processed
  bool isMessageProcessed(String messageId) {
    return _processedMessageIds.contains(messageId);
  }

  /// Update mesh device registry from received message
  /// This tracks ALL devices we've seen in the network, not just direct neighbors
  void updateMeshDeviceRegistry(MessageModel message) {
    try {
      final routePath = message.routePath ?? [];
      final now = DateTime.now();

      // Register the sender (direct neighbor, hop count = 0)
      if (message.deviceId != null && message.deviceId!.isNotEmpty) {
        final senderId = message.deviceId!;
        final senderName = message.fromUser;

        if (!_meshDeviceRegistry.containsKey(senderId)) {
          _meshDeviceRegistry[senderId] = DeviceModel(
            id: senderId,
            deviceId: senderId,
            userName: senderName,
            isHost: false,
            isOnline: true,
            lastSeen: now,
            createdAt: now,
          );
          debugPrint(
            '🌐 Mesh registry: Added sender $senderName ($senderId) - DIRECT',
          );
        }
        _meshDeviceLastSeen[senderId] = now;
        _meshDeviceHopCount[senderId] = 0; // Direct connection
      }

      // Register all devices in the route path (multi-hop)
      for (int i = 0; i < routePath.length; i++) {
        final deviceId = routePath[i];
        if (deviceId.isEmpty || deviceId == _deviceId) continue;

        final hopCount = routePath.length - i; // Distance from current device

        if (!_meshDeviceRegistry.containsKey(deviceId)) {
          // New device discovered via multi-hop
          _meshDeviceRegistry[deviceId] = DeviceModel(
            id: deviceId,
            deviceId: deviceId,
            userName: 'Device ${deviceId.substring(0, 8)}', // Placeholder name
            isHost: false,
            isOnline: true,
            lastSeen: now,
            createdAt: now,
          );
          debugPrint(
            '🌐 Mesh registry: Added device $deviceId via multi-hop (${hopCount} hops)',
          );
        } else {
          // Update existing device's last seen
          _meshDeviceLastSeen[deviceId] = now;

          // Update hop count if this path is shorter
          final currentHops = _meshDeviceHopCount[deviceId] ?? 99;
          if (hopCount < currentHops) {
            _meshDeviceHopCount[deviceId] = hopCount;
            debugPrint(
              '🌐 Mesh registry: Updated $deviceId hop count: $currentHops → $hopCount',
            );
          }
        }

        _meshDeviceLastSeen[deviceId] = now;
        if (!_meshDeviceHopCount.containsKey(deviceId) ||
            hopCount < _meshDeviceHopCount[deviceId]!) {
          _meshDeviceHopCount[deviceId] = hopCount;
        }
      }

      // Cleanup stale devices (not seen in 10 minutes)
      final staleThreshold = now.subtract(Duration(minutes: 10));
      final staleDevices = <String>[];
      _meshDeviceLastSeen.forEach((deviceId, lastSeen) {
        if (lastSeen.isBefore(staleThreshold)) {
          staleDevices.add(deviceId);
        }
      });

      for (final deviceId in staleDevices) {
        _meshDeviceRegistry.remove(deviceId);
        _meshDeviceLastSeen.remove(deviceId);
        _meshDeviceHopCount.remove(deviceId);
        debugPrint('🧹 Mesh registry: Removed stale device $deviceId');
      }
    } catch (e) {
      debugPrint('❌ Error updating mesh device registry: $e');
    }
  }

  /// Add connected device with deduplication
  void addConnectedDevice(
    String deviceId,
    String userName, {
    String? macAddress,
  }) {
    final now = DateTime.now();

    // Check if device is already connected to prevent duplicate processing
    final existingDevice = _connectedDevices[deviceId];
    bool isNewConnection = existingDevice == null;
    bool nameChanged = existingDevice?.userName != userName;

    if (!isNewConnection && !nameChanged) {
      debugPrint(
        'ℹ️ Device already connected with same name: $userName ($deviceId)',
      );
      return;
    }

    final device = DeviceModel(
      id: deviceId,
      deviceId: deviceId,
      userName: userName,
      isHost: false,
      isOnline: true,
      lastSeen: now,
      createdAt:
          existingDevice?.createdAt ?? now, // Preserve original creation time
    );

    _connectedDevices[deviceId] = device;

    // Store MAC to UUID mapping if provided
    if (macAddress != null && macAddress.isNotEmpty) {
      _macToUuidMapping[macAddress] = deviceId;
      debugPrint('🔗 Mapped MAC $macAddress -> UUID $deviceId');
    }

    // Also update the discovered device with the correct name if it exists
    final discoveredIndex = _discoveredResQLinkDevices.indexWhere(
      (d) => d.deviceId == deviceId,
    );
    if (discoveredIndex >= 0) {
      final discoveredDevice = _discoveredResQLinkDevices[discoveredIndex];
      final updatedDevice = discoveredDevice.copyWith(
        userName: userName,
        isOnline: true,
        lastSeen: now,
      );
      _discoveredResQLinkDevices[discoveredIndex] = updatedDevice;
      debugPrint('📝 Updated discovered device name: $userName ($deviceId)');
    }

    // Only call the connection callback for new connections
    if (isNewConnection) {
      onDeviceConnected?.call(deviceId, userName);
      debugPrint('✅ NEW device connected: $userName ($deviceId)');
    } else if (nameChanged) {
      debugPrint('🔄 Device name updated: $userName ($deviceId)');
    }

    notifyListeners();
  }

  /// Remove connected device
  void removeConnectedDevice(String deviceId) {
    final device = _connectedDevices.remove(deviceId);
    if (device != null) {
      onDeviceDisconnected?.call(deviceId);
      notifyListeners();
      debugPrint('❌ Device disconnected: ${device.userName} ($deviceId)');
    }
  }

  /// Apply group roster broadcast from host
  void applyGroupRoster(List<dynamic> roster) {
    final now = DateTime.now();
    for (final entry in roster) {
      if (entry is! Map) continue;
      final deviceId = entry['deviceId']?.toString() ?? '';
      if (deviceId.isEmpty || deviceId == _deviceId) continue;

      final userName = entry['userName']?.toString() ?? 'Unknown Device';
      final isHostDevice = entry['isHost'] == true;

      final deviceModel = DeviceModel(
        id: deviceId,
        deviceId: deviceId,
        userName: userName,
        isHost: isHostDevice,
        isOnline: true,
        lastSeen: now,
        createdAt: now,
        discoveryMethod: 'group_roster',
        isConnected: true,
      );

      _meshDeviceRegistry[deviceId] = deviceModel;
      _meshDeviceLastSeen[deviceId] = now;
      _meshDeviceHopCount[deviceId] = 0;
    }

    notifyListeners();
    debugPrint('👥 Applied group roster with ${roster.length} entries');
  }

  /// Update connection status
  void updateConnectionStatus(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      notifyListeners();
      debugPrint('🔗 Connection status changed: $connected');
    }
  }

  /// Get current user's display name from temporary identity service
  Future<String?> getCurrentDisplayName() async {
    try {
      // First try to get from temporary identity service
      final tempName = await TemporaryIdentityService.getTemporaryDisplayName();
      if (tempName != null && tempName.isNotEmpty) {
        return tempName;
      }

      // Fallback to stored username
      return _userName;
    } catch (e) {
      debugPrint('❌ Error getting current display name: $e');
      return _userName;
    }
  }

  /// Abstract methods to be implemented by subclasses
  Future<void> discoverDevices({bool force = false});
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
  });

  /// Emergency mode methods
  void _startEmergencyMode() {
    debugPrint('🚨 Starting emergency mode');
    // Override in subclasses
  }

  void _stopEmergencyMode() {
    debugPrint('✅ Stopping emergency mode');
    // Override in subclasses
  }

  /// Dispose resources
  @override
  void dispose() {
    debugPrint('🗑️ P2P Base Service disposing...');

    _isDisposed = true;

    _keepAliveTimer?.cancel();
    _connectionWatchdog?.cancel();
    _messageCleanupTimer?.cancel();
    _connectivitySubscription?.cancel();

    _connectedDevices.clear();
    _discoveredResQLinkDevices.clear();

    super.dispose();
  }
}

/// P2P Role enumeration
enum P2PRole { none, host, client }

/// P2P Connection Mode enumeration
enum P2PConnectionMode { none, client, wifiDirect }

/// Emergency template enumeration
enum EmergencyTemplate { sos, trapped, medical, safe, evacuating }
