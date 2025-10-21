import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages MAC address retrieval, validation, and updates
class MacAddressManager {
  static const String _placeholderMac = '02:00:00:00:00:00';
  static const String _prefKey = 'wifi_direct_mac_address';
  static const Duration _macRetrievalTimeout = Duration(seconds: 5);

  String? _currentMacAddress;
  final _macAddressController = StreamController<String>.broadcast();
  final Map<String, String> _ipToMacCache = {};
  final Map<String, String> _deviceIdToMacMap = {};

  // Callbacks
  Function(String oldMac, String newMac)? onMacAddressUpdated;

  /// Get the current MAC address stream
  Stream<String> get macAddressStream => _macAddressController.stream;

  /// Get the current MAC address (may be null if not yet retrieved)
  String? get currentMacAddress => _currentMacAddress;

  /// Check if a MAC address is valid (not placeholder, not empty)
  static bool isValidMac(String? mac) {
    if (mac == null || mac.isEmpty) return false;
    if (mac == _placeholderMac) return false;
    if (!mac.contains(':')) return false;
    return true;
  }

  /// Wait for a valid MAC address to be available
  Future<String?> waitForValidMac({Duration? timeout}) async {
    // If we already have a valid MAC, return it immediately
    if (isValidMac(_currentMacAddress)) {
      return _currentMacAddress;
    }

    debugPrint('⏳ Waiting for valid MAC address...');

    try {
      // Try to get from SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      final storedMac = prefs.getString(_prefKey);

      if (isValidMac(storedMac)) {
        debugPrint('✅ Found valid MAC in SharedPreferences: $storedMac');
        _updateMacAddress(storedMac!);
        return storedMac;
      }

      // Wait for MAC address to be broadcast
      final result = await _macAddressController.stream
          .firstWhere(
            (mac) => isValidMac(mac),
            orElse: () => _placeholderMac,
          )
          .timeout(
            timeout ?? _macRetrievalTimeout,
            onTimeout: () {
              debugPrint('⏰ Timeout waiting for valid MAC address');
              return _placeholderMac;
            },
          );

      if (isValidMac(result)) {
        debugPrint('✅ Valid MAC address received: $result');
        return result;
      }

      debugPrint('❌ Failed to get valid MAC address within timeout');
      return null;
    } catch (e) {
      debugPrint('❌ Error waiting for MAC address: $e');
      return null;
    }
  }

  /// Update the MAC address and notify listeners
  Future<void> updateMacAddress(String newMac) async {
    if (!isValidMac(newMac)) {
      debugPrint('⚠️ MacAddressManager: Rejecting invalid MAC address: $newMac');
      return;
    }

    final oldMac = _currentMacAddress;

    // Skip update if MAC hasn't changed
    if (oldMac == newMac) {
      debugPrint('ℹ️ MacAddressManager: MAC address unchanged: $newMac');
      return;
    }

    _currentMacAddress = newMac;
    debugPrint('📍 MacAddressManager: Updating MAC address: ${oldMac ?? "null"} → $newMac');

    // Store in SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newMac);
      debugPrint('✅ MacAddressManager: Stored MAC address to SharedPreferences: $newMac');
    } catch (e) {
      debugPrint('❌ MacAddressManager: Error storing MAC address: $e');
    }

    // Notify listeners via stream
    _macAddressController.add(newMac);
    debugPrint('📡 MacAddressManager: Broadcast MAC address update to stream listeners');

    // Trigger callback if registered
    if (oldMac != null && onMacAddressUpdated != null) {
      debugPrint('🔄 MacAddressManager: Triggering onMacAddressUpdated callback: $oldMac → $newMac');
      onMacAddressUpdated!(oldMac, newMac);
    } else if (oldMac == null && onMacAddressUpdated != null) {
      debugPrint('✨ MacAddressManager: First MAC address set, triggering callback with initial value');
      // For first-time MAC address, create a synthetic "old" value for clarity
      onMacAddressUpdated!('', newMac);
    } else if (onMacAddressUpdated == null) {
      debugPrint('⚠️ MacAddressManager: No callback registered for MAC address updates!');
    }
  }

  /// Internal method for updating without callbacks
  void _updateMacAddress(String newMac) {
    _currentMacAddress = newMac;
    _macAddressController.add(newMac);
  }

  /// Cache IP to MAC mapping
  void cacheIpToMac(String ipAddress, String macAddress) {
    if (isValidMac(macAddress)) {
      _ipToMacCache[ipAddress] = macAddress;
      debugPrint('📝 Cached IP→MAC: $ipAddress → $macAddress');
    }
  }

  /// Get MAC from IP cache
  String? getMacFromIp(String ipAddress) {
    return _ipToMacCache[ipAddress];
  }

  /// Cache device ID to MAC mapping
  void cacheDeviceIdToMac(String deviceId, String macAddress) {
    if (isValidMac(macAddress)) {
      _deviceIdToMacMap[deviceId] = macAddress;
      debugPrint('📝 Cached DeviceID→MAC: $deviceId → $macAddress');
    }
  }

  /// Get MAC from device ID
  String? getMacFromDeviceId(String deviceId) {
    return _deviceIdToMacMap[deviceId];
  }

  /// Update device references when MAC changes
  Future<void> updateDeviceReferences(String oldIdentifier, String newMac) async {
    debugPrint('🔄 Updating device references: $oldIdentifier → $newMac');

    // Update cache mappings
    if (_deviceIdToMacMap.containsKey(oldIdentifier)) {
      _deviceIdToMacMap.remove(oldIdentifier);
      _deviceIdToMacMap[newMac] = newMac;
    }

    // Update IP to MAC cache if old identifier was an IP
    if (oldIdentifier.contains('.')) {
      _ipToMacCache[oldIdentifier] = newMac;
    }
  }

  /// Clear all caches
  void clearCaches() {
    _ipToMacCache.clear();
    _deviceIdToMacMap.clear();
    debugPrint('🧹 Cleared MAC address caches');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'currentMac': _currentMacAddress,
      'isValid': isValidMac(_currentMacAddress),
      'ipToMacCacheSize': _ipToMacCache.length,
      'deviceIdToMacCacheSize': _deviceIdToMacMap.length,
      'ipToMacCache': Map.from(_ipToMacCache),
      'deviceIdToMacCache': Map.from(_deviceIdToMacMap),
    };
  }

  /// Dispose and cleanup
  void dispose() {
    _macAddressController.close();
    clearCaches();
    debugPrint('🗑️ MAC address manager disposed');
  }
}
