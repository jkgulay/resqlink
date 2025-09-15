import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WiFiDirectService {
  static const String channelName = 'resqlink/wifi';
  static const String permissionChannelName = 'resqlink/permissions';

  static const MethodChannel _wifiChannel = MethodChannel(channelName);
  static const MethodChannel _permissionChannel = MethodChannel(permissionChannelName);

  static WiFiDirectService? _instance;
  static WiFiDirectService get instance => _instance ??= WiFiDirectService._();
  WiFiDirectService._();

  final StreamController<List<WiFiDirectPeer>> _peersController = StreamController.broadcast();
  final StreamController<WiFiDirectConnectionState> _connectionController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _stateController = StreamController.broadcast();

  Stream<List<WiFiDirectPeer>> get peersStream => _peersController.stream;
  Stream<WiFiDirectConnectionState> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get stateStream => _stateController.stream;

  bool _isInitialized = false;
  bool _isDiscovering = false;
  List<WiFiDirectPeer> _discoveredPeers = [];
  WiFiDirectConnectionState _connectionState = WiFiDirectConnectionState.disconnected;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('🔧 WiFiDirectService: Initializing...');

      // Set up method call handler for callbacks from native
      _wifiChannel.setMethodCallHandler(_handleMethodCall);
      _permissionChannel.setMethodCallHandler(_handlePermissionCall);

      // Check WiFi Direct support
      final hasSupport = await _wifiChannel.invokeMethod<bool>('checkWifiDirectSupport') ?? false;
      if (!hasSupport) {
        debugPrint('❌ WiFi Direct not supported on this device');
        return false;
      }

      // Enable WiFi if needed
      await _wifiChannel.invokeMethod('enableWifi');

      _isInitialized = true;
      debugPrint('✅ WiFiDirectService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('❌ WiFiDirectService initialization failed: $e');
      return false;
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    try {
      debugPrint('🔐 Checking WiFi Direct permissions...');

      // First check if all permissions are already granted
      final hasAllPermissions = await _permissionChannel.invokeMethod<bool>('hasAllWifiDirectPermissions') ?? false;

      if (hasAllPermissions) {
        debugPrint('✅ All WiFi Direct permissions already granted');
        return true;
      }

      debugPrint('📱 Requesting WiFi Direct permissions...');

      // Request all required permissions at once
      final permissionsGranted = await _permissionChannel.invokeMethod<bool>('requestWifiDirectPermissions') ?? false;

      if (permissionsGranted) {
        debugPrint('✅ All WiFi Direct permissions granted immediately');
        return true;
      }

      debugPrint('⏳ Waiting for permission dialog results...');

      // Wait for permission results through callbacks
      final completer = Completer<bool>();
      Timer? timeoutTimer;

      // Set up timeout
      timeoutTimer = Timer(Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          debugPrint('⏰ Permission request timed out');
          completer.complete(false);
        }
      });

      // Monitor for permission result callback
      late StreamSubscription subscription;
      subscription = _stateController.stream.listen((data) async {
        if (data['wifiDirectReady'] == true) {
          timeoutTimer?.cancel();
          subscription.cancel();
          if (!completer.isCompleted) {
            debugPrint('✅ WiFi Direct permissions confirmed via callback');
            completer.complete(true);
          }
        }
      });

      final result = await completer.future;

      // Final verification
      if (result) {
        final verified = await _permissionChannel.invokeMethod<bool>('hasAllWifiDirectPermissions') ?? false;
        debugPrint('🔍 Final verification: $verified');
        return verified;
      }

      debugPrint('❌ WiFi Direct permissions not granted');
      return false;

    } catch (e) {
      debugPrint('❌ Permission check failed: $e');
      return false;
    }
  }

  Future<bool> startDiscovery() async {
    if (!_isInitialized) {
      debugPrint('❌ WiFiDirectService not initialized');
      return false;
    }

    if (_isDiscovering) {
      debugPrint('⚠️ Discovery already in progress');
      return true;
    }

    try {
      debugPrint('🔍 Starting WiFi Direct peer discovery...');

      // Check permissions first
      final hasPermissions = await checkAndRequestPermissions();
      if (!hasPermissions) {
        debugPrint('❌ Required permissions not granted');
        return false;
      }

      final result = await _wifiChannel.invokeMethod<bool>('startDiscovery');
      _isDiscovering = result ?? false;

      if (_isDiscovering) {
        debugPrint('✅ WiFi Direct discovery started');

        // Start getting peer list periodically
        _startPeriodicPeerListRefresh();
      } else {
        debugPrint('❌ Failed to start WiFi Direct discovery');
      }

      return _isDiscovering;
    } catch (e) {
      debugPrint('❌ WiFi Direct discovery failed: $e');
      _isDiscovering = false;
      return false;
    }
  }

  Future<bool> stopDiscovery() async {
    if (!_isDiscovering) return true;

    try {
      debugPrint('🛑 Stopping WiFi Direct discovery...');

      final result = await _wifiChannel.invokeMethod<bool>('stopDiscovery');
      _isDiscovering = false;

      debugPrint('✅ WiFi Direct discovery stopped');
      return result ?? true;
    } catch (e) {
      debugPrint('❌ Failed to stop discovery: $e');
      _isDiscovering = false;
      return false;
    }
  }

  void _startPeriodicPeerListRefresh() {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      if (!_isDiscovering) {
        timer.cancel();
        return;
      }

      await _refreshPeerList();
    });
  }

  Future<void> _refreshPeerList() async {
    try {
      final result = await _wifiChannel.invokeMethod<Map>('getPeerList');
      if (result != null && result['peers'] != null) {
        final peerList = result['peers'] as List;
        final peers = peerList.map((peer) => WiFiDirectPeer.fromMap(peer as Map<String, dynamic>)).toList();

        _discoveredPeers = peers;
        _peersController.add(peers);

        debugPrint('📡 Found ${peers.length} WiFi Direct peers');
        for (final peer in peers) {
          debugPrint('  - ${peer.deviceName} (${peer.deviceAddress})');
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to refresh peer list: $e');
    }
  }

  Future<bool> connectToPeer(String deviceAddress) async {
    try {
      debugPrint('🔗 Connecting to WiFi Direct peer: $deviceAddress');

      final result = await _wifiChannel.invokeMethod<bool>('connectToPeer', {
        'deviceAddress': deviceAddress,
      });

      if (result == true) {
        debugPrint('✅ WiFi Direct connection initiated');
        _connectionState = WiFiDirectConnectionState.connecting;
        _connectionController.add(_connectionState);
      } else {
        debugPrint('❌ Failed to initiate WiFi Direct connection');
      }

      return result ?? false;
    } catch (e) {
      debugPrint('❌ WiFi Direct connection failed: $e');
      return false;
    }
  }

  Future<bool> createGroup() async {
    try {
      debugPrint('👑 Creating WiFi Direct group...');

      final result = await _wifiChannel.invokeMethod<bool>('createGroup');

      if (result == true) {
        debugPrint('✅ WiFi Direct group created');
      } else {
        debugPrint('❌ Failed to create WiFi Direct group');
      }

      return result ?? false;
    } catch (e) {
      debugPrint('❌ WiFi Direct group creation failed: $e');
      return false;
    }
  }

  Future<bool> removeGroup() async {
    try {
      debugPrint('🗑️ Removing WiFi Direct group...');

      final result = await _wifiChannel.invokeMethod<bool>('removeGroup');

      if (result == true) {
        debugPrint('✅ WiFi Direct group removed');
        _connectionState = WiFiDirectConnectionState.disconnected;
        _connectionController.add(_connectionState);
      }

      return result ?? false;
    } catch (e) {
      debugPrint('❌ WiFi Direct group removal failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getGroupInfo() async {
    try {
      final result = await _wifiChannel.invokeMethod<Map>('getGroupInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('❌ Failed to get group info: $e');
      return null;
    }
  }

  // Handle callbacks from native code
  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint('📞 WiFiDirectService callback: ${call.method} - ${call.arguments}');

    switch (call.method) {
      case 'onStateChanged':
        final args = call.arguments as Map<String, dynamic>;
        _stateController.add(args);
        break;

      case 'onPeersChanged':
        await _refreshPeerList();
        break;

      case 'onPeersAvailable':
        final args = call.arguments as Map<String, dynamic>;
        if (args['peers'] != null) {
          final peerList = args['peers'] as List;
          final peers = peerList.map((peer) => WiFiDirectPeer.fromMap(peer as Map<String, dynamic>)).toList();
          _discoveredPeers = peers;
          _peersController.add(peers);
        }
        break;

      case 'onConnectionChanged':
        final args = call.arguments as Map<String, dynamic>;
        final isConnected = args['isConnected'] as bool? ?? false;
        _connectionState = isConnected
          ? WiFiDirectConnectionState.connected
          : WiFiDirectConnectionState.disconnected;
        _connectionController.add(_connectionState);
        break;

      case 'onSystemConnectionDetected':
        await _handleSystemConnection(call.arguments as Map<String, dynamic>);
        break;

      case 'onSocketEstablished':
        final args = call.arguments as Map<String, dynamic>;
        debugPrint('🔌 Socket connection established: $args');
        _stateController.add({
          'socketEstablished': true,
          'connectionInfo': args,
        });
        break;

      case 'onDeviceChanged':
        final args = call.arguments as Map<String, dynamic>;
        debugPrint('📱 Device info: ${args['deviceName']} (${args['deviceAddress']})');
        break;
    }
  }

  Future<void> _handlePermissionCall(MethodCall call) async {
    debugPrint('🔐 Permission callback: ${call.method} - ${call.arguments}');

    switch (call.method) {
      case 'onPermissionResult':
        final args = call.arguments as Map<String, dynamic>;
        final permission = args['permission'] as String?;
        final granted = args['granted'] as bool? ?? false;
        debugPrint('📋 Permission result: $permission = $granted');

        // Forward to state controller for listeners
        _stateController.add({
          'permission': permission,
          'granted': granted,
          'wifiDirectReady': permission == 'wifiDirectReady' ? granted : null,
        });
        break;
    }
  }

  /// Handle system-level WiFi Direct connection
  Future<void> _handleSystemConnection(Map<String, dynamic> data) async {
    debugPrint('🔗 System WiFi Direct connection detected!');

    final connectionInfo = data['connectionInfo'] as Map<String, dynamic>?;
    final peers = data['peers'] as List?;

    if (connectionInfo != null) {
      final isConnected = connectionInfo['isConnected'] as bool? ?? false;
      final groupFormed = connectionInfo['groupFormed'] as bool? ?? false;

      if (isConnected && groupFormed) {
        debugPrint('✅ Valid system connection detected');

        // Update connection state
        _connectionState = WiFiDirectConnectionState.connected;
        _connectionController.add(_connectionState);

        // Update peer list if available
        if (peers != null) {
          final systemPeers = peers.map((peer) =>
            WiFiDirectPeer.fromMap(peer as Map<String, dynamic>)).toList();
          _discoveredPeers = systemPeers;
          _peersController.add(systemPeers);
        }

        // Attempt to establish socket communication
        await _establishSocketCommunication();
      }
    }
  }

  /// Establish socket communication after system connection
  Future<void> _establishSocketCommunication() async {
    try {
      debugPrint('🔌 Establishing socket communication...');

      final result = await _wifiChannel.invokeMethod<Map>('establishSocketConnection');

      if (result != null && result['success'] == true) {
        debugPrint('✅ Socket communication established');
        debugPrint('  - Is Group Owner: ${result['isGroupOwner']}');
        debugPrint('  - Group Owner Address: ${result['groupOwnerAddress']}');
        debugPrint('  - Socket Port: ${result['socketPort']}');

        _stateController.add({
          'socketReady': true,
          'socketInfo': result,
        });
      } else {
        debugPrint('❌ Failed to establish socket communication');
      }
    } catch (e) {
      debugPrint('❌ Socket establishment error: $e');
    }
  }

  /// Get current connection info
  Future<Map<String, dynamic>?> getConnectionInfo() async {
    try {
      final result = await _wifiChannel.invokeMethod<Map>('getConnectionInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('❌ Failed to get connection info: $e');
      return null;
    }
  }

  /// Monitor for system connections (call this when returning from settings)
  Future<void> checkForSystemConnection() async {
    try {
      debugPrint('🔍 Checking for system-level WiFi Direct connections...');

      final connectionInfo = await getConnectionInfo();

      if (connectionInfo != null) {
        final isConnected = connectionInfo['isConnected'] as bool? ?? false;
        final groupFormed = connectionInfo['groupFormed'] as bool? ?? false;

        if (isConnected && groupFormed) {
          debugPrint('✅ System connection found!');

          // Trigger socket establishment
          await _establishSocketCommunication();

          // Refresh peer list
          await _refreshPeerList();

          // Update connection state
          _connectionState = WiFiDirectConnectionState.connected;
          _connectionController.add(_connectionState);
        } else {
          debugPrint('ℹ️ No active WiFi Direct connection found');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking system connection: $e');
    }
  }

  List<WiFiDirectPeer> get discoveredPeers => List.from(_discoveredPeers);
  bool get isDiscovering => _isDiscovering;
  WiFiDirectConnectionState get connectionState => _connectionState;

  /// Run comprehensive WiFi Direct diagnostic
  Future<Map<String, dynamic>?> runDiagnostic() async {
    if (!_isInitialized) {
      debugPrint('❌ WiFiDirectService not initialized for diagnostic');
      return null;
    }

    try {
      debugPrint('🔍 Running WiFi Direct diagnostic...');
      final diagnostic = await _wifiChannel.invokeMethod<Map>('runDiagnostic');
      return diagnostic?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('❌ Diagnostic failed: $e');
      return null;
    }
  }

  /// Get service status summary
  Map<String, dynamic> getServiceStatus() {
    return {
      'initialized': _isInitialized,
      'discovering': _isDiscovering,
      'connectionState': _connectionState.name,
      'peersFound': _discoveredPeers.length,
      'peersDetails': _discoveredPeers.map((p) => p.toMap()).toList(),
    };
  }

  void dispose() {
    _peersController.close();
    _connectionController.close();
    _stateController.close();
  }
}

class WiFiDirectPeer {
  final String deviceName;
  final String deviceAddress;
  final String primaryDeviceType;
  final String secondaryDeviceType;
  final int status;
  final bool supportsWps;

  WiFiDirectPeer({
    required this.deviceName,
    required this.deviceAddress,
    required this.primaryDeviceType,
    required this.secondaryDeviceType,
    required this.status,
    required this.supportsWps,
  });

  factory WiFiDirectPeer.fromMap(Map<String, dynamic> map) {
    return WiFiDirectPeer(
      deviceName: map['deviceName'] as String? ?? 'Unknown Device',
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      primaryDeviceType: map['primaryDeviceType'] as String? ?? 'Unknown Type',
      secondaryDeviceType: map['secondaryDeviceType'] as String? ?? 'Unknown Secondary Type',
      status: map['status'] as int? ?? 0,
      supportsWps: map['supportsWps'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'deviceAddress': deviceAddress,
      'primaryDeviceType': primaryDeviceType,
      'secondaryDeviceType': secondaryDeviceType,
      'status': status,
      'supportsWps': supportsWps,
    };
  }

  @override
  String toString() {
    return 'WiFiDirectPeer{name: $deviceName, address: $deviceAddress, status: $status}';
  }
}

enum WiFiDirectConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}