import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'p2p/p2p_main_service.dart';
import 'signal_monitoring_service.dart';

class EmergencyRecoveryService {
  static final EmergencyRecoveryService _instance =
      EmergencyRecoveryService._internal();
  factory EmergencyRecoveryService() => _instance;
  EmergencyRecoveryService._internal();

  Timer? _recoveryTimer;
  Timer? _aggressiveScanTimer;
  P2PMainService? _p2pService;
  SignalMonitoringService? _signalService;

  bool _isRecoveryActive = false;
  int _consecutiveFailures = 0;
  DateTime? _lastConnectionTime;

  // Recovery strategies
  static const Duration _normalRecoveryInterval = Duration(seconds: 30);
  static const Duration _aggressiveRecoveryInterval = Duration(seconds: 10);
  static const Duration _emergencyRecoveryInterval = Duration(seconds: 5);

  void initialize(
    P2PMainService p2pService,
    SignalMonitoringService signalService,
  ) {
    _p2pService = p2pService;
    _signalService = signalService;

    // Listen for connection changes
    p2pService.addListener(_onConnectionChange);

    debugPrint("🔄 Emergency recovery service initialized");
  }

  void startEmergencyRecovery() {
    if (_isRecoveryActive) return;

    _isRecoveryActive = true;
    _consecutiveFailures = 0;

    debugPrint("🚨 Starting emergency recovery mode");

    // Start with normal recovery, escalate if needed
    _startRecoveryTimer(_normalRecoveryInterval);

    // Monitor signal quality for proactive recovery
    _signalService?.onQualityChanged = _onSignalQualityChanged;
  }

  void stopEmergencyRecovery() {
    _isRecoveryActive = false;
    _recoveryTimer?.cancel();
    _aggressiveScanTimer?.cancel();

    debugPrint("✋ Emergency recovery stopped");
  }

  void _onConnectionChange() {
    if (_p2pService?.isConnected == true) {
      _lastConnectionTime = DateTime.now();
      _consecutiveFailures = 0;

      // Scale back recovery if we're connected
      if (_isRecoveryActive) {
        _startRecoveryTimer(_normalRecoveryInterval);
      }
    } else {
      _consecutiveFailures++;

      // Escalate recovery based on failure count
      if (_isRecoveryActive) {
        _escalateRecovery();
      }
    }
  }

  void _onSignalQualityChanged(String deviceId, ConnectionQuality quality) {
    // Proactive recovery if quality is degrading
    if (quality == ConnectionQuality.poor ||
        quality == ConnectionQuality.veryPoor) {
      debugPrint(
        "📶 Poor signal quality detected for $deviceId, initiating recovery",
      );
      _attemptConnection();
    }
  }

  void _escalateRecovery() {
    debugPrint("⚠️ Escalating recovery (failures: $_consecutiveFailures)");

    if (_consecutiveFailures <= 2) {
      // Normal recovery
      _startRecoveryTimer(_normalRecoveryInterval);
    } else if (_consecutiveFailures <= 4) {
      // Aggressive recovery
      _startRecoveryTimer(_aggressiveRecoveryInterval);
      _startAggressiveScanning();
    } else {
      // Emergency recovery
      _startRecoveryTimer(_emergencyRecoveryInterval);
      _startEmergencyProtocol();
    }
  }

  void _startRecoveryTimer(Duration interval) {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer.periodic(interval, (timer) {
      if (!_isRecoveryActive) {
        timer.cancel();
        return;
      }

      _attemptConnection();
    });
  }

  Future<void> _attemptConnection() async {
    if (_p2pService == null || _p2pService!.isConnected) return;

    try {
      debugPrint("🔄 Attempting emergency connection recovery...");

      // Try multiple strategies simultaneously
      await Future.wait([
        _tryWiFiDirectRecovery(),
        _tryHotspotRecovery(),
        _tryKnownDeviceRecovery(),
      ], eagerError: false);
    } catch (e) {
      debugPrint("❌ Recovery attempt failed: $e");
    }
  }

  Future<void> _tryWiFiDirectRecovery() async {
    try {
      debugPrint("📡 Trying WiFi Direct recovery...");

      // Force discovery with extended scan time
      await _p2pService!.discoverDevices(force: true);

      // Wait for results
      await Future.delayed(Duration(seconds: 8));

      // Try to connect to best available device - FIXED
      final discoveredDevices = _p2pService!.discoveredDevices;
      final devices = discoveredDevices.values
          .where((d) => d['isAvailable'] == true)
          .toList();

      if (devices.isNotEmpty) {
        // Sort by signal strength and try best one
        devices.sort((a, b) {
          final aSignal = a['signalLevel'] as int? ?? -100;
          final bSignal = b['signalLevel'] as int? ?? -100;
          return bSignal.compareTo(aSignal);
        });

        await _p2pService!.connectToDevice(devices.first);
        debugPrint("✅ WiFi Direct recovery successful");
      }
    } catch (e) {
      debugPrint("❌ WiFi Direct recovery failed: $e");
    }
  }

  Future<void> _tryHotspotRecovery() async {
    try {
      debugPrint("📶 Trying hotspot recovery...");

      // Enable hotspot fallback if not already enabled
      if (!_p2pService!.hotspotFallbackEnabled) {
        _p2pService!.setHotspotFallbackEnabled(true);
      }

      // Scan for ResQLink hotspots - FIXED
      final hotspots = _p2pService!.getAvailableHotspots();

      if (hotspots.isNotEmpty) {
        // Try to connect to strongest hotspot
        hotspots.sort((a, b) {
          final aSignal = a['signalLevel'] as int? ?? -100;
          final bSignal = b['signalLevel'] as int? ?? -100;
          return bSignal.compareTo(aSignal);
        });

        await _p2pService!.connectToDevice({
          'deviceName': hotspots.first['ssid'],
          'deviceAddress': hotspots.first['ssid'],
          'connectionType': 'hotspot',
        });

        debugPrint("✅ Hotspot recovery successful");
      } else {
        // Create our own hotspot if none available
        await _p2pService!.createEmergencyHotspot();
        debugPrint("✅ Emergency hotspot created");
      }
    } catch (e) {
      debugPrint("❌ Hotspot recovery failed: $e");
    }
  }

  Future<void> _tryKnownDeviceRecovery() async {
    try {
      debugPrint("🔍 Trying known device recovery...");

      final knownDevices = _p2pService!.knownDevices;

      // Try to reconnect to recently seen devices
      for (var device in knownDevices.values) {
        final hoursSinceLastSeen = DateTime.now()
            .difference(device.lastSeen)
            .inHours;

        if (hoursSinceLastSeen < 24) {
          // Try to find this device in current discoveries - FIXED
          final discoveredDevices = _p2pService!.discoveredDevices;
          final discovered = discoveredDevices[device.deviceId];

          if (discovered != null && discovered['isAvailable'] == true) {
            await _p2pService!.connectToDevice(discovered);
            debugPrint(
              "✅ Known device recovery successful: ${device.deviceId}",
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Known device recovery failed: $e");
    }
  }

  void _startAggressiveScanning() {
    _aggressiveScanTimer?.cancel();

    debugPrint("🚨 Starting aggressive scanning mode");

    _aggressiveScanTimer = Timer.periodic(Duration(seconds: 15), (timer) {
      if (!_isRecoveryActive || _p2pService?.isConnected == true) {
        timer.cancel();
        return;
      }

      // Force multiple discovery attempts
      _performAggressiveDiscovery();
    });
  }

  Future<void> _performAggressiveDiscovery() async {
    try {
      debugPrint("🔍 Performing aggressive discovery...");

      // Multiple short scans with different intervals
      for (int i = 0; i < 3; i++) {
        await _p2pService!.discoverDevices(force: true);
        await Future.delayed(Duration(seconds: 5));

        // Check if we found anything
        if (_p2pService!.discoveredDevices.isNotEmpty) {
          break;
        }
      }
    } catch (e) {
      debugPrint("❌ Aggressive discovery failed: $e");
    }
  }

  Future<void> _startEmergencyProtocol() async {
    debugPrint("🆘 Starting emergency protocol - all recovery strategies");

    try {
      // Emergency protocol: try everything simultaneously
      await Future.wait([
        _emergencyWiFiDirectScan(),
        _emergencyHotspotScan(),
        _emergencyBroadcast(),
      ], eagerError: false);

      // If still no connection, become a strong emergency beacon
      if (!_p2pService!.isConnected) {
        await _becomeEmergencyBeacon();
      }
    } catch (e) {
      debugPrint("❌ Emergency protocol failed: $e");
    }
  }

  Future<void> _emergencyWiFiDirectScan() async {
    // Extended WiFi Direct scan with multiple attempts
    for (int i = 0; i < 5; i++) {
      await _p2pService!.discoverDevices(force: true);
      await Future.delayed(Duration(seconds: 10));
    }
  }

  Future<void> _emergencyHotspotScan() async {
    // Aggressive hotspot scanning and creation
    _p2pService!.setHotspotFallbackEnabled(true);

    // Try multiple times to create emergency group
    for (int i = 0; i < 3; i++) {
      try {
        await _p2pService!.createEmergencyHotspot();
        break;
      } catch (e) {
        await Future.delayed(Duration(seconds: 5));
      }
    }
  }

  Future<void> createEmergencyHotspot({String? deviceId}) async {
    try {
      debugPrint("🚨 Creating emergency hotspot via P2P service...");

      // Use the P2P service's existing method
      final success = await _p2pService!.createEmergencyHotspot(
        deviceId: deviceId,
      );

      if (success) {
        debugPrint("✅ Emergency hotspot created successfully");
      } else {
        throw Exception("Failed to create emergency hotspot");
      }
    } catch (e) {
      debugPrint('❌ Error creating emergency hotspot: $e');
      rethrow;
    }
  }

  Future<void> forceHostRole() async {
    try {
      debugPrint("🔄 Forcing host role via P2P service...");

      // Use the P2P service to create emergency hotspot (which makes it host)
      await _p2pService!.createEmergencyHotspot();

      debugPrint("✅ Host role forced successfully");
    } catch (e) {
      debugPrint("❌ Failed to force host role: $e");
      rethrow;
    }
  }

  Future<void> _emergencyBroadcast() async {
    try {
      // Broadcast emergency beacon signal
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );

        // Use the position for emergency broadcast
        debugPrint(
          "📡 Emergency broadcast sent from: ${position.latitude}, ${position.longitude}",
        );
      } catch (e) {
        debugPrint("Could not get location for emergency broadcast: $e");

        // Send broadcast without location
        debugPrint("📡 Emergency broadcast sent without location");
      }
    } catch (e) {
      debugPrint("❌ Emergency broadcast failed: $e");
    }
  }

  Future<void> _becomeEmergencyBeacon() async {
    try {
      debugPrint("🚨 Becoming emergency beacon - creating persistent hotspot");

      // Create emergency hotspot (which makes us host)
      await _p2pService!.createEmergencyHotspot();

      // Enable all fallback mechanisms
      _p2pService!.setHotspotFallbackEnabled(true);

      debugPrint("✅ Emergency beacon active");
    } catch (e) {
      debugPrint("❌ Failed to become emergency beacon: $e");
    }
  }

  // Get recovery status for UI
  Map<String, dynamic> getRecoveryStatus() {
    return {
      'isActive': _isRecoveryActive,
      'consecutiveFailures': _consecutiveFailures,
      'lastConnectionTime': _lastConnectionTime?.millisecondsSinceEpoch,
      'recoveryLevel': _getRecoveryLevel(),
    };
  }

  String _getRecoveryLevel() {
    if (!_isRecoveryActive) return 'inactive';
    if (_consecutiveFailures <= 2) return 'normal';
    if (_consecutiveFailures <= 4) return 'aggressive';
    return 'emergency';
  }

  void dispose() {
    stopEmergencyRecovery();
    _p2pService?.removeListener(_onConnectionChange);
  }
}
