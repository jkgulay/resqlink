import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resqlink/gps_page.dart';
import 'package:wifi_direct_plugin/wifi_direct_plugin.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:multicast_dns/multicast_dns.dart';
import '../models/message_model.dart';
import '../services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'queued_message.dart';
import 'hotspot_manager.dart';
import 'connection_fallback.dart';
import 'emergency_connection.dart';

class P2PConnectionService with ChangeNotifier {
  // Constants
  static const String resqlinkPrefix = "ResQLink_";
  static const String emergencyPassword = "RESQLINK911";
  static const String serviceType = "_resqlink._tcp.local";
  static const int defaultPort = 8080;
  static const int tcpPort = 8888;
  static const Duration messageExpiry = Duration(hours: 24);
  static const Duration autoConnectDelay = Duration(seconds: 5);
  static const int maxTtl = 5;
  static const MethodChannel _wifiChannel = MethodChannel('resqlink/wifi');

  // Singleton instance
  static P2PConnectionService? _instance;

  // Network Manager Integration
  bool _isHotspotEnabled = false;
  bool _isWiFiEnabled = false;
  List<WiFiAccessPoint> _availableNetworks = [];
  List<ResQLinkDevice> _discoveredResQLinkDevices = [];
  HttpServer? _localServer;
  WebSocketChannel? _wsChannel;
  MDnsClient? _mdnsClient;

  // Enhanced manager system
  late EnhancedMessageQueue _messageQueue;
  late HotspotManager _hotspotManager;
  late ConnectionFallbackManager _connectionFallbackManager;
  late EmergencyConnectionManager _emergencyConnectionManager;

  // Device identity and role
  String? _deviceId;
  String? _userName;
  P2PRole _currentRole = P2PRole.none;
  String? _preferredRole;
  ConnectionMode _currentConnectionMode = ConnectionMode.none;

  // Enhanced connection state
  bool _isDiscovering = false;
  bool _isDisposed = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isGroupOwner = false;
  bool _isOnline = false;
  DateTime? _lastDiscoveryTime;
  String? _groupOwnerAddress;

  // Role and emergency management
  bool _forceRoleMode = false;
  P2PRole? _forcedRole;
  Timer? _roleDecisionTimer;
  bool _emergencyMode = false;

  // Enhanced networking state
  bool _hotspotFallbackEnabled = false;
  Timer? _hotspotScanTimer;
  List<WiFiAccessPoint> _availableHotspots = [];
  String? _connectedHotspotSSID;

  // Network state management
  final Map<String, ConnectedDevice> _connectedDevices = {};
  final Map<String, DeviceCredentials> _knownDevices = {};
  final Map<String, Map<String, dynamic>> _discoveredDevices = {};

  // Enhanced socket management
  Timer? _keepAliveTimer;
  Timer? _connectionWatchdog;
  Timer? _connectionHealthTimer;
  bool _socketHealthy = true;
  DateTime? _lastSuccessfulPing;
  int _consecutiveFailures = 0;

  // Message handling
  final Set<String> _processedMessageIds = {};
  final List<P2PMessage> _messageHistory = [];
  Timer? _messageCleanupTimer;
  Timer? _syncTimer;
  Timer? _reconnectTimer;

  // Enhanced timers
  Timer? _autoConnectTimer;
  Timer? _discoveryTimer;
  Timer? _heartbeatTimer;

  // Stream subscriptions
  StreamSubscription? _peersChangeSubscription;
  StreamSubscription? _connectionChangeSubscription;
  StreamSubscription? _connectivitySubscription;

  // Enhanced TCP sockets
  ServerSocket? _hotspotServer;
  Socket? _hotspotSocket;
  final Map<String, Socket> _deviceSockets = {};
  final Map<String, WebSocketChannel> _webSocketConnections = {};

  // Factory and initialization
  factory P2PConnectionService() {
    if (_instance == null || _instance!._isDisposed) {
      _instance = P2PConnectionService._internal();
    }
    return _instance!;
  }

  P2PConnectionService._internal();

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  // Enhanced callbacks
  Function(P2PMessage message)? onMessageReceived;
  Function(String deviceId, String userName)? onDeviceConnected;
  Function(String deviceId)? onDeviceDisconnected;
  Function(List<Map<String, dynamic>> devices)? onDevicesDiscovered;
  Function(ResQLinkMessage message)? onResQLinkMessageReceived;

  // Enhanced getters
  bool get isHotspotEnabled => _isHotspotEnabled;
  bool get isWiFiEnabled => _isWiFiEnabled;
  List<WiFiAccessPoint> get availableNetworks => _availableNetworks;
  List<ResQLinkDevice> get discoveredResQLinkDevices =>
      _discoveredResQLinkDevices;
  ConnectionMode get currentConnectionMode => _currentConnectionMode;

  // Existing getters
  bool get hotspotFallbackEnabled => _hotspotFallbackEnabled;
  String? get connectedHotspotSSID => _connectedHotspotSSID;
  bool get emergencyMode => _emergencyMode;

  set emergencyMode(bool value) {
    if (_emergencyMode != value) {
      _emergencyMode = value;
      if (value) {
        _startEmergencyMode();
        _emergencyConnectionManager.startEmergencyMonitoring();
      } else {
        _stopEmergencyMode();
        _emergencyConnectionManager.stopEmergencyMonitoring();
      }
      notifyListeners();
    }
  }

  bool get isRoleForced => _forceRoleMode;
  P2PRole? get forcedRole => _forcedRole;

  // Manager getters
  EnhancedMessageQueue get messageQueue => _messageQueue;
  HotspotManager get hotspotManager => _hotspotManager;
  ConnectionFallbackManager get connectionFallbackManager =>
      _connectionFallbackManager;
  EmergencyConnectionManager get emergencyConnectionManager =>
      _emergencyConnectionManager;

  // State getters
  bool get isDiscovering => _isDiscovering;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  bool get isGroupOwner => _isGroupOwner;
  bool get isOnline => _isOnline;
  String? get deviceId => _deviceId;
  String? get userName => _userName;
  P2PRole get currentRole => _currentRole;
  String? get groupOwnerAddress => _groupOwnerAddress;

  // Collection getters
  Map<String, ConnectedDevice> get connectedDevices =>
      Map.from(_connectedDevices);
  Map<String, DeviceCredentials> get knownDevices => Map.from(_knownDevices);
  Map<String, Map<String, dynamic>> get discoveredDevices =>
      Map.from(_discoveredDevices);
  List<P2PMessage> get messageHistory => List.from(_messageHistory);

  // Enhanced initialization
  Future<bool> initialize(String userName, {String? preferredRole}) async {
    try {
      _userName = userName;
      _deviceId = _generateDeviceId(userName);
      _preferredRole = preferredRole;

      // Initialize enhanced network manager features
      await _initializeNetworkManager();

      // Initialize existing managers
      _messageQueue = EnhancedMessageQueue(sendToDevice: _sendToDevice);

      _hotspotManager = HotspotManager(
        wifiChannel: _wifiChannel,
        deviceId: _deviceId,
        startHotspotTcpServer: _startHotspotTcpServer,
        connectToHotspotTcpServer: (ssid) =>
            _connectToHotspotTcpServer({'ssid': ssid}),
        setCurrentRole: (role) {
          _currentRole = role == 'host' ? P2PRole.host : P2PRole.client;
          notifyListeners();
        },
      );

      _connectionFallbackManager = ConnectionFallbackManager(
        performDiscoveryScan: _performDiscoveryScan,
        connectToAvailableDevice: _connectToAvailableDevice,
        scanForResQLinkHotspots: _scanForResQLinkHotspots,
        connectToResQLinkHotspot: _connectToResQLinkHotspot,
        createResQLinkHotspot: _createResQLinkHotspot,
        getDiscoveredDevices: () => _discoveredDevices,
        isConnected: () => _isConnected,
        onConnectionModeChanged: (mode) {
          debugPrint("🔗 Connection mode changed to: $mode");
          notifyListeners();
        },
        onConnectionFailed: () {
          debugPrint("❌ All connection attempts failed");
          notifyListeners();
        },
      );

      _emergencyConnectionManager = EmergencyConnectionManager(
        isConnected: () => _isConnected,
        isEmergencyMode: () => _emergencyMode,
        sendEmergencyPing: _sendKeepAlivePing,
        attemptEmergencyReconnection: () =>
            _connectionFallbackManager.initiateConnection(),
        createResQLinkHotspot: _createResQLinkHotspot,
        broadcastEmergencyBeacon: _broadcastEmergencyBeacon,
        handleEmergencyConnectionLoss: () async =>
            _handleTcpConnectionLoss(), // FIXED: Added async wrapper
      );

      // Load and setup
      await _messageQueue.loadPendingMessages();
      await _setupPlatformChannels();

      // Initialize WiFi Direct
      bool success = await WifiDirectPlugin.initialize();
      if (!success) {
        debugPrint("❌ Failed to initialize WiFi Direct");
        return false;
      }

      // Setup listeners and monitoring
      _setupWifiDirectListeners();
      _startMessageCleanup();
      _startHeartbeat();
      _startReconnectTimer();
      _startConnectionHealthMonitoring();
      _monitorConnectivity();

      // Load data
      await _loadKnownDevices();
      await _loadPendingMessages();
      Timer(Duration(seconds: 2), () => _ensureConnection());

      debugPrint("✅ Enhanced P2P Service initialized successfully");
      return true;
    } catch (e) {
      debugPrint("❌ Enhanced P2P initialization error: $e");
      return false;
    }
  }

  // MISSING METHODS IMPLEMENTATION

  Future<void> _sendToDevice(String deviceId, String message) async {
    try {
      if (_deviceSockets.containsKey(deviceId)) {
        _deviceSockets[deviceId]!.write(message);
      } else if (_webSocketConnections.containsKey(deviceId)) {
        _webSocketConnections[deviceId]!.sink.add(message);
      }
    } catch (e) {
      debugPrint('Error sending to device $deviceId: $e');
    }
  }

  Future<void> _startEmergencyMode() async {
    debugPrint("🚨 Starting emergency mode");
    _emergencyMode = true;
    await createEmergencyHotspot();
  }

  Future<void> _stopEmergencyMode() async {
    debugPrint("✅ Stopping emergency mode");
    _emergencyMode = false;
  }

  Future<void> _startHotspotTcpServer() async {
    try {
      _hotspotServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        tcpPort,
      );
      debugPrint("🔌 TCP server started on port $tcpPort");

      _hotspotServer!.listen((socket) {
        final clientId = '${socket.remoteAddress.address}:${socket.remotePort}';
        _deviceSockets[clientId] = socket;

        socket.listen(
          (data) {
            final message = String.fromCharCodes(data);
            _handleIncomingText(message);
          },
          onDone: () {
            _deviceSockets.remove(clientId);
          },
        );
      });
    } catch (e) {
      debugPrint("❌ Failed to start TCP server: $e");
    }
  }

  Future<void> _connectToHotspotTcpServer(
    Map<String, dynamic> deviceInfo,
  ) async {
    try {
      final socket = await Socket.connect(InternetAddress.anyIPv4, tcpPort);
      _hotspotSocket = socket;

      socket.listen(
        (data) {
          final message = String.fromCharCodes(data);
          _handleIncomingText(message);
        },
        onDone: () {
          _hotspotSocket = null;
        },
      );
    } catch (e) {
      debugPrint("❌ Failed to connect to TCP server: $e");
    }
  }

  Future<void> _sendKeepAlivePing() async {
    try {
      final pingMessage = jsonEncode({
        'type': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      if (_hotspotSocket != null) {
        _hotspotSocket!.write(pingMessage);
      }

      for (final socket in _deviceSockets.values) {
        socket.write(pingMessage);
      }
    } catch (e) {
      debugPrint("❌ Keep alive ping failed: $e");
    }
  }

  void _handleTcpConnectionLoss() {
    debugPrint("❌ TCP connection lost");
    _isConnected = false;
    notifyListeners();
  }

  Future<void> _setupPlatformChannels() async {
    // Platform channel setup for native functionality
  }

  void _startMessageCleanup() {
    _messageCleanupTimer = Timer.periodic(Duration(hours: 1), (timer) {
      final now = DateTime.now();
      _messageHistory.removeWhere(
        (msg) => now.difference(msg.timestamp) > messageExpiry,
      );
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _sendKeepAlivePing();
      }
    });
  }

  void _startReconnectTimer() {
    _reconnectTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      if (!_isConnected && _emergencyMode) {
        _connectionFallbackManager.initiateConnection();
      }
    });
  }

  void _startConnectionHealthMonitoring() {
    _connectionHealthTimer = Timer.periodic(Duration(seconds: 15), (timer) {
      if (_isConnected) {
        // Check connection health
        _checkConnectionHealth();
      }
    });
  }

  void _monitorConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      // FIXED: Handle List<ConnectivityResult> instead of single result
      _isOnline = !results.contains(ConnectivityResult.none);
      notifyListeners();
    });
  }

  Future<void> _loadKnownDevices() async {
    // Load known devices from database
  }

  Future<void> _loadPendingMessages() async {
    // Load pending messages from database
  }

  void _ensureConnection() {
    if (!_isConnected && _emergencyMode) {
      _connectionFallbackManager.initiateConnection();
    }
  }

  void _checkConnectionHealth() {
    // Implementation for connection health checking
  }

  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000000);
    return '$_deviceId-$random-$timestamp';
  }

  Future<void> _saveMessage(P2PMessage message, bool isOutgoing) async {
    try {
      final messageModel = MessageModel(
        endpointId: message.targetDeviceId ?? 'broadcast',
        fromUser: message.senderId,
        message: message.message,
        isMe: isOutgoing,
        isEmergency:
            message.type == MessageType.emergency ||
            message.type == MessageType.sos,
        timestamp: message.timestamp.millisecondsSinceEpoch,
        latitude: message.latitude,
        longitude: message.longitude,
        messageId: message.id,
        type: message.type.name,
        status: MessageStatus.sent,
      );

      await DatabaseService.insertMessage(messageModel);
    } catch (e) {
      debugPrint('Error saving message: $e');
    }
  }

  Future<void> _broadcastMessage(P2PMessage message) async {
    final messageJson = jsonEncode(message.toJson());
    await _sendToAllConnectedClients(messageJson);
  }

  Future<void> _sendToAllConnectedClients(String message) async {
    for (final socket in _deviceSockets.values) {
      try {
        socket.write(message);
      } catch (e) {
        debugPrint('Error sending to client: $e');
      }
    }
  }

  void _scheduleAutoConnect() {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = Timer(autoConnectDelay, () {
      if (!_isConnected && _discoveredDevices.isNotEmpty) {
        _connectToAvailableDevice(_discoveredDevices.values.toList());
      }
    });
  }

  void _handleConnectionEstablished() {
    debugPrint("✅ Connection established");
    _isConnected = true;
    _consecutiveFailures = 0;
    notifyListeners();
  }

  void _handleConnectionLost() {
    debugPrint("❌ Connection lost");
    _isConnected = false;
    notifyListeners();
  }

  void _handleIncomingText(String text) {
    try {
      final data = jsonDecode(text);
      if (data['type'] == 'message') {
        final message = P2PMessage.fromJson(data['data']);
        onMessageReceived?.call(message);
      }
    } catch (e) {
      debugPrint('Error handling incoming text: $e');
    }
  }

  Future<bool> connectToDevice(Map<String, dynamic> device) async {
    try {
      _isConnecting = true;
      notifyListeners();

      final deviceAddress = device['deviceAddress'] as String;
      final success = await WifiDirectPlugin.connect(deviceAddress);

      if (success) {
        _connectedDevices[deviceAddress] = ConnectedDevice(
          id: deviceAddress,
          name: device['deviceName'] as String,
          isHost: false,
          connectedAt: DateTime.now(),
        );
      }

      return success;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Enhanced Network Manager Integration
  Future<void> _initializeNetworkManager() async {
    await _requestPermissions();
    await _initializeMDNS();
    await _checkWiFiStatus();
    _startNetworkMonitoring();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.nearbyWifiDevices.request();
  }

  Future<void> _initializeMDNS() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
    } catch (e) {
      debugPrint('Failed to initialize mDNS: $e');
    }
  }

  Future<void> _checkWiFiStatus() async {
    try {
      _isWiFiEnabled = await WiFiForIoTPlugin.isEnabled();
      _isConnected = await WiFiForIoTPlugin.isConnected();

      if (_isConnected) {
        final ssid = await WiFiForIoTPlugin.getSSID();
        _connectedHotspotSSID = ssid;
      }

      _isHotspotEnabled = await WiFiForIoTPlugin.isWiFiAPEnabled();

      notifyListeners();
    } catch (e) {
      debugPrint('Error checking WiFi status: $e');
    }
  }

  void _startNetworkMonitoring() {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      await _checkWiFiStatus();
      await _scanForResQLinkNetworks();
      await _discoverResQLinkDevices();
    });
  }

  // Enhanced createEmergencyHotspot method with fallback:
  Future<bool> createEmergencyHotspot({String? deviceId}) async {
    try {
      await WiFiForIoTPlugin.setEnabled(true);

      final hotspotSSID =
          "$resqlinkPrefix${deviceId ?? DateTime.now().millisecondsSinceEpoch}";

      bool configSuccess = false;
      try {
        await WiFiForIoTPlugin.setWiFiAPSSID(hotspotSSID);
        await WiFiForIoTPlugin.setWiFiAPPreSharedKey(emergencyPassword);
        configSuccess = true;
        debugPrint('✅ WiFi AP configured using legacy methods');
      } catch (e) {
        debugPrint('⚠️ Legacy WiFi AP config failed (Android SDK 26+): $e');
      }

      // Enable hotspot
      final result = await WiFiForIoTPlugin.setWiFiAPEnabled(true);

      if (result) {
        _isHotspotEnabled = true;
        _currentRole = P2PRole.host;
        _currentConnectionMode = ConnectionMode.hotspot;

        // Start both HTTP server and TCP server
        await _startLocalServer();
        await _startHotspotTcpServer();
        await _advertiseMDNSService();

        if (configSuccess) {
          debugPrint("✅ Emergency hotspot created: $hotspotSSID");
        } else {
          debugPrint("✅ Emergency hotspot created with system defaults");
        }

        notifyListeners();
      } else {
        throw Exception("Failed to enable hotspot");
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error creating emergency hotspot: $e');
      return false;
    }
  }

  Future<void> checkAndRequestPermissions() async {
    try {
      debugPrint("🔐 Checking and requesting permissions...");

      // Request location permission (required for WiFi Direct)
      final locationStatus = await Permission.location.request();
      if (locationStatus != PermissionStatus.granted) {
        debugPrint("❌ Location permission denied");
      }

      // Request nearby WiFi devices permission (Android 13+)
      if (Platform.isAndroid) {
        final nearbyStatus = await Permission.nearbyWifiDevices.request();
        if (nearbyStatus != PermissionStatus.granted) {
          debugPrint("❌ Nearby WiFi devices permission denied");
        }
      }

      // Request storage permission for message saving
      final storageStatus = await Permission.storage.request();
      if (storageStatus != PermissionStatus.granted) {
        debugPrint("❌ Storage permission denied");
      }

      debugPrint("✅ Permission check completed");
    } catch (e) {
      debugPrint("❌ Error checking permissions: $e");
    }
  }

  Future<void> _startLocalServer() async {
    final router = shelf_router.Router();

    // Enhanced API endpoints
    router.get('/api/ping', _handlePing);
    router.post('/api/message', _handleMessage);
    router.get('/api/devices', _handleGetDevices);
    router.get('/ws', _handleWebSocket);
    router.get('/api/status', _handleStatus);
    router.post('/api/emergency', _handleEmergencyMessage);

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call); // FIXED: Added explicit .call

    _localServer = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      defaultPort,
    );
    debugPrint(
      '🌐 Enhanced ResQLink HTTP server running on ${_localServer!.address.host}:${_localServer!.port}',
    );
  }

  Future<void> _advertiseMDNSService() async {
    // Enhanced mDNS service advertisement
    try {
      if (_mdnsClient != null) {
        // Advertise the service with enhanced metadata
        final serviceRecord = {
          'service': serviceType,
          'port': defaultPort,
          'hostname': '$_deviceId.local',
          'attributes': {
            'version': '2.0',
            'deviceId': _deviceId,
            'userName': _userName,
            'emergency': _emergencyMode.toString(),
            'role': _currentRole.name,
            'features': 'multi_hop,location,emergency,websocket',
          },
        };

        debugPrint('📡 Enhanced mDNS service advertised: $serviceRecord');
      }
    } catch (e) {
      debugPrint('❌ mDNS advertisement error: $e');
    }
  }

  void setHotspotFallbackEnabled(bool enabled) {
    _hotspotFallbackEnabled = enabled;
    debugPrint("🔄 Hotspot fallback ${enabled ? 'enabled' : 'disabled'}");

    if (enabled && !_isConnected && _emergencyMode) {
      // Try to connect using fallback methods
      _connectionFallbackManager.initiateConnection();
    }

    notifyListeners();
  }

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

    final messageId = 'emergency_${DateTime.now().millisecondsSinceEpoch}';

    await sendMessage(
      id: messageId,
      senderName: userName ?? 'Emergency User',
      message: message,
      type: MessageType.emergency,
      ttl: maxTtl,
      routePath: [],
    );
  }

  // Enhanced network scanning
  Future<void> _scanForResQLinkNetworks() async {
    try {
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        final results = await WiFiScan.instance.getScannedResults();

        _availableNetworks = results
            .where((ap) => ap.ssid.startsWith(resqlinkPrefix))
            .toList();

        // Update discovered devices with network info
        for (final network in _availableNetworks) {
          _discoveredDevices[network.ssid] = {
            'deviceName': network.ssid,
            'deviceAddress': network.ssid,
            'status': 0,
            'isAvailable': true,
            'discoveredAt': DateTime.now().millisecondsSinceEpoch,
            'connectionType': 'hotspot_enhanced',
            'signalLevel': network.level,
            'frequency': network.frequency,
            'bssid': network.bssid,
            'capabilities': network.capabilities,
          };
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error scanning networks: $e');
    }
  }

  Future<void> _discoverResQLinkDevices() async {
    try {
      _discoveredResQLinkDevices.clear();

      if (_mdnsClient != null) {
        await for (final PtrResourceRecord ptr
            in _mdnsClient!.lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(serviceType),
            )) {
          await for (final SrvResourceRecord srv
              in _mdnsClient!.lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(ptr.domainName),
              )) {
            final device = ResQLinkDevice(
              id: ptr.domainName,
              name: srv.target,
              port: srv.port,
              lastSeen: DateTime.now(),
            );

            _discoveredResQLinkDevices.add(device);

            // Add to discovered devices for unified handling
            _discoveredDevices[device.id] = {
              'deviceName': device.name,
              'deviceAddress': device.id,
              'status': 0,
              'isAvailable': true,
              'discoveredAt': DateTime.now().millisecondsSinceEpoch,
              'connectionType': 'mdns_enhanced',
              'port': device.port,
            };
          }
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error discovering ResQLink devices: $e');
    }
  }

  // Enhanced connection methods
  Future<bool> connectToResQLinkNetwork(String ssid) async {
    try {
      final result = await WiFiForIoTPlugin.connect(
        ssid,
        password: emergencyPassword,
        security: NetworkSecurity.WPA,
      );

      if (result) {
        _isConnected = true;
        _connectedHotspotSSID = ssid;
        _currentRole = P2PRole.client;
        _currentConnectionMode = ConnectionMode.hotspot;

        await _connectToServerWebSocket();
        await _connectToHotspotTcpServer({'ssid': ssid});

        notifyListeners();
      }

      return result;
    } catch (e) {
      debugPrint('Error connecting to ResQLink network: $e');
      return false;
    }
  }

  Future<void> _connectToServerWebSocket() async {
    try {
      final networkInfo = NetworkInfo();
      final gatewayIP = await networkInfo.getWifiGatewayIP();

      if (gatewayIP != null) {
        final wsUrl = Uri.parse('ws://$gatewayIP:$defaultPort/ws');
        _wsChannel = WebSocketChannel.connect(wsUrl);

        await _wsChannel!.ready;

        _wsChannel!.stream.listen(
          (message) => _handleIncomingWebSocketMessage(message),
          onError: (error) => debugPrint('WebSocket error: $error'),
          onDone: () => debugPrint('WebSocket connection closed'),
        );

        debugPrint('🔌 WebSocket connected to: $gatewayIP');
      }
    } catch (e) {
      debugPrint('Error connecting WebSocket: $e');
    }
  }

  // Enhanced message handling
  Future<bool> sendResQLinkMessage(ResQLinkMessage message) async {
    try {
      if (_wsChannel != null) {
        _wsChannel!.sink.add(jsonEncode(message.toJson()));
        return true;
      } else if (_isHotspotEnabled && _localServer != null) {
        await _broadcastToWebSocketClients(message);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error sending ResQLink message: $e');
      return false;
    }
  }

  Future<void> _broadcastToWebSocketClients(ResQLinkMessage message) async {
    final messageJson = jsonEncode(message.toJson());
    for (final ws in _webSocketConnections.values) {
      try {
        ws.sink.add(messageJson);
      } catch (e) {
        debugPrint('Error broadcasting to WebSocket client: $e');
      }
    }
  }

  Map<String, dynamic> getConnectionInfo() {
    return {
      'deviceId': _deviceId,
      'userName': _userName,
      'role': _currentRole.name,
      'connectionMode': _currentConnectionMode.name,
      'isConnected': _isConnected,
      'isGroupOwner': _isGroupOwner,
      'isDiscovering': _isDiscovering,
      'emergencyMode': _emergencyMode,
      'connectedDevices': _connectedDevices.length,
      'discoveredDevices': _discoveredDevices.length,
      'isOnline': _isOnline,
      'hotspotFallbackEnabled': _hotspotFallbackEnabled,
      'connectedHotspotSSID': _connectedHotspotSSID,
      'connectionType': _currentConnectionMode.name,
      // Add role forcing information
      'isRoleForced': _forceRoleMode,
      'forcedRole': _forcedRole?.name,
      'socketHealthy': _socketHealthy,
      'consecutiveFailures': _consecutiveFailures,
    };
  }

  Map<String, dynamic> getDeviceInfo(String deviceAddress) {
    if (_connectedDevices.containsKey(deviceAddress)) {
      final device = _connectedDevices[deviceAddress]!;
      return {
        'isConnected': true,
        'deviceName': device.name,
        'connectedAt': device.connectedAt.millisecondsSinceEpoch,
        'isHost': device.isHost,
        'isKnown': _knownDevices.containsKey(deviceAddress),
      };
    }

    // Check if device is in discovered devices
    if (_discoveredDevices.containsKey(deviceAddress)) {
      final device = _discoveredDevices[deviceAddress]!;
      return {
        'isConnected': false,
        'deviceName': device['deviceName'],
        'discoveredAt': device['discoveredAt'],
        'isAvailable': device['isAvailable'],
        'connectionType': device['connectionType'],
        'isKnown': _knownDevices.containsKey(deviceAddress),
      };
    }

    // Check if device is in known devices
    if (_knownDevices.containsKey(deviceAddress)) {
      final device = _knownDevices[deviceAddress]!;
      return {
        'isConnected': false,
        'deviceName': device.deviceId,
        'lastSeen': device.lastSeen.millisecondsSinceEpoch,
        'isHost': device.isHost,
        'isKnown': true,
      };
    }

    // Device not found
    return {
      'isConnected': false,
      'isKnown': false,
      'deviceName': 'Unknown Device',
    };
  }

  void _handleIncomingWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final resqMessage = ResQLinkMessage.fromJson(data);

      onResQLinkMessageReceived?.call(resqMessage);

      // Forward to P2P system if applicable
      if (resqMessage.type == MessageType.emergency ||
          resqMessage.type == MessageType.sos) {
        final p2pMessage = P2PMessage(
          id: resqMessage.id,
          senderId: resqMessage.senderId,
          senderName: resqMessage.senderId,
          message: resqMessage.content,
          type: resqMessage.type,
          timestamp: resqMessage.timestamp,
          ttl: maxTtl,
          latitude: resqMessage.latitude,
          longitude: resqMessage.longitude,
          routePath: [_deviceId!],
        );

        onMessageReceived?.call(p2pMessage);
      }
    } catch (e) {
      debugPrint('Error handling incoming WebSocket message: $e');
    }
  }

  // Enhanced API handlers
  Response _handleStatus(Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'deviceId': _deviceId,
        'userName': _userName,
        'role': _currentRole.name,
        'connectionMode': _currentConnectionMode.name,
        'emergencyMode': _emergencyMode,
        'connectedDevices': _connectedDevices.length,
        'discoveredDevices': _discoveredDevices.length,
        'features': ['multi_hop', 'emergency', 'location', 'websocket', 'p2p'],
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<Response> _handleEmergencyMessage(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);

      final emergencyMessage = ResQLinkMessage(
        id: _generateMessageId(),
        senderId: data['senderId'] ?? _deviceId!,
        content: '🚨 ${data['content']}',
        type: MessageType.emergency,
        timestamp: DateTime.now(),
        latitude: data['latitude'],
        longitude: data['longitude'],
      );

      await _broadcastToWebSocketClients(emergencyMessage);

      return Response.ok(jsonEncode({'status': 'emergency_broadcasted'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Response _handleWebSocket(Request request) {
    return Response.notFound('WebSocket upgrade required - use /ws endpoint');
  }

  Response _handlePing(Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'deviceId': _deviceId,
        'role': _currentRole.name,
        'emergencyMode': _emergencyMode,
      }),
    );
  }

  Future<Response> _handleMessage(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);
      final message = ResQLinkMessage.fromJson(data);

      await _broadcastToWebSocketClients(message);

      return Response.ok(jsonEncode({'status': 'sent'}));
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Response _handleGetDevices(Request request) {
    final devices = [
      ..._discoveredResQLinkDevices.map((d) => d.toJson()),
      ..._connectedDevices.values.map(
        (d) => {
          'id': d.id,
          'name': d.name,
          'isHost': d.isHost,
          'connectedAt': d.connectedAt.toIso8601String(),
          'connectionType': 'connected',
        },
      ),
    ];
    return Response.ok(jsonEncode(devices));
  }

  Middleware _corsMiddleware() {
    return (handler) {
      return (request) async {
        final response = await handler(request);
        return response.change(
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          },
        );
      };
    };
  }

  // Enhanced discovery methods
  Future<List<String>> _scanForResQLinkHotspots() async {
    await _scanForResQLinkNetworks();
    return _availableNetworks.map((n) => n.ssid).toList();
  }

  Future<bool> _connectToResQLinkHotspot(String ssid) async {
    return await connectToResQLinkNetwork(ssid);
  }

  Future<bool> _createResQLinkHotspot() async {
    return await createEmergencyHotspot();
  }

  // Integration with existing P2P methods
  Future<void> _performDiscoveryScan() async {
    if (_isDisposed) return;

    try {
      debugPrint(
        "🔍 Starting enhanced discovery (WiFi Direct + Hotspot + mDNS)...",
      );
      _isDiscovering = true;

      // Run all discovery methods in parallel
      await Future.wait([
        _discoverWiFiDirect(),
        _scanForResQLinkNetworks(),
        _discoverResQLinkDevices(),
      ]);

      Timer(Duration(seconds: 15), () async {
        if (_isDiscovering) {
          await _stopDiscovery();
          _isDiscovering = false;

          if (_discoveredDevices.isEmpty && _emergencyMode) {
            debugPrint("🔄 No devices found, creating emergency hotspot...");
            await createEmergencyHotspot();
          }
        }
      });
    } catch (e) {
      debugPrint("❌ Enhanced discovery error: $e");
      _isDiscovering = false;
    }
  }

  Future<void> _discoverWiFiDirect() async {
    try {
      bool success = await WifiDirectPlugin.startDiscovery();
      if (success) {
        debugPrint("✅ WiFi Direct discovery started");
      }
    } catch (e) {
      debugPrint("❌ WiFi Direct discovery error: $e");
    }
  }

  Future<void> _connectToAvailableDevice(
    List<Map<String, dynamic>> devices,
  ) async {
    devices.sort((a, b) {
      final aKnown = _knownDevices.containsKey(a['deviceAddress']) ? 1 : 0;
      final bKnown = _knownDevices.containsKey(b['deviceAddress']) ? 1 : 0;

      if (aKnown != bKnown) return bKnown.compareTo(aKnown);

      final aTime = a['discoveredAt'] ?? 0;
      final bTime = b['discoveredAt'] ?? 0;
      return bTime.compareTo(aTime);
    });

    for (final device in devices) {
      try {
        final connectionType = device['connectionType'] as String?;

        if (connectionType == 'hotspot' ||
            connectionType == 'hotspot_enhanced') {
          await _connectToResQLinkHotspot(device['deviceAddress']);
        } else if (connectionType == 'mdns_enhanced') {
          await _connectToMDNSDevice(device);
        } else {
          await connectToDevice(device);
        }
        return;
      } catch (e) {
        debugPrint("❌ Failed to connect to ${device['deviceName']}: $e");
        continue;
      }
    }

    debugPrint("❌ Failed to connect to any device, creating emergency hotspot");
    await createEmergencyHotspot();
  }

  Future<void> _connectToMDNSDevice(Map<String, dynamic> device) async {
    try {
      final deviceId = device['deviceAddress'] as String;
      final port = device['port'] as int? ?? defaultPort;

      // Try to connect via HTTP/WebSocket first
      final wsUrl = Uri.parse('ws://${device['name']}:$port/ws');
      final wsChannel = WebSocketChannel.connect(wsUrl);

      await wsChannel.ready;

      _webSocketConnections[deviceId] = wsChannel;

      wsChannel.stream.listen(
        (message) => _handleIncomingWebSocketMessage(message),
        onDone: () {
          _webSocketConnections.remove(deviceId);
          _connectedDevices.remove(deviceId);
          notifyListeners();
        },
      );

      _connectedDevices[deviceId] = ConnectedDevice(
        id: deviceId,
        name: device['deviceName'] as String,
        isHost: false,
        connectedAt: DateTime.now(),
      );

      _currentRole = P2PRole.client;
      _currentConnectionMode = ConnectionMode.websocket;
      _isConnected = true;

      debugPrint("✅ Connected to mDNS device via WebSocket: $deviceId");
      onDeviceConnected?.call(deviceId, device['deviceName'] as String);
      notifyListeners();
    } catch (e) {
      debugPrint("❌ mDNS device connection failed: $e");
      rethrow;
    }
  }

  String _generateDeviceId(String userName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = md5.convert(utf8.encode('$userName$timestamp')).toString();
    return hash.substring(0, 16);
  }

  Future<void> forceHostRole() async {
    try {
      debugPrint("🔄 Forcing host role...");

      _forceRoleMode = true;
      _forcedRole = P2PRole.host;
      _currentRole = P2PRole.host;

      // Try to create emergency hotspot as host
      await createEmergencyHotspot();

      // Also try to create WiFi Direct group
      try {
        await WifiDirectPlugin.startDiscovery();

        // Set device as group owner
        _isGroupOwner = true;
        _currentRole = P2PRole.host;

        debugPrint("✅ WiFi Direct group owner mode enabled");
      } catch (e) {
        debugPrint("⚠️ WiFi Direct group creation failed: $e");
        // Continue with hotspot mode
      }

      debugPrint("✅ Host role forced successfully");
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Failed to force host role: $e");
      rethrow;
    }
  }

  Future<void> forceClientRole() async {
    try {
      debugPrint("🔄 Forcing client role...");

      _forceRoleMode = true;
      _forcedRole = P2PRole.client;
      _currentRole = P2PRole.client;

      // Disconnect from any existing connections first
      await disconnect();

      // Start discovering devices to connect as client
      await discoverDevices(force: true);

      // Wait a bit for discovery, then try to connect to available devices
      Timer(Duration(seconds: 5), () async {
        if (_discoveredDevices.isNotEmpty) {
          await _connectToAvailableDevice(_discoveredDevices.values.toList());
        }
      });

      debugPrint("✅ Client role forced successfully");
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Failed to force client role: $e");
      rethrow;
    }
  }

  Future<void> clearForcedRole() async {
    try {
      debugPrint("🔄 Clearing forced role...");

      _forceRoleMode = false;
      _forcedRole = null;

      // Reset to automatic role selection
      await disconnect();

      // Let the system decide the role automatically
      Timer(Duration(seconds: 2), () async {
        await discoverDevices(force: true);
      });

      debugPrint("✅ Forced role cleared - returning to automatic mode");
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Failed to clear forced role: $e");
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      debugPrint("🔌 Disconnecting from all connections...");

      // Disconnect WiFi Direct
      await WifiDirectPlugin.disconnect();

      // Close WebSocket connections
      for (final ws in _webSocketConnections.values) {
        ws.sink.close();
      }
      _webSocketConnections.clear();

      // Close TCP sockets
      for (final socket in _deviceSockets.values) {
        socket.close();
      }
      _deviceSockets.clear();

      // Close hotspot socket
      _hotspotSocket?.close();
      _hotspotSocket = null;

      // Close main WebSocket channel
      _wsChannel?.sink.close();
      _wsChannel = null;

      // Clear connected devices
      _connectedDevices.clear();

      // Update state
      _isConnected = false;
      _isGroupOwner = false;
      _groupOwnerAddress = null;
      _currentConnectionMode = ConnectionMode.none;

      // If not in forced mode, reset role
      if (!_forceRoleMode) {
        _currentRole = P2PRole.none;
      }

      debugPrint("✅ Disconnected from all connections");
      notifyListeners();
    } catch (e) {
      debugPrint("❌ Error during disconnect: $e");
      rethrow;
    }
  }

  Future<void> _broadcastEmergencyBeacon() async {
    try {
      // Enhanced emergency beacon with multiple transport methods
      final beaconMessage = P2PMessage(
        id: _generateMessageId(),
        senderId: _deviceId!,
        senderName: _userName!,
        message: "🚨 EMERGENCY BEACON - Device seeking assistance",
        type: MessageType.emergency,
        timestamp: DateTime.now(),
        ttl: maxTtl,
        routePath: [_deviceId!],
      );

      // Broadcast via all available methods
      await _broadcastMessage(beaconMessage);

      // Also broadcast via ResQLink WebSocket if available
      if (_wsChannel != null || _webSocketConnections.isNotEmpty) {
        final resqBeacon = ResQLinkMessage(
          id: beaconMessage.id,
          senderId: _deviceId!,
          content: beaconMessage.message,
          type: beaconMessage.type,
          timestamp: beaconMessage.timestamp,
        );
        await sendResQLinkMessage(resqBeacon);
      }

      debugPrint("📡 Enhanced emergency beacon broadcasted via all channels");
    } catch (e) {
      debugPrint("❌ Failed to broadcast emergency beacon: $e");
    }
  }

  // Enhanced WiFi Direct event listeners
  void _setupWifiDirectListeners() {
    _peersChangeSubscription = WifiDirectPlugin.peersStream.listen((peers) {
      if (_isDisposed) return;

      debugPrint("📡 Discovered ${peers.length} WiFi Direct peers");

      // Add WiFi Direct peers to unified discovered devices
      for (var peer in peers) {
        final deviceData = {
          'deviceName': peer.deviceName,
          'deviceAddress': peer.deviceAddress,
          'status': peer.status,
          'isAvailable': peer.status == 0,
          'discoveredAt': DateTime.now().millisecondsSinceEpoch,
          'connectionType': 'wifi_direct',
        };
        _discoveredDevices[peer.deviceAddress] = deviceData;
      }

      // Combine with other discovered devices
      final allDevices = _discoveredDevices.values.toList();
      onDevicesDiscovered?.call(allDevices);

      if (_emergencyMode &&
          !_isConnecting &&
          !_isConnected &&
          allDevices.isNotEmpty) {
        _scheduleAutoConnect();
      }

      notifyListeners();
    });

    _connectionChangeSubscription = WifiDirectPlugin.connectionStream.listen((
      info,
    ) {
      if (_isDisposed) return;

      final wasConnected = _isConnected;
      _isConnected = info.isConnected;
      _isGroupOwner = info.isGroupOwner;
      _groupOwnerAddress = info.groupOwnerAddress;

      if (_isConnected && !wasConnected) {
        _currentConnectionMode = ConnectionMode.wifiDirect;
        _handleConnectionEstablished();
      } else if (!_isConnected && wasConnected) {
        _handleConnectionLost();
      }

      _isConnecting = false;
      notifyListeners();
    });

    WifiDirectPlugin.onTextReceived = (text) {
      if (_isDisposed) return;
      _handleIncomingText(text);
    };
  }

  // Enhanced message sending with multiple transport support
  Future<void> sendMessage({
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
    required String senderName,
    String? id,
    int? ttl,
    List<String>? routePath,
  }) async {
    final messageId = id ?? _generateMessageId();

    final p2pMessage = P2PMessage(
      id: messageId,
      senderId: _deviceId!,
      senderName: _userName!,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      ttl: ttl ?? maxTtl,
      targetDeviceId: targetDeviceId,
      latitude: latitude,
      longitude: longitude,
      routePath: routePath ?? [_deviceId!],
    );

    await _saveMessage(p2pMessage, true);

    // If it's a location message, also save to LocationService
    if (type == MessageType.location && latitude != null && longitude != null) {
      try {
        final locationModel = LocationModel(
          latitude: latitude,
          longitude: longitude,
          timestamp: p2pMessage.timestamp,
          userId: _deviceId,
          type: LocationType.normal,
          message: message,
          synced: false,
        );

        await LocationService.insertLocation(locationModel);
        debugPrint('✅ Location also saved to LocationService');
      } catch (e) {
        debugPrint('❌ Error saving to LocationService: $e');
      }
    }

    _processedMessageIds.add(p2pMessage.id);
    _messageHistory.add(p2pMessage);

    // Send via multiple channels
    await _sendMessageViaAllChannels(p2pMessage);
  }

  Future<void> _sendMessageViaAllChannels(P2PMessage message) async {
    final messageJson = jsonEncode(message.toJson());

    try {
      // Send via WiFi Direct
      if (_isConnected && _currentConnectionMode == ConnectionMode.wifiDirect) {
        await WifiDirectPlugin.sendText(messageJson);
      }

      // Send via WebSocket connections
      for (final ws in _webSocketConnections.values) {
        try {
          ws.sink.add(messageJson);
        } catch (e) {
          debugPrint('WebSocket send failed: $e');
        }
      }

      // Send via TCP sockets
      for (final socket in _deviceSockets.values) {
        try {
          socket.write(messageJson);
        } catch (e) {
          debugPrint('TCP send failed: $e');
        }
      }

      // Send via hotspot TCP if available
      if (_hotspotSocket != null) {
        try {
          _hotspotSocket!.write(messageJson);
        } catch (e) {
          debugPrint('Hotspot TCP send failed: $e');
        }
      }

      // FIXED: Use message.targetDeviceId
      if (_webSocketConnections.isEmpty &&
          _deviceSockets.isEmpty &&
          !_isConnected) {
        await _messageQueue.queueMessage(
          message,
          message.targetDeviceId ?? 'broadcast',
        );
      }
    } catch (e) {
      debugPrint('Error sending message via all channels: $e');
      // FIXED: Use message.targetDeviceId
      await _messageQueue.queueMessage(
        message,
        message.targetDeviceId ?? 'broadcast',
      );
    }
  }

  // Enhanced connection info
  Map<String, dynamic> getEnhancedConnectionInfo() {
    return {
      // Basic P2P info
      'deviceId': _deviceId,
      'userName': _userName,
      'role': _currentRole.name,
      'connectionMode': _currentConnectionMode.name,
      'preferredRole': _preferredRole,
      'isRoleForced': _forceRoleMode,
      'forcedRole': _forcedRole?.name,

      // Connection state
      'isConnected': _isConnected,
      'isGroupOwner': _isGroupOwner,
      'isDiscovering': _isDiscovering,
      'isConnecting': _isConnecting,
      'emergencyMode': _emergencyMode,

      // Network state
      'isHotspotEnabled': _isHotspotEnabled,
      'isWiFiEnabled': _isWiFiEnabled,
      'connectedHotspotSSID': _connectedHotspotSSID,
      'hotspotFallbackEnabled': _hotspotFallbackEnabled,

      // Device counts
      'connectedDevices': _connectedDevices.length,
      'knownDevices': _knownDevices.length,
      'discoveredDevices': _discoveredDevices.length,
      'discoveredResQLinkDevices': _discoveredResQLinkDevices.length,
      'availableNetworks': _availableNetworks.length,
      'webSocketConnections': _webSocketConnections.length,

      // Health metrics
      'socketHealthy': _socketHealthy,
      'lastPing': _lastSuccessfulPing?.millisecondsSinceEpoch,
      'consecutiveFailures': _consecutiveFailures,
      'isOnline': _isOnline,

      // Server info
      'httpServerRunning': _localServer != null,
      'tcpServerRunning': _hotspotServer != null,
      'mdnsClientRunning': _mdnsClient != null,

      // Features
      'supportedFeatures': [
        'wifi_direct',
        'hotspot_fallback',
        'websocket',
        'http_api',
        'mdns_discovery',
        'multi_hop_messaging',
        'emergency_mode',
        'location_sharing',
        'offline_messaging',
      ],
    };
  }

  List<Map<String, dynamic>> getAvailableHotspots() {
    return _availableHotspots
        .map(
          (hotspot) => {
            'ssid': hotspot.ssid,
            'bssid': hotspot.bssid,
            'level': hotspot.level,
            'frequency': hotspot.frequency,
            'capabilities': hotspot.capabilities,
            'isResQLink': hotspot.ssid.startsWith(resqlinkPrefix),
          },
        )
        .toList();
  }

  // Enhanced discovery with all methods
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

      await _performDiscoveryScan();
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
  }

  Future<void> _stopDiscovery() async {
    if (!_isDiscovering) return;

    try {
      await WifiDirectPlugin.stopDiscovery();
      _isDiscovering = false;
      debugPrint("🛑 Enhanced discovery stopped");
    } catch (e) {
      debugPrint("❌ Error stopping discovery: $e");
    }

    notifyListeners();
  }

  // Enhanced cleanup
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    debugPrint("🗑️ Disposing Enhanced P2P service...");

    // Cancel all timers
    _hotspotScanTimer?.cancel();
    _autoConnectTimer?.cancel();
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _messageCleanupTimer?.cancel();
    _syncTimer?.cancel();
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    _connectionWatchdog?.cancel();
    _connectionHealthTimer?.cancel();
    _roleDecisionTimer?.cancel();

    // Dispose enhanced components
    _emergencyConnectionManager.dispose();
    _messageQueue.clearAllQueues();

    // Close enhanced sockets and servers
    await _localServer?.close();
    await _hotspotServer?.close();
    _wsChannel?.sink.close();

    for (final ws in _webSocketConnections.values) {
      ws.sink.close();
    }
    _webSocketConnections.clear();

    for (final socket in _deviceSockets.values) {
      socket.close();
    }
    _deviceSockets.clear();

    // Stop mDNS
    _mdnsClient?.stop();
    _mdnsClient = null;

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

    debugPrint("✅ Enhanced P2P service disposed");
    super.dispose();
  }
}

enum ConnectionMode { none, wifiDirect, hotspot, websocket, mdns, hybrid }

enum P2PRole { none, host, client }

enum MessageType { text, emergency, location, sos, system, file }

enum EmergencyTemplate { sos, trapped, medical, safe, evacuating }

class ResQLinkDevice {
  final String id;
  final String name;
  final int port;
  final DateTime lastSeen;

  ResQLinkDevice({
    required this.id,
    required this.name,
    required this.port,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'port': port,
    'lastSeen': lastSeen.toIso8601String(),
  };

  factory ResQLinkDevice.fromJson(Map<String, dynamic> json) => ResQLinkDevice(
    id: json['id'],
    name: json['name'],
    port: json['port'],
    lastSeen: DateTime.parse(json['lastSeen']),
  );
}

class ResQLinkMessage {
  final String id;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  ResQLinkMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.type,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'content': content,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
  };

  factory ResQLinkMessage.fromJson(Map<String, dynamic> json) =>
      ResQLinkMessage(
        id: json['id'],
        senderId: json['senderId'],
        content: json['content'],
        type: MessageType.values.firstWhere((e) => e.name == json['type']),
        timestamp: DateTime.parse(json['timestamp']),
        latitude: json['latitude'],
        longitude: json['longitude'],
      );
}

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

class QueuedMessage {
  final P2PMessage message;
  final DateTime timestamp;
  int retryCount;

  QueuedMessage({
    required this.message,
    required this.timestamp,
    this.retryCount = 0,
  });
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

extension EmergencyConnectionManagerExtensions on EmergencyConnectionManager {
  void dispose() {
    stopEmergencyMonitoring();
  }
}
