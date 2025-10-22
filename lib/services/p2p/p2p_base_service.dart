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
  List<DeviceModel> get discoveredResQLinkDevices => List.from(_discoveredResQLinkDevices);
  List<MessageModel> get messageHistory => List.from(_messageHistory);

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

      debugPrint('✅ P2P Base Service initialized - UUID: $_deviceId, DisplayName: $_userName');
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
    debugPrint('🔄 Base service device ID updated: $oldDeviceId → $newDeviceId');
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
      final permissions = [
        Permission.locationWhenInUse,
        Permission.location,
        Permission.nearbyWifiDevices,
      ];

      bool allGranted = true;
      for (final permission in permissions) {
        final status = await permission.request();
        if (status != PermissionStatus.granted) {
          debugPrint('❌ Permission denied: $permission');
          allGranted = false;
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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final hasConnection = results.any((result) => result != ConnectivityResult.none);
        debugPrint('📶 Connectivity changed: $hasConnection');
        _onConnectivityChanged(hasConnection);
      },
    );
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
    
    _messageHistory.removeWhere((message) => message.timestamp < cutoffTimestamp);
    _processedMessageIds.removeWhere((messageId) {
      // Remove processed IDs that are older than cutoff
      // This requires checking against message history
      return !_messageHistory.any((msg) => msg.messageId == messageId);
    });
    
    debugPrint('🧹 Cleaned up old messages. History: ${_messageHistory.length}, Processed IDs: ${_processedMessageIds.length}');
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

  /// Add connected device with deduplication
  void addConnectedDevice(String deviceId, String userName, {String? macAddress}) {
    final now = DateTime.now();

    // Check if device is already connected to prevent duplicate processing
    final existingDevice = _connectedDevices[deviceId];
    bool isNewConnection = existingDevice == null;
    bool nameChanged = existingDevice?.userName != userName;

    if (!isNewConnection && !nameChanged) {
      debugPrint('ℹ️ Device already connected with same name: $userName ($deviceId)');
      return;
    }

    final device = DeviceModel(
      id: deviceId,
      deviceId: deviceId,
      userName: userName,
      isHost: false,
      isOnline: true,
      lastSeen: now,
      createdAt: existingDevice?.createdAt ?? now, // Preserve original creation time
    );

    _connectedDevices[deviceId] = device;

    // Store MAC to UUID mapping if provided
    if (macAddress != null && macAddress.isNotEmpty) {
      _macToUuidMapping[macAddress] = deviceId;
      debugPrint('🔗 Mapped MAC $macAddress -> UUID $deviceId');
    }

    // Also update the discovered device with the correct name if it exists
    final discoveredIndex = _discoveredResQLinkDevices.indexWhere(
      (d) => d.deviceId == deviceId
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
enum P2PConnectionMode {
  none,
  client,
  wifiDirect
}

/// Emergency template enumeration
enum EmergencyTemplate { sos, trapped, medical, safe, evacuating }