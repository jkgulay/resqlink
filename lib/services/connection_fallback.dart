import 'dart:async';
import 'package:flutter/foundation.dart';

enum ConnectionMode { wifiDirect, hotspotHost, hotspotClient, failed }

class ConnectionFallbackManager {
  ConnectionMode _currentMode = ConnectionMode.wifiDirect;
  int _wifiDirectRetries = 0;
  static const int maxRetries = 3; // Fixed: lowerCamelCase
  
  // Callbacks for P2P service integration
  final Future<void> Function()? _performDiscoveryScan;
  final Future<void> Function(List<Map<String, dynamic>>)? _connectToAvailableDevice;
  final Future<List<String>> Function()? _scanForResQLinkHotspots;
  final Future<bool> Function(String)? _connectToResQLinkHotspot;
  final Future<bool> Function()? _createResQLinkHotspot;
  final Map<String, Map<String, dynamic>> Function()? _getDiscoveredDevices;
  final bool Function()? _isConnected;
  final Function(String mode)? _onConnectionModeChanged;
  final Function()? _onConnectionFailed;

  ConnectionFallbackManager({
    Future<void> Function()? performDiscoveryScan,
    Future<void> Function(List<Map<String, dynamic>>)? connectToAvailableDevice,
    Future<List<String>> Function()? scanForResQLinkHotspots,
    Future<bool> Function(String)? connectToResQLinkHotspot,
    Future<bool> Function()? createResQLinkHotspot,
    Map<String, Map<String, dynamic>> Function()? getDiscoveredDevices,
    bool Function()? isConnected,
    Function(String mode)? onConnectionModeChanged,
    Function()? onConnectionFailed,
  }) : _performDiscoveryScan = performDiscoveryScan,
       _connectToAvailableDevice = connectToAvailableDevice,
       _scanForResQLinkHotspots = scanForResQLinkHotspots,
       _connectToResQLinkHotspot = connectToResQLinkHotspot,
       _createResQLinkHotspot = createResQLinkHotspot,
       _getDiscoveredDevices = getDiscoveredDevices,
       _isConnected = isConnected,
       _onConnectionModeChanged = onConnectionModeChanged,
       _onConnectionFailed = onConnectionFailed;

  ConnectionMode get currentMode => _currentMode;
  int get retryCount => _wifiDirectRetries;

  Future<void> initiateConnection() async {
    _currentMode = ConnectionMode.wifiDirect;
    _wifiDirectRetries = 0;
    
    await _attemptWifiDirectConnection();
  }

  Future<void> _attemptWifiDirectConnection() async {
    try {
      debugPrint("🔄 Attempting WiFi Direct connection (attempt ${_wifiDirectRetries + 1})");
      
      if (_performDiscoveryScan != null) {
        await _performDiscoveryScan(); // Fixed: removed !
      }
      
      // Wait for discovery results
      await Future.delayed(Duration(seconds: 10));
      
      final discoveredDevices = _getDiscoveredDevices?.call() ?? {};
      
      if (discoveredDevices.isNotEmpty) {
        if (_connectToAvailableDevice != null) {
          await _connectToAvailableDevice(discoveredDevices.values.toList()); // Fixed: removed !
        }
        
        // Check if connection was successful
        await Future.delayed(Duration(seconds: 5));
        
        final isConnected = _isConnected?.call() ?? false;
        if (!isConnected) {
          throw Exception("WiFi Direct connection failed");
        }
        
        _showConnectionModeNotification("WiFi Direct");
        
      } else {
        throw Exception("No devices discovered");
      }
      
    } catch (e) {
      _wifiDirectRetries++;
      
      if (_wifiDirectRetries < maxRetries) { // Fixed: use lowerCamelCase
        debugPrint("🔄 WiFi Direct retry $_wifiDirectRetries/$maxRetries"); // Fixed: removed braces
        Timer(Duration(seconds: 5), _attemptWifiDirectConnection);
      } else {
        debugPrint("❌ WiFi Direct failed, falling back to hotspot");
        await _fallbackToHotspot();
      }
    }
  }

  Future<void> _fallbackToHotspot() async {
    _currentMode = ConnectionMode.hotspotHost;
    
    try {
      // First try to find existing ResQLink hotspots
      final resqlinkHotspots = await (_scanForResQLinkHotspots?.call() ?? Future.value(<String>[]));
      
      if (resqlinkHotspots.isNotEmpty) {
        // Connect as client
        _currentMode = ConnectionMode.hotspotClient;
        
        for (final hotspot in resqlinkHotspots) {
          final connected = await (_connectToResQLinkHotspot?.call(hotspot) ?? Future.value(false));
          if (connected) {
            _showConnectionModeNotification("Hotspot Client");
            return;
          }
        }
      }
      
      // No existing hotspots, create our own
      final created = await (_createResQLinkHotspot?.call() ?? Future.value(false));
      if (created) {
        _showConnectionModeNotification("Hotspot Host");
      } else {
        _currentMode = ConnectionMode.failed;
        _showConnectionFailedNotification();
      }
      
    } catch (e) {
      debugPrint("❌ Hotspot fallback failed: $e");
      _currentMode = ConnectionMode.failed;
      _showConnectionFailedNotification();
    }
  }

  void _showConnectionModeNotification(String mode) {
    debugPrint("✅ Connected via: $mode");
    _onConnectionModeChanged?.call(mode);
  }

  void _showConnectionFailedNotification() {
    debugPrint("❌ All connection methods failed");
    _onConnectionFailed?.call();
  }

  void reset() {
    _currentMode = ConnectionMode.wifiDirect;
    _wifiDirectRetries = 0;
  }

  Map<String, dynamic> getStatus() {
    return {
      'currentMode': _currentMode.name,
      'retryCount': _wifiDirectRetries,
      'maxRetries': maxRetries,
      'canRetry': _wifiDirectRetries < maxRetries,
    };
  }
}