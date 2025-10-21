import 'dart:async';
import 'package:flutter/material.dart';

/// Connection quality metrics for a specific device
class ConnectionQuality {
  final String deviceId;
  final double rtt; // Round Trip Time in milliseconds
  final double packetLoss; // Percentage (0-100)
  final int signalStrength; // dBm (-100 to 0)
  final DateTime lastUpdated;
  final ConnectionQualityLevel level;

  ConnectionQuality({
    required this.deviceId,
    required this.rtt,
    required this.packetLoss,
    required this.signalStrength,
    required this.lastUpdated,
    required this.level,
  });

  bool get isHealthy => level != ConnectionQualityLevel.poor && level != ConnectionQualityLevel.critical;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'rtt': rtt,
        'packetLoss': packetLoss,
        'signalStrength': signalStrength,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'level': level.name,
      };
}

enum ConnectionQualityLevel {
  excellent, // RTT < 50ms, no packet loss
  good, // RTT < 150ms, < 5% packet loss
  fair, // RTT < 300ms, < 15% packet loss
  poor, // RTT < 500ms, < 30% packet loss
  critical, // RTT >= 500ms or > 30% packet loss
}

/// Monitors connection quality for all connected devices
class ConnectionQualityMonitor {
  // RTT tracking
  final Map<String, List<double>> _rttHistory = {};
  final Map<String, DateTime> _lastPingTime = {};
  final Map<String, int> _pingSequence = {};

  // Packet loss tracking
  final Map<String, int> _packetsSent = {};
  final Map<String, int> _packetsReceived = {};

  // Quality metrics
  final Map<String, ConnectionQuality> _deviceQuality = {};

  // Monitoring state
  Timer? _monitoringTimer;
  final Duration _monitorInterval = Duration(seconds: 10);
  final int _maxRttSamples = 10;

  // Callbacks
  Function(String deviceId, ConnectionQuality quality)? onQualityChanged;
  Function(String deviceId)? onConnectionDegraded;

  /// Start monitoring connection quality
  void startMonitoring() {
    if (_monitoringTimer != null) return;

    debugPrint('📊 Starting connection quality monitoring');
    _monitoringTimer = Timer.periodic(_monitorInterval, (_) {
      _updateAllDeviceMetrics();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('📊 Stopped connection quality monitoring');
  }

  /// Record ping sent to device
  void recordPingSent(String deviceId) {
    _lastPingTime[deviceId] = DateTime.now();
    _pingSequence[deviceId] = (_pingSequence[deviceId] ?? 0) + 1;
    _packetsSent[deviceId] = (_packetsSent[deviceId] ?? 0) + 1;
  }

  /// Record ping response received
  void recordPingReceived(String deviceId, int sequence) {
    final sentTime = _lastPingTime[deviceId];
    if (sentTime == null) return;

    // Calculate RTT
    final rtt = DateTime.now().difference(sentTime).inMilliseconds.toDouble();

    // Store RTT history
    _rttHistory.putIfAbsent(deviceId, () => []);
    _rttHistory[deviceId]!.add(rtt);

    // Keep only recent samples
    if (_rttHistory[deviceId]!.length > _maxRttSamples) {
      _rttHistory[deviceId]!.removeAt(0);
    }

    _packetsReceived[deviceId] = (_packetsReceived[deviceId] ?? 0) + 1;

    debugPrint('📊 RTT for $deviceId: ${rtt.toStringAsFixed(1)}ms');

    // Update quality metrics
    _updateDeviceQuality(deviceId);
  }

  /// Record packet timeout (for packet loss calculation)
  void recordPacketTimeout(String deviceId) {
    _packetsSent[deviceId] = (_packetsSent[deviceId] ?? 0) + 1;
    debugPrint('⏰ Packet timeout for $deviceId');

    // Update quality metrics
    _updateDeviceQuality(deviceId);
  }

  /// Update signal strength for device
  void updateSignalStrength(String deviceId, int signalStrength) {
    final quality = _deviceQuality[deviceId];
    if (quality != null) {
      _deviceQuality[deviceId] = ConnectionQuality(
        deviceId: deviceId,
        rtt: quality.rtt,
        packetLoss: quality.packetLoss,
        signalStrength: signalStrength,
        lastUpdated: DateTime.now(),
        level: quality.level,
      );
    }
  }

  /// Update quality metrics for a specific device
  void _updateDeviceQuality(String deviceId) {
    // Calculate average RTT
    final rttSamples = _rttHistory[deviceId];
    if (rttSamples == null || rttSamples.isEmpty) return;

    final avgRtt = rttSamples.reduce((a, b) => a + b) / rttSamples.length;

    // Calculate packet loss percentage
    final sent = _packetsSent[deviceId] ?? 0;
    final received = _packetsReceived[deviceId] ?? 0;
    final packetLoss = sent > 0 ? ((sent - received) / sent * 100) : 0.0;

    // Get current signal strength or use default
    final currentQuality = _deviceQuality[deviceId];
    final signalStrength = currentQuality?.signalStrength ?? -70;

    // Determine quality level
    final level = _calculateQualityLevel(avgRtt, packetLoss);

    final oldQuality = _deviceQuality[deviceId];
    final newQuality = ConnectionQuality(
      deviceId: deviceId,
      rtt: avgRtt,
      packetLoss: packetLoss,
      signalStrength: signalStrength,
      lastUpdated: DateTime.now(),
      level: level,
    );

    _deviceQuality[deviceId] = newQuality;

    // Notify if quality changed
    if (oldQuality?.level != level) {
      debugPrint(
        '📊 Connection quality changed for $deviceId: ${oldQuality?.level.name} → ${level.name}',
      );
      onQualityChanged?.call(deviceId, newQuality);

      // Notify if connection degraded
      if (_isQualityDegraded(oldQuality?.level, level)) {
        debugPrint('⚠️ Connection degraded for $deviceId');
        onConnectionDegraded?.call(deviceId);
      }
    }
  }

  /// Calculate quality level from metrics
  ConnectionQualityLevel _calculateQualityLevel(double rtt, double packetLoss) {
    if (rtt >= 500 || packetLoss > 30) {
      return ConnectionQualityLevel.critical;
    } else if (rtt >= 300 || packetLoss > 15) {
      return ConnectionQualityLevel.poor;
    } else if (rtt >= 150 || packetLoss > 5) {
      return ConnectionQualityLevel.fair;
    } else if (rtt >= 50 || packetLoss > 0) {
      return ConnectionQualityLevel.good;
    } else {
      return ConnectionQualityLevel.excellent;
    }
  }

  /// Check if quality degraded (worse than before)
  bool _isQualityDegraded(
    ConnectionQualityLevel? oldLevel,
    ConnectionQualityLevel newLevel,
  ) {
    if (oldLevel == null) return false;

    final qualityOrder = [
      ConnectionQualityLevel.excellent,
      ConnectionQualityLevel.good,
      ConnectionQualityLevel.fair,
      ConnectionQualityLevel.poor,
      ConnectionQualityLevel.critical,
    ];

    return qualityOrder.indexOf(newLevel) > qualityOrder.indexOf(oldLevel);
  }

  /// Update metrics for all devices periodically
  void _updateAllDeviceMetrics() {
    for (final deviceId in _deviceQuality.keys.toList()) {
      final quality = _deviceQuality[deviceId];
      if (quality == null) continue;

      // Remove stale metrics (older than 60 seconds)
      if (DateTime.now().difference(quality.lastUpdated).inSeconds > 60) {
        debugPrint('🧹 Removing stale quality metrics for $deviceId');
        _removeDevice(deviceId);
      }
    }
  }

  /// Get quality for specific device
  ConnectionQuality? getDeviceQuality(String deviceId) {
    return _deviceQuality[deviceId];
  }

  /// Get all device qualities
  Map<String, ConnectionQuality> getAllQualities() {
    return Map.from(_deviceQuality);
  }

  /// Get average RTT for device
  double? getAverageRtt(String deviceId) {
    return _deviceQuality[deviceId]?.rtt;
  }

  /// Check if device connection is healthy
  bool isDeviceHealthy(String deviceId) {
    final quality = _deviceQuality[deviceId];
    return quality?.isHealthy ?? false;
  }

  /// Remove device from monitoring
  void _removeDevice(String deviceId) {
    _rttHistory.remove(deviceId);
    _lastPingTime.remove(deviceId);
    _pingSequence.remove(deviceId);
    _packetsSent.remove(deviceId);
    _packetsReceived.remove(deviceId);
    _deviceQuality.remove(deviceId);
  }

  /// Clear all metrics
  void clearAll() {
    _rttHistory.clear();
    _lastPingTime.clear();
    _pingSequence.clear();
    _packetsSent.clear();
    _packetsReceived.clear();
    _deviceQuality.clear();
  }

  /// Generate heartbeat/ping message
  Map<String, dynamic> generatePingMessage(String deviceId) {
    final sequence = _pingSequence[deviceId] ?? 0;
    return {
      'type': 'ping',
      'deviceId': deviceId,
      'sequence': sequence,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Generate pong response message
  Map<String, dynamic> generatePongMessage(
    String deviceId,
    int sequence,
    int originalTimestamp,
  ) {
    return {
      'type': 'pong',
      'deviceId': deviceId,
      'sequence': sequence,
      'originalTimestamp': originalTimestamp,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Get monitoring statistics
  Map<String, dynamic> getStatistics() {
    return {
      'monitoredDevices': _deviceQuality.length,
      'totalPingsSent': _packetsSent.values.fold(0, (a, b) => a + b),
      'totalPingsReceived': _packetsReceived.values.fold(0, (a, b) => a + b),
      'deviceQualities': _deviceQuality.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
    };
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    clearAll();
    debugPrint('🗑️ Connection quality monitor disposed');
  }
}
