import 'package:flutter/material.dart';
import 'mac_address_manager.dart';


class IdentifierResolver {
  // Singleton
  static final IdentifierResolver _instance = IdentifierResolver._internal();
  factory IdentifierResolver() => _instance;
  IdentifierResolver._internal();

  // Store device registry: MAC -> Display Name mapping
  final Map<String, String> _macToDisplayName = {};
  final Map<String, String> _displayNameToMac = {};

  /// Register a device with its MAC address and display name
  void registerDevice(String macAddress, String displayName) {
    if (!MacAddressManager.isValidMac(macAddress)) {
      debugPrint('⚠️ Cannot register device with invalid MAC: $macAddress');
      return;
    }

    _macToDisplayName[macAddress] = displayName;
    _displayNameToMac[displayName] = macAddress;

    debugPrint('✅ Registered device: $displayName -> $macAddress');
  }

  /// Get display name for a MAC address
  String? getDisplayName(String macAddress) {
    return _macToDisplayName[macAddress];
  }

  /// Get MAC address for a display name
  String? getMacAddress(String displayName) {
    return _displayNameToMac[displayName];
  }

  /// Resolve any identifier to a valid MAC address
  /// Priority: Direct MAC > Display Name lookup > Reject
  String? resolveToMac(String? identifier) {
    if (identifier == null || identifier.isEmpty) {
      debugPrint('⚠️ Cannot resolve null/empty identifier');
      return null;
    }

    // Check if already a valid MAC
    if (MacAddressManager.isValidMac(identifier)) {
      return identifier;
    }

    // Try to resolve as display name
    final mac = _displayNameToMac[identifier];
    if (mac != null && MacAddressManager.isValidMac(mac)) {
      debugPrint('✅ Resolved display name "$identifier" to MAC: $mac');
      return mac;
    }

    // Check if it's an IP address that needs resolution
    if (_isIpAddress(identifier)) {
      debugPrint('⚠️ Cannot resolve IP address without context: $identifier');
      return null;
    }

    debugPrint('❌ Failed to resolve identifier to MAC: $identifier');
    return null;
  }

  /// Validate that an identifier is or can be resolved to a valid MAC
  bool isValidIdentifier(String? identifier) {
    return resolveToMac(identifier) != null;
  }

  /// Get display name or fallback to MAC if not registered
  String getDisplayNameOrMac(String macAddress) {
    if (!MacAddressManager.isValidMac(macAddress)) {
      return macAddress; // Return as-is if invalid
    }

    return _macToDisplayName[macAddress] ?? macAddress;
  }

  /// Check if string is an IP address
  bool _isIpAddress(String value) {
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    return ipPattern.hasMatch(value);
  }

  /// Validate device identifier before any operation
  /// Returns validated MAC address or null if invalid
  String? validateDeviceIdentifier({
    required String? identifier,
    required String operation,
    String? context,
  }) {
    if (identifier == null || identifier.isEmpty) {
      debugPrint('❌ $operation failed: identifier is null/empty ${context ?? ""}');
      return null;
    }

    // Reject placeholder MACs
    if (identifier == '02:00:00:00:00:00') {
      debugPrint('❌ $operation blocked: placeholder MAC not allowed ${context ?? ""}');
      return null;
    }

    // Reject IP addresses
    if (_isIpAddress(identifier)) {
      debugPrint('❌ $operation blocked: IP addresses not allowed as identifiers ${context ?? ""}');
      debugPrint('   Use MAC address resolution before calling $operation');
      return null;
    }

    // Try to resolve to MAC
    final mac = resolveToMac(identifier);
    if (mac == null) {
      debugPrint('❌ $operation blocked: cannot resolve "$identifier" to valid MAC ${context ?? ""}');
      return null;
    }

    return mac;
  }

  /// Clear all registered devices
  void clearRegistry() {
    _macToDisplayName.clear();
    _displayNameToMac.clear();
    debugPrint('🧹 Cleared identifier registry');
  }

  /// Get registry statistics
  Map<String, dynamic> getStats() {
    return {
      'registeredDevices': _macToDisplayName.length,
      'macToName': Map.from(_macToDisplayName),
      'nameToMac': Map.from(_displayNameToMac),
    };
  }

  /// Update display name for existing MAC
  void updateDisplayName(String macAddress, String newDisplayName) {
    if (!MacAddressManager.isValidMac(macAddress)) {
      debugPrint('⚠️ Cannot update display name for invalid MAC: $macAddress');
      return;
    }

    // Remove old display name mapping if exists
    final oldDisplayName = _macToDisplayName[macAddress];
    if (oldDisplayName != null) {
      _displayNameToMac.remove(oldDisplayName);
    }

    // Register new display name
    registerDevice(macAddress, newDisplayName);
    debugPrint('🔄 Updated display name for $macAddress: $oldDisplayName -> $newDisplayName');
  }

  /// Bulk register devices from a map
  void registerDevices(Map<String, String> macToNameMap) {
    macToNameMap.forEach((mac, name) {
      registerDevice(mac, name);
    });
    debugPrint('✅ Bulk registered ${macToNameMap.length} devices');
  }
}
