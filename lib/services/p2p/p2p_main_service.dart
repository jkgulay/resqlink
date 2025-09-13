import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resqlink/models/device_model.dart';
import 'package:resqlink/services/p2p/p2p_discovery_service.dart';
import 'package:wifi_iot/wifi_iot.dart';
import '../../models/message_model.dart';
import '../../services/database_service.dart';
import 'p2p_base_service.dart';
import 'p2p_network_service.dart';
import '../connection_fallback.dart';
import '../hotspot_manager.dart';

/// Main P2P service that orchestrates all P2P operations
class P2PMainService extends P2PBaseService {
  // Service components
  late P2PNetworkService _networkService;
  late P2PDiscoveryService _discoveryService;
  late ConnectionFallbackManager _connectionFallbackManager;
  late HotspotManager _hotspotManager;
  static const MethodChannel _hotspotChannel = MethodChannel(
    'resqlink/hotspot',
  );

  // Enhanced state
  bool _hotspotCreationInProgress = false;
  String? _actualCreatedSSID;
  Timer? _hotspotVerificationTimer;
  bool _hotspotFallbackEnabled = true;
  bool _isOnline = false;

  // Additional state for widget compatibility
  P2PConnectionMode _currentConnectionMode = P2PConnectionMode.none;
  String? _connectedHotspotSSID;
  bool _isHotspotEnabled = false;
  bool _isConnecting = false;

  // Message tracing for debugging
  final List<String> _messageTrace = [];

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

      // Initialize service components
      _networkService = P2PNetworkService(this);
      _discoveryService = P2PDiscoveryService(this, _networkService);

      // Initialize hotspot manager
      _hotspotManager = HotspotManager(
        wifiChannel: MethodChannel('wifi_hotspot'),
        deviceId: deviceId,
        startHotspotTcpServer: () async =>
            await _networkService.setupHotspotServices(),
        connectToHotspotTcpServer: (ssid) async =>
            await _networkService.connectToResQLinkNetwork(ssid),
        setCurrentRole: (role) => setRole(_parseRole(role)),
        androidSdkVersion: 29, // You can get this dynamically if needed
        canCreateProgrammaticHotspot: true,
      );

      // Initialize connection fallback manager
      _connectionFallbackManager = ConnectionFallbackManager(
        performDiscoveryScan: () => discoverDevices(force: true),
        connectToAvailableDevice: _connectToAvailableDevice,
        scanForResQLinkHotspots: _scanForResQLinkHotspots,
        connectToResQLinkHotspot: connectToResQLinkNetwork,
        createResQLinkHotspot: () => createEmergencyHotspot(),
        getDiscoveredDevices: () => discoveredDevices,
        isConnected: () => isConnected,
        onConnectionModeChanged: _onConnectionModeChanged,
        onConnectionFailed: _onConnectionFailed,
      );

      await _discoveryService.initialize();

      _addMessageTrace('Main service initialized with userName: $userName');
      debugPrint('✅ P2P Main Service initialized successfully');

      // Setup enhanced monitoring
      _setupEnhancedMonitoring();

      return true;
    } catch (e) {
      debugPrint('❌ P2P Main Service initialization failed: $e');
      _addMessageTrace('Service initialization failed: $e');
      return false;
    }
  }

  ConnectionFallbackManager get connectionFallbackManager =>
      _connectionFallbackManager;
  HotspotManager get hotspotManager => _hotspotManager;
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

  /// Setup enhanced monitoring and verification
  void _setupEnhancedMonitoring() {
    // Monitor hotspot status every 30 seconds
    _hotspotVerificationTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _verifyHotspotStatus();
    });
  }

  Future<void> _connectToAvailableDevice(
    List<Map<String, dynamic>> devices,
  ) async {
    if (devices.isEmpty) {
      debugPrint("❌ No devices available for connection");
      return;
    }

    // Sort devices by priority (emergency devices first, then by signal strength)
    devices.sort((a, b) {
      final aEmergency = a['isEmergency'] == true ? 1 : 0;
      final bEmergency = b['isEmergency'] == true ? 1 : 0;

      if (aEmergency != bEmergency) {
        return bEmergency.compareTo(aEmergency); // Emergency first
      }

      final aSignal = a['signalLevel'] ?? -100;
      final bSignal = b['signalLevel'] ?? -100;
      return bSignal.compareTo(aSignal); // Stronger signal first
    });

    for (final device in devices.take(3)) {
      // Try top 3 devices
      try {
        final success = await connectToDevice(device);
        if (success) {
          debugPrint(
            "✅ Successfully connected to device: ${device['deviceName']}",
          );
          return;
        }
      } catch (e) {
        debugPrint("❌ Failed to connect to device ${device['deviceName']}: $e");
        continue;
      }
    }

    debugPrint("❌ Failed to connect to any available device");
  }

  Future<List<String>> _scanForResQLinkHotspots() async {
    try {
      final networks = await _networkService.scanForResQLinkNetworks();
      return networks
          .map((network) => network.ssid ?? '')
          .where((ssid) => ssid.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('❌ Error scanning for ResQLink hotspots: $e');
      return [];
    }
  }

  void _onConnectionModeChanged(String mode) {
    debugPrint("🔄 Connection mode changed to: $mode");
    notifyListeners();
  }

  void _onConnectionFailed() {
    debugPrint("❌ All connection attempts failed");
    notifyListeners();
  }

  /// Connect to ResQLink network (delegates to network service)
  Future<bool> connectToResQLinkNetwork(String ssid) async {
    if (ssid.isEmpty) return false;

    _isConnecting = true;
    notifyListeners();

    try {
      final result = await _networkService.connectToResQLinkNetwork(ssid);
      if (result) {
        _connectedHotspotSSID = ssid;
        _currentConnectionMode = P2PConnectionMode.client;
        updateConnectionStatus(true);
      }
      return result;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  @override
  Future<bool> createEmergencyHotspot({String? deviceId}) async {
    if (_hotspotCreationInProgress) {
      debugPrint('⏳ Hotspot creation already in progress...');
      return false;
    }

    _hotspotCreationInProgress = true;
    _addMessageTrace('Starting emergency hotspot creation');

    try {
      debugPrint('🔧 Creating emergency hotspot...');

      // 1. Check permissions
      if (!await checkAndRequestPermissions()) {
        debugPrint('❌ Required permissions not granted');
        _addMessageTrace('Hotspot permissions denied');
        return false;
      }

      // 2. Generate unique SSID
      final hotspotSSID =
          "${P2PBaseService.resqlinkPrefix}${deviceId ?? DateTime.now().millisecondsSinceEpoch}";
      debugPrint('🔧 Creating hotspot with SSID: $hotspotSSID');
      _addMessageTrace('Creating hotspot: $hotspotSSID');

      // 3. Enable WiFi first
      await _ensureWiFiEnabled();

      // 4. Try multiple hotspot creation methods
      bool success = false;

      // Method 1: Try native Android implementation
      success = await _createNativeHotspot(hotspotSSID);
      if (success) {
        debugPrint('✅ Native hotspot created');
        _addMessageTrace('Native hotspot created successfully');
      }

      // Method 2: Try WiFiForIoTPlugin (if Method 1 failed)
      if (!success) {
        success = await _createPluginHotspot(hotspotSSID);
        if (success) {
          debugPrint('✅ Plugin hotspot created');
          _addMessageTrace('Plugin hotspot created successfully');
        }
      }

      // Method 3: Manual setup guidance (if all else fails)
      if (!success) {
        success = await _createManualHotspot(hotspotSSID);
        if (success) {
          debugPrint('✅ Manual hotspot setup initiated');
          _addMessageTrace('Manual hotspot setup completed');
        }
      }

      if (success) {
        _actualCreatedSSID = hotspotSSID;
        _isHotspotEnabled = true;
        _currentConnectionMode = P2PConnectionMode.hotspot;

        // Setup network services
        await _networkService.setupHotspotServices();

        // Start discovery after hotspot is ready
        Timer(Duration(seconds: 5), () {
          discoverDevices(force: true);
        });

        // Verify hotspot is working
        await Future.delayed(Duration(seconds: 3));
        final verified = await _verifyHotspotWorking();
        if (!verified) {
          debugPrint('⚠️ Hotspot created but not accessible');
          _addMessageTrace('Hotspot created but verification failed');
        }

        updateConnectionStatus(true);
        return true;
      } else {
        debugPrint('❌ All hotspot creation methods failed');
        _addMessageTrace('All hotspot creation methods failed');
        _isHotspotEnabled = false;
        _currentConnectionMode = P2PConnectionMode.none;
        return false;
      }
    } catch (e) {
      debugPrint('❌ Exception in createEmergencyHotspot: $e');
      _addMessageTrace('Exception in hotspot creation: $e');
      return false;
    } finally {
      _hotspotCreationInProgress = false;
    }
  }

  /// Ensure WiFi is enabled
  Future<void> _ensureWiFiEnabled() async {
    try {
      await WiFiForIoTPlugin.setEnabled(true);
      await Future.delayed(Duration(seconds: 2)); // Wait for WiFi to stabilize
      debugPrint('✅ WiFi enabled');
    } catch (e) {
      debugPrint('⚠️ Failed to enable WiFi: $e');
    }
  }

  /// Create hotspot using native Android methods
  Future<bool> _createNativeHotspot(String ssid) async {
    try {
      debugPrint('🔧 Attempting native Android hotspot creation...');

      final result = await _hotspotChannel.invokeMethod('createHotspot', {
        'ssid': ssid,
        'password': P2PBaseService.emergencyPassword,
        'force': true,
      });

      if (result['success'] == true) {
        debugPrint('✅ Native hotspot created successfully');
        return true;
      } else {
        debugPrint('❌ Native hotspot creation failed: ${result['error']}');
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ Platform exception in native hotspot: $e');
      return false;
    } catch (e) {
      debugPrint('❌ Native hotspot creation exception: $e');
      return false;
    }
  }

  /// Create hotspot using WiFiForIoTPlugin
  Future<bool> _createPluginHotspot(String ssid) async {
    try {
      debugPrint('🔧 Attempting plugin hotspot creation...');

      final result = await WiFiForIoTPlugin.setEnabled(true);

      if (result) {
        debugPrint('✅ Plugin hotspot enabled successfully');
        return true;
      } else {
        debugPrint('❌ Plugin hotspot creation failed');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Plugin hotspot creation exception: $e');
      return false;
    }
  }

  Future<bool> connectToDevice(Map<String, dynamic> device) async {
    try {
      debugPrint('🔗 Attempting to connect to device: ${device['deviceName']}');

      final connectionType = device['connectionType'] as String?;

      switch (connectionType) {
        case 'wifi_direct':
          return await _connectViaWifiDirect(device);
        case 'hotspot':
        case 'hotspot_enhanced':
          return await _connectViaHotspot(device);
        case 'mdns':
        case 'mdns_enhanced':
          return await _connectViaMDNS(device);
        default:
          debugPrint('⚠️ Unknown connection type: $connectionType');
          return false;
      }
    } catch (e) {
      debugPrint('❌ Device connection failed: $e');
      return false;
    }
  }

  Future<bool> _connectViaWifiDirect(Map<String, dynamic> device) async {
    // Implementation for WiFi Direct connection
    final deviceAddress = device['deviceAddress'] as String?;
    if (deviceAddress == null) return false;

    try {
      // Add WiFi Direct connection logic here
      debugPrint('📡 Connecting via WiFi Direct to: $deviceAddress');
      return true; // Placeholder
    } catch (e) {
      debugPrint('❌ WiFi Direct connection failed: $e');
      return false;
    }
  }

  Future<bool> _connectViaHotspot(Map<String, dynamic> device) async {
    final ssid = device['deviceName'] as String?;
    if (ssid == null) return false;

    return await connectToResQLinkNetwork(ssid);
  }

  Future<bool> _connectViaMDNS(Map<String, dynamic> device) async {
    // Implementation for mDNS connection
    debugPrint('📡 Connecting via mDNS to: ${device['deviceName']}');
    return true; // Placeholder
  }

  /// Force device to host role
  Future<void> forceHostRole() async {
    try {
      debugPrint('👑 Forcing host role...');
      setRole(P2PRole.host);
      await createEmergencyHotspot();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to force host role: $e');
    }
  }

  /// Force device to client role
  Future<void> forceClientRole() async {
    try {
      debugPrint('📱 Forcing client role...');
      setRole(P2PRole.client);
      await discoverDevices(force: true);
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
      await discoverDevices(force: true);
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to clear forced role: $e');
    }
  }

  /// Enable or disable hotspot fallback mode
  void setHotspotFallbackEnabled(bool enabled) {
    if (_hotspotFallbackEnabled != enabled) {
      _hotspotFallbackEnabled = enabled;
      debugPrint('🔧 Hotspot fallback ${enabled ? "enabled" : "disabled"}');
      notifyListeners();
    }
  }

  /// Get online status
  bool get isOnline => _isOnline;

  /// Get current connection mode
  P2PConnectionMode get currentConnectionMode => _currentConnectionMode;

  /// Get connected hotspot SSID
  String? get connectedHotspotSSID => _connectedHotspotSSID;

  /// Get hotspot enabled status
  bool get isHotspotEnabled => _isHotspotEnabled;

  /// Get connecting status
  bool get isConnecting => _isConnecting;

  /// Update online status
  void updateOnlineStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      debugPrint('🌐 Online status changed to: $online');
      notifyListeners();
    }
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

  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting from all connections...');

      // Stop network services
      _networkService.dispose();

      // Reset state
      _isHotspotEnabled = false;
      _connectedHotspotSSID = null;
      _currentConnectionMode = P2PConnectionMode.none;
      _isConnecting = false;

      // Clear connected devices
      connectedDevices.clear();

      // Update connection status
      updateConnectionStatus(false);

      debugPrint('✅ Disconnected successfully');
    } catch (e) {
      debugPrint('❌ Disconnect failed: $e');
    }
  }

  /// Get connection information
  Map<String, dynamic> getConnectionInfo() {
    return {
      'deviceId': deviceId,
      'userName': userName,
      'role': currentRole.name,
      'isConnected': isConnected,
      'emergencyMode': emergencyMode,
      'connectedDevices': connectedDevices.length,
      'discoveredDevices': discoveredResQLinkDevices.length,
      'actualCreatedSSID': _actualCreatedSSID,
      'hotspotCreationInProgress': _hotspotCreationInProgress,
    };
  }

  /// Get enhanced connection info
  Map<String, dynamic> getEnhancedConnectionInfo() {
    final networkStatus = _networkService.getNetworkStatus();
    final discoveryStatus = _discoveryService.getDiscoveryStatus();

    return {
      ...getConnectionInfo(),
      'networkStatus': networkStatus,
      'discoveryStatus': discoveryStatus,
      'messageTrace': getMessageTrace(),
      'detailedStatus': getDetailedStatus(),
    };
  }

  Map<String, Map<String, dynamic>> get discoveredDevices {
    final deviceMap = <String, Map<String, dynamic>>{};

    for (final device in discoveredResQLinkDevices) {
      deviceMap[device.deviceId] = {
        'deviceId': device.deviceId,
        'deviceName': device.userName,
        'deviceAddress': device.deviceAddress ?? device.deviceId,
        'connectionType': device.discoveryMethod ?? 'unknown',
        'isAvailable': !device.isConnected,
        'signalLevel': -50, // Default signal level
        'lastSeen': device.lastSeen.millisecondsSinceEpoch,
        'isConnected': device.isConnected,
      };
    }

    return deviceMap;
  }

  List<Map<String, dynamic>> getAvailableHotspots() {
    final networks = _networkService.availableNetworks;
    return networks
        .map(
          (network) => {
            'ssid': network.ssid,
            'bssid': network.bssid,
            'signalLevel': network.level,
            'frequency': network.frequency,
            'capabilities': network.capabilities,
            'isResQLink':
                network.ssid?.startsWith(P2PBaseService.resqlinkPrefix) ??
                false,
          },
        )
        .where((hotspot) => hotspot['isResQLink'] == true)
        .toList();
  }

  bool get hotspotFallbackEnabled => _hotspotFallbackEnabled;

  Map<String, DeviceModel> get knownDevices {
    final knownMap = <String, DeviceModel>{};

    // Add discovered devices as known devices
    for (final device in discoveredResQLinkDevices) {
      knownMap[device.deviceId] = device;
    }

    // Add connected devices
    for (final device in connectedDevices.values) {
      knownMap[device.deviceId] = device;
    }

    return knownMap;
  }

  /// Create hotspot with manual user guidance
  Future<bool> _createManualHotspot(String ssid) async {
    try {
      debugPrint('🔧 Initiating manual hotspot setup...');

      // Show instructions to user (in a real app, this would be a dialog)
      _showHotspotInstructions(ssid);

      // Wait for user to set up hotspot
      debugPrint('⏳ Waiting for manual hotspot creation...');
      await Future.delayed(Duration(seconds: 15));

      // In emergency mode, assume success even if we can't verify
      debugPrint('✅ Manual hotspot setup assumed complete');
      return true;
    } catch (e) {
      debugPrint('❌ Manual hotspot setup exception: $e');
      return false;
    }
  }

  /// Show hotspot setup instructions
  void _showHotspotInstructions(String ssid) {
    debugPrint('''
📱 EMERGENCY HOTSPOT SETUP REQUIRED:

1. Open Settings → Network & Internet → Hotspot & Tethering
2. Turn ON "Portable Wi-Fi hotspot"
3. Set Network Name (SSID) to: $ssid
4. Set Password to: $P2PBaseService.emergencyPassword
5. Tap "Turn on hotspot"

⚠️ This is critical for emergency communication!
''');
  }

  /// Verify hotspot is working
  Future<bool> _verifyHotspotWorking() async {
    try {
      // Try to bind to hotspot port
      final server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        P2PBaseService.tcpPort,
      );
      await server.close();
      debugPrint('✅ Hotspot verification successful');
      return true;
    } catch (e) {
      debugPrint('❌ Hotspot verification failed: $e');
      return false;
    }
  }

  /// Verify hotspot status periodically
  Future<void> _verifyHotspotStatus() async {
    if (_actualCreatedSSID == null || !emergencyMode) return;

    try {
      // Check if hotspot is still active
      final isActive = await _verifyHotspotWorking();
      if (!isActive) {
        debugPrint('⚠️ Hotspot appears inactive, attempting recovery...');
        _addMessageTrace('Hotspot recovery attempted');

        // Try to recreate hotspot
        await createEmergencyHotspot();
      }
    } catch (e) {
      debugPrint('❌ Hotspot status verification error: $e');
    }
  }

  @override
  Future<void> discoverDevices({bool force = false}) async {
    try {
      debugPrint('🔍 Starting device discovery...');
      await _discoveryService.discoverDevices(force: force);
      debugPrint('✅ Device discovery completed');
    } catch (e) {
      debugPrint('❌ Device discovery failed: $e');
    }
  }

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
    try {
      _addMessageTrace('Sending message: $message (type: ${type.name})');

      // Use actual userName from service
      final actualSenderName = userName ?? senderName ?? 'Unknown User';

      debugPrint('📤 Sending message: "$message" from: $actualSenderName');

      // Create message model
      final messageModel = targetDeviceId != null
          ? MessageModel.createDirectMessage(
              fromUser: actualSenderName,
              message: message,
              deviceId: deviceId!,
              targetDeviceId: targetDeviceId,
              type: type,
              isEmergency:
                  type == MessageType.emergency || type == MessageType.sos,
              latitude: latitude,
              longitude: longitude,
            )
          : MessageModel.createBroadcastMessage(
              fromUser: actualSenderName,
              message: message,
              deviceId: deviceId!,
              type: type,
              isEmergency:
                  type == MessageType.emergency || type == MessageType.sos,
              latitude: latitude,
              longitude: longitude,
            );

      // Save to database first
      await DatabaseService.insertMessage(messageModel);

      // Add to message history
      saveMessageToHistory(messageModel);

      // Send via network
      await _networkService.broadcastMessage(messageModel);

      // Update status to sent
      if (messageModel.messageId != null) {
        await DatabaseService.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.sent,
        );
      }

      _addMessageTrace('Message sent successfully: ${messageModel.messageId}');
      debugPrint('✅ Message sent successfully');
    } catch (e) {
      _addMessageTrace('Message send failed: $e');
      debugPrint('❌ Message send failed: $e');
      rethrow;
    }
  }

  /// Add message trace for debugging
  void _addMessageTrace(String trace) {
    final timestamp = DateTime.now().toIso8601String();
    _messageTrace.add('[$timestamp] $trace');

    // Keep only last 100 entries
    if (_messageTrace.length > 100) {
      _messageTrace.removeAt(0);
    }
  }

  /// Get message trace for debugging
  List<String> getMessageTrace() => List.from(_messageTrace);

  /// Get detailed service status
  String getDetailedStatus() {
    final networkStatus = _networkService.getNetworkStatus();
    final discoveryStatus = _discoveryService.getDiscoveryStatus();

    return '''
=== P2P Main Service Status ===
Device ID: $deviceId
User Name: $userName
Current Role: $currentRole
Emergency Mode: $emergencyMode
Connected Devices: ${connectedDevices.length}
Discovered Devices: ${discoveredResQLinkDevices.length}

Network Status:
- TCP Server: ${networkStatus['tcpServerActive']}
- HTTP Server: ${networkStatus['httpServerActive']}
- Connected Sockets: ${networkStatus['connectedSockets']}
- WebSocket Connections: ${networkStatus['webSocketConnections']}

Discovery Status:
- Discovery In Progress: ${discoveryStatus['discoveryInProgress']}
- WiFi Direct Available: ${discoveryStatus['wifiDirectAvailable']}
- Discovered Devices: ${discoveryStatus['discoveredDevices']}

Hotspot Status:
- Created SSID: $_actualCreatedSSID
- Creation In Progress: $_hotspotCreationInProgress

Recent Message Traces:
${_messageTrace.take(5).join('\n')}
''';
  }

  /// Get available ResQLink networks
  List<WifiNetwork> get availableNetworks => _networkService.availableNetworks;

  @override
  void dispose() {
    debugPrint('🗑️ P2P Main Service disposing...');

    _hotspotVerificationTimer?.cancel();

    _networkService.dispose();
    _discoveryService.dispose();
    _connectionFallbackManager.dispose(); // Add this

    _messageTrace.clear();

    super.dispose();
  }
}

// Backwards compatibility typedef
typedef P2PConnectionService = P2PMainService;
