import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WiFiDirectService {
  static const String channelName = 'resqlink/wifi';
  static const String permissionChannelName = 'resqlink/permissions';
  static const MethodChannel _channel = MethodChannel('resqlink/wifi');

  static const MethodChannel _wifiChannel = MethodChannel(channelName);
  static const MethodChannel _permissionChannel = MethodChannel(
    permissionChannelName,
  );

  static WiFiDirectService? _instance;
  static WiFiDirectService get instance => _instance ??= WiFiDirectService._();
  WiFiDirectService._();

  final StreamController<List<WiFiDirectPeer>> _peersController =
      StreamController.broadcast();
  final StreamController<WiFiDirectConnectionState> _connectionController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _stateController =
      StreamController.broadcast();

  Stream<List<WiFiDirectPeer>> get peersStream => _peersController.stream;
  Stream<WiFiDirectConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<Map<String, dynamic>> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream {
    _channel.setMethodCallHandler(_handleMethodCall);
    return _messageController.stream;
  }

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  bool _isInitialized = false;
  bool _isDiscovering = false;
  bool _isRefreshingPeers = false;
  List<WiFiDirectPeer> _discoveredPeers = [];
  WiFiDirectConnectionState _connectionState =
      WiFiDirectConnectionState.disconnected;

  // Getters for discovered peers
  List<WiFiDirectPeer> get discoveredPeers => List.from(_discoveredPeers);

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('🔧 WiFiDirectService: Initializing...');

      // Set up method call handler for callbacks from native
      _wifiChannel.setMethodCallHandler(_handleMethodCall);
      _permissionChannel.setMethodCallHandler(_handlePermissionCall);

      // Check WiFi Direct support
      final hasSupport =
          await _wifiChannel.invokeMethod<bool>('checkWifiDirectSupport') ??
          false;
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
      final hasAllPermissions =
          await _permissionChannel.invokeMethod<bool>(
            'hasAllWifiDirectPermissions',
          ) ??
          false;

      if (hasAllPermissions) {
        debugPrint('✅ All WiFi Direct permissions already granted');
        return true;
      }

      debugPrint('📱 Requesting WiFi Direct permissions...');

      // Request all required permissions at once
      final permissionsGranted =
          await _permissionChannel.invokeMethod<bool>(
            'requestWifiDirectPermissions',
          ) ??
          false;

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
        final verified =
            await _permissionChannel.invokeMethod<bool>(
              'hasAllWifiDirectPermissions',
            ) ??
            false;
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
    if (_isRefreshingPeers) return;
    _isRefreshingPeers = true;

    try {
      final result = await _wifiChannel.invokeMethod<Map>('getPeerList');
      if (result != null && result['peers'] != null) {
        final peerList = result['peers'] as List;
        final peers = peerList
            .map((peer) => WiFiDirectPeer.fromMap(Map<String, dynamic>.from(peer as Map? ?? {})))
            .toList();

        if (!_peersEqual(_discoveredPeers, peers)) {
          _discoveredPeers = peers;
          _peersController.add(peers);

          final hasConnectedPeers = peers.any(
            (p) => p.status == WiFiDirectPeerStatus.connected,
          );
          if (hasConnectedPeers !=
              (_connectionState == WiFiDirectConnectionState.connected)) {
            _updateConnectionState(
              hasConnectedPeers
                  ? WiFiDirectConnectionState.connected
                  : WiFiDirectConnectionState.disconnected,
            );
          }
        }
      }
    } finally {
      _isRefreshingPeers = false;
    }
  }

  void _updateConnectionState(WiFiDirectConnectionState newState) {
    if (_connectionState != newState) {
      final previousState = _connectionState;
      _connectionState = newState;

      debugPrint(
        '🔄 WiFi Direct connection state: ${previousState.name} → ${newState.name}',
      );

      // Notify connection state listeners
      _connectionController.add(_connectionState);

      // Send detailed state information
      _stateController.add({
        'connectionStateChanged': true,
        'previousState': previousState.name,
        'currentState': newState.name,
        'isConnected': newState == WiFiDirectConnectionState.connected,
        'isConnecting': newState == WiFiDirectConnectionState.connecting,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Log connection events for debugging
      switch (newState) {
        case WiFiDirectConnectionState.connected:
          debugPrint('✅ WiFi Direct connected successfully');
        case WiFiDirectConnectionState.connecting:
          debugPrint('🔄 WiFi Direct connecting...');
        case WiFiDirectConnectionState.disconnected:
          debugPrint('❌ WiFi Direct disconnected');
        case WiFiDirectConnectionState.error:
          debugPrint('💥 WiFi Direct connection error');
      }
    }
  }

  bool _peersEqual(List<WiFiDirectPeer> list1, List<WiFiDirectPeer> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].deviceAddress != list2[i].deviceAddress ||
          list1[i].status != list2[i].status) {
        return false;
      }
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> getPeerList() async {
    try {
      debugPrint('📡 Requesting WiFi Direct peer list...');

      final result = await _channel.invokeMethod('getPeerList');

      if (result != null && result['peers'] != null) {
        final peers = List<Map<String, dynamic>>.from(
          (result['peers'] as List).map(
            (peer) => Map<String, dynamic>.from(peer),
          ),
        );

        debugPrint('✅ Found ${peers.length} WiFi Direct peers');

        final wifiDirectPeers = <WiFiDirectPeer>[];
        for (final peerData in peers) {
          final peer = WiFiDirectPeer(
            deviceName: peerData['deviceName'] ?? 'Unknown',
            deviceAddress: peerData['deviceAddress'] ?? '',
            primaryDeviceType: peerData['primaryDeviceType'] ?? 'Unknown Type',
            secondaryDeviceType:
                peerData['secondaryDeviceType'] ?? 'Unknown Secondary Type',
            status: peerData['status'] ?? 0,
            supportsWps: peerData['supportsWps'] ?? false,
            signalLevel: peerData['signalLevel'],
          );

          wifiDirectPeers.add(peer);

          // Log connection status
          if (peer.status == WiFiDirectPeerStatus.connected) {
            debugPrint(
              '🔗 CONNECTED: ${peer.deviceName} (${peer.deviceAddress})',
            );
          }
        }

        _discoveredPeers = wifiDirectPeers;
        _peersController.add(wifiDirectPeers);

        // Check connection state
        _checkForConnectionStatusChanges(wifiDirectPeers);

        return peers;
      }

      return [];
    } catch (e) {
      debugPrint('❌ Error getting peer list: $e');
      return [];
    }
  }

  Future<bool> establishSocketConnection() async {
    try {
      debugPrint('🔌 Establishing socket connection...');

      final result = await _channel.invokeMethod('establishSocketConnection');

      if (result != null && result['success'] == true) {
        debugPrint('✅ Socket connection established');
        debugPrint('  - Group Owner: ${result['isGroupOwner']}');
        debugPrint('  - Address: ${result['groupOwnerAddress']}');
        debugPrint('  - Port: ${result['socketPort']}');

        // Update state
        _stateController.add({
          'socketEstablished': true,
          'socketReady': true,
          'connectionInfo': result,
        });

        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error establishing socket connection: $e');
      return false;
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

  Future<bool> sendMessage(String message) async {
    try {
      debugPrint('📤 Sending message via WiFi Direct: $message');

      final result = await _channel.invokeMethod('sendMessage', {
        'message': message,
      });

      return result == true;
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint(
      '📞 WiFiDirectService callback: ${call.method} - ${call.arguments}',
    );

    switch (call.method) {
      case 'onStateChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        _stateController.add(args);

      case 'onPeersChanged':
        await _refreshPeerList();

      case 'onPeersAvailable':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        if (args['peers'] != null) {
          final peerList = args['peers'] as List;
          final peers = peerList
              .map(
                (peer) => WiFiDirectPeer.fromMap(Map<String, dynamic>.from(peer as Map? ?? {})),
              )
              .toList();
          _discoveredPeers = peers;
          _peersController.add(peers);

          // CRITICAL FIX: Check for connection changes
          _checkForConnectionStatusChanges(peers);
        }

      case 'onConnectionChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        await _handleConnectionChanged(args);

      case 'onSystemConnectionDetected':
        await _handleSystemConnection(Map<String, dynamic>.from(call.arguments as Map? ?? {}));

      case 'onSocketEstablished':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        debugPrint('🔌 Socket established: $args');
        _stateController.add({
          'socketEstablished': true,
          'connectionInfo': args,
        });

      case 'onExistingConnectionFound':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        debugPrint('🔗 Existing connection found: $args');
        _connectionState = WiFiDirectConnectionState.connected;
        _connectionController.add(_connectionState);
        _stateController.add({
          'existingConnection': true,
          'connectionInfo': args,
        });

        // CRITICAL FIX: Refresh peer list when existing connection found
        await _refreshPeerList();

      case 'onMessageReceived':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        debugPrint('📨 Message received: ${args['message']}');

        // CRITICAL FIX: Process the message through the message router
        final message = args['message'] as String?;
        final from = args['from'] as String?;

        if (message != null && from != null) {
          // Send to message router for processing
          _messageController.add({
            'type': 'message_received',
            'message': message,
            'from': from,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }

        _stateController.add({
          'messageReceived': true,
          'message': args['message'],
          'from': args['from'],
        });

      case 'onPeersUpdated':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        if (args['peers'] != null) {
          final peerList = args['peers'] as List;
          final peers = peerList
              .map(
                (peer) => WiFiDirectPeer.fromMap(Map<String, dynamic>.from(peer as Map? ?? {})),
              )
              .toList();
          _discoveredPeers = peers;
          _peersController.add(peers);

          // CRITICAL FIX: Check for connection changes
          _checkForConnectionStatusChanges(peers);
        }

      case 'onDeviceChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        debugPrint(
          '📱 Device info: ${args['deviceName']} (${args['deviceAddress']})',
        );

      case 'onServerSocketReady':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        debugPrint('🔌 Server socket ready on port ${args['port']}');
        _stateController.add({
          'serverSocketReady': true,
          'socketInfo': args,
        });

      case 'onConnectionError':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        debugPrint('❌ Connection error: ${args['error']}');
        _stateController.add({
          'connectionError': true,
          'error': args['error'],
          'details': args['details'],
        });
    }
  }

  Future<void> _handleConnectionChanged(Map<String, dynamic> args) async {
    final isConnected = args['isConnected'] as bool? ?? false;
    final groupFormed = args['groupFormed'] as bool? ?? false;

    debugPrint(
      '🔄 WiFi Direct connection changed: connected=$isConnected, groupFormed=$groupFormed',
    );

    final newState = (isConnected && groupFormed)
        ? WiFiDirectConnectionState.connected
        : WiFiDirectConnectionState.disconnected;

    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionController.add(_connectionState);

      // Send detailed connection info
      _stateController.add({
        'connectionChanged': true,
        'connectionInfo': {
          'isConnected': isConnected,
          'groupFormed': groupFormed,
          'isGroupOwner': args['isGroupOwner'] ?? false,
          'groupOwnerAddress': args['groupOwnerAddress'] ?? '',
        },
      });

      // If connected, refresh peer list to get connected devices
      if (isConnected && groupFormed) {
        debugPrint('🔄 Connection established, refreshing peer list...');
        await Future.delayed(Duration(milliseconds: 500));
        await _refreshPeerList();
      }
    }
  }

  void _checkForConnectionStatusChanges(List<WiFiDirectPeer> peers) {
    bool hasConnectedPeers = false;

    for (final peer in peers) {
      if (peer.status == WiFiDirectPeerStatus.connected) {
        hasConnectedPeers = true;
        debugPrint(
          '✅ Connected peer found: ${peer.deviceName} (${peer.deviceAddress})',
        );
      }
    }

    // Update connection state based on peer status
    final newConnectionState = hasConnectedPeers
        ? WiFiDirectConnectionState.connected
        : WiFiDirectConnectionState.disconnected;

    if (_connectionState != newConnectionState) {
      debugPrint(
        '🔄 Connection state changing from ${_connectionState.name} to ${newConnectionState.name}',
      );
      _connectionState = newConnectionState;
      _connectionController.add(_connectionState);

      // Send connection change notification
      _stateController.add({
        'connectionChanged': true,
        'connectionInfo': {
          'isConnected': hasConnectedPeers,
          'groupFormed': hasConnectedPeers,
          'connectedPeers': peers
              .where((p) => p.status == WiFiDirectPeerStatus.connected)
              .length,
        },
      });
    }
  }

  Future<void> _handlePermissionCall(MethodCall call) async {
    debugPrint('🔐 Permission callback: ${call.method} - ${call.arguments}');

    switch (call.method) {
      case 'onPermissionResult':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        final permission = args['permission'] as String?;
        final granted = args['granted'] as bool? ?? false;
        debugPrint('📋 Permission result: $permission = $granted');

        // Forward to state controller for listeners
        _stateController.add({
          'permission': permission,
          'granted': granted,
          'wifiDirectReady': permission == 'wifiDirectReady' ? granted : null,
        });
    }
  }

  /// Handle system-level WiFi Direct connection
  Future<void> _handleSystemConnection(Map<String, dynamic> data) async {
    debugPrint('🔗 System WiFi Direct connection detected!');

    final connectionInfo = data['connectionInfo'] != null ?
      Map<String, dynamic>.from(data['connectionInfo'] as Map? ?? {}) : null;
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
          final systemPeers = peers
              .map(
                (peer) => WiFiDirectPeer.fromMap(Map<String, dynamic>.from(peer as Map? ?? {})),
              )
              .toList();
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

      final result = await _wifiChannel.invokeMethod<Map>(
        'establishSocketConnection',
      );

      if (result != null && result['success'] == true) {
        debugPrint('✅ Socket communication established');
        debugPrint('  - Is Group Owner: ${result['isGroupOwner']}');
        debugPrint('  - Group Owner Address: ${result['groupOwnerAddress']}');
        debugPrint('  - Socket Port: ${result['socketPort']}');

        _stateController.add({'socketReady': true, 'socketInfo': result});
      } else {
        debugPrint('❌ Failed to establish socket communication');
      }
    } catch (e) {
      debugPrint('❌ Socket establishment error: $e');
    }
  }

  Future<Map<String, dynamic>?> getConnectionInfo() async {
    try {
      debugPrint('📡 Getting WiFi Direct connection info...');

      final result = await _channel.invokeMethod('getConnectionInfo');

      if (result != null) {
        debugPrint('✅ Connection info retrieved:');
        debugPrint('  - Connected: ${result['isConnected']}');
        debugPrint('  - Group Owner: ${result['isGroupOwner']}');
        debugPrint('  - Group Formed: ${result['groupFormed']}');

        return Map<String, dynamic>.from(result as Map? ?? {});
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error getting connection info: $e');
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

          await _establishSocketCommunication();

          await _refreshPeerList();

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
  final int _statusInt;
  final bool supportsWps;
  final int? signalLevel;

  WiFiDirectPeer({
    required this.deviceName,
    required this.deviceAddress,
    required this.primaryDeviceType,
    required this.secondaryDeviceType,
    required int status,
    required this.supportsWps,
    this.signalLevel,
  }) : _statusInt = status;

  factory WiFiDirectPeer.fromMap(Map<String, dynamic> map) {
    return WiFiDirectPeer(
      deviceName: map['deviceName'] as String? ?? 'Unknown Device',
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      primaryDeviceType: map['primaryDeviceType'] as String? ?? 'Unknown Type',
      secondaryDeviceType:
          map['secondaryDeviceType'] as String? ?? 'Unknown Secondary Type',
      status: map['status'] as int? ?? 0,
      supportsWps: map['supportsWps'] as bool? ?? false,
      signalLevel: map['signalLevel'] as int?,
    );
  }

  WiFiDirectPeerStatus get status => _intToStatus(_statusInt);

  WiFiDirectPeerStatus _intToStatus(int statusInt) {
    switch (statusInt) {
      case 0:
        return WiFiDirectPeerStatus.connected;
      case 1:
        return WiFiDirectPeerStatus.invited;
      case 2:
        return WiFiDirectPeerStatus.failed;
      case 3:
        return WiFiDirectPeerStatus.available;
      case 4:
        return WiFiDirectPeerStatus.unavailable;
      default:
        return WiFiDirectPeerStatus.unknown;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'deviceAddress': deviceAddress,
      'primaryDeviceType': primaryDeviceType,
      'secondaryDeviceType': secondaryDeviceType,
      'status': _statusInt,
      'supportsWps': supportsWps,
      'signalLevel': signalLevel,
    };
  }

  @override
  String toString() {
    return 'WiFiDirectPeer{name: $deviceName, address: $deviceAddress, status: ${status.name}}';
  }
}

enum WiFiDirectConnectionState { disconnected, connecting, connected, error }

enum WiFiDirectPeerStatus {
  connected,
  invited,
  failed,
  available,
  unavailable,
  unknown,
}
