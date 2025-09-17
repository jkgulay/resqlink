import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wifi_direct_plugin/wifi_direct_plugin.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../../models/device_model.dart';
import 'p2p_base_service.dart';
import 'p2p_network_service.dart';

/// Device discovery service for P2P connections
class P2PDiscoveryService {
  final P2PBaseService _baseService;
  final P2PNetworkService _networkService;
  
  // Discovery state
  bool _discoveryInProgress = false;
  Timer? _discoveryRetryTimer;
  Timer? _discoveryTimeoutTimer;
  
  // Discovery methods
  bool _wifiDirectAvailable = false;
  bool _mdnsAvailable = false;
  
  // Discovered devices tracking
  final Map<String, DateTime> _lastSeenDevices = {};
  final Map<String, int> _deviceConnectionAttempts = {};
  
  P2PDiscoveryService(this._baseService, this._networkService);

  /// Initialize discovery service
  Future<void> initialize() async {
    try {
      debugPrint('🔍 Initializing P2P Discovery Service...');
      
      // Check WiFi Direct availability
      await _checkWifiDirectAvailability();
      
      // Start periodic discovery
      _startPeriodicDiscovery();
      
      debugPrint('✅ P2P Discovery Service initialized');
      
    } catch (e) {
      debugPrint('❌ Discovery service initialization failed: $e');
    }
  }

  /// Check if WiFi Direct is available
  Future<void> _checkWifiDirectAvailability() async {
    try {
      // Try to initialize WiFi Direct
      await WifiDirectPlugin.initialize();
      _wifiDirectAvailable = true;
      debugPrint('✅ WiFi Direct available');
    } catch (e) {
      _wifiDirectAvailable = false;
      debugPrint('❌ WiFi Direct not available: $e');
    }
  }

  /// Start device discovery
  Future<void> discoverDevices({bool force = false}) async {
    if (_discoveryInProgress && !force) {
      debugPrint('⏳ Discovery already in progress');
      return;
    }
    
    if (_baseService.isDisposed) {
      debugPrint('⚠️ Service disposed, skipping discovery');
      return;
    }
    
    _discoveryInProgress = true;
    debugPrint('🔍 Starting enhanced device discovery...');
    
    try {
      // Set discovery timeout
      _discoveryTimeoutTimer = Timer(Duration(seconds: 30), () {
        debugPrint('⏰ Discovery timeout reached');
        _discoveryInProgress = false;
      });
      
      // Run multiple discovery methods in parallel
      await Future.wait([
        _discoverWifiDirectDevices(),
        _discoverResQLinkNetworks(),
        _discoverMDNSDevices(),
        _discoverBroadcastDevices(),
      ], eagerError: false);
      
      debugPrint('✅ Enhanced discovery completed');
      
    } catch (e) {
      debugPrint('❌ Discovery error: $e');
    } finally {
      _discoveryTimeoutTimer?.cancel();
      _discoveryInProgress = false;
    }
  }

  /// Discover devices via WiFi Direct
  Future<void> _discoverWifiDirectDevices() async {
    if (!_wifiDirectAvailable) return;
    
    try {
      debugPrint('🔍 Starting WiFi Direct discovery...');
      
      // Start WiFi Direct discovery
      await WifiDirectPlugin.startDiscovery();
      
      // Listen for peers
      //       WifiDirectPlugin.onPeersChanged.listen((peers) {
      //         debugPrint('📱 WiFi Direct peers found: ${peers.length}');
      //         
      //         for (final peer in peers) {
      //           _handleDiscoveredWifiDirectDevice(peer);
      //         }
      //       });
      
      // Wait for discovery to complete
      await Future.delayed(Duration(seconds: 10));
      
      debugPrint('✅ WiFi Direct discovery completed');
      
    } catch (e) {
      debugPrint('❌ WiFi Direct discovery failed: $e');
    }
  }

  /// Discover devices via ResQLink networks
  Future<void> _discoverResQLinkNetworks() async {
    try {
      debugPrint('🔍 Starting ResQLink network discovery...');

      final networks = await _networkService.scanForResQLinkNetworks();

      for (final network in networks) {
        if (network.ssid!.startsWith(P2PBaseService.resqlinkPrefix)) {
          final deviceId = network.ssid!.replaceFirst(P2PBaseService.resqlinkPrefix, '');

          final device = DeviceModel(
            id: deviceId,
            deviceId: deviceId,
            userName: "User_$deviceId",
            isHost: false,
            isOnline: false,
            lastSeen: DateTime.now(),
            createdAt: DateTime.now(),
            discoveryMethod: 'hotspot',
          );

          _addDiscoveredDevice(device);
          debugPrint('📡 ResQLink network found: ${network.ssid} (Signal: ${network.level} dBm)');

          // Optionally try to connect
          if (_shouldAttemptConnection(deviceId)) {
            await _attemptNetworkConnection(network);
          }
        }
      }

      debugPrint('✅ ResQLink network discovery completed - found ${networks.length} total networks');

    } catch (e) {
      debugPrint('❌ Network discovery failed: $e');
    }
  }

  /// Discover devices via mDNS
  Future<void> _discoverMDNSDevices() async {
    try {
      debugPrint('🔍 Starting mDNS discovery...');
      
      final client = MDnsClient();
      await client.start();
      
      // Look for ResQLink services
      await for (final ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('_resqlink._tcp.local'),
          )
          .timeout(Duration(seconds: 10))) {
        
        debugPrint('📡 mDNS service found: ${ptr.domainName}');
        
        // Try to resolve service details
        await _resolveMDNSService(client, ptr.domainName);
      }
      
      client.stop();
      
    } catch (e) {
      debugPrint('❌ mDNS discovery failed: $e');
    }
  }

  /// Resolve mDNS service details
  Future<void> _resolveMDNSService(MDnsClient client, String serviceName) async {
    try {
      // Look for SRV records to get port and target
      await for (final srv in client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(serviceName))
          .timeout(Duration(seconds: 5))) {
        
        debugPrint('📡 mDNS SRV record: ${srv.target}:${srv.port}');
        
        // Look for TXT records to get device info
        await for (final txt in client
            .lookup<TxtResourceRecord>(ResourceRecordQuery.text(serviceName))
            .timeout(Duration(seconds: 3))) {
          
          final deviceInfo = _parseMDNSTxtRecord(txt.text as List<int>);
          if (deviceInfo.containsKey('deviceId') && deviceInfo.containsKey('userName')) {
            
            final device = DeviceModel(
              id: deviceInfo["deviceId"]!,
              deviceId: deviceInfo["deviceId"]!,
              userName: deviceInfo["userName"]!,
              isHost: false,
              isOnline: false,
              lastSeen: DateTime.now(),
              createdAt: DateTime.now(),
              discoveryMethod: 'mdns',
            );
            _addDiscoveredDevice(device);
            debugPrint('📡 mDNS ResQLink device found: ${device.userName}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ mDNS service resolution failed: $e');
    }
  }

  /// Parse mDNS TXT record
  Map<String, String> _parseMDNSTxtRecord(List<int> txtData) {
    final result = <String, String>{};
    
    try {
      final txtString = String.fromCharCodes(txtData);
      final pairs = txtString.split(',');
      
      for (final pair in pairs) {
        final parts = pair.split('=');
        if (parts.length == 2) {
          result[parts[0].trim()] = parts[1].trim();
        }
      }
    } catch (e) {
      debugPrint('❌ Error parsing TXT record: $e');
    }
    
    return result;
  }

  /// Discover devices via UDP broadcast
  Future<void> _discoverBroadcastDevices() async {
    try {
      debugPrint('🔍 Starting UDP broadcast discovery...');
      
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      
      // Send discovery broadcast
      final discoveryMessage = jsonEncode({
        'type': 'discovery_request',
        'deviceId': _baseService.deviceId,
        'userName': _baseService.userName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      final data = utf8.encode(discoveryMessage);
      socket.send(data, InternetAddress('255.255.255.255'), P2PBaseService.defaultPort);
      
      debugPrint('📡 Discovery broadcast sent');
      
      // Listen for responses
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final packet = socket.receive();
          if (packet != null) {
            try {
              final response = utf8.decode(packet.data);
              final data = jsonDecode(response);
              
              if (data['type'] == 'discovery_response') {
                _handleBroadcastResponse(data, packet.address.address);
              }
            } catch (e) {
              debugPrint('❌ Error processing broadcast response: $e');
            }
          }
        }
      });
      
      // Wait for responses
      await Future.delayed(Duration(seconds: 5));
      socket.close();
      
    } catch (e) {
      debugPrint('❌ Broadcast discovery failed: $e');
    }
  }

  /// Handle broadcast discovery response
  void _handleBroadcastResponse(Map<String, dynamic> data, String address) {
    try {
      final deviceId = data['deviceId'] as String?;
      final userName = data['userName'] as String?;
      
      if (deviceId != null && userName != null && deviceId != _baseService.deviceId) {
        final device = DeviceModel(
          id: deviceId,
          deviceId: deviceId,
          userName: userName,
          isHost: false,
          isOnline: false,
          lastSeen: DateTime.now(),
          createdAt: DateTime.now(),
          discoveryMethod: 'broadcast',
        );
        
        _addDiscoveredDevice(device);
        debugPrint('📡 Broadcast ResQLink device found: $userName');
      }
    } catch (e) {
      debugPrint('❌ Error handling broadcast response: $e');
    }
  }

  /// Add discovered device to list
  void _addDiscoveredDevice(DeviceModel device) {
    // Update last seen time
    _lastSeenDevices[device.deviceId] = DateTime.now();

    // Add to discovered devices if not already there
    final existingIndex = _baseService.discoveredResQLinkDevices
        .indexWhere((d) => d.deviceId == device.deviceId);

    if (existingIndex >= 0) {
      // Update existing device
      _baseService.discoveredResQLinkDevices[existingIndex] = device;
    } else {
      // Add new device
      _baseService.discoveredResQLinkDevices.add(device);
    }

    // Notify discovery callback with all discovered devices
    _triggerDevicesDiscoveredCallback();
  }

  /// Trigger the devices discovered callback with current device list
  void _triggerDevicesDiscoveredCallback() {
    final deviceList = _baseService.discoveredResQLinkDevices.map((device) => {
      "deviceId": device.deviceId,
      "deviceName": device.userName,
      "deviceAddress": device.deviceAddress ?? device.deviceId,
      "connectionType": device.discoveryMethod ?? 'unknown',
      "isAvailable": !device.isConnected,
      "signalLevel": _calculateDeviceSignal(device),
      "lastSeen": device.lastSeen.millisecondsSinceEpoch,
      "isConnected": device.isConnected,
      "isEmergency": device.userName.toLowerCase().contains('emergency'),
    }).toList();

    _baseService.onDevicesDiscovered?.call(deviceList);
  }

  /// Calculate signal strength for discovered device
  int _calculateDeviceSignal(DeviceModel device) {
    final timeDiff = DateTime.now().difference(device.lastSeen).inMinutes;

    switch (device.discoveryMethod) {
      case 'mdns':
      case 'mdns_enhanced':
        return -45 - (timeDiff * 2); // Strong for local network
      case 'broadcast':
        return -55 - (timeDiff * 3); // Medium for broadcast
      case 'hotspot':
      case 'hotspot_enhanced':
        return -60 - (timeDiff * 2); // Medium for hotspot
      default:
        return -70 - (timeDiff * 5); // Weak for unknown
    }
  }
  /// Check if we should attempt connection to this device
  bool _shouldAttemptConnection(String deviceId) {
    final attempts = _deviceConnectionAttempts[deviceId] ?? 0;
    final maxAttempts = 3;
    
    if (attempts >= maxAttempts) {
      return false;
    }
    
    // Don't attempt too frequently
    final lastSeen = _lastSeenDevices[deviceId];
    if (lastSeen != null) {
      final timeSinceLastSeen = DateTime.now().difference(lastSeen);
      if (timeSinceLastSeen.inMinutes < 5) {
        return false;
      }
    }
    
    return true;
  }

  /// Attempt to connect to network
  Future<void> _attemptNetworkConnection(dynamic network) async {
    try {
      final deviceId = network.ssid?.replaceFirst(P2PBaseService.resqlinkPrefix, '') ?? '';
      
      // Increment attempt counter
      _deviceConnectionAttempts[deviceId] = (_deviceConnectionAttempts[deviceId] ?? 0) + 1;
      
      debugPrint('🔗 Attempting connection to: ${network.ssid} (attempt ${_deviceConnectionAttempts[deviceId]})');
      
      final connected = await _networkService.connectToResQLinkNetwork(network.ssid ?? "");
      
      if (connected) {
        debugPrint('✅ Successfully connected to: ${network.ssid}');
        // Reset attempt counter on success
        _deviceConnectionAttempts.remove(deviceId);
      } else {
        debugPrint('❌ Failed to connect to: ${network.ssid}');
      }
      
    } catch (e) {
      debugPrint('❌ Network connection attempt failed: $e');
    }
  }

  /// Start periodic discovery
  void _startPeriodicDiscovery() {
    _discoveryRetryTimer = Timer.periodic(Duration(seconds: 60), (_) {
      if (!_discoveryInProgress && _baseService.connectedDevices.isEmpty) {
        debugPrint('🔄 Starting periodic discovery...');
        discoverDevices(force: false);
      }
    });
  }

  /// Stop periodic discovery
  void _stopPeriodicDiscovery() {
    _discoveryRetryTimer?.cancel();
    _discoveryRetryTimer = null;
  }

  /// Get discovery status
  Map<String, dynamic> getDiscoveryStatus() {
    return {
      'discoveryInProgress': _discoveryInProgress,
      'wifiDirectAvailable': _wifiDirectAvailable,
      'mdnsAvailable': _mdnsAvailable,
      'discoveredDevices': _baseService.discoveredResQLinkDevices.length,
      'lastSeenDevices': _lastSeenDevices.length,
      'connectionAttempts': _deviceConnectionAttempts,
    };
  }

  /// Cleanup old discovered devices
  void cleanupOldDevices() {
    final cutoff = DateTime.now().subtract(Duration(minutes: 30));
    
    _baseService.discoveredResQLinkDevices.removeWhere((device) {
      final lastSeen = device.lastSeen;
      return lastSeen.isBefore(cutoff);
    });
    
    // Clean up tracking maps
    _lastSeenDevices.removeWhere((_, lastSeen) => lastSeen.isBefore(cutoff));
    
    debugPrint('🧹 Cleaned up old discovered devices');
  }

  /// Dispose discovery resources
  void dispose() {
    debugPrint('🗑️ P2P Discovery Service disposing...');
    
    _discoveryInProgress = false;
    _stopPeriodicDiscovery();
    _discoveryTimeoutTimer?.cancel();
    
    _lastSeenDevices.clear();
    _deviceConnectionAttempts.clear();
  }
}