import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class HotspotManager {
  static const String hotspotPrefix = "ResQLink_"; // Fixed: lowerCamelCase
  static const String hotspotPassword = "RESQLINK911"; // Fixed: lowerCamelCase
  
  final MethodChannel _wifiChannel;
  final String? _deviceId;
  final Future<void> Function()? _startHotspotTcpServer; // Fixed: Future<void>
  final Future<void> Function(String)? _connectToHotspotTcpServer; // Fixed: Future<void>
  final Function(String role)? _setCurrentRole;

  HotspotManager({
    required MethodChannel wifiChannel,
    required String? deviceId,
    Future<void> Function()? startHotspotTcpServer, // Fixed: Future<void>
    Future<void> Function(String)? connectToHotspotTcpServer, // Fixed: Future<void>
    Function(String role)? setCurrentRole,
  }) : _wifiChannel = wifiChannel,
       _deviceId = deviceId,
       _startHotspotTcpServer = startHotspotTcpServer,
       _connectToHotspotTcpServer = connectToHotspotTcpServer,
       _setCurrentRole = setCurrentRole;

  Future<bool> createResQLinkHotspot() async {
    try {
      final deviceId = _deviceId?.substring(0, 8) ?? "Unknown";
      final hotspotSSID = "$hotspotPrefix$deviceId";

      debugPrint("📶 Creating ResQLink hotspot: $hotspotSSID");

      // Use platform channel to create hotspot
      final result = await _wifiChannel.invokeMethod('createHotspot', {
        'ssid': hotspotSSID,
        'password': hotspotPassword,
        'frequency': 2437, // Channel 6
      });

      if (result['success'] == true) {
        debugPrint("✅ Hotspot created: $hotspotSSID");
        
        if (_startHotspotTcpServer != null) {
          await _startHotspotTcpServer(); // Fixed: removed !
        }
        
        if (_setCurrentRole != null) {
          _setCurrentRole('host'); // Fixed: removed !
        }
        
        return true;
      }

      return false;
    } catch (e) {
      debugPrint("❌ Failed to create hotspot: $e");
      return false;
    }
  }

  Future<List<String>> scanForResQLinkHotspots() async {
    try {
      debugPrint("📡 Scanning for ResQLink hotspots...");
      
      final result = await _wifiChannel.invokeMethod('scanWifi');
      
      if (result['success'] == true) {
        final networks = result['networks'] as List;
        
        final resqlinkNetworks = networks
            .where((network) => network['ssid']?.startsWith(hotspotPrefix) == true)
            .map((network) => network['ssid'] as String)
            .toList();
            
        debugPrint("🔍 Found ${resqlinkNetworks.length} ResQLink hotspots");
        return resqlinkNetworks;
      }
      
      return [];
    } catch (e) {
      debugPrint("❌ WiFi scan failed: $e");
      return [];
    }
  }

  Future<bool> connectToResQLinkHotspot(String ssid) async {
    try {
      debugPrint("🔗 Connecting to ResQLink hotspot: $ssid");
      
      final result = await _wifiChannel.invokeMethod('connectToWiFi', {
        'ssid': ssid,
        'password': hotspotPassword,
      });

      if (result['success'] == true) {
        debugPrint("✅ Connected to hotspot: $ssid");
        
        if (_connectToHotspotTcpServer != null) {
          await _connectToHotspotTcpServer(ssid); // Fixed: removed !
        }
        
        if (_setCurrentRole != null) {
          _setCurrentRole('client'); // Fixed: removed !
        }
        
        return true;
      }

      return false;
    } catch (e) {
      debugPrint("❌ Failed to connect to hotspot: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> getHotspotInfo() async {
    try {
      final result = await _wifiChannel.invokeMethod('getHotspotInfo');
      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint("❌ Failed to get hotspot info: $e");
      return {'isEnabled': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getCurrentWiFiInfo() async {
    try {
      final result = await _wifiChannel.invokeMethod('getCurrentWiFi');
      return result as Map<String, dynamic>;
    } catch (e) {
      debugPrint("❌ Failed to get current WiFi info: $e");
      return {'ssid': null, 'error': e.toString()};
    }
  }

  bool isResQLinkHotspot(String ssid) {
    return ssid.startsWith(hotspotPrefix);
  }

  String generateHotspotName() {
    final deviceId = _deviceId?.substring(0, 8) ?? "Unknown";
    return "$hotspotPrefix$deviceId";
  }
}