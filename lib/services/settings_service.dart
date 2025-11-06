import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static SettingsService? _instance;
  static SettingsService get instance => _instance ??= SettingsService._();
  SettingsService._();

  // Settings state
  bool _offlineMode = false;
  bool _locationSharingEnabled = true;
  // CRITICAL FIX: Multi-hop disabled by default - can interfere with regular chat
  bool _multiHopEnabled = false;
  bool _emergencyNotifications = true;
  bool _soundNotifications = true;
  bool _vibrationNotifications = true;
  bool _silentMode = false;
  bool _autoSync = true;
  bool _backgroundSync = true;

  String _connectionMode = 'hybrid';
  String get connectionMode => _connectionMode;

  // Getters
  bool get offlineMode => _offlineMode;
  bool get locationSharingEnabled => _locationSharingEnabled;
  bool get multiHopEnabled => _multiHopEnabled;
  bool get emergencyNotifications => _emergencyNotifications;
  bool get soundNotifications => _soundNotifications;
  bool get vibrationNotifications => _vibrationNotifications;
  bool get silentMode => _silentMode;
  bool get autoSync => _autoSync;
  bool get backgroundSync => _backgroundSync;

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _offlineMode = prefs.getBool('offline_mode') ?? false;
    _locationSharingEnabled = prefs.getBool('location_sharing_enabled') ?? true;
    // CRITICAL FIX: Multi-hop disabled by default to prevent chat interference
    _multiHopEnabled = prefs.getBool('multi_hop_enabled') ?? false;
    _emergencyNotifications = prefs.getBool('emergency_notifications') ?? true;
    _soundNotifications = prefs.getBool('sound_notifications') ?? true;
    _vibrationNotifications = prefs.getBool('vibration_notifications') ?? true;
    _silentMode = prefs.getBool('silent_mode') ?? false;
    _autoSync = prefs.getBool('auto_sync') ?? true;
    _backgroundSync = prefs.getBool('background_sync') ?? true;
    _connectionMode = prefs.getString('connection_mode') ?? 'hybrid';

    notifyListeners();
  }

  Future<void> setConnectionMode(String mode) async {
    _connectionMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connection_mode', mode);
    notifyListeners();
  }

  // Save individual setting
  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    notifyListeners();
  }

  // Update methods
  Future<void> setOfflineMode(bool value) async {
    _offlineMode = value;
    await _saveSetting('offline_mode', value);
  }

  Future<void> setLocationSharing(bool value) async {
    _locationSharingEnabled = value;
    await _saveSetting('location_sharing_enabled', value);
  }

  Future<void> setMultiHop(bool value) async {
    _multiHopEnabled = value;
    await _saveSetting('multi_hop_enabled', value);
  }

  Future<void> setEmergencyNotifications(bool value) async {
    _emergencyNotifications = value;
    await _saveSetting('emergency_notifications', value);
  }

  Future<void> setSoundNotifications(bool value) async {
    _soundNotifications = value;
    await _saveSetting('sound_notifications', value);
  }

  Future<void> setVibrationNotifications(bool value) async {
    _vibrationNotifications = value;
    await _saveSetting('vibration_notifications', value);
  }

  Future<void> setSilentMode(bool value) async {
    _silentMode = value;
    await _saveSetting('silent_mode', value);
  }

  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    await _saveSetting('auto_sync', value);
  }

  Future<void> setBackgroundSync(bool value) async {
    _backgroundSync = value;
    await _saveSetting('background_sync', value);
  }

  // Batch save all settings
  Future<void> saveAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('offline_mode', _offlineMode),
      prefs.setBool('location_sharing_enabled', _locationSharingEnabled),
      prefs.setBool('multi_hop_enabled', _multiHopEnabled),
      prefs.setBool('emergency_notifications', _emergencyNotifications),
      prefs.setBool('sound_notifications', _soundNotifications),
      prefs.setBool('vibration_notifications', _vibrationNotifications),
      prefs.setBool('silent_mode', _silentMode),
      prefs.setBool('auto_sync', _autoSync),
      prefs.setBool('background_sync', _backgroundSync),
      prefs.setString('connection_mode', _connectionMode),
    ]);
    notifyListeners();
  }
}
