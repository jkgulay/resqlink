import 'dart:async';
import 'package:flutter/material.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/models/message_model.dart';
import 'package:resqlink/services/p2p/p2p_base_service.dart';
import '../services/p2p/p2p_main_service.dart';
import '../pages/gps_page.dart';

class HomeController extends ChangeNotifier {
  final P2PMainService p2pService;

  HomeController(this.p2pService) {
    _initialize();
  }

  // State
  LocationModel? _currentLocation;
  bool _isLoadingLocation = true;
  int _unsyncedCount = 0;
  List<Map<String, dynamic>> _discoveredDevices = [];
  bool _isScanning = false;

  // Getters
  LocationModel? get currentLocation => _currentLocation;
  bool get isLoadingLocation => _isLoadingLocation;
  int get unsyncedCount => _unsyncedCount;
  List<Map<String, dynamic>> get discoveredDevices => _discoveredDevices;
  bool get isScanning => _isScanning;
  bool get isConnected => p2pService.connectedDevices.isNotEmpty;

  void _initialize() {
    p2pService.onDevicesDiscovered = _onDevicesDiscovered;
    p2pService.addListener(notifyListeners);
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadLatestLocation(), _checkUnsyncedLocations()]);
  }

  Future<void> _loadLatestLocation() async {
    try {
      _isLoadingLocation = true;
      notifyListeners();

      final lastLocation = await LocationService.getLastKnownLocation();
      _currentLocation = lastLocation;
      _isLoadingLocation = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading location: $e');
      _isLoadingLocation = false;
      notifyListeners();
    }
  }

  Future<void> _checkUnsyncedLocations() async {
    try {
      final messages = await MessageRepository.getUnsyncedMessages();
      _unsyncedCount = messages.length;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking unsynced: $e');
    }
  }

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) {
    // Convert devices map to list format that UI expects
    final deviceList = p2pService.discoveredDevices.values.toList();
    _discoveredDevices = deviceList;

    // Stop scanning if we found devices
    if (_isScanning && deviceList.isNotEmpty) {
      _isScanning = false;
    }

    debugPrint('📱 Devices discovered: ${deviceList.length} devices');
    for (final device in deviceList) {
      debugPrint(
        '  - ${device['deviceName']} (${device['connectionType']}) - Signal: ${device['signalLevel']} dBm',
      );
    }

    notifyListeners();
  }

  void toggleEmergencyMode() {
    p2pService.emergencyMode = !p2pService.emergencyMode;
    notifyListeners();
  }

  Future<void> sendEmergencyMessage(EmergencyTemplate template) async {
    final connectedDevices = p2pService.connectedDevices;
    final senderName = p2pService.userName ?? 'Emergency User';

    // Get the emergency message text
    final messageText = _getEmergencyMessage(template);
    final messageType = template == EmergencyTemplate.sos
        ? MessageType.sos
        : MessageType.emergency;

    if (connectedDevices.isEmpty) {
      debugPrint('⚠️ No connected devices - emergency message will be queued');
      // Still attempt to send in case there are background connections
      await p2pService.sendMessage(
        message: messageText,
        type: messageType,
        senderName: senderName,
      );
      return;
    }

    // Send to all connected devices specifically
    for (final deviceId in connectedDevices.keys) {
      try {
        await p2pService.sendMessage(
          message: messageText,
          type: messageType,
          targetDeviceId: deviceId, // CRITICAL: Target specific device
          senderName: senderName, // CRITICAL: Include actual sender name
        );
        debugPrint('✅ Emergency message sent to device: $deviceId');
      } catch (e) {
        debugPrint('❌ Failed to send emergency message to $deviceId: $e');
      }
    }
  }

  String _getEmergencyMessage(EmergencyTemplate template) {
    switch (template) {
      case EmergencyTemplate.sos:
        return '🆘 SOS - Emergency assistance needed!';
      case EmergencyTemplate.trapped:
        return '🚧 TRAPPED - Cannot move from current location!';
      case EmergencyTemplate.medical:
        return '🏥 MEDICAL EMERGENCY - Immediate medical attention needed!';
      case EmergencyTemplate.safe:
        return '✅ SAFE - I am safe and secure';
      case EmergencyTemplate.evacuating:
        return '🏃 EVACUATING - Moving to safer location';
    }
  }

  Future<void> startScan() async {
    _isScanning = true;
    _discoveredDevices.clear();
    notifyListeners();

    try {
      debugPrint("🔍 Starting enhanced device scan...");

      // Check permissions first
      await p2pService.checkAndRequestPermissions();

      // Start discovery with all methods
      await p2pService.discoverDevices(force: true);

      // Force update devices discovered callback after a short delay
      Timer(Duration(seconds: 2), () {
        final deviceList = p2pService.discoveredDevices.values.toList();
        _discoveredDevices = deviceList;
        debugPrint(
          "🔄 Force updating discovered devices: ${deviceList.length} devices",
        );
        notifyListeners();
      });

      // Auto-stop after 20 seconds with results check
      Timer(Duration(seconds: 20), () {
        if (_isScanning) {
          _isScanning = false;
          debugPrint("⏰ Scan timeout reached");

          // Final device update
          final deviceList = p2pService.discoveredDevices.values.toList();
          _discoveredDevices = deviceList;

          if (_discoveredDevices.isEmpty) {
            debugPrint("📭 No devices found during scan");
            debugPrint(
              "🔍 Available WiFi Direct peers: ${p2pService.wifiDirectService?.discoveredPeers.length ?? 0}",
            );
            debugPrint(
              "🔍 ResQLink devices: ${p2pService.discoveredResQLinkDevices.length}",
            );
          } else {
            debugPrint(
              "✅ Scan completed - found ${_discoveredDevices.length} devices",
            );
          }

          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("❌ Scan error: $e");
      _isScanning = false;
      notifyListeners();
      rethrow;
    }
  }

  void stopScan() {
    if (_isScanning) {
      _isScanning = false;
      debugPrint("⏹️ Scan cancelled by user");
      notifyListeners();
    }
  }

  Future<void> createGroup() async {
    try {
      debugPrint("📡 Creating WiFi Direct group (host mode)...");

      // Check permissions first
      await p2pService.checkAndRequestPermissions();

      // Create WiFi Direct group
      final success =
          await p2pService.wifiDirectService?.createGroup() ?? false;

      if (success) {
        debugPrint("✅ WiFi Direct group created successfully");
      } else {
        debugPrint("❌ Failed to create WiFi Direct group");
        throw Exception("Failed to create WiFi Direct group");
      }

      notifyListeners();
    } catch (e) {
      debugPrint("❌ Create group error: $e");
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connectToDevice(Map<String, dynamic> device) async {
    await p2pService.connectToDevice(device);
  }

  Future<void> refreshLocation() async {
    await _loadLatestLocation();
    await _checkUnsyncedLocations();
  }

  Future<void> shareLocation() async {
    if (_currentLocation == null) {
      debugPrint('⚠️ No location available to share');
      return;
    }

    final connectedDevices = p2pService.connectedDevices;
    if (connectedDevices.isEmpty) {
      debugPrint('⚠️ No connected devices to share location with');
      return;
    }

    final senderName = p2pService.userName ?? 'Unknown User';
    final locationMessage =
        '📍 Shared location\nLat: ${_currentLocation!.latitude.toStringAsFixed(6)}\nLng: ${_currentLocation!.longitude.toStringAsFixed(6)}';

    // Send location to all connected devices
    for (final deviceId in connectedDevices.keys) {
      try {
        await p2pService.sendMessage(
          message: locationMessage,
          type: MessageType.location,
          targetDeviceId: deviceId, // CRITICAL: Target specific device
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
          senderName: senderName, // CRITICAL: Include actual sender name
        );
        debugPrint('✅ Location shared with device: $deviceId');
      } catch (e) {
        debugPrint('❌ Failed to share location with $deviceId: $e');
      }
    }
  }

  @override
  void dispose() {
    p2pService.removeListener(notifyListeners);
    super.dispose();
  }
}
