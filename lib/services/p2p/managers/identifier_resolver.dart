import 'package:flutter/material.dart';

class IdentifierResolver {
  // Singleton
  static final IdentifierResolver _instance = IdentifierResolver._internal();
  factory IdentifierResolver() => _instance;
  IdentifierResolver._internal();

  // Store device registry: UUID -> Display Name mapping
  final Map<String, String> _deviceIdToDisplayName = {};
  final Map<String, String> _displayNameToDeviceId = {};

  /// Register a device with its UUID and display name
  void registerDevice(String deviceId, String displayName) {
    if (deviceId.isEmpty) {
      debugPrint('⚠️ Cannot register device with empty UUID');
      return;
    }

    _deviceIdToDisplayName[deviceId] = displayName;
    _displayNameToDeviceId[displayName] = deviceId;

    debugPrint('✅ Registered device: $displayName -> $deviceId');
  }

  /// Get display name for a UUID
  String? getDisplayName(String deviceId) {
    return _deviceIdToDisplayName[deviceId];
  }

  /// Get device ID for a display name
  String? getDeviceId(String displayName) {
    return _displayNameToDeviceId[displayName];
  }

  /// Resolve any identifier to a valid UUID
  /// Priority: Direct UUID > Display name lookup > Reject
  String? resolveToDeviceId(String? identifier) {
    if (identifier == null || identifier.isEmpty) {
      debugPrint('⚠️ Cannot resolve null/empty identifier');
      return null;
    }

    // If it's already a known UUID, return it immediately
    if (_deviceIdToDisplayName.containsKey(identifier) ||
        _isLikelyUuid(identifier)) {
      return identifier;
    }

    // Try to resolve as display name
    final resolvedId = _displayNameToDeviceId[identifier];
    if (resolvedId != null) {
      debugPrint('✅ Resolved display name "$identifier" to UUID: $resolvedId');
      return resolvedId;
    }

    // Check if it's an IP address that needs resolution
    if (_isIpAddress(identifier)) {
      debugPrint('⚠️ Cannot resolve IP address without context: $identifier');
      return null;
    }

    debugPrint('❌ Failed to resolve identifier to MAC: $identifier');
    return null;
  }

  /// Validate that an identifier is or can be resolved to a valid UUID
  bool isValidIdentifier(String? identifier) {
    return resolveToDeviceId(identifier) != null;
  }

  /// Get display name or fallback to UUID if not registered
  String getDisplayNameOrId(String deviceId) {
    return _deviceIdToDisplayName[deviceId] ?? deviceId;
  }

  /// Check if string is an IP address
  bool _isIpAddress(String value) {
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    return ipPattern.hasMatch(value);
  }

  bool _isLikelyUuid(String value) {
    final uuidPattern = RegExp(r'^[0-9a-fA-F-]{16,}$');
    return uuidPattern.hasMatch(value);
  }

  /// Validate device identifier before any operation
  /// Returns validated UUID or null if invalid
  String? validateDeviceIdentifier({
    required String? identifier,
    required String operation,
    String? context,
  }) {
    if (identifier == null || identifier.isEmpty) {
      debugPrint(
        '❌ $operation failed: identifier is null/empty ${context ?? ""}',
      );
      return null;
    }

    // Reject IP addresses
    if (_isIpAddress(identifier)) {
      debugPrint(
        '❌ $operation blocked: IP addresses not allowed as identifiers ${context ?? ""}',
      );
      debugPrint('   Use UUID resolution before calling $operation');
      return null;
    }

    // Try to resolve to UUID
    final deviceId = resolveToDeviceId(identifier);
    if (deviceId == null) {
      debugPrint(
        '❌ $operation blocked: cannot resolve "$identifier" to valid UUID ${context ?? ""}',
      );
      return null;
    }

    return deviceId;
  }

  /// Clear all registered devices
  void clearRegistry() {
    _deviceIdToDisplayName.clear();
    _displayNameToDeviceId.clear();
    debugPrint('🧹 Cleared identifier registry');
  }

  /// Get registry statistics
  Map<String, dynamic> getStats() {
    return {
      'registeredDevices': _deviceIdToDisplayName.length,
      'deviceIdToName': Map.from(_deviceIdToDisplayName),
      'nameToDeviceId': Map.from(_displayNameToDeviceId),
    };
  }

  /// Update display name for existing UUID
  void updateDisplayName(String deviceId, String newDisplayName) {
    if (deviceId.isEmpty) {
      debugPrint('⚠️ Cannot update display name for empty UUID');
      return;
    }

    // Remove old display name mapping if exists
    final oldDisplayName = _deviceIdToDisplayName[deviceId];
    if (oldDisplayName != null) {
      _displayNameToDeviceId.remove(oldDisplayName);
    }

    // Register new display name
    registerDevice(deviceId, newDisplayName);
    debugPrint(
      '🔄 Updated display name for $deviceId: $oldDisplayName -> $newDisplayName',
    );
  }

  /// Bulk register devices from a map
  void registerDevices(Map<String, String> deviceIdToNameMap) {
    deviceIdToNameMap.forEach((deviceId, name) {
      registerDevice(deviceId, name);
    });
    debugPrint('✅ Bulk registered ${deviceIdToNameMap.length} devices');
  }
}
