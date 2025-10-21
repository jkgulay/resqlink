import 'dart:async';
import 'package:flutter/material.dart';

/// Reconnection attempt information
class ReconnectionAttempt {
  final String deviceId;
  final DateTime timestamp;
  final int attemptNumber;
  final bool success;
  final String? error;

  ReconnectionAttempt({
    required this.deviceId,
    required this.timestamp,
    required this.attemptNumber,
    required this.success,
    this.error,
  });
}

/// Manages automatic reconnection attempts for lost connections
class ReconnectionManager {
  // Reconnection state tracking
  final Map<String, Timer> _reconnectionTimers = {};
  final Map<String, int> _reconnectionAttempts = {};
  final Map<String, DateTime> _lastAttemptTime = {};
  final Map<String, List<ReconnectionAttempt>> _attemptHistory = {};

  // Reconnection strategy parameters
  final int maxReconnectionAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final bool useExponentialBackoff;

  // Callbacks
  Future<bool> Function(String deviceId, Map<String, dynamic> deviceInfo)?
      onReconnectAttempt;
  Function(String deviceId, int attemptNumber)? onReconnectionStarted;
  Function(String deviceId)? onReconnectionSuccess;
  Function(String deviceId)? onReconnectionFailed;
  Function(String deviceId)? onMaxAttemptsReached;

  ReconnectionManager({
    this.maxReconnectionAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.useExponentialBackoff = true,
  });

  /// Start reconnection attempts for a device
  void startReconnection(String deviceId, Map<String, dynamic> deviceInfo) {
    // Don't start if already reconnecting
    if (_reconnectionTimers.containsKey(deviceId)) {
      debugPrint('🔄 Already attempting reconnection to $deviceId');
      return;
    }

    debugPrint('🔄 Starting reconnection attempts for $deviceId');

    // Reset attempt counter
    _reconnectionAttempts[deviceId] = 0;
    _attemptHistory[deviceId] = [];

    // Schedule first attempt
    _scheduleReconnectionAttempt(deviceId, deviceInfo);
  }

  /// Schedule a reconnection attempt
  void _scheduleReconnectionAttempt(
    String deviceId,
    Map<String, dynamic> deviceInfo,
  ) {
    final attemptNumber = (_reconnectionAttempts[deviceId] ?? 0) + 1;

    // Check if max attempts reached
    if (attemptNumber > maxReconnectionAttempts) {
      debugPrint('❌ Max reconnection attempts reached for $deviceId');
      _handleMaxAttemptsReached(deviceId);
      return;
    }

    // Calculate delay using exponential backoff
    final delay = _calculateDelay(attemptNumber);

    debugPrint(
      '⏱️ Scheduling reconnection attempt #$attemptNumber for $deviceId in ${delay.inSeconds}s',
    );

    // Schedule the attempt
    _reconnectionTimers[deviceId] = Timer(delay, () {
      _executeReconnectionAttempt(deviceId, deviceInfo, attemptNumber);
    });
  }

  /// Calculate delay for reconnection attempt
  Duration _calculateDelay(int attemptNumber) {
    if (!useExponentialBackoff) {
      return initialDelay;
    }

    // Exponential backoff: 2^(n-1) * initialDelay
    // Attempt 1: 2s, 2: 4s, 3: 8s, 4: 16s, 5: 32s, etc.
    final delayMs = initialDelay.inMilliseconds * (1 << (attemptNumber - 1));
    final calculatedDelay = Duration(milliseconds: delayMs);

    // Cap at max delay
    return calculatedDelay > maxDelay ? maxDelay : calculatedDelay;
  }

  /// Execute reconnection attempt
  Future<void> _executeReconnectionAttempt(
    String deviceId,
    Map<String, dynamic> deviceInfo,
    int attemptNumber,
  ) async {
    _reconnectionAttempts[deviceId] = attemptNumber;
    _lastAttemptTime[deviceId] = DateTime.now();

    debugPrint('🔄 Executing reconnection attempt #$attemptNumber for $deviceId');

    onReconnectionStarted?.call(deviceId, attemptNumber);

    try {
      // Call reconnection callback
      final success = await onReconnectAttempt?.call(deviceId, deviceInfo) ??
          false;

      // Record attempt
      _recordAttempt(
        deviceId,
        attemptNumber,
        success,
        null,
      );

      if (success) {
        debugPrint('✅ Reconnection successful for $deviceId');
        _handleReconnectionSuccess(deviceId);
      } else {
        debugPrint(
          '❌ Reconnection attempt #$attemptNumber failed for $deviceId',
        );
        // Schedule next attempt
        _scheduleReconnectionAttempt(deviceId, deviceInfo);
      }
    } catch (e) {
      debugPrint('❌ Reconnection attempt #$attemptNumber error: $e');

      // Record attempt with error
      _recordAttempt(
        deviceId,
        attemptNumber,
        false,
        e.toString(),
      );

      // Schedule next attempt
      _scheduleReconnectionAttempt(deviceId, deviceInfo);
    }
  }

  /// Record reconnection attempt
  void _recordAttempt(
    String deviceId,
    int attemptNumber,
    bool success,
    String? error,
  ) {
    _attemptHistory.putIfAbsent(deviceId, () => []);
    _attemptHistory[deviceId]!.add(
      ReconnectionAttempt(
        deviceId: deviceId,
        timestamp: DateTime.now(),
        attemptNumber: attemptNumber,
        success: success,
        error: error,
      ),
    );

    // Keep only last 20 attempts
    if (_attemptHistory[deviceId]!.length > 20) {
      _attemptHistory[deviceId]!.removeAt(0);
    }
  }

  /// Handle successful reconnection
  void _handleReconnectionSuccess(String deviceId) {
    onReconnectionSuccess?.call(deviceId);
    stopReconnection(deviceId);
  }

  /// Handle max attempts reached
  void _handleMaxAttemptsReached(String deviceId) {
    onMaxAttemptsReached?.call(deviceId);
    onReconnectionFailed?.call(deviceId);
    stopReconnection(deviceId);
  }

  /// Stop reconnection attempts for a device
  void stopReconnection(String deviceId) {
    _reconnectionTimers[deviceId]?.cancel();
    _reconnectionTimers.remove(deviceId);
    _reconnectionAttempts.remove(deviceId);
    _lastAttemptTime.remove(deviceId);

    debugPrint('🛑 Stopped reconnection attempts for $deviceId');
  }

  /// Stop all reconnection attempts
  void stopAll() {
    for (final deviceId in _reconnectionTimers.keys.toList()) {
      stopReconnection(deviceId);
    }
    debugPrint('🛑 Stopped all reconnection attempts');
  }

  /// Check if device is currently reconnecting
  bool isReconnecting(String deviceId) {
    return _reconnectionTimers.containsKey(deviceId);
  }

  /// Get current attempt number for device
  int getAttemptNumber(String deviceId) {
    return _reconnectionAttempts[deviceId] ?? 0;
  }

  /// Get last attempt time for device
  DateTime? getLastAttemptTime(String deviceId) {
    return _lastAttemptTime[deviceId];
  }

  /// Get attempt history for device
  List<ReconnectionAttempt> getAttemptHistory(String deviceId) {
    return _attemptHistory[deviceId] ?? [];
  }

  /// Get all reconnecting devices
  List<String> getReconnectingDevices() {
    return _reconnectionTimers.keys.toList();
  }

  /// Reset reconnection state for device
  void resetDevice(String deviceId) {
    stopReconnection(deviceId);
    _attemptHistory.remove(deviceId);
    debugPrint('🔄 Reset reconnection state for $deviceId');
  }

  /// Get reconnection statistics
  Map<String, dynamic> getStatistics() {
    return {
      'activeReconnections': _reconnectionTimers.length,
      'reconnectingDevices': getReconnectingDevices(),
      'attemptCounts': Map.from(_reconnectionAttempts),
      'totalAttempts': _attemptHistory.values
          .fold(0, (sum, history) => sum + history.length),
    };
  }

  /// Dispose resources
  void dispose() {
    stopAll();
    _attemptHistory.clear();
    debugPrint('🗑️ Reconnection manager disposed');
  }
}
