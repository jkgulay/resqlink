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

  String? _normalizeMacAddress(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (cleaned.length != 12) return null;
    final buffer = StringBuffer();
    for (int i = 0; i < cleaned.length; i += 2) {
      if (buffer.isNotEmpty) buffer.write(':');
      buffer.write(cleaned.substring(i, i + 2).toUpperCase());
    }
    return buffer.toString();
  }

  /// Resolve any identifier (session ID, MAC, UUID) into a canonical UUID/MAC
  String? resolveDeviceIdentifier(String? identifier) {
    if (identifier == null) return null;
    var normalized = identifier.trim();
    if (normalized.isEmpty) return null;

    if (normalized.startsWith('chat_')) {
      normalized = normalized.substring(5);
    }

    final restored = _restoreIdentifierFormatting(normalized);
    final candidates = <String>{normalized, restored};

    for (final candidate in candidates) {
      if (_connectedDevices.containsKey(candidate) ||
          _meshDeviceRegistry.containsKey(candidate) ||
          candidate == _deviceId) {
        return candidate;
      }
    }

    for (final candidate in candidates) {
      final macAddress = _normalizeMacAddress(candidate);
      if (macAddress == null) continue;

      if (_macToUuidMapping.containsKey(macAddress)) {
        return _macToUuidMapping[macAddress];
      }

      if (_connectedDevices.containsKey(macAddress) ||
          _meshDeviceRegistry.containsKey(macAddress)) {
        return macAddress;
      }
    }

    return restored;
  }

  /// Convert placeholder identifiers (e.g., chat session IDs) back to UUID/MAC format
  String _restoreIdentifierFormatting(String value) {
    if (!value.contains('_')) {
      return value;
    }

    final segments = value.split('_');

    // UUIDs stored as chat_<uuid with underscores>
    if (segments.length == 5 &&
        segments[0].length == 8 &&
        segments[1].length == 4 &&
        segments[2].length == 4 &&
        segments[3].length == 4 &&
        segments[4].length == 12 &&
        segments.every((part) => RegExp(r'^[0-9a-fA-F]+$').hasMatch(part))) {
      final uuid = [
        segments[0],
        segments[1],
        segments[2],
        segments[3],
        segments[4],
      ].join('-');
      return uuid;
    }

    // MAC addresses stored as chat_<aa_bb_cc_dd_ee_ff>
    if (segments.length == 6 &&
        segments.every(
          (part) =>
              part.length == 2 && RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(part),
        )) {
      return segments.map((part) => part.toUpperCase()).join(':');
    }

    return value;
  }

  /// Check if a device is directly connected (WiFi Direct / socket peer)
  bool isDeviceDirectlyConnected(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return false;

    if (_connectedDevices.containsKey(deviceId)) {
      return true;
    }

    final resolved = resolveDeviceIdentifier(deviceId);
    if (resolved != null && _connectedDevices.containsKey(resolved)) {
      return true;
    }

    final macVariant = _normalizeMacAddress(deviceId);
    if (macVariant != null && _connectedDevices.containsKey(macVariant)) {
      return true;
    }

    return false;
  }

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
  String? getUuidForMac(String macAddress) {
    final normalized = _normalizeMacAddress(macAddress);
    if (normalized == null) return null;
    return _macToUuidMapping[normalized];
  }

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
            '🌐 Mesh registry: Added device $deviceId via multi-hop ($hopCount hops)',
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
      // Notify listeners so UI and pages update reachability immediately
      notifyListeners();
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

    final normalizedId = _normalizeMacAddress(deviceId) ?? deviceId;

    // Check if device is already connected to prevent duplicate processing
    final existingDevice = _connectedDevices[normalizedId];
    bool isNewConnection = existingDevice == null;
    bool nameChanged = existingDevice?.userName != userName;

    if (!isNewConnection && !nameChanged) {
      debugPrint(
        'ℹ️ Device already connected with same name: $userName ($deviceId)',
      );
      return;
    }

    final device = DeviceModel(
      id: normalizedId,
      deviceId: normalizedId,
      userName: userName,
      isHost: false,
      isOnline: true,
      lastSeen: now,
      createdAt:
          existingDevice?.createdAt ?? now, // Preserve original creation time
    );

    _connectedDevices[normalizedId] = device;

    // Store MAC to UUID mapping if provided
    if (macAddress != null && macAddress.isNotEmpty) {
      final normalizedMac = _normalizeMacAddress(macAddress);
      if (normalizedMac != null) {
        _macToUuidMapping[normalizedMac] = normalizedId;
        if (_connectedDevices.containsKey(normalizedMac) &&
            normalizedMac != normalizedId) {
          _connectedDevices.remove(normalizedMac);
          debugPrint(
            '♻️ Removed temporary MAC entry $normalizedMac after resolving UUID $normalizedId',
          );
        }
        debugPrint('🔗 Mapped MAC $normalizedMac -> UUID $normalizedId');
      }
    }

    // Also update the discovered device with the correct name if it exists
    final discoveredIndex = _discoveredResQLinkDevices.indexWhere(
      (d) => d.deviceId == deviceId || d.deviceId == normalizedId,
    );
    if (discoveredIndex >= 0) {
      final discoveredDevice = _discoveredResQLinkDevices[discoveredIndex];
      final updatedDevice = discoveredDevice.copyWith(
        userName: userName,
        isOnline: true,
        lastSeen: now,
      );
      _discoveredResQLinkDevices[discoveredIndex] = updatedDevice;
      debugPrint(
        '📝 Updated discovered device name: $userName ($normalizedId)',
      );
    }

    // Only call the connection callback for new connections
    if (isNewConnection) {
      onDeviceConnected?.call(normalizedId, userName);
      debugPrint('✅ NEW device connected: $userName ($normalizedId)');
    } else if (nameChanged) {
      debugPrint('🔄 Device name updated: $userName ($normalizedId)');
    }

    // Ensure mesh registry records the fresh direct connection
    _meshDeviceRegistry[normalizedId] = device;
    _meshDeviceLastSeen[normalizedId] = now;
    _meshDeviceHopCount[normalizedId] = 0;

    notifyListeners();
  }

  /// Remove connected device
  void removeConnectedDevice(String deviceId) {
    final resolvedId = resolveDeviceIdentifier(deviceId) ?? deviceId;
    final device =
        _connectedDevices.remove(resolvedId) ??
        (resolvedId == deviceId ? null : _connectedDevices.remove(deviceId));
    if (device != null) {
      onDeviceDisconnected?.call(resolvedId);
      notifyListeners();
      debugPrint('❌ Device disconnected: ${device.userName} ($resolvedId)');
    }

    _meshDeviceRegistry.remove(resolvedId);
    _meshDeviceLastSeen.remove(resolvedId);
    _meshDeviceHopCount.remove(resolvedId);
  }

  /// Check if a device is reachable either directly or via mesh roster
  bool isDeviceReachable(String? deviceId, {Duration? maxAge}) {
    final resolvedId = resolveDeviceIdentifier(deviceId);
    if (resolvedId == null || resolvedId.isEmpty) return false;

    // Direct connection check
    if (_connectedDevices.containsKey(resolvedId)) {
      return true;
    }

    // Mesh registry check
    final meshDevice = _meshDeviceRegistry[resolvedId];
    if (meshDevice == null) {
      return false;
    }

    final lastSeen = _meshDeviceLastSeen[resolvedId];
    if (lastSeen == null) return false;

    final freshnessWindow = maxAge ?? Duration(minutes: 5);
    final isFresh = DateTime.now().difference(lastSeen) <= freshnessWindow;

    if (isFresh) {
      final hopCount = _meshDeviceHopCount[resolvedId] ?? 99;
      debugPrint(
        '✅ Device $resolvedId is reachable (hops: $hopCount, last seen: ${DateTime.now().difference(lastSeen).inSeconds}s ago)',
      );
    }

    return isFresh;
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
      _meshDeviceHopCount[deviceId] = isHostDevice
          ? 0
          : 1; // Host is direct, others are 1 hop away
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
