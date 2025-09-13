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

      final permissions = await _permissionChannel.invokeMethod<Map>('checkAllPermissions');
      if (permissions == null) {
        debugPrint('❌ Failed to check permissions');
        return false;
      }

      final locationGranted = permissions['location'] == true;
      final nearbyDevicesGranted = permissions['nearbyDevices'] == true;
      final wifiDirectSupported = permissions['wifiDirect'] == true;

      debugPrint('📊 Permission Status:');
      debugPrint('  - Location: $locationGranted');
      debugPrint('  - Nearby Devices: $nearbyDevicesGranted');
      debugPrint('  - WiFi Direct Support: $wifiDirectSupported');

      if (!wifiDirectSupported) {
        debugPrint('❌ WiFi Direct not supported');
        return false;
      }

      if (!locationGranted) {
        debugPrint('📱 Requesting location permission...');
        await _permissionChannel.invokeMethod('requestLocationPermission');
        // Wait for result via callback
        await Future.delayed(Duration(seconds: 2));
      }

      if (!nearbyDevicesGranted) {
        debugPrint('📱 Requesting nearby devices permission...');
        await _permissionChannel.invokeMethod('requestNearbyDevicesPermission');
        // Wait for result via callback
        await Future.delayed(Duration(seconds: 2));
      }

      // Re-check permissions after requests
      final finalPermissions = await _permissionChannel.invokeMethod<Map>('checkAllPermissions');
      final allGranted = (finalPermissions?['location'] == true) &&
                        (finalPermissions?['nearbyDevices'] == true);

      debugPrint('✅ Final permission status: $allGranted');
      return allGranted;
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
        break;
    }
  }

  List<WiFiDirectPeer> get discoveredPeers => List.from(_discoveredPeers);
  bool get isDiscovering => _isDiscovering;
  WiFiDirectConnectionState get connectionState => _connectionState;

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