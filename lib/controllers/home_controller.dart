import 'dart:async';
import 'package:flutter/material.dart';
import 'package:resqlink/models/message_model.dart';
import 'package:resqlink/services/p2p/p2p_base_service.dart';
import '../services/p2p/p2p_main_service.dart';
import '../services/database_service.dart';
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
      final messages = await DatabaseService.getUnsyncedMessages();
      _unsyncedCount = messages.length;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking unsynced: $e');
    }
  }

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) {
    _discoveredDevices = devices;
    if (_isScanning && devices.isNotEmpty) {
      _isScanning = false;
    }
    notifyListeners();
  }

  void toggleEmergencyMode() {
    p2pService.emergencyMode = !p2pService.emergencyMode;
    notifyListeners();
  }

  Future<void> sendEmergencyMessage(EmergencyTemplate template) async {
    await p2pService.sendEmergencyTemplate(template);
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

      // Auto-stop after 20 seconds with results check
      Timer(Duration(seconds: 20), () {
        if (_isScanning) {
          _isScanning = false;
          debugPrint("⏰ Scan timeout reached");

          if (_discoveredDevices.isEmpty) {
            debugPrint("📭 No devices found during scan");
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

  Future<void> connectToDevice(Map<String, dynamic> device) async {
    await p2pService.connectToDevice(device);
  }

  Future<void> refreshLocation() async {
    await _loadLatestLocation();
    await _checkUnsyncedLocations();
  }

  Future<void> shareLocation() async {
    if (_currentLocation != null) {
      await p2pService.sendMessage(
        message: 'My current location',
        type: MessageType.location,
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        senderName: '',
      );
    }
  }

  @override
  void dispose() {
    p2pService.removeListener(notifyListeners);
    super.dispose();
  }
}
