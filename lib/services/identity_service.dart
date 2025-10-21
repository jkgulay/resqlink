import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Central identity service for the app.
///
/// Manages a single persistent UUID that identifies this device across:
/// - P2P connections
/// - Chat sessions
/// - Database records
/// - WiFi Direct handshakes
///
/// This replaces all previous identifier schemes (MAC addresses, ANDROID_ID, temp IDs).
class IdentityService {
  static final IdentityService _instance = IdentityService._internal();
  factory IdentityService() => _instance;
  IdentityService._internal();

  // Keys for SharedPreferences
  static const String _deviceIdKey = 'device_uuid';
  static const String _displayNameKey = 'display_name';

  // Cached values
  String? _cachedDeviceId;
  String? _cachedDisplayName;

  /// Get the persistent device UUID.
  ///
  /// Generated once on first app launch, then persists forever.
  /// This is the PRIMARY identifier for this device.
  Future<String> getDeviceId() async {
    // Return cached value if available
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString(_deviceIdKey);

    if (storedId != null && storedId.isNotEmpty) {
      _cachedDeviceId = storedId;
      debugPrint('📱 Device UUID (cached): $_cachedDeviceId');
      return storedId;
    }

    // Generate new UUID
    const uuid = Uuid();
    final newId = uuid.v4();

    // Store persistently
    await prefs.setString(_deviceIdKey, newId);
    _cachedDeviceId = newId;

    debugPrint('✨ Generated new device UUID: $newId');
    return newId;
  }

  /// Get the user's display name.
  ///
  /// This is shown in WiFi Direct peer lists and chat UI.
  /// Separate from deviceId - user can change this anytime.
  Future<String> getDisplayName() async {
    if (_cachedDisplayName != null) {
      return _cachedDisplayName!;
    }

    final prefs = await SharedPreferences.getInstance();
    String? storedName = prefs.getString(_displayNameKey);

    if (storedName != null && storedName.isNotEmpty) {
      _cachedDisplayName = storedName;
      return storedName;
    }

    // Default if not set
    return 'User';
  }

  /// Set the user's display name.
  Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
    _cachedDisplayName = name;
    debugPrint('👤 Display name updated: $name');
  }

  /// Get both deviceId and displayName together.
  ///
  /// Useful for handshakes and initialization.
  Future<Map<String, String>> getIdentity() async {
    final deviceId = await getDeviceId();
    final displayName = await getDisplayName();

    return {
      'deviceId': deviceId,
      'displayName': displayName,
    };
  }

  /// Clear cached values (for testing or reset).
  void clearCache() {
    _cachedDeviceId = null;
    _cachedDisplayName = null;
  }

  /// Reset identity (WARNING: will break existing conversations).
  Future<void> resetIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_displayNameKey);
    clearCache();
    debugPrint('⚠️ Identity reset - new UUID will be generated');
  }
}
