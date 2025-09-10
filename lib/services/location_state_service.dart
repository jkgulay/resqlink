import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../gps_page.dart';
import '../services/p2p_service.dart';

class LocationStateService extends ChangeNotifier {
  static final LocationStateService _instance =
      LocationStateService._internal();
  factory LocationStateService() => _instance;
  LocationStateService._internal();

  LocationModel? _currentLocation;
  bool _isLocationServiceEnabled = false;
  int _unsyncedCount = 0;
  bool _isLoadingLocation = false;
  P2PConnectionService? _p2pService;

  // Getters
  LocationModel? get currentLocation => _currentLocation;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  int get unsyncedCount => _unsyncedCount;
  bool get isLoadingLocation => _isLoadingLocation;

  // Set P2P service for location sharing
  void setP2PService(P2PConnectionService p2pService) {
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
      final lastLocation = await LocationService.getLastKnownLocation();
      final unsyncedCount = await LocationService.getUnsyncedCount();

      _currentLocation = lastLocation;
      _unsyncedCount = unsyncedCount;
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
        await _p2pService!.sendMessage(
          message: _getLocationShareMessage(),
          type:
              _currentLocation!.type == LocationType.emergency ||
                  _currentLocation!.type == LocationType.sos
              ? MessageType.emergency
              : MessageType.location,
          senderName: _p2pService!.userName ?? 'Unknown User',
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          ttl: 3600,
          routePath: [_p2pService!.deviceId ?? 'unknown_device'],
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
        );

        debugPrint(
          '📡 Location shared via P2P to ${_p2pService!.connectedDevices.length} devices',
        );
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
      // Fix: Use named parameters for sendMessage call
      await _p2pService!.sendMessage(
        message: _getLocationShareMessage(),
        type:
            _currentLocation!.type == LocationType.emergency ||
                _currentLocation!.type == LocationType.sos
            ? MessageType.emergency
            : MessageType.location,
        senderName: _p2pService!.userName ?? 'Emergency User',
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        ttl: 7200, // 2 hours for emergency messages
        routePath: [_p2pService!.deviceId ?? 'emergency_device'],
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
      );

      debugPrint(
        '✅ Location broadcast completed to ${_p2pService!.connectedDevices.length} devices',
      );
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
