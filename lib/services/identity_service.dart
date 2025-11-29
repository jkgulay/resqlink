import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Central identity service for the app.
///
/// Manages a single persistent UUID and the user's current display name.
/// It acts as a ChangeNotifier to notify listeners when the display name changes.
class IdentityService extends ChangeNotifier {
  static final IdentityService _instance = IdentityService._internal();
  factory IdentityService() => _instance;

  IdentityService._internal() {
    loadDisplayName();
  }

  // Keys for SharedPreferences
  static const String _deviceIdKey = 'device_uuid';
  static const String _displayNameKey = 'display_name';

  // State
  String? _cachedDeviceId;
  String _displayName = 'User';

  /// The current display name for the user.
  String get displayName => _displayName;

  /// Loads the display name from persistent storage.
  Future<void> loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(_displayNameKey);
    if (storedName != null && storedName.isNotEmpty) {
      if (_displayName != storedName) {
        _displayName = storedName;
        notifyListeners();
      }
    }
  }

  /// Get the persistent device UUID.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString(_deviceIdKey);

    if (storedId != null && storedId.isNotEmpty) {
      _cachedDeviceId = storedId;
      return storedId;
    }

    const uuid = Uuid();
    final newId = uuid.v4();
    await prefs.setString(_deviceIdKey, newId);
    _cachedDeviceId = newId;

    debugPrint('✨ Generated new device UUID: $newId');
    return newId;
  }

  /// Set the user's display name, persist it, and notify listeners.
  Future<void> setDisplayName(String name) async {
    if (name.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);

    if (_displayName != name) {
      _displayName = name;
      debugPrint('👤 Display name updated: $name');
      notifyListeners();
    }
  }

  /// Reset the display name to default and clear from storage.
  Future<void> resetIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_displayNameKey);
    _displayName = 'User';
    debugPrint('⚠️ Display name reset');
    notifyListeners();
  }
}
