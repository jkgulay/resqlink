import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HotspotService {
  static const String channelName = 'resqlink/hotspot';
  static const String permissionChannelName = 'resqlink/permissions';

  static const MethodChannel _hotspotChannel = MethodChannel(channelName);
  static const MethodChannel _permissionChannel = MethodChannel(permissionChannelName);

  static HotspotService? _instance;
  static HotspotService get instance => _instance ??= HotspotService._();
  HotspotService._();

  final StreamController<HotspotState> _stateController = StreamController.broadcast();
  final StreamController<List<ConnectedClient>> _clientsController = StreamController.broadcast();

  Stream<HotspotState> get stateStream => _stateController.stream;
  Stream<List<ConnectedClient>> get clientsStream => _clientsController.stream;

  bool _isInitialized = false;
  HotspotState _currentState = HotspotState.disabled;
  String? _currentSSID;
  String? _currentPassword;
  List<ConnectedClient> _connectedClients = [];

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('🔧 HotspotService: Initializing...');

      // Set up method call handler for callbacks
      _hotspotChannel.setMethodCallHandler(_handleMethodCall);

      _isInitialized = true;
      debugPrint('✅ HotspotService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('❌ HotspotService initialization failed: $e');
      return false;
    }
  }

  Future<bool> checkHotspotCapabilities() async {
    try {
      final result = await _hotspotChannel.invokeMethod<bool>('checkHotspotCapabilities');
      debugPrint('📊 Hotspot capabilities: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Failed to check hotspot capabilities: $e');
      return false;
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    try {
      debugPrint('🔐 Checking hotspot permissions...');

      final permissions = await _permissionChannel.invokeMethod<Map>('checkAllPermissions');
      if (permissions == null) {
        debugPrint('❌ Failed to check permissions');
        return false;
      }

      final locationGranted = permissions['location'] == true;
      final nearbyDevicesGranted = permissions['nearbyDevices'] == true;

      debugPrint('📊 Permission Status:');
      debugPrint('  - Location: $locationGranted');
      debugPrint('  - Nearby Devices: $nearbyDevicesGranted');

      if (!locationGranted) {
        debugPrint('📱 Requesting location permission...');
        await _permissionChannel.invokeMethod('requestLocationPermission');
        await Future.delayed(Duration(seconds: 2));
      }

      if (!nearbyDevicesGranted) {
        debugPrint('📱 Requesting nearby devices permission...');
        await _permissionChannel.invokeMethod('requestNearbyDevicesPermission');
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

  Future<bool> createLocalOnlyHotspot({String? ssid, String? password}) async {
    if (!_isInitialized) {
      debugPrint('❌ HotspotService not initialized');
      return false;
    }

    try {
      debugPrint('🔥 Creating LocalOnly hotspot...');

      // Check capabilities first
      final hasCapability = await checkHotspotCapabilities();
      if (!hasCapability) {
        debugPrint('❌ Device does not support hotspot creation');
        return false;
      }

      // Check permissions
      final hasPermissions = await checkAndRequestPermissions();
      if (!hasPermissions) {
        debugPrint('❌ Required permissions not granted');
        return false;
      }

      // Generate SSID and password if not provided
      final hotspotSSID = ssid ?? 'ResQLink_${DateTime.now().millisecondsSinceEpoch}';
      final hotspotPassword = password ?? 'RESQLINK911';

      debugPrint('📶 Creating hotspot: $hotspotSSID');

      _currentState = HotspotState.creating;
      _stateController.add(_currentState);

      final result = await _hotspotChannel.invokeMethod<Map>('createLocalOnlyHotspot', {
        'ssid': hotspotSSID,
        'password': hotspotPassword,
      });

      if (result != null && result['success'] == true) {
        _currentState = HotspotState.enabled;
        _currentSSID = result['ssid'] as String?;
        _currentPassword = result['password'] as String?;

        debugPrint('✅ Hotspot created successfully');
        debugPrint('  - SSID: $_currentSSID');
        debugPrint('  - Password: $_currentPassword');

        _stateController.add(_currentState);

        // Start monitoring connected clients
        _startClientMonitoring();

        return true;
      } else {
        debugPrint('❌ Failed to create hotspot: ${result?['error']}');
        _currentState = HotspotState.error;
        _stateController.add(_currentState);
        return false;
      }
    } catch (e) {
      debugPrint('❌ Hotspot creation failed: $e');
      _currentState = HotspotState.error;
      _stateController.add(_currentState);
      return false;
    }
  }

  Future<bool> createLegacyHotspot({String? ssid, String? password}) async {
    try {
      debugPrint('🔥 Creating legacy hotspot...');

      // Generate SSID and password if not provided
      final hotspotSSID = ssid ?? 'ResQLink_${DateTime.now().millisecondsSinceEpoch}';
      final hotspotPassword = password ?? 'RESQLINK911';

      debugPrint('📶 Creating legacy hotspot: $hotspotSSID');

      _currentState = HotspotState.creating;
      _stateController.add(_currentState);

      final result = await _hotspotChannel.invokeMethod<Map>('createLegacyHotspot', {
        'ssid': hotspotSSID,
        'password': hotspotPassword,
      });

      if (result != null && result['success'] == true) {
        _currentState = HotspotState.enabled;
        _currentSSID = result['ssid'] as String?;
        _currentPassword = result['password'] as String?;

        debugPrint('✅ Legacy hotspot created successfully');
        debugPrint('  - SSID: $_currentSSID');
        debugPrint('  - Password: $_currentPassword');

        _stateController.add(_currentState);
        _startClientMonitoring();

        return true;
      } else {
        debugPrint('❌ Failed to create legacy hotspot: ${result?['error']}');
        _currentState = HotspotState.error;
        _stateController.add(_currentState);
        return false;
      }
    } catch (e) {
      debugPrint('❌ Legacy hotspot creation failed: $e');
      _currentState = HotspotState.error;
      _stateController.add(_currentState);
      return false;
    }
  }

  Future<bool> createHotspot({String? ssid, String? password, bool forceLegacy = false}) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (forceLegacy) {
      return await createLegacyHotspot(ssid: ssid, password: password);
    } else {
      // Try modern method first, fall back to legacy
      final success = await createLocalOnlyHotspot(ssid: ssid, password: password);
      if (!success) {
        debugPrint('⚠️ Modern hotspot failed, trying legacy method...');
        return await createLegacyHotspot(ssid: ssid, password: password);
      }
      return success;
    }
  }

  Future<bool> stopHotspot() async {
    try {
      debugPrint('🛑 Stopping hotspot...');

      final result = await _hotspotChannel.invokeMethod<bool>('stopHotspot');

      if (result == true) {
        _currentState = HotspotState.disabled;
        _currentSSID = null;
        _currentPassword = null;
        _connectedClients.clear();

        _stateController.add(_currentState);
        _clientsController.add(_connectedClients);

        debugPrint('✅ Hotspot stopped successfully');
        return true;
      } else {
        debugPrint('❌ Failed to stop hotspot');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Hotspot stop failed: $e');
      return false;
    }
  }

  Future<List<ConnectedClient>> getConnectedClients() async {
    try {
      final result = await _hotspotChannel.invokeMethod<List>('getConnectedClients');
      if (result != null) {
        final clients = result.map((client) => ConnectedClient.fromMap(client as Map<String, dynamic>)).toList();
        _connectedClients = clients;
        _clientsController.add(_connectedClients);
        return clients;
      }
      return [];
    } catch (e) {
      debugPrint('❌ Failed to get connected clients: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getHotspotInfo() async {
    try {
      final result = await _hotspotChannel.invokeMethod<Map>('getHotspotInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('❌ Failed to get hotspot info: $e');
      return null;
    }
  }

  void _startClientMonitoring() {
    Timer.periodic(Duration(seconds: 10), (timer) async {
      if (_currentState != HotspotState.enabled) {
        timer.cancel();
        return;
      }

      await getConnectedClients();
    });
  }

  // Handle callbacks from native code
  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint('📞 HotspotService callback: ${call.method} - ${call.arguments}');

    switch (call.method) {
      case 'onHotspotStateChanged':
        final args = call.arguments as Map<String, dynamic>;
        final event = args['event'] as String?;

        switch (event) {
          case 'hotspot_started':
            _currentState = HotspotState.enabled;
            break;
          case 'hotspot_stopped':
            _currentState = HotspotState.disabled;
            _currentSSID = null;
            _currentPassword = null;
            _connectedClients.clear();
            _clientsController.add(_connectedClients);
            break;
          case 'hotspot_failed':
            _currentState = HotspotState.error;
            break;
        }

        _stateController.add(_currentState);
        break;

      case 'onClientConnected':
        final args = call.arguments as Map<String, dynamic>;
        final client = ConnectedClient.fromMap(args);
        _connectedClients.add(client);
        _clientsController.add(_connectedClients);
        debugPrint('📱 Client connected: ${client.deviceName} (${client.ipAddress})');
        break;

      case 'onClientDisconnected':
        final args = call.arguments as Map<String, dynamic>;
        final ipAddress = args['ipAddress'] as String?;
        if (ipAddress != null) {
          _connectedClients.removeWhere((client) => client.ipAddress == ipAddress);
          _clientsController.add(_connectedClients);
          debugPrint('📱 Client disconnected: $ipAddress');
        }
        break;
    }
  }

  // Getters
  HotspotState get currentState => _currentState;
  String? get currentSSID => _currentSSID;
  String? get currentPassword => _currentPassword;
  List<ConnectedClient> get connectedClients => List.from(_connectedClients);
  bool get isEnabled => _currentState == HotspotState.enabled;

  void dispose() {
    _stateController.close();
    _clientsController.close();
  }
}

enum HotspotState {
  disabled,
  creating,
  enabled,
  error,
}

class ConnectedClient {
  final String ipAddress;
  final String macAddress;
  final String deviceName;
  final int connectionTime;

  ConnectedClient({
    required this.ipAddress,
    required this.macAddress,
    required this.deviceName,
    required this.connectionTime,
  });

  factory ConnectedClient.fromMap(Map<String, dynamic> map) {
    return ConnectedClient(
      ipAddress: map['ipAddress'] as String? ?? 'Unknown IP',
      macAddress: map['macAddress'] as String? ?? 'Unknown MAC',
      deviceName: map['deviceName'] as String? ?? 'Unknown Device',
      connectionTime: map['connectionTime'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ipAddress': ipAddress,
      'macAddress': macAddress,
      'deviceName': deviceName,
      'connectionTime': connectionTime,
    };
  }

  @override
  String toString() {
    return 'ConnectedClient{name: $deviceName, ip: $ipAddress, mac: $macAddress}';
  }
}