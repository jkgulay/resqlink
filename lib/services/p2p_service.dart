import 'dart:io';
import 'dart:math' as math;
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
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

class P2PConnectionService with ChangeNotifier {
  static const String serviceType = "_resqlink._tcp";
  static const Duration messageExpiry = Duration(hours: 24);
  static const String emergencyPassword = "RESQLINK911";
  static const Duration autoConnectDelay = Duration(seconds: 5);
  static const int maxTtl = 5;
  static const String hotspotPrefix = "ResQLink_";
  static const String hotspotPassword = "RESQLINK911";

  // Hotspot fallback state
  bool _hotspotFallbackEnabled = false;
  Timer? _hotspotScanTimer;
  List<WiFiAccessPoint> _availableHotspots = [];
  String? _connectedHotspotSSID;

  bool get hotspotFallbackEnabled => _hotspotFallbackEnabled;

  void setHotspotFallbackEnabled(bool enabled) {
    _hotspotFallbackEnabled = enabled;
    debugPrint("🔧 Hotspot fallback ${enabled ? 'enabled' : 'disabled'}");
    notifyListeners();
  }

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

  bool _allowRoleSwitching = true;
  Timer? _roleDecisionTimer;

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

  // Socket keep-alive management
  Timer? _keepAliveTimer;
  Timer? _connectionWatchdog;
  int _consecutiveFailures = 0;
  static const int _maxFailures = 3;
  static const Duration _keepAliveInterval = Duration(seconds: 10);
  static const Duration _connectionTimeout = Duration(seconds: 30);

  // Socket health monitoring
  bool _socketHealthy = true;
  DateTime? _lastSuccessfulPing;
  int _pingSequence = 0;
  final Map<int, DateTime> _pendingPings = {};

  // Manual role forcing
  bool _forceRoleMode = false;
  P2PRole? _forcedRole;

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
  List<Map<String, dynamic>> getAvailableHotspots() {
    return _availableHotspots
        .map(
          (hotspot) => {
            'ssid': hotspot.ssid,
            'signalLevel': hotspot.level,
            'frequency': hotspot.frequency,
            'bssid': hotspot.bssid,
            'capabilities': hotspot.capabilities,
          },
        )
        .toList();
  }

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
      _startConnectionHealthMonitoring();

      // Monitor connectivity
      _monitorConnectivity();

      // Load known devices and pending messages
      await _loadKnownDevices();
      await _loadPendingMessages();
      Timer(Duration(seconds: 2), () => _ensureConnection());

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

  Future<void> forceHostRole() async {
    debugPrint("👑 FORCING device to become HOST");

    _forceRoleMode = true;
    _forcedRole = P2PRole.host;

    // Disconnect from current connections if any
    if (_isConnected) {
      debugPrint("🔄 Disconnecting from current connection to become host");
      await _gracefulDisconnect();
      await Future.delayed(Duration(seconds: 2));
    }

    // Stop any ongoing discovery
    if (_isDiscovering) {
      await _stopDiscovery();
      await Future.delayed(Duration(milliseconds: 500));
    }

    // Force create group as host
    await _becomeHost();

    // Update UI
    notifyListeners();
  }

  // Force device to be client
  Future<void> forceClientRole() async {
    debugPrint("🔗 FORCING device to become CLIENT");

    _forceRoleMode = true;
    _forcedRole = P2PRole.client;

    // Disconnect from current connections if hosting
    if (_isConnected && _currentRole == P2PRole.host) {
      debugPrint("🔄 Stopping host mode to become client");
      await _gracefulDisconnect();
      await Future.delayed(Duration(seconds: 2));
    }

    // Start discovery to find hosts to connect to
    await discoverDevices(force: true);

    // Wait for discovery and try to connect
    Timer(Duration(seconds: 5), () async {
      final availableDevices = _discoveredDevices.values
          .where((device) => device['isAvailable'] == true)
          .toList();

      if (availableDevices.isNotEmpty) {
        try {
          await connectToDevice(availableDevices.first);
        } catch (e) {
          debugPrint("❌ Failed to connect as forced client: $e");
          _showNoHostsAvailableError();
        }
      } else {
        debugPrint("❌ No hosts available for client connection");
        _showNoHostsAvailableError();
      }
    });

    // Update UI
    notifyListeners();
  }

  // Clear role forcing (return to auto mode)
  Future<void> clearForcedRole() async {
    debugPrint("🔄 Clearing forced role, returning to AUTO mode");

    _forceRoleMode = false;
    _forcedRole = null;

    // If currently connected, stay connected but allow future auto-decisions
    if (!_isConnected && _emergencyMode) {
      // Restart auto-connection process
      _scheduleRoleDecision();
    }

    notifyListeners();
  }

  void _showNoHostsAvailableError() {
    debugPrint("⚠️ No hosts available for client connection");
    // You can emit an error event here for the UI to show
    // Or use a callback if needed
  }

  // Check if role is currently forced
  bool get isRoleForced => _forceRoleMode;
  P2PRole? get forcedRole => _forcedRole;

  Future<void> _makeRoleDecision() async {
    // Check if role is forced
    if (_forceRoleMode && _forcedRole != null) {
      debugPrint("🎯 Using FORCED role: ${_forcedRole!.name}");

      switch (_forcedRole!) {
        case P2PRole.host:
          await _becomeHost();
          return;
        case P2PRole.client:
          await _forceClientConnection();
          return;
        case P2PRole.none:
          // Should not happen, but handle gracefully
          break;
      }
    }

    // Continue with normal auto-decision logic
    debugPrint("🤔 Making automatic role decision...");

    await Future.delayed(Duration(seconds: 3));

    final availableDevices = _discoveredDevices.values
        .where((device) => device['isAvailable'] == true)
        .toList();

    debugPrint(
      "📊 Found ${availableDevices.length} available devices for auto-decision",
    );

    if (availableDevices.isEmpty) {
      debugPrint("👑 No devices found, becoming host (auto)");
      await _becomeHost();
    } else {
      final shouldBecomeHost = _shouldBecomeHost(availableDevices.length);

      if (shouldBecomeHost) {
        debugPrint("👑 Auto-decision: becoming host");
        await _becomeHost();
      } else {
        debugPrint("🔗 Auto-decision: becoming client");
        await _connectToAvailableDevice(availableDevices);
      }
    }
  }

  Future<void> _forceClientConnection() async {
    debugPrint("🔗 Forcing client connection...");

    final availableDevices = _discoveredDevices.values
        .where((device) => device['isAvailable'] == true)
        .toList();

    if (availableDevices.isEmpty) {
      debugPrint("⚠️ No hosts available, starting discovery...");
      await discoverDevices(force: true);

      // Wait and try again
      Timer(Duration(seconds: 5), () async {
        final newDevices = _discoveredDevices.values
            .where((device) => device['isAvailable'] == true)
            .toList();

        if (newDevices.isNotEmpty) {
          await _connectToAvailableDevice(newDevices);
        } else {
          _showNoHostsAvailableError();
        }
      });
    } else {
      await _connectToAvailableDevice(availableDevices);
    }
  }

  Future<void> _becomeHost() async {
    if (_isConnecting || _isConnected) return;

    try {
      _isConnecting = true;
      _currentRole = P2PRole.host;

      debugPrint("👑 Creating WiFi Direct group (becoming Group Owner)...");

      // Stop any ongoing discovery
      await WifiDirectPlugin.stopDiscovery();
      await Future.delayed(Duration(milliseconds: 500));

      // Create WiFi Direct group - this establishes us as Group Owner
      // and sets up the TCP server socket for incoming connections
      bool success = await WifiDirectPlugin.startAsServer(
        "RESQLINK_$_userName",
      );

      if (success) {
        debugPrint("✅ WiFi Direct group created successfully");
        debugPrint("📡 TCP server socket listening for connections...");
        notifyListeners();
      } else {
        debugPrint("❌ Failed to create WiFi Direct group");
        _currentRole = P2PRole.none;
        _isConnecting = false;
      }
    } catch (e) {
      debugPrint("❌ Error creating WiFi Direct group: $e");
      _currentRole = P2PRole.none;
      _isConnecting = false;
    }
  }

  bool _shouldBecomeHost(int availableDevicesCount) {
    // User preference takes priority
    if (_preferredRole == 'host') return true;
    if (_preferredRole == 'client') return false;

    // Auto mode: Random factor for load balancing
    final random = DateTime.now().millisecond % 100;

    if (availableDevicesCount > 3) {
      return random < 25; // 25% chance
    } else if (availableDevicesCount > 1) {
      return random < 50; // 50% chance
    } else {
      return random < 75; // 75% chance with few devices
    }
  }

  Future<void> _connectToAvailableDevice(
    List<Map<String, dynamic>> devices,
  ) async {
    // Sort devices by preference (known devices first, then by signal strength, etc.)
    devices.sort((a, b) {
      // Prefer known devices
      final aKnown = _knownDevices.containsKey(a['deviceAddress']) ? 1 : 0;
      final bKnown = _knownDevices.containsKey(b['deviceAddress']) ? 1 : 0;

      if (aKnown != bKnown) return bKnown.compareTo(aKnown);

      // Then by discovery time (more recent first)
      final aTime = a['discoveredAt'] ?? 0;
      final bTime = b['discoveredAt'] ?? 0;
      return bTime.compareTo(aTime);
    });

    // Try to connect to the best device
    for (final device in devices) {
      try {
        await connectToDevice(device);
        return; // Success
      } catch (e) {
        debugPrint("❌ Failed to connect to ${device['deviceName']}: $e");
        continue; // Try next device
      }
    }

    // If all connections failed, become host
    debugPrint("❌ Failed to connect to any device, becoming host");
    await _becomeHost();
  }

  void setRolePreference(String? preference) {
    _preferredRole = preference;
    debugPrint("📝 Role preference set to: $preference");

    // If emergency mode is on, apply the change immediately
    if (_emergencyMode && !_isConnected && !_isConnecting) {
      _scheduleRoleDecision();
    }
  }

  void _scheduleRoleDecision() {
    _roleDecisionTimer?.cancel();
    _roleDecisionTimer = Timer(Duration(seconds: 2), _makeRoleDecision);
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

  Future<void> _ensureConnection() async {
    if (_isConnected || _isConnecting || _isDisposed) return;

    debugPrint("🔄 Ensuring P2P connection...");

    // Try discovery first
    if (!_isDiscovering) {
      await discoverDevices(force: true);
    }

    // Wait for discovery to find devices
    await Future.delayed(Duration(seconds: 3));

    // If emergency mode is on and we still don't have connection, be more aggressive
    if (_emergencyMode && !_isConnected && !_isConnecting) {
      await _aggressiveConnectionAttempt();
    }
  }

  Future<void> _aggressiveConnectionAttempt() async {
    debugPrint("🚨 Aggressive connection attempt in emergency mode");

    final availableDevices = _discoveredDevices.values
        .where((device) => device['isAvailable'] == true)
        .toList();

    if (availableDevices.isEmpty) {
      // No devices found, become host immediately
      debugPrint("👑 No devices found, creating emergency group");
      await createEmergencyGroup();
      return;
    }

    // Try connecting to all available devices simultaneously (first one wins)
    final connectionFutures = availableDevices.map((device) async {
      try {
        await connectToDevice(device);
        return true;
      } catch (e) {
        debugPrint("Failed to connect to ${device['deviceName']}: $e");
        return false;
      }
    });

    final results = await Future.wait(connectionFutures, eagerError: false);

    // If none connected, create our own group
    if (!results.any((success) => success) && !_isConnected) {
      debugPrint(
        "🆘 All connections failed, creating emergency group as last resort",
      );
      await createEmergencyGroup();
    }
  }

  // Add periodic connection health check
  Timer? _connectionHealthTimer;

  void _startConnectionHealthMonitoring() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      if (_emergencyMode && !_isConnected && !_isConnecting) {
        debugPrint(
          "⚠️ Emergency mode active but not connected, attempting reconnection",
        );
        _ensureConnection();
      }

      // Also check if we should switch roles for better connectivity
      if (_allowRoleSwitching && _connectedDevices.length < 2) {
        _evaluateRoleSwitch();
      }
    });
  }

  void _evaluateRoleSwitch() {
    final now = DateTime.now();
    final timeSinceLastConnection = _lastPongTime != null
        ? now.difference(_lastPongTime!)
        : Duration(minutes: 10);

    // If we've been without good connections for too long, try switching roles
    if (timeSinceLastConnection > Duration(minutes: 2)) {
      if (_currentRole == P2PRole.client) {
        debugPrint("🔄 Poor connectivity as client, trying to become host");
        _gracefulDisconnect().then((_) => _becomeHost());
      } else if (_currentRole == P2PRole.host && _connectedDevices.isEmpty) {
        debugPrint("🔄 No clients connecting to host, trying client mode");
        _gracefulDisconnect().then((_) => discoverDevices(force: true));
      }
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

    // Reset current connections if needed
    if (_allowRoleSwitching && _isConnected) {
      _gracefulDisconnect();
    }

    // Start discovery
    if (!_isDiscovering) {
      discoverDevices(force: true);
    }

    // Schedule role decision
    _scheduleRoleDecision();

    // Set up periodic rediscovery
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (!_isConnected && !_isDiscovering && !_isDisposed) {
        debugPrint("🔄 Periodic rediscovery in emergency mode");
        discoverDevices(force: true);
        _scheduleRoleDecision();
      }
    });
  }

  Future<void> _gracefulDisconnect() async {
    try {
      debugPrint("🔄 Gracefully disconnecting for role switch");
      await WifiDirectPlugin.disconnect();
      _isConnected = false;
      _currentRole = P2PRole.none;
      _connectedDevices.clear();
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Error during graceful disconnect: $e");
    }
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

  Future<void> createEmergencyGroup() async {
    try {
      if (_isConnected) {
        debugPrint('Cleaning up existing P2P connections...');
        await stopP2P();
        await Future.delayed(const Duration(seconds: 1));
      }

      debugPrint("🚨 Creating emergency group with fallback...");

      _currentRole = P2PRole.host;
      _emergencyMode = true;

      // Try WiFi Direct first
      bool wifiDirectSuccess = await WifiDirectPlugin.startAsServer(
        "RESQLINK_$_userName",
      );

      if (wifiDirectSuccess) {
        debugPrint("✅ Emergency WiFi Direct group created");
      } else {
        debugPrint("⚠️ WiFi Direct failed, creating hotspot fallback...");
        await _createResQLinkHotspot();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error creating emergency group: $e');

      // Final fallback - create hotspot
      try {
        await _createResQLinkHotspot();
      } catch (hotspotError) {
        debugPrint('❌ Hotspot fallback also failed: $hotspotError');
        rethrow;
      }
    }
  }

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
      final connectionType =
          deviceData['connectionType'] as String? ?? 'wifi_direct';

      debugPrint(
        "🔗 Connecting to: $deviceName ($deviceAddress) via $connectionType",
      );

      if (connectionType == 'hotspot') {
        await _connectToHotspot(deviceData);
      } else {
        await _connectViaWifiDirect(deviceData);
      }
    } catch (e) {
      _isConnecting = false;
      notifyListeners();
      debugPrint("❌ Connection error: $e");
      rethrow;
    }
  }

  Future<void> _connectToHotspot(Map<String, dynamic> deviceData) async {
    final hotspotSSID = deviceData['deviceAddress'] as String;
    final signalLevel = deviceData['signalLevel'] as int? ?? -100;

    debugPrint(
      "📶 Connecting to ResQLink hotspot: $hotspotSSID (Signal: ${signalLevel}dBm)",
    );

    try {
      // For Android, we need to use platform channels or show user instructions
      if (Platform.isAndroid) {
        await _connectToAndroidWiFi(hotspotSSID, hotspotPassword);
      } else if (Platform.isIOS) {
        await _connectToiOSWiFi(hotspotSSID, hotspotPassword);
      } else {
        throw UnsupportedError('Platform not supported for WiFi connection');
      }

      // Wait for WiFi connection to establish
      await Future.delayed(Duration(seconds: 5));

      // Try to establish TCP connection to the hotspot host
      await _connectToHotspotTcpServer(deviceData);
    } catch (e) {
      debugPrint("❌ Hotspot connection failed: $e");
      rethrow;
    }
  }

  // Android WiFi connection using platform channels
  Future<void> _connectToAndroidWiFi(String ssid, String password) async {
    try {
      debugPrint("🤖 Attempting Android WiFi connection to: $ssid");

      // For Android 10+ (API 29+), we need to use WifiNetworkSpecifier
      // This requires platform-specific code (method channels)

      // Show user instructions for manual connection
      await _showWiFiConnectionDialog(ssid, password);
    } catch (e) {
      debugPrint("❌ Android WiFi connection error: $e");
      rethrow;
    }
  }

  // iOS WiFi connection
  Future<void> _connectToiOSWiFi(String ssid, String password) async {
    try {
      debugPrint("🍎 Attempting iOS WiFi connection to: $ssid");

      // iOS doesn't allow programmatic WiFi connection
      // Show user instructions
      await _showWiFiConnectionDialog(ssid, password);
    } catch (e) {
      debugPrint("❌ iOS WiFi connection error: $e");
      rethrow;
    }
  }

  Future<void> _showWiFiConnectionDialog(String ssid, String password) async {
    debugPrint("📋 Showing WiFi connection instructions for: $ssid");

    // You can implement a callback here to show UI dialog
    // For now, just log the instructions
    debugPrint("🔧 MANUAL CONNECTION REQUIRED:");
    debugPrint("   1. Go to WiFi Settings");
    debugPrint("   2. Connect to: $ssid");
    debugPrint("   3. Enter password: $password");
    debugPrint("   4. Return to ResQLink app");

    // Simulate user action time
    await Future.delayed(Duration(seconds: 10));
  }

  Future<void> _connectViaWifiDirect(Map<String, dynamic> deviceData) async {
    // Your existing WiFi Direct connection logic
    final deviceAddress = deviceData['deviceAddress'] as String;
    final deviceName = deviceData['deviceName'] as String;

    debugPrint(
      "🔗 Initiating WiFi Direct connection to: $deviceName ($deviceAddress)",
    );

    await WifiDirectPlugin.stopDiscovery();
    await Future.delayed(Duration(milliseconds: 500));

    bool success = await WifiDirectPlugin.connect(deviceAddress);

    if (success) {
      debugPrint("✅ WiFi Direct connection initiated successfully");
      _currentRole = P2PRole.client;
      await _waitForFullConnectionEstablishment();

      await _saveDeviceCredentials(
        deviceAddress,
        DeviceCredentials(
          deviceId: deviceAddress,
          ssid: "DIRECT-$deviceName",
          psk: "",
          isHost: false,
          lastSeen: DateTime.now(),
        ),
      );

      debugPrint("🎉 Full TCP connection established with $deviceName");
    } else {
      throw Exception('Failed to connect to device');
    }
  }

  // TCP server for hotspot mode
  ServerSocket? _hotspotServer;

  Future<void> _startHotspotTcpServer() async {
    try {
      _hotspotServer = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);
      debugPrint("📡 Hotspot TCP server listening on port 8888");

      _hotspotServer!.listen((Socket client) {
        debugPrint("🔗 New hotspot client connected: ${client.remoteAddress}");
        _handleHotspotClient(client);
      });
    } catch (e) {
      debugPrint("❌ Failed to start hotspot TCP server: $e");
      rethrow;
    }
  }

  void _handleHotspotClient(Socket client) {
    final clientId = "${client.remoteAddress}:${client.remotePort}";

    client.listen(
      (data) {
        final message = String.fromCharCodes(data);
        debugPrint("📨 Hotspot message from $clientId: $message");
        _handleIncomingText(message);
      },
      onDone: () {
        debugPrint("👋 Hotspot client disconnected: $clientId");
        _connectedDevices.remove(clientId);
        notifyListeners();
      },
      onError: (error) {
        debugPrint("❌ Hotspot client error: $error");
        _connectedDevices.remove(clientId);
        notifyListeners();
      },
    );

    // Send handshake
    final handshake = {
      'type': 'handshake',
      'deviceId': _deviceId,
      'userName': _userName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'role': _currentRole.name,
      'connectionType': 'hotspot',
    };

    client.add(utf8.encode(jsonEncode(handshake)));
  }

  Future<void> _connectToHotspotTcpServer(
    Map<String, dynamic> deviceData,
  ) async {
    try {
      final possibleIPs = [
        "192.168.43.1", // Android hotspot
        "192.168.1.1", // Common router IP
        "10.0.0.1", // Alternative hotspot IP
        "172.20.10.1", // iOS hotspot
      ];

      const port = 8888;
      Socket? socket;
      String? connectedIP;

      // Try connecting to each possible IP
      for (final ip in possibleIPs) {
        try {
          debugPrint("🔌 Trying to connect to: $ip:$port");
          socket = await Socket.connect(ip, port).timeout(Duration(seconds: 3));
          connectedIP = ip; // ✅ We use this variable
          debugPrint(
            "✅ Connected to ResQLink TCP server at: $connectedIP:$port",
          );
          break;
        } catch (e) {
          debugPrint("❌ Failed to connect to $ip:$port - $e");
          continue;
        }
      }

      if (socket == null || connectedIP == null) {
        throw Exception('Could not connect to any ResQLink TCP server');
      }

      // Rest of the method remains the same...
      // Handle the connection like a regular P2P connection
      final deviceId = deviceData['deviceAddress'] as String;

      _connectedDevices[deviceId] = ConnectedDevice(
        id: deviceId,
        name: deviceData['deviceName'] as String,
        isHost: false,
        connectedAt: DateTime.now(),
      );

      _currentRole = P2PRole.client;
      _isConnected = true;
      _isConnecting = false;
      _connectedHotspotSSID = deviceId;

      // Log successful connection with IP
      debugPrint("🎉 Successfully connected to $deviceId via $connectedIP");

      // Continue with rest of method...
      // Set up message handling, etc.
      socket.listen(
        (data) {
          final message = String.fromCharCodes(data);
          debugPrint("📨 Hotspot message received: ${message.length} bytes");
          _handleIncomingText(message);
        },
        onDone: () {
          debugPrint("🔌 Hotspot connection closed");
          _handleConnectionLost();
        },
        onError: (error) {
          debugPrint("❌ Hotspot connection error: $error");
          _handleConnectionLost();
        },
      );

      // Send handshake
      final handshake = {
        'type': 'resqlink_handshake',
        'version': '1.0',
        'deviceId': _deviceId,
        'userName': _userName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'role': _currentRole.name,
        'connectionType': 'hotspot',
        'capabilities': ['messaging', 'location', 'emergency'],
        'deviceInfo': {
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
        },
      };

      socket.add(utf8.encode(jsonEncode(handshake)));
      debugPrint("🤝 ResQLink handshake sent via hotspot");

      _startHotspotKeepAlive(socket);
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Failed to connect to hotspot TCP server: $e");
      rethrow;
    }
  }

  Socket? _hotspotSocket;

  void _startHotspotKeepAlive(Socket socket) {
    _hotspotSocket = socket;

    Timer.periodic(Duration(seconds: 15), (timer) {
      if (_hotspotSocket == null || _isDisposed) {
        timer.cancel();
        return;
      }

      try {
        final keepAlive = {
          'type': 'hotspot_keepalive',
          'deviceId': _deviceId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        _hotspotSocket!.add(utf8.encode(jsonEncode(keepAlive)));
        debugPrint("💓 Hotspot keep-alive sent");
      } catch (e) {
        debugPrint("❌ Hotspot keep-alive failed: $e");
        timer.cancel();
        _handleConnectionLost();
      }
    });
  }

  Future<void> _waitForFullConnectionEstablishment() async {
    int attempts = 0;
    const maxAttempts = 30; // 15 seconds timeout

    debugPrint(
      "⏳ Waiting for WiFi Direct group formation and TCP socket establishment...",
    );

    while (!_isConnected && attempts < maxAttempts) {
      await Future.delayed(Duration(milliseconds: 500));
      attempts++;

      // Log progress
      if (attempts % 6 == 0) {
        // Every 3 seconds
        debugPrint("⏳ Still waiting for connection... (${attempts * 0.5}s)");
      }
    }

    if (!_isConnected) {
      throw Exception(
        'Connection timeout - WiFi Direct group or TCP socket failed to establish',
      );
    }

    debugPrint(
      "✅ WiFi Direct connection fully established (${attempts * 0.5}s)",
    );
  }

  Future<bool> testTcpConnection() async {
    if (!_isConnected) return false;

    try {
      final testMessage = jsonEncode({
        'type': 'connection_test',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'testData': 'Hello TCP!',
      });

      await _sendMessage(testMessage);
      debugPrint("✅ TCP connection test successful");
      return true;
    } catch (e) {
      debugPrint("❌ TCP connection test failed: $e");
      return false;
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

  Map<String, dynamic> getNetworkInfo() {
    return {
      'isConnected': _isConnected,
      'isGroupOwner': _isGroupOwner,
      'groupOwnerAddress': _groupOwnerAddress,
      'role': _currentRole.name,
      'networkType': 'WiFi Direct over TCP',
    };
  }

  DateTime? _lastPongTime;

  void _handleTcpConnectionLoss() {
    debugPrint("💔 Handling TCP connection loss");

    // TCP connection lost - this could be due to:
    // - Physical distance
    // - WiFi interference
    // - Device going to sleep
    // - App being backgrounded

    _isConnected = false;
    _currentRole = P2PRole.none;
    _connectedDevices.clear();
    notifyListeners();

    // In emergency mode, try to re-establish WiFi Direct group
    if (_emergencyMode && !_isDisposed) {
      Timer(Duration(seconds: 2), () {
        if (!_isConnected && !_isConnecting) {
          debugPrint("🔄 Attempting to re-establish WiFi Direct connection");
          discoverDevices(force: true);
          _scheduleRoleDecision();
        }
      });
    }
  }

  void _handlePong(Map<String, dynamic> json) {
    final isKeepAlive = json['type'] == 'keep_alive_pong';

    if (isKeepAlive) {
      final sequence = json['sequence'] as int?;
      if (sequence != null && _pendingPings.containsKey(sequence)) {
        final sentTime = _pendingPings.remove(sequence)!;
        final latency = DateTime.now().difference(sentTime);

        // Reset failure counters on successful response
        _consecutiveFailures = 0;
        _socketHealthy = true;
        _lastSuccessfulPing = DateTime.now();

        debugPrint(
          "🏓 Keep-alive pong received (seq: $sequence, latency: ${latency.inMilliseconds}ms)",
        );
      }
    } else {
      _lastPongTime = DateTime.now();
      debugPrint("🏓 Regular pong received");
    }
  }

  // Heartbeat to maintain connection
  void _startHeartbeat() {
    _keepAliveTimer?.cancel();
    _connectionWatchdog?.cancel();

    debugPrint("💓 Starting enhanced TCP keep-alive system");

    // Primary keep-alive timer - sends pings
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (timer) {
      if (_isConnected && !_isDisposed) {
        _sendKeepAlivePing();
      } else {
        timer.cancel();
      }
    });

    // Connection watchdog - monitors for dead connections
    _connectionWatchdog = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      if (_isConnected) {
        _checkSocketHealth();
      } else {
        timer.cancel();
      }
    });

    // Reset health indicators
    _consecutiveFailures = 0;
    _socketHealthy = true;
    _lastSuccessfulPing = DateTime.now();
  }

  void _stopHeartbeat() {
    _keepAliveTimer?.cancel();
    _connectionWatchdog?.cancel();
    _keepAliveTimer = null;
    _connectionWatchdog = null;
    _pendingPings.clear();
    debugPrint("💤 TCP keep-alive system stopped");
  }

  Future<void> _sendKeepAlivePing() async {
    if (!_isConnected || _isDisposed) return;

    try {
      _pingSequence++;
      final now = DateTime.now();
      _pendingPings[_pingSequence] = now;

      final keepAlivePacket = {
        'type': 'keep_alive_ping',
        'sequence': _pingSequence,
        'timestamp': now.millisecondsSinceEpoch,
        'deviceId': _deviceId,
        'socketCheck': true,
      };

      await _sendMessage(jsonEncode(keepAlivePacket));

      debugPrint("📡 Keep-alive ping sent (seq: $_pingSequence)");

      // Set timeout for this specific ping
      Timer(Duration(seconds: 10), () {
        if (_pendingPings.containsKey(_pingSequence)) {
          debugPrint("⏰ Keep-alive ping $_pingSequence timed out");
          _handlePingTimeout(_pingSequence);
        }
      });
    } catch (e) {
      debugPrint("❌ Keep-alive ping failed: $e");
      _handleSocketError();
    }
  }

  void _checkSocketHealth() {
    final now = DateTime.now();

    // Check if we have too many pending pings
    if (_pendingPings.length > 3) {
      debugPrint(
        "⚠️ Too many pending pings (${_pendingPings.length}), socket may be dead",
      );
      _handleSocketSuspectedDead();
      return;
    }

    // Check if last successful communication was too long ago
    if (_lastSuccessfulPing != null) {
      final timeSinceLastSuccess = now.difference(_lastSuccessfulPing!);
      if (timeSinceLastSuccess > _connectionTimeout) {
        debugPrint(
          "💀 No successful communication for ${timeSinceLastSuccess.inSeconds}s",
        );
        _handleSocketSuspectedDead();
        return;
      }
    }

    // Check consecutive failures
    if (_consecutiveFailures >= _maxFailures) {
      debugPrint("💀 Too many consecutive failures ($_consecutiveFailures)");
      _handleSocketSuspectedDead();
      return;
    }

    debugPrint("✅ Socket health check passed");
  }

  void _handlePingTimeout(int sequence) {
    _pendingPings.remove(sequence);
    _consecutiveFailures++;

    debugPrint(
      "⚠️ Ping timeout (failures: $_consecutiveFailures/$_maxFailures)",
    );

    if (_consecutiveFailures >= _maxFailures) {
      _handleSocketSuspectedDead();
    }
  }

  void _handleSocketSuspectedDead() {
    debugPrint("💀 TCP socket suspected dead, attempting recovery");

    _socketHealthy = false;
    _pendingPings.clear();

    // Force disconnect and attempt reconnection
    _handleTcpConnectionLoss();
  }

  void _handleSocketError() {
    _consecutiveFailures++;
    debugPrint(
      "❌ Socket error (failures: $_consecutiveFailures/$_maxFailures)",
    );

    if (_consecutiveFailures >= _maxFailures) {
      _handleSocketSuspectedDead();
    }
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

  Future<void> _sendMessage(String message) async {
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        if (_hotspotFallbackEnabled && _hotspotServer != null) {
          await _sendToAllHotspotClients(message);
        } else {
          await WifiDirectPlugin.sendText(message);
        }

        debugPrint(
          "📤 Sent ${message.length} bytes over ${_hotspotFallbackEnabled ? 'hotspot' : 'WiFi Direct'} (attempt ${retries + 1})",
        );

        if (retries > 0) {
          _consecutiveFailures = math.max(
            0,
            _consecutiveFailures - 1,
          ); // ✅ Fixed
        }

        return; // Success
      } catch (e) {
        retries++;
        debugPrint("❌ Send error (attempt $retries/$maxRetries): $e");

        if (retries < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retries));
        } else {
          _handleSocketError();
          rethrow;
        }
      }
    }
  }

  Future<void> _sendToAllHotspotClients(String message) async {
    if (_hotspotServer == null) return;

    final messageBytes = utf8.encode(message);

    for (final device in _connectedDevices.values) {
      try {
        // Send via the hotspot socket if available
        if (_hotspotSocket != null) {
          _hotspotSocket!.add(messageBytes);
          await _hotspotSocket!.flush();
          debugPrint("📤 Sent to hotspot client: ${device.name}");
        }
      } catch (e) {
        debugPrint("❌ Failed to send to ${device.name}: $e");
      }
    }
  }

  // Enhanced discovery with cooldown
  Future<void> discoverDevices({bool force = false}) async {
    final now = DateTime.now();

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

      debugPrint(
        "🔍 Starting unified device discovery (WiFi Direct + Hotspot)...",
      );

      // Clear old discoveries
      _discoveredDevices.clear();

      // First, try WiFi Direct discovery
      bool wifiDirectSuccess = await WifiDirectPlugin.startDiscovery();

      if (wifiDirectSuccess) {
        debugPrint("✅ WiFi Direct discovery started");

        // Wait for WiFi Direct results
        await Future.delayed(Duration(seconds: 8));

        // If WiFi Direct found devices, we're good
        if (_discoveredDevices.isNotEmpty) {
          debugPrint(
            "📱 WiFi Direct found ${_discoveredDevices.length} devices",
          );
          _stopDiscovery();
          return;
        }
      }

      // WiFi Direct failed or found no devices - try hotspot fallback
      debugPrint("🔄 WiFi Direct found no devices, trying hotspot fallback...");
      await _discoverHotspotDevices();
    } catch (e) {
      debugPrint("❌ Discovery error: $e");
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
  }

  Future<void> _discoverHotspotDevices() async {
    try {
      // Check WiFi scan permission
      final locationPermission = await Permission.locationWhenInUse.request();
      if (!locationPermission.isGranted) {
        debugPrint("❌ Location permission denied for WiFi scan");
        return;
      }

      debugPrint("📡 Scanning for ResQLink hotspots...");

      // Check if we can start WiFi scan
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan != CanStartScan.yes) {
        debugPrint("❌ Cannot start WiFi scan: $canScan");
        return;
      }

      // Start WiFi scan
      final scanResult = await WiFiScan.instance.startScan();
      debugPrint("📡 WiFi scan started: $scanResult");

      // Wait for scan to complete
      await Future.delayed(Duration(seconds: 3));

      // Get scan results
      final canGetResults = await WiFiScan.instance.canGetScannedResults();
      if (canGetResults != CanGetScannedResults.yes) {
        debugPrint("❌ Cannot get scan results: $canGetResults");
        return;
      }

      final scanResults = await WiFiScan.instance.getScannedResults();

      // Filter for ResQLink hotspots
      _availableHotspots = scanResults
          .where((ap) => ap.ssid.startsWith(hotspotPrefix))
          .toList();

      debugPrint("🔍 Found ${_availableHotspots.length} ResQLink hotspots");

      // Add discovered hotspots to discovered devices
      for (final hotspot in _availableHotspots) {
        _discoveredDevices[hotspot.ssid] = {
          'deviceName': hotspot.ssid,
          'deviceAddress': hotspot.ssid,
          'status': 0, // Available
          'isAvailable': true,
          'discoveredAt': DateTime.now().millisecondsSinceEpoch,
          'connectionType': 'hotspot',
          'isHost': true,
          'signalLevel': hotspot.level,
          'frequency': hotspot.frequency,
          'bssid': hotspot.bssid,
        };
      }

      // If no ResQLink hotspots found, create our own
      if (_availableHotspots.isEmpty) {
        debugPrint("📶 No ResQLink hotspots found, creating our own...");
        Timer(Duration(seconds: 2), () async {
          if (_discoveredDevices.isEmpty && _hotspotFallbackEnabled) {
            await _createResQLinkHotspot();
          }
        });
      }

      notifyListeners();
    } catch (e) {
      debugPrint("❌ Hotspot discovery error: $e");
    }
  }

  

  Future<void> _createResQLinkHotspot() async {
    try {
      final hotspotName =
          "$hotspotPrefix${_userName}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";

      debugPrint("📶 Creating ResQLink hotspot: $hotspotName");

      // Start TCP server on hotspot
      await _startHotspotTcpServer();

      // Update role
      _currentRole = P2PRole.host;
      _connectedHotspotSSID = hotspotName;

      // Add ourselves as a "discovered" hotspot device for UI purposes
      _discoveredDevices[hotspotName] = {
        'deviceName': hotspotName,
        'deviceAddress': hotspotName,
        'status': 0, // Available
        'isAvailable': true,
        'discoveredAt': DateTime.now().millisecondsSinceEpoch,
        'connectionType': 'hotspot',
        'isHost': true,
      };

      debugPrint("✅ ResQLink hotspot created: $hotspotName");
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Failed to create hotspot: $e");
    }
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

  final Map<String, Socket> _deviceSockets = {};

  Future<void> _sendToDevice(String deviceId, String message) async {
    final socket = _deviceSockets[deviceId];
    if (socket != null) {
      try {
        socket.write(message);
        await socket.flush();
      } catch (e) {
        debugPrint("Failed to send to $deviceId: $e");
        _deviceSockets.remove(deviceId);
      }
    }
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
      await _sendToDevice(deviceId!, messageJson);
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
        case 'ping':
          _handlePing(json);
        case 'pong':
          _handlePong(json);
        case 'message':
          _handleChatMessage(json);
        default:
          debugPrint("🤷 Unknown message type: $messageType");
      }
    } catch (e) {
      debugPrint("❌ Error handling incoming text: $e");
    }
  }

  void _handlePing(Map<String, dynamic> json) {
    final isKeepAlive = json['socketCheck'] == true;

    if (isKeepAlive) {
      // Respond to keep-alive ping immediately
      final pong = {
        'type': 'keep_alive_pong',
        'sequence': json['sequence'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'deviceId': _deviceId,
        'originalTimestamp': json['timestamp'],
      };

      _sendMessage(jsonEncode(pong));
      debugPrint("🏓 Keep-alive pong sent (seq: ${json['sequence']})");
    } else {
      // Handle regular ping
      final pong = {
        'type': 'pong',
        'deviceId': _deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'originalTimestamp': json['timestamp'],
      };

      _sendMessage(jsonEncode(pong));
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

  Future<void> _forwardMessage(P2PMessage message) async {
    // Don't forward our own messages or messages we've already seen
    if (message.senderId == _deviceId ||
        _processedMessageIds.contains(message.id)) {
      return;
    }

    // Decrease TTL
    final forwardedMessage = message.copyWith(
      ttl: message.ttl - 1,
      routePath: [...message.routePath, _deviceId!],
    );

    if (forwardedMessage.ttl <= 0) {
      debugPrint("Message TTL expired, not forwarding: ${message.id}");
      return;
    }

    // Forward to ALL connected devices except the sender
    for (var deviceId in _connectedDevices.keys) {
      if (deviceId != message.senderId) {
        try {
          final messageJson = jsonEncode({
            'type': 'message',
            ...forwardedMessage.toJson(),
          });
          await _sendMessage(messageJson);
          debugPrint("📡 Forwarded message ${message.id} to $deviceId");
        } catch (e) {
          debugPrint("❌ Failed to forward to $deviceId: $e");
        }
      }
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

      // 🔥 ADD THIS: Forward to other devices for multi-hop
      _forwardMessage(message);

      debugPrint(
        "📨 Received and forwarded message from ${message.senderName}",
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
      'preferredRole': _preferredRole,
      'isRoleForced': _forceRoleMode,
      'forcedRole': _forcedRole?.name,
      'isConnected': _isConnected,
      'isGroupOwner': _isGroupOwner,
      'connectedDevices': _connectedDevices.length,
      'knownDevices': _knownDevices.length,
      'discoveredDevices': _discoveredDevices.length,
      'isDiscovering': _isDiscovering,
      'isConnecting': _isConnecting,
      'emergencyMode': _emergencyMode,
      'socketHealthy': _socketHealthy,
      'lastPing': _lastSuccessfulPing?.millisecondsSinceEpoch,
      'consecutiveFailures': _consecutiveFailures,
      'hotspotFallbackEnabled': _hotspotFallbackEnabled,
      'connectedHotspot': _connectedHotspotSSID,
      'connectionType': _hotspotFallbackEnabled ? 'hotspot' : 'wifi_direct',
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
    _hotspotScanTimer?.cancel();
    _autoConnectTimer?.cancel();
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _messageCleanupTimer?.cancel();
    _syncTimer?.cancel();
    _reconnectTimer?.cancel();

    // Close hotspot server
    await _hotspotServer?.close();
    _hotspotServer = null;

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
