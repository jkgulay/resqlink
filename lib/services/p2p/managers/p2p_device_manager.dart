import 'dart:async';
import 'package:flutter/material.dart';
import '../p2p_base_service.dart';
import '../../../models/device_model.dart';
import '../wifi_direct_service.dart';
import 'p2p_connection_manager.dart';

/// Manages device discovery, tracking, and device information
class P2PDeviceManager {
  final P2PBaseService _baseService;
  final P2PConnectionManager _connectionManager;
  WiFiDirectService? _wifiDirectService;

  // Callbacks
  void Function(List<Map<String, dynamic>>)? onDevicesDiscovered;

  P2PDeviceManager(this._baseService, this._connectionManager);

  /// Set WiFi Direct service
  void setWiFiDirectService(WiFiDirectService? service) {
    _wifiDirectService = service;
  }

  Map<String, Map<String, dynamic>> get discoveredDevices {
    final deviceMap = <String, Map<String, dynamic>>{};
    final seenMacAddresses =
        <String>{}; // Track MAC addresses to prevent duplicates

    // 1. Add WiFi Direct peers (direct neighbors)
    for (final peer in (_wifiDirectService?.discoveredPeers ?? <dynamic>[])) {
      final isConnected = peer.status == WiFiDirectPeerStatus.connected;

      // CRITICAL: Use UUID as primary key if available, otherwise use MAC
      final uuid = _baseService.getUuidForMac(peer.deviceAddress);
      final deviceKey = uuid ?? peer.deviceAddress; // Prefer UUID over MAC

      // Track MAC address to prevent duplicates
      seenMacAddresses.add(peer.deviceAddress);

      final connectedDevice = uuid != null
          ? _baseService.connectedDevices[uuid]
          : null;
      final customNameFromDiscovery = _wifiDirectService?.getCustomName(
        peer.deviceAddress,
      );
      final displayName =
          connectedDevice?.userName ??
          customNameFromDiscovery ??
          peer.deviceName;

      deviceMap[deviceKey] = {
        'deviceId': deviceKey, // Use consistent UUID key
        'deviceName': displayName,
        'deviceAddress': peer.deviceAddress,
        'connectionType': 'wifi_direct',
        'isAvailable':
            peer.status == WiFiDirectPeerStatus.available || isConnected,
        'signalLevel': peer.signalLevel ?? -50,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'isConnected': isConnected,
        'status': wifiDirectPeerStatusToString(peer.status),
        'isEmergency':
            displayName.toLowerCase().contains('resqlink') ||
            displayName.toLowerCase().contains('emergency'),
        'hopCount': 0, // Direct WiFi Direct connection
        'isDirect': true,
        'isMultiHop': false,
      };
    }

    // 2. Add ResQLink devices from discovery service (don't overwrite WiFi Direct devices)
    for (final device in _baseService.discoveredResQLinkDevices) {
      // Skip if we've already added this device via WiFi Direct using its MAC address
      if (device.deviceAddress != null &&
          seenMacAddresses.contains(device.deviceAddress)) {
        debugPrint(
          '⏭️ Skipping duplicate device: ${device.userName} (already added via WiFi Direct)',
        );
        continue;
      }

      if (!deviceMap.containsKey(device.deviceId)) {
        deviceMap[device.deviceId] = {
          'deviceId': device.deviceId,
          'deviceName': device.userName,
          'deviceAddress': device.deviceAddress ?? device.deviceId,
          'connectionType': device.discoveryMethod ?? 'unknown',
          'isAvailable': !device.isConnected,
          'signalLevel': _calculateSignalStrength(device),
          'lastSeen': device.lastSeen.millisecondsSinceEpoch,
          'isConnected': device.isConnected,
          'isEmergency': device.userName.toLowerCase().contains('emergency'),
          'hopCount': 0,
          'isDirect': true,
          'isMultiHop': false,
        };
      } else {
        // Merge information if device exists in both lists
        final existing = deviceMap[device.deviceId]!;
        deviceMap[device.deviceId] = {
          ...existing,
          'isConnected': device.isConnected || existing['isConnected'],
          'lastSeen': device.lastSeen.millisecondsSinceEpoch,
        };
      }
    }

    // 3. ADD MESH DEVICES - devices discovered via multi-hop messages
    // DO THIS BEFORE updating connected devices so they can be marked as connected
    final reachableDevices = _baseService.reachableDevices;
    debugPrint('🌐 Adding ${reachableDevices.length} mesh-discovered devices');

    for (final meshDevice in reachableDevices) {
      final deviceId = meshDevice['deviceId'] as String;
      final deviceName = meshDevice['deviceName'] as String;
      final hopCount = meshDevice['hopCount'] as int;
      final isDirect = meshDevice['isDirect'] as bool;
      final isMultiHop = meshDevice['isMultiHop'] as bool;
      final lastSeen = meshDevice['lastSeen'] as int;

      // Only add if not already in list (direct connections take precedence)
      if (!deviceMap.containsKey(deviceId)) {
        deviceMap[deviceId] = {
          'deviceId': deviceId,
          'deviceName': '$deviceName ${isMultiHop ? "($hopCount hops)" : ""}',
          'deviceAddress': deviceId,
          'connectionType': 'mesh',
          'isAvailable': true,
          'signalLevel': -60 - (hopCount * 10), // Weaker signal for more hops
          'lastSeen': lastSeen,
          'isConnected': false,
          'isMeshReachable': true, // Mark as mesh-reachable for UI
          'isEmergency': deviceName.toLowerCase().contains('emergency'),
          'hopCount': hopCount,
          'isDirect': isDirect,
          'isMultiHop': isMultiHop,
        };
        debugPrint('🌐 Added mesh device: $deviceName ($hopCount hops)');
      }
    }

    // 4. Override device info with connected device data (real names from handshake)
    // This runs AFTER mesh devices are added so they get marked as connected
    for (final connectedDevice in _baseService.connectedDevices.values) {
      if (deviceMap.containsKey(connectedDevice.deviceId)) {
        deviceMap[connectedDevice.deviceId] = {
          ...deviceMap[connectedDevice.deviceId]!,
          'deviceName': connectedDevice.userName,
          'isConnected': true,
          'isOnline': connectedDevice.isOnline,
        };
        debugPrint(
          '🔄 Updated device from connectedDevices: ${connectedDevice.userName} (${connectedDevice.deviceId}) - isConnected=true',
        );
      }
    }

    // 5. Add devices from mesh registry (multi-hop reachable via group roster)
    // These are devices reachable through relays but not directly connected
    for (final entry in _baseService.meshDevices.entries) {
      final deviceId = entry.key;
      final meshDevice = entry.value;

      // Only add if not already in deviceMap (direct connections take precedence)
      if (!deviceMap.containsKey(deviceId)) {
        final hopCount = _baseService.meshDeviceHopCount[deviceId] ?? 99;
        final lastSeen = _baseService.meshDeviceLastSeen[deviceId];

        deviceMap[deviceId] = {
          'deviceId': deviceId,
          'deviceName': '${meshDevice.userName} ($hopCount hops)',
          'deviceAddress': deviceId,
          'connectionType': 'mesh',
          'isAvailable': true,
          'signalLevel': -60 - (hopCount * 10),
          'lastSeen': lastSeen?.millisecondsSinceEpoch ?? 0,
          'isConnected': false, // Multi-hop, not directly connected
          'isMeshReachable': true, // But reachable via mesh
          'isEmergency': meshDevice.userName.toLowerCase().contains(
            'emergency',
          ),
          'hopCount': hopCount,
          'isDirect': false,
          'isMultiHop': hopCount > 1,
        };
        debugPrint(
          '🔗 Added mesh registry device: ${meshDevice.userName} ($hopCount hops) - reachable via relay',
        );
      }
    }

    return deviceMap;
  }

  /// Get known devices (discovered + connected)
  Map<String, DeviceModel> get knownDevices {
    final knownMap = <String, DeviceModel>{};

    // Add discovered devices as known devices
    for (final device in _baseService.discoveredResQLinkDevices) {
      knownMap[device.deviceId] = device;
    }

    // Add connected devices
    for (final device in _baseService.connectedDevices.values) {
      knownMap[device.deviceId] = device;
    }

    return knownMap;
  }

  /// Calculate signal strength for non-WiFi Direct devices
  int _calculateSignalStrength(DeviceModel device) {
    // Base signal strength on discovery method and recency
    final timeDiff = DateTime.now().difference(device.lastSeen).inMinutes;

    switch (device.discoveryMethod) {
      case 'mdns':
      case 'mdns_enhanced':
        return -45 - (timeDiff * 2); // Strong for local network
      case 'broadcast':
        return -55 - (timeDiff * 3); // Medium for broadcast
      default:
        return -70 - (timeDiff * 5); // Weak for unknown
    }
  }

  /// Trigger devices discovered callback
  void triggerDevicesDiscoveredCallback() {
    if (onDevicesDiscovered != null) {
      final allDevices = discoveredDevices.values.toList();
      onDevicesDiscovered!(allDevices);
    }
  }

  /// Connect to a device
  Future<bool> connectToDevice(Map<String, dynamic> device) async {
    try {
      debugPrint('🔗 Attempting to connect to device: ${device['deviceName']}');

      final connectionType = device['connectionType'] as String?;

      switch (connectionType) {
        case 'wifi_direct':
          return await _connectViaWifiDirect(device);
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

  /// Connect via WiFi Direct
  Future<bool> _connectViaWifiDirect(Map<String, dynamic> device) async {
    final deviceAddress = device['deviceAddress'] as String?;
    if (deviceAddress == null) return false;

    try {
      debugPrint('📡 Connecting via WiFi Direct to: $deviceAddress');

      final success =
          await _wifiDirectService?.connectToPeer(deviceAddress) ?? false;

      if (success) {
        _connectionManager.setConnectionMode(P2PConnectionMode.wifiDirect);

        final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
        _baseService.addConnectedDevice(deviceAddress, deviceName);

        debugPrint('✅ WiFi Direct connection successful');
        return true;
      } else {
        debugPrint('❌ WiFi Direct connection failed');
        return false;
      }
    } catch (e) {
      debugPrint('❌ WiFi Direct connection failed: $e');
      return false;
    }
  }

  /// Connect via mDNS (placeholder)
  Future<bool> _connectViaMDNS(Map<String, dynamic> device) async {
    debugPrint('📡 Connecting via mDNS to: ${device['deviceName']}');
    return true; // Placeholder
  }

  /// Get device statistics
  Map<String, dynamic> getDeviceStats() {
    return {
      'discoveredDevices': discoveredDevices.length,
      'connectedDevices': _baseService.connectedDevices.length,
      'knownDevices': knownDevices.length,
      'wifiDirectPeers': _wifiDirectService?.discoveredPeers.length ?? 0,
      'resqlinkDevices': _baseService.discoveredResQLinkDevices.length,
    };
  }

  /// Clear all discovered devices
  void clearDiscoveredDevices() {
    _baseService.discoveredResQLinkDevices.clear();
    debugPrint('🧹 Cleared all discovered devices');
  }

  /// Dispose and cleanup
  void dispose() {
    debugPrint('🗑️ Device manager disposed');
  }
}
