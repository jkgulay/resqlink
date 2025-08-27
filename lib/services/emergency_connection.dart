import 'dart:async';
import 'package:flutter/foundation.dart';

class EmergencyConnectionManager {
  static const Duration emergencyPingInterval = Duration(seconds: 5); // Fixed: lowerCamelCase
  static const Duration emergencyReconnectInterval = Duration(seconds: 10); // Fixed: lowerCamelCase
  
  Timer? _emergencyMonitorTimer;
  DateTime? _lastSuccessfulConnection;
  
  // Callbacks for P2P service integration
  final bool Function()? _isConnected;
  final bool Function()? _isEmergencyMode;
  final Future<void> Function()? _sendEmergencyPing;
  final Future<void> Function()? _attemptEmergencyReconnection;
  final Future<bool> Function()? _createResQLinkHotspot;
  final Future<void> Function()? _broadcastEmergencyBeacon;
  final Future<void> Function()? _handleEmergencyConnectionLoss;

  EmergencyConnectionManager({
    bool Function()? isConnected,
    bool Function()? isEmergencyMode,
    Future<void> Function()? sendEmergencyPing,
    Future<void> Function()? attemptEmergencyReconnection,
    Future<bool> Function()? createResQLinkHotspot,
    Future<void> Function()? broadcastEmergencyBeacon,
    Future<void> Function()? handleEmergencyConnectionLoss,
  }) : _isConnected = isConnected,
       _isEmergencyMode = isEmergencyMode,
       _sendEmergencyPing = sendEmergencyPing,
       _attemptEmergencyReconnection = attemptEmergencyReconnection,
       _createResQLinkHotspot = createResQLinkHotspot,
       _broadcastEmergencyBeacon = broadcastEmergencyBeacon,
       _handleEmergencyConnectionLoss = handleEmergencyConnectionLoss;

  void startEmergencyMonitoring() {
    debugPrint("🚨 Starting emergency connection monitoring");
    
    _emergencyMonitorTimer?.cancel();
    _emergencyMonitorTimer = Timer.periodic(emergencyPingInterval, (_) {
      _performEmergencyHealthCheck();
    });
  }

  void stopEmergencyMonitoring() {
    debugPrint("🛑 Stopping emergency connection monitoring");
    
    _emergencyMonitorTimer?.cancel();
    _emergencyMonitorTimer = null;
  }

  Future<void> _performEmergencyHealthCheck() async {
    final isConnected = _isConnected?.call() ?? false;
    final isEmergencyMode = _isEmergencyMode?.call() ?? false;
    
    if (!isConnected) {
      // Attempt immediate reconnection in emergency mode
      if (isEmergencyMode) {
        debugPrint("🚨 Emergency mode: Attempting immediate reconnection");
        await _attemptEmergencyReconnection?.call();
      }
      return;
    }
    
    // Test connection with emergency ping
    try {
      await _sendEmergencyPing?.call();
      _lastSuccessfulConnection = DateTime.now();
      debugPrint("💓 Emergency ping successful");
    } catch (e) {
      debugPrint("🚨 Emergency ping failed: $e");
      await _handleEmergencyConnectionLoss?.call();
    }
  }

  Future<void> attemptEmergencyReconnection() async {
    debugPrint("🔄 Emergency reconnection attempt");
    
    // More aggressive reconnection in emergency mode
    await _attemptEmergencyReconnection?.call();
    
    // If still not connected after 30 seconds, try different approach
    Timer(Duration(seconds: 30), () {
      final isConnected = _isConnected?.call() ?? false;
      final isEmergencyMode = _isEmergencyMode?.call() ?? false;
      
      if (!isConnected && isEmergencyMode) {
        _tryAlternativeEmergencyConnection();
      }
    });
  }

  Future<void> _tryAlternativeEmergencyConnection() async {
    debugPrint("🚨 Trying alternative emergency connection methods");
    
    try {
      // Force hotspot creation with emergency settings
      final created = await (_createResQLinkHotspot?.call() ?? Future.value(false));
      
      if (created) {
        debugPrint("✅ Emergency hotspot created");
      }
      
      // Broadcast emergency beacon
      await _broadcastEmergencyBeacon?.call();
      
    } catch (e) {
      debugPrint("❌ Alternative emergency connection failed: $e");
    }
  }

  Duration? getTimeSinceLastSuccess() {
    if (_lastSuccessfulConnection == null) return null;
    return DateTime.now().difference(_lastSuccessfulConnection!);
  }

  bool get isMonitoring => _emergencyMonitorTimer != null;

  Map<String, dynamic> getStatus() {
    return {
      'isMonitoring': isMonitoring,
      'lastSuccessfulConnection': _lastSuccessfulConnection?.millisecondsSinceEpoch,
      'timeSinceLastSuccess': getTimeSinceLastSuccess()?.inSeconds,
      'pingInterval': emergencyPingInterval.inSeconds,
    };
  }

  void dispose() {
    stopEmergencyMonitoring();
  }
}