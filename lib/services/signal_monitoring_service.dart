import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'p2p/p2p_main_service.dart';

class SignalMonitoringService {
  static final SignalMonitoringService _instance = SignalMonitoringService._internal();
  factory SignalMonitoringService() => _instance;
  SignalMonitoringService._internal();

  Timer? _monitoringTimer;
  final Map<String, List<SignalReading>> _signalHistory = {};
  final Map<String, ConnectionQuality> _deviceQuality = {};
  
  // Callbacks
  Function(String deviceId, ConnectionQuality quality)? onQualityChanged;
  Function(String deviceId, int signalStrength)? onSignalChanged;

  void startMonitoring(P2PConnectionService p2pService) {
    _monitoringTimer?.cancel();
    
    _monitoringTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _updateSignalStrengths(p2pService);
    });
    
    debugPrint("📶 Signal monitoring started");
  }

  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint("📶 Signal monitoring stopped");
  }

  Future<void> _updateSignalStrengths(P2PConnectionService p2pService) async {
    try {
      // Monitor connected devices
      for (var deviceId in p2pService.connectedDevices.keys) {
        final signalStrength = await _measureSignalStrength(deviceId);
        _recordSignalReading(deviceId, signalStrength);
        
        final quality = _calculateConnectionQuality(deviceId);
        _updateDeviceQuality(deviceId, quality);
      }

      // Monitor discovered devices (for potential connections)
      for (var device in p2pService.discoveredDevices.values) {
        final deviceId = device['deviceAddress'] as String;
        final signalLevel = device['signalLevel'] as int? ?? -100;
        
        _recordSignalReading(deviceId, signalLevel);
      }
    } catch (e) {
      debugPrint("❌ Error updating signal strengths: $e");
    }
  }

  Future<int> _measureSignalStrength(String deviceId) async {
    try {
      // For WiFi Direct, we simulate signal strength based on connection stability
      // In a real implementation, this would use platform channels to get actual RSSI
      
      // Simulate signal strength with some variation (-40 to -90 dBm)
      final baseSignal = -50;
      final variation = math.Random().nextInt(40);
      final currentSignal = baseSignal - variation;
      
      return currentSignal;
    } catch (e) {
      debugPrint("❌ Error measuring signal strength: $e");
      return -100; // Very poor signal
    }
  }

  void _recordSignalReading(String deviceId, int signalStrength) {
    final reading = SignalReading(
      timestamp: DateTime.now(),
      signalStrength: signalStrength,
      quality: _getSignalQuality(signalStrength),
    );

    _signalHistory.putIfAbsent(deviceId, () => []).add(reading);
    
    // Keep only last 20 readings
    if (_signalHistory[deviceId]!.length > 20) {
      _signalHistory[deviceId]!.removeAt(0);
    }

    onSignalChanged?.call(deviceId, signalStrength);
  }

  ConnectionQuality _calculateConnectionQuality(String deviceId) {
    final readings = _signalHistory[deviceId] ?? [];
    if (readings.isEmpty) return ConnectionQuality.unknown;

    // Calculate average signal strength
    final avgSignal = readings
        .map((r) => r.signalStrength)
        .reduce((a, b) => a + b) / readings.length;

    // Calculate signal stability (lower variance = more stable)
    final variance = readings
        .map((r) => math.pow(r.signalStrength - avgSignal, 2))
        .reduce((a, b) => a + b) / readings.length;
    
    final stability = variance < 100 ? 1.0 : math.max(0.0, 1.0 - (variance / 1000));

    // Combine signal strength and stability
    final strengthScore = _getSignalScore(avgSignal.round());
    final overallScore = (strengthScore * 0.7) + (stability * 0.3);

    if (overallScore >= 0.8) return ConnectionQuality.excellent;
    if (overallScore >= 0.6) return ConnectionQuality.good;
    if (overallScore >= 0.4) return ConnectionQuality.fair;
    if (overallScore >= 0.2) return ConnectionQuality.poor;
    return ConnectionQuality.veryPoor;
  }

  double _getSignalScore(int dbm) {
    if (dbm >= -50) return 1.0;      // Excellent
    if (dbm >= -60) return 0.8;      // Very Good
    if (dbm >= -70) return 0.6;      // Good
    if (dbm >= -80) return 0.4;      // Fair
    if (dbm >= -90) return 0.2;      // Poor
    return 0.0;                      // Very Poor
  }

  SignalQuality _getSignalQuality(int dbm) {
    if (dbm >= -50) return SignalQuality.excellent;
    if (dbm >= -60) return SignalQuality.veryGood;
    if (dbm >= -70) return SignalQuality.good;
    if (dbm >= -80) return SignalQuality.fair;
    if (dbm >= -90) return SignalQuality.poor;
    return SignalQuality.veryPoor;
  }

  void _updateDeviceQuality(String deviceId, ConnectionQuality quality) {
    final previousQuality = _deviceQuality[deviceId];
    if (previousQuality != quality) {
      _deviceQuality[deviceId] = quality;
      onQualityChanged?.call(deviceId, quality);
      
      debugPrint("📶 Quality changed for $deviceId: ${quality.name}");
    }
  }

  // Get current signal info for a device
  SignalInfo? getSignalInfo(String deviceId) {
    final readings = _signalHistory[deviceId];
    if (readings == null || readings.isEmpty) return null;

    final latest = readings.last;
    final quality = _deviceQuality[deviceId] ?? ConnectionQuality.unknown;

    return SignalInfo(
      deviceId: deviceId,
      currentSignalStrength: latest.signalStrength,
      signalQuality: latest.quality,
      connectionQuality: quality,
      lastUpdated: latest.timestamp,
      isStable: _isSignalStable(deviceId),
      estimatedRange: _estimateRange(latest.signalStrength),
    );
  }

  bool _isSignalStable(String deviceId) {
    final readings = _signalHistory[deviceId] ?? [];
    if (readings.length < 5) return false;

    final recent = readings.skip(readings.length - 5);
    final variance = recent
        .map((r) => r.signalStrength)
        .reduce((a, b) => a + b) / 5;
    
    return recent.every((r) => (r.signalStrength - variance).abs() < 10);
  }

  double _estimateRange(int signalStrength) {
    // Rough estimation based on signal strength
    // These are approximate values for WiFi Direct/hotspot
    if (signalStrength >= -50) return 10.0;   // ~10 meters
    if (signalStrength >= -60) return 25.0;   // ~25 meters
    if (signalStrength >= -70) return 50.0;   // ~50 meters
    if (signalStrength >= -80) return 100.0;  // ~100 meters
    if (signalStrength >= -90) return 200.0;  // ~200 meters
    return 300.0; // Beyond reliable range
  }

  // Get all devices with their signal info
  Map<String, SignalInfo> getAllSignalInfo() {
    final result = <String, SignalInfo>{};
    for (var deviceId in _signalHistory.keys) {
      final info = getSignalInfo(deviceId);
      if (info != null) {
        result[deviceId] = info;
      }
    }
    return result;
  }

  void dispose() {
    stopMonitoring();
    _signalHistory.clear();
    _deviceQuality.clear();
  }
}

// Data classes
class SignalReading {
  final DateTime timestamp;
  final int signalStrength;
  final SignalQuality quality;

  SignalReading({
    required this.timestamp,
    required this.signalStrength,
    required this.quality,
  });
}

class SignalInfo {
  final String deviceId;
  final int currentSignalStrength;
  final SignalQuality signalQuality;
  final ConnectionQuality connectionQuality;
  final DateTime lastUpdated;
  final bool isStable;
  final double estimatedRange;

  SignalInfo({
    required this.deviceId,
    required this.currentSignalStrength,
    required this.signalQuality,
    required this.connectionQuality,
    required this.lastUpdated,
    required this.isStable,
    required this.estimatedRange,
  });
}

enum SignalQuality {
  excellent,
  veryGood,
  good,
  fair,
  poor,
  veryPoor,
}

enum ConnectionQuality {
  excellent,
  good,
  fair,
  poor,
  veryPoor,
  unknown,
}