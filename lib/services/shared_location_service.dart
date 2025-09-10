import 'dart:async';
import 'package:flutter/material.dart';
import '../gps_page.dart';

class LocationStateService extends ChangeNotifier {
  static final LocationStateService _instance = LocationStateService._internal();
  factory LocationStateService() => _instance;
  LocationStateService._internal();

  LocationModel? _currentLocation;
  bool _isLocationServiceEnabled = false;
  int _unsyncedCount = 0;
  bool _isLoadingLocation = false;

  // Getters
  LocationModel? get currentLocation => _currentLocation;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  int get unsyncedCount => _unsyncedCount;
  bool get isLoadingLocation => _isLoadingLocation;

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

  void shareLocation() {
    // Implement location sharing logic
    debugPrint('Sharing location: $_currentLocation');
  }
}