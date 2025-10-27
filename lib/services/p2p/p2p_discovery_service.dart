import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wifi_direct_plugin/wifi_direct_plugin.dart';
import 'p2p_base_service.dart';

/// Device discovery service for P2P connections (WiFi Direct only)
class P2PDiscoveryService {
  final P2PBaseService _baseService;

  // Discovery state
  bool _discoveryInProgress = false;
  Timer? _discoveryTimeoutTimer;

  // Discovery methods
  bool _wifiDirectAvailable = false;
  bool _mdnsAvailable = false;

  // Discovered devices tracking
  final Map<String, DateTime> _lastSeenDevices = {};
  final Map<String, int> _deviceConnectionAttempts = {};

  P2PDiscoveryService(this._baseService);

  /// Initialize discovery service
  Future<void> initialize() async {
    try {
      debugPrint('🔍 Initializing P2P Discovery Service...');

      // Check WiFi Direct availability
      await _checkWifiDirectAvailability();

      // Don't start periodic discovery automatically - only discover when user explicitly scans
      // _startPeriodicDiscovery(); // DISABLED: User must manually scan

      debugPrint('✅ P2P Discovery Service initialized (manual scan mode)');
    } catch (e) {
      debugPrint('❌ Discovery service initialization failed: $e');
    }
  }

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

      // WiFi Direct discovery only
      debugPrint('📡 Starting WiFi Direct discovery');
      await _discoverWifiDirectDevices();

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
    _discoveryTimeoutTimer?.cancel();

    _lastSeenDevices.clear();
    _deviceConnectionAttempts.clear();
  }
}
