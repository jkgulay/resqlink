import 'dart:async';
import 'package:flutter/material.dart';
import '../p2p_base_service.dart';

/// Manages P2P connection state, debouncing, and connection lifecycle
class P2PConnectionManager {
  final P2PBaseService _baseService;

  // Connection state
  P2PConnectionMode _currentConnectionMode = P2PConnectionMode.none;
  bool _isConnecting = false;
  bool _isOnline = false;

  // Debounce mechanism for connection state changes
  Timer? _connectionStateDebounceTimer;
  static const Duration _connectionStateDebounceDelay = Duration(
    milliseconds: 500,
  );

  // Debounce mechanism for peer updates
  Timer? _peerUpdateDebounceTimer;
  static const Duration _peerUpdateDebounceDelay = Duration(milliseconds: 1000);

  // Track recently connected devices to prevent duplicate processing
  final Set<String> _processingDevices = {};
  final Set<String> _handshakeResponsesSent = {};

  // Callbacks
  VoidCallback? onConnectionStateChanged;
  VoidCallback? onPeerListUpdated;

  P2PConnectionManager(this._baseService);

  // Getters
  P2PConnectionMode get currentConnectionMode => _currentConnectionMode;
  bool get isConnecting => _isConnecting;
  bool get isOnline => _isOnline;
  bool get isConnected => _currentConnectionMode != P2PConnectionMode.none;

  /// Update connection mode
  void setConnectionMode(P2PConnectionMode mode) {
    if (_currentConnectionMode != mode) {
      _currentConnectionMode = mode;
      _baseService.updateConnectionStatus(mode != P2PConnectionMode.none);
      debugPrint('🔄 Connection mode changed to: ${mode.name}');
      onConnectionStateChanged?.call();
    }
  }

  /// Update connecting status
  void setConnecting(bool connecting) {
    if (_isConnecting != connecting) {
      _isConnecting = connecting;
      debugPrint('🔄 Connecting status changed to: $connecting');
      onConnectionStateChanged?.call();
    }
  }

  /// Update online status
  void updateOnlineStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      debugPrint('🌐 Online status changed to: $online');
      onConnectionStateChanged?.call();
    }
  }

  /// Debounce connection state changes to prevent race conditions
  void debounceConnectionStateChange(VoidCallback callback) {
    _connectionStateDebounceTimer?.cancel();
    _connectionStateDebounceTimer = Timer(
      _connectionStateDebounceDelay,
      callback,
    );
  }

  /// Debounce peer updates to prevent excessive processing
  void debouncePeerUpdate(VoidCallback callback) {
    _peerUpdateDebounceTimer?.cancel();
    _peerUpdateDebounceTimer = Timer(
      _peerUpdateDebounceDelay,
      callback,
    );
  }

  /// Check if device is currently being processed
  bool isDeviceProcessing(String deviceId) {
    return _processingDevices.contains(deviceId);
  }

  /// Mark device as processing
  void markDeviceProcessing(String deviceId) {
    _processingDevices.add(deviceId);
    debugPrint('🔒 Marked device as processing: $deviceId');
  }

  /// Unmark device from processing
  void unmarkDeviceProcessing(String deviceId) {
    _processingDevices.remove(deviceId);
    debugPrint('🔓 Unmarked device from processing: $deviceId');
  }

  /// Check if handshake response was sent to device
  bool hasHandshakeResponseSent(String deviceId) {
    return _handshakeResponsesSent.contains(deviceId);
  }

  /// Mark handshake response as sent
  void markHandshakeResponseSent(String deviceId) {
    _handshakeResponsesSent.add(deviceId);
  }

  /// Clear handshake response tracking
  void clearHandshakeResponses() {
    _handshakeResponsesSent.clear();
  }

  /// Get connection type as string
  String get connectionType {
    switch (_currentConnectionMode) {
      case P2PConnectionMode.wifiDirect:
        return 'wifi_direct';
      case P2PConnectionMode.client:
        return 'client';
      default:
        return 'none';
    }
  }

  /// Get connection information
  Map<String, dynamic> getConnectionInfo() {
    return {
      'connectionMode': _currentConnectionMode.name,
      'isConnecting': _isConnecting,
      'isOnline': _isOnline,
      'isConnected': isConnected,
      'connectionType': connectionType,
    };
  }

  /// Reset connection state
  void reset() {
    _currentConnectionMode = P2PConnectionMode.none;
    _isConnecting = false;
    _baseService.updateConnectionStatus(false);
    debugPrint('🔄 Connection manager reset');
    onConnectionStateChanged?.call();
  }

  /// Dispose and cleanup
  void dispose() {
    _connectionStateDebounceTimer?.cancel();
    _peerUpdateDebounceTimer?.cancel();
    _processingDevices.clear();
    _handshakeResponsesSent.clear();
    debugPrint('🗑️ Connection manager disposed');
  }
}
