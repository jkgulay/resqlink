import 'dart:async';
import 'package:flutter/material.dart';

/// Timeout configuration for different operations
class TimeoutConfig {
  final Duration discovery;
  final Duration connection;
  final Duration handshake;
  final Duration messageDelivery;
  final Duration ping;

  const TimeoutConfig({
    this.discovery = const Duration(seconds: 30),
    this.connection = const Duration(seconds: 15),
    this.handshake = const Duration(seconds: 10),
    this.messageDelivery = const Duration(seconds: 5),
    this.ping = const Duration(seconds: 3),
  });

  /// Emergency mode timeouts (longer)
  const TimeoutConfig.emergency()
      : discovery = const Duration(seconds: 60),
        connection = const Duration(seconds: 30),
        handshake = const Duration(seconds: 20),
        messageDelivery = const Duration(seconds: 10),
        ping = const Duration(seconds: 5);

  /// Fast mode timeouts (shorter, for good connections)
  const TimeoutConfig.fast()
      : discovery = const Duration(seconds: 15),
        connection = const Duration(seconds: 10),
        handshake = const Duration(seconds: 5),
        messageDelivery = const Duration(seconds: 3),
        ping = const Duration(seconds: 2);
}

/// Timeout operation types
enum TimeoutOperation {
  discovery,
  connection,
  handshake,
  messageDelivery,
  ping,
  custom,
}

/// Active timeout tracker
class ActiveTimeout {
  final String id;
  final TimeoutOperation operation;
  final DateTime startTime;
  final Duration timeout;
  final Timer timer;
  final VoidCallback onTimeout;

  ActiveTimeout({
    required this.id,
    required this.operation,
    required this.startTime,
    required this.timeout,
    required this.timer,
    required this.onTimeout,
  });

  Duration get elapsed => DateTime.now().difference(startTime);
  Duration get remaining => timeout - elapsed;
  bool get hasExpired => elapsed >= timeout;
}

/// Manages timeouts for various P2P operations
class TimeoutManager {
  TimeoutConfig config;

  // Active timeouts
  final Map<String, ActiveTimeout> _activeTimeouts = {};

  // Statistics
  int _totalTimeouts = 0;
  int _timeoutOccurred = 0;
  int _timeoutCancelled = 0;

  // Callbacks
  Function(String id, TimeoutOperation operation)? onTimeout;
  Function(String id, TimeoutOperation operation, Duration elapsed)? onCompleted;

  TimeoutManager({this.config = const TimeoutConfig()});

  /// Start a timeout for an operation
  String startTimeout({
    required TimeoutOperation operation,
    String? customId,
    Duration? customDuration,
    required VoidCallback onTimeoutCallback,
  }) {
    final id = customId ?? _generateId(operation);
    final duration = customDuration ?? _getDuration(operation);

    // Cancel existing timeout with same ID
    if (_activeTimeouts.containsKey(id)) {
      debugPrint('⚠️ Replacing existing timeout: $id');
      cancelTimeout(id);
    }

    debugPrint(
      '⏱️ Starting ${operation.name} timeout: $id (${duration.inSeconds}s)',
    );

    final timer = Timer(duration, () {
      _handleTimeout(id, operation);
      onTimeoutCallback();
    });

    _activeTimeouts[id] = ActiveTimeout(
      id: id,
      operation: operation,
      startTime: DateTime.now(),
      timeout: duration,
      timer: timer,
      onTimeout: onTimeoutCallback,
    );

    _totalTimeouts++;

    return id;
  }

  /// Complete a timeout (cancel before expiry)
  void completeTimeout(String id) {
    final timeout = _activeTimeouts[id];
    if (timeout == null) return;

    final elapsed = timeout.elapsed;

    debugPrint(
      '✅ Completed ${timeout.operation.name}: $id (${elapsed.inMilliseconds}ms)',
    );

    timeout.timer.cancel();
    _activeTimeouts.remove(id);
    _timeoutCancelled++;

    onCompleted?.call(id, timeout.operation, elapsed);
  }

  /// Cancel a timeout without completion callback
  void cancelTimeout(String id) {
    final timeout = _activeTimeouts[id];
    if (timeout == null) return;

    debugPrint('🛑 Cancelled timeout: $id');

    timeout.timer.cancel();
    _activeTimeouts.remove(id);
    _timeoutCancelled++;
  }

  /// Cancel all timeouts for an operation type
  void cancelByOperation(TimeoutOperation operation) {
    final toCancel = _activeTimeouts.entries
        .where((e) => e.value.operation == operation)
        .map((e) => e.key)
        .toList();

    for (final id in toCancel) {
      cancelTimeout(id);
    }

    if (toCancel.isNotEmpty) {
      debugPrint('🛑 Cancelled ${toCancel.length} ${operation.name} timeouts');
    }
  }

  /// Cancel all active timeouts
  void cancelAll() {
    final count = _activeTimeouts.length;
    for (final timeout in _activeTimeouts.values) {
      timeout.timer.cancel();
    }
    _activeTimeouts.clear();

    if (count > 0) {
      debugPrint('🛑 Cancelled all $count active timeouts');
    }
  }

  /// Handle timeout expiry
  void _handleTimeout(String id, TimeoutOperation operation) {
    debugPrint('⏰ Timeout expired: $id (${operation.name})');

    _activeTimeouts.remove(id);
    _timeoutOccurred++;

    onTimeout?.call(id, operation);
  }

  /// Get duration for operation type
  Duration _getDuration(TimeoutOperation operation) {
    switch (operation) {
      case TimeoutOperation.discovery:
        return config.discovery;
      case TimeoutOperation.connection:
        return config.connection;
      case TimeoutOperation.handshake:
        return config.handshake;
      case TimeoutOperation.messageDelivery:
        return config.messageDelivery;
      case TimeoutOperation.ping:
        return config.ping;
      case TimeoutOperation.custom:
        return const Duration(seconds: 10); // Default for custom
    }
  }

  /// Generate ID for operation
  String _generateId(TimeoutOperation operation) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${operation.name}_$timestamp';
  }

  /// Check if timeout is active
  bool isActive(String id) {
    return _activeTimeouts.containsKey(id);
  }

  /// Get active timeout
  ActiveTimeout? getTimeout(String id) {
    return _activeTimeouts[id];
  }

  /// Get all active timeouts
  List<ActiveTimeout> getActiveTimeouts() {
    return _activeTimeouts.values.toList();
  }

  /// Get active timeouts by operation
  List<ActiveTimeout> getTimeoutsByOperation(TimeoutOperation operation) {
    return _activeTimeouts.values
        .where((t) => t.operation == operation)
        .toList();
  }

  /// Get count of active timeouts
  int get activeCount => _activeTimeouts.length;

  /// Update timeout configuration
  void updateConfig(TimeoutConfig newConfig) {
    config = newConfig;
    debugPrint('⚙️ Timeout configuration updated');
  }

  /// Switch to emergency mode timeouts
  void setEmergencyMode(bool enabled) {
    config = enabled ? const TimeoutConfig.emergency() : const TimeoutConfig();
    debugPrint(
      '🚨 ${enabled ? "Enabled" : "Disabled"} emergency timeout mode',
    );
  }

  /// Get timeout statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalTimeouts': _totalTimeouts,
      'timeoutOccurred': _timeoutOccurred,
      'timeoutCancelled': _timeoutCancelled,
      'activeTimeouts': _activeTimeouts.length,
      'successRate': _totalTimeouts > 0
          ? ((_timeoutCancelled / _totalTimeouts) * 100).toStringAsFixed(1)
          : '0.0',
      'byOperation': {
        for (final op in TimeoutOperation.values)
          op.name: getTimeoutsByOperation(op).length,
      },
    };
  }

  /// Reset statistics
  void resetStatistics() {
    _totalTimeouts = 0;
    _timeoutOccurred = 0;
    _timeoutCancelled = 0;
    debugPrint('📊 Timeout statistics reset');
  }

  /// Wrap an async operation with timeout
  Future<T> withTimeout<T>({
    required Future<T> Function() operation,
    required TimeoutOperation timeoutType,
    String? id,
    Duration? customTimeout,
  }) async {
    final timeoutId = id ?? _generateId(timeoutType);
    final completer = Completer<T>();
    bool completed = false;

    // Start timeout
    startTimeout(
      operation: timeoutType,
      customId: timeoutId,
      customDuration: customTimeout,
      onTimeoutCallback: () {
        if (!completed) {
          completed = true;
          completer.completeError(
            TimeoutException(
              'Operation ${timeoutType.name} timed out',
              customTimeout ?? _getDuration(timeoutType),
            ),
          );
        }
      },
    );

    // Execute operation
    try {
      final result = await operation();
      if (!completed) {
        completed = true;
        completeTimeout(timeoutId);
        completer.complete(result);
      }
      return result;
    } catch (e) {
      if (!completed) {
        completed = true;
        cancelTimeout(timeoutId);
        completer.completeError(e);
      }
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    cancelAll();
    resetStatistics();
    debugPrint('🗑️ Timeout manager disposed');
  }
}
