import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resqlink/models/message_model.dart';
// ChatService import removed - no longer needed after fixing duplicate send issue
import '../pages/gps_page.dart';
import 'p2p/p2p_main_service.dart';

class LocationStateService extends ChangeNotifier {
  static final LocationStateService _instance =
      LocationStateService._internal();
  factory LocationStateService() => _instance;
  LocationStateService._internal();

  LocationModel? _currentLocation;
  bool _isLocationServiceEnabled = false;
  int _unsyncedCount = 0;
  bool _isLoadingLocation = false;
  P2PMainService? _p2pService;

  // Getters
  LocationModel? get currentLocation => _currentLocation;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  int get unsyncedCount => _unsyncedCount;
  bool get isLoadingLocation => _isLoadingLocation;

  // Set P2P service for location sharing
  void setP2PService(P2PMainService p2pService) {
    _p2pService = p2pService;
  }

  // Update methods
  void updateCurrentLocation(LocationModel? location) {
    _currentLocation = location;
    notifyListeners();
  }

  void updateLocationServiceStatus(bool enabled) {
    _isLocationServiceEnabled = enabled;
    notifyListeners();
  }

  void updateUnsyncedCount(int count) {
    _unsyncedCount = count;
    notifyListeners();
  }

  void updateLoadingStatus(bool loading) {
    _isLoadingLocation = loading;
    notifyListeners();
  }

  Future<void> refreshLocation() async {
    _isLoadingLocation = true;
    notifyListeners();

    try {
      // Add timeout to prevent loading state from hanging
      final results =
          await Future.wait([
            LocationService.getLastKnownLocation(),
            LocationService.getUnsyncedCount(),
          ]).timeout(
            Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⚠️ Location refresh timed out after 5 seconds');
              return [_currentLocation, _unsyncedCount];
            },
          );

      _currentLocation = results[0] as LocationModel?;
      _unsyncedCount = results[1] as int;
    } catch (e) {
      debugPrint('Error refreshing location: $e');
    } finally {
      _isLoadingLocation = false;
      notifyListeners();
    }
  }

  Future<void> shareLocation() async {
    if (_currentLocation == null) {
      debugPrint('❌ No location to share');
      return;
    }

    try {
      // 1. Copy coordinates to clipboard
      final locationText =
          '${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}';
      await Clipboard.setData(ClipboardData(text: locationText));
      debugPrint('📋 Location copied to clipboard: $locationText');

      // 2. Share via P2P if service is available and connected
      if (_p2pService != null && _p2pService!.connectedDevices.isNotEmpty) {
        final locationMessage = _getLocationShareMessage();
        final messageType =
            _currentLocation!.type == LocationType.emergency ||
                _currentLocation!.type == LocationType.sos
            ? MessageType.emergency
            : MessageType.location;

        // CRITICAL FIX: Only send via P2P, let MessageRouter handle DB saving
        // Removed duplicate chatService.sendMessage() loop that created race conditions

        debugPrint(
          '📤 Sharing location via P2P to ${_p2pService!.connectedDevices.length} device(s)',
        );

        // Send via P2P for actual transmission
        // MessageRouter will handle saving to DB when message is routed
        await _p2pService!.sendMessage(
          message: locationMessage,
          type: messageType,
          senderName: _p2pService!.userName ?? 'Unknown User',
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          ttl: 3600,
          routePath: [_p2pService!.deviceId ?? 'unknown_device'],
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
        );

        debugPrint('✅ Location shared via P2P successfully');
      }

      // 3. REAL Firebase sync
      try {
        if (_currentLocation!.type == LocationType.emergency ||
            _currentLocation!.type == LocationType.sos) {
          // High priority emergency sync
          await FirebaseLocationService.syncEmergencyLocation(
            _currentLocation!,
          );
          debugPrint('🚨 Emergency location synced to Firebase');
        } else {
          // Regular sync
          await FirebaseLocationService.syncLocation(_currentLocation!);
          debugPrint('☁️ Location synced to Firebase');
        }
      } catch (e) {
        debugPrint('⚠️ Firebase sync failed: $e');
        // Don't fail the whole operation if Firebase sync fails
      }

      // 4. Mark as shared locally
      if (_currentLocation!.id != null) {
        await LocationService.markLocationSynced(_currentLocation!.id!);
        await refreshLocation(); // Refresh to update unsynced count
      }

      debugPrint('✅ Location sharing completed successfully');
    } catch (e) {
      debugPrint('❌ Error sharing location: $e');
      rethrow;
    }
  }

  // Alternative method for broadcasting to all connected devices
  Future<void> broadcastLocationToAll() async {
    if (_currentLocation == null || _p2pService == null) {
      debugPrint('❌ Cannot broadcast: no location or P2P service');
      return;
    }

    try {
      final locationMessage = _getLocationShareMessage();
      final messageType =
          _currentLocation!.type == LocationType.emergency ||
              _currentLocation!.type == LocationType.sos
          ? MessageType.emergency
          : MessageType.location;

      // CRITICAL FIX: Only send via P2P broadcast, let MessageRouter handle DB saving
      // Removed duplicate chatService.sendMessage() loop that created race conditions

      debugPrint(
        '📡 Broadcasting emergency location to ${_p2pService!.connectedDevices.length} device(s)',
      );

      // Send via P2P for actual transmission
      // MessageRouter will handle saving to DB when message is routed
      await _p2pService!.sendMessage(
        message: locationMessage,
        type: messageType,
        senderName: _p2pService!.userName ?? 'Emergency User',
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        ttl: 5, // 5 hops max for multi-hop mesh forwarding (emergency only)
        routePath: [_p2pService!.deviceId ?? 'emergency_device'],
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        // targetDeviceId: null (omitted = broadcast mode for multi-hop)
      );

      debugPrint('✅ Emergency location broadcast completed via P2P');
    } catch (e) {
      debugPrint('❌ Error broadcasting location: $e');
      rethrow;
    }
  }

  String _getLocationShareMessage() {
    if (_currentLocation == null) return 'Location shared';

    final locationTypeText = _getLocationTypeText(_currentLocation!.type);
    final timestamp = _formatTimestamp(_currentLocation!.timestamp);
    final accuracy = _currentLocation!.accuracy != null
        ? '±${_currentLocation!.accuracy!.toStringAsFixed(1)}m'
        : 'Unknown accuracy';

    String message = '$locationTypeText shared at $timestamp';

    if (_currentLocation!.emergencyLevel != null &&
        _currentLocation!.emergencyLevel != EmergencyLevel.safe) {
      message += ' [${_currentLocation!.emergencyLevel!.name.toUpperCase()}]';
    }

    if (_currentLocation!.batteryLevel != null) {
      message += ' Battery: ${_currentLocation!.batteryLevel}%';
    }

    message += ' Accuracy: $accuracy';

    if (_currentLocation!.message != null &&
        _currentLocation!.message!.isNotEmpty) {
      message += ' Note: ${_currentLocation!.message}';
    }

    return message;
  }

  String _getLocationTypeText(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return 'Current location';
      case LocationType.emergency:
        return '🚨 EMERGENCY LOCATION';
      case LocationType.sos:
        return '🆘 SOS LOCATION';
      case LocationType.safezone:
        return '🛡️ Safe zone';
      case LocationType.hazard:
        return '⚠️ Hazard area';
      case LocationType.evacuationPoint:
        return '🚪 Evacuation point';
      case LocationType.medicalAid:
        return '🏥 Medical aid';
      case LocationType.supplies:
        return '📦 Supplies';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  String getGoogleMapsUrl() {
    if (_currentLocation == null) return '';
    return 'https://maps.google.com/?q=${_currentLocation!.latitude},${_currentLocation!.longitude}';
  }

  String getShareableText() {
    if (_currentLocation == null) return 'No location available';

    final coords =
        '${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}';
    final timestamp = _formatTimestamp(_currentLocation!.timestamp);
    final locationTypeText = _getLocationTypeText(_currentLocation!.type);

    return '''
$locationTypeText
📍 Coordinates: $coords
🕒 Time: $timestamp

Shared via ResQLink Emergency App
''';
  }
}
