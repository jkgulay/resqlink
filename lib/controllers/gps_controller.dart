import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:resqlink/pages/gps_page.dart';
import '../services/p2p/p2p_main_service.dart';
import '../services/map_service.dart';
import '../services/location_state_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GpsController extends ChangeNotifier {
  final P2PMainService p2pService;
  final String? userId;
  final Function(LocationModel)? onLocationShare;
  final LocationStateService _locationStateService = LocationStateService();
  late PhilippinesMapService _mapService;

  // Singleton pattern to prevent multiple initializations
  static GpsController? _instance;
  static bool _isInitialized = false;

  factory GpsController(
    P2PConnectionService p2pService, {
    String? userId,
    Function(LocationModel)? onLocationShare,
  }) {
    _instance ??= GpsController._internal(
      p2pService,
      userId: userId,
      onLocationShare: onLocationShare,
    );
    return _instance!;
  }

  GpsController._internal(
    this.p2pService, {
    this.userId,
    this.onLocationShare,
  }) {
    if (!_isInitialized) {
      _initialize();
      _isInitialized = true;
    }
  }

  // Core State
  final List<LocationModel> savedLocations = [];
  LocationModel? _lastKnownLocation;
  LatLng? _currentLocation;
  bool _isLocationServiceEnabled = false;
  bool _isConnected = false;
  EmergencyLevel _currentEmergencyLevel = EmergencyLevel.safe;
  bool _sosMode = false;
  int _batteryLevel = 100;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isMapReady = false;
  bool _isMoving = false;

  // Download State - Fixed to persist
  bool _isDownloadingMaps = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = 'Ready to download';
  int _totalTiles = 0;
  int _downloadedTiles = 0;
  Map<String, dynamic> _cacheInfo = {};
  bool _hasDownloadedMaps = false; // Add this to track download completion
  bool _hasOfflineMap = false;
  bool _isDownloadingOfflineMap = false;
  double _offlineMapSizeInMB = 0.0;
  DateTime? _offlineMapLastUpdated;

  // Settings
  bool _autoSaveEnabled = false;
  bool _emergencyBroadcastEnabled = true;
  bool _showTrackingPath = true;
  bool _showEmergencyZones = false;
  bool _showCriticalInfrastructure = false;
  LocationType _selectedLocationType = LocationType.normal;

  // Context storage
  BuildContext? _context;

  // Subscriptions
  final Battery _battery = Battery();
  Timer? _locationTimer;
  Timer? _sosTimer;
  Timer? _batteryTimer;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<double>? _downloadProgressSubscription;

  // Getters
  List<LocationModel> get locations => savedLocations;
  LocationModel? get lastKnownLocation => _lastKnownLocation;
  LatLng? get currentLocation => _currentLocation;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isConnected => _isConnected;
  EmergencyLevel get currentEmergencyLevel => _currentEmergencyLevel;
  bool get sosMode => _sosMode;
  int get batteryLevel => _batteryLevel;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isMapReady => _isMapReady;
  bool get isDownloadingMaps => _isDownloadingMaps;
  double get downloadProgress => _downloadProgress;
  String get downloadStatus => _downloadStatus;
  int get totalTiles => _totalTiles;
  int get downloadedTiles => _downloadedTiles;
  Map<String, dynamic> get cacheInfo => _cacheInfo;
  bool get autoSaveEnabled => _autoSaveEnabled;
  bool get emergencyBroadcastEnabled => _emergencyBroadcastEnabled;
  bool get hasOfflineMap =>
      _hasDownloadedMaps ||
      (_cacheInfo['cachedTiles'] != null && _cacheInfo['cachedTiles'] > 0);
  bool get showTrackingPath => _showTrackingPath;
  bool get showEmergencyZones => _showEmergencyZones;
  bool get showCriticalInfrastructure => _showCriticalInfrastructure;
  LocationType get selectedLocationType => _selectedLocationType;
  BuildContext? get context => _context;
  // Getters
  bool get isDownloadingOfflineMap => _isDownloadingOfflineMap;
  String get mapStorageSize => '${_offlineMapSizeInMB.toStringAsFixed(1)} MB';
  String get mapLastUpdated {
    if (_offlineMapLastUpdated == null) return 'Never';

    final now = DateTime.now();
    final difference = now.difference(_offlineMapLastUpdated!);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else {
      return 'Recently';
    }
  }

  void setContext(BuildContext context) {
    _context = context;
  }

  void setSelectedLocationType(LocationType type) {
    _selectedLocationType = type;
    notifyListeners();
  }

  String get mapCoverageArea {
    if (_currentLocation != null) {
      return 'Current Region';
    }
    return 'Unknown Area';
  }

  Future<void> _initialize() async {
    try {
      _isLoading = true;
      notifyListeners();
      _locationStateService.updateLoadingStatus(true);
      _mapService = PhilippinesMapService.instance;
      await _mapService.initialize();
      final offlineReady = await _mapService.testOfflineCapability();
      debugPrint('🗺️ Offline maps ready: $offlineReady');

      await Future.wait([
        _initializeServices(),
        _loadSavedLocations(),
        _checkConnectivity(),
        _startBatteryMonitoring(),
        _loadOfflineMapStatus(),
      ]).timeout(
        Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⏰ Initialization timeout - using fallback mode');
          return <void>[];
        },
      );

      _startLocationTracking();
      await updateCacheInfo();

      _isLoading = false;
      notifyListeners();
      _locationStateService.updateLoadingStatus(false);
    } catch (e) {
      debugPrint('❌ Initialization error: $e');
      _isLoading = false;
      _errorMessage =
          'GPS initialization failed. Tap retry or check permissions.';
      notifyListeners();
      _locationStateService.updateLoadingStatus(false);
    }
  }

  Future<void> _initializeServices() async {
    try {
      await PhilippinesMapService.instance.initialize().timeout(
        Duration(seconds: 10),
      );
      debugPrint('✅ Map service initialized');
    } catch (e) {
      debugPrint('⚠️ Map service timeout/error: $e - using fallback');
    }

    await checkLocationPermission();
    await _loadLastKnownLocation();
    await _checkBatteryLevel();
  }

  Future<void> shareCurrentLocation() async {
    if (_lastKnownLocation == null) {
      _errorMessage = 'No location to share';
      notifyListeners();
      return;
    }

    try {
      // Update the shared location service
      _locationStateService.updateCurrentLocation(_lastKnownLocation);

      // Use the shared service to handle sharing
      await _locationStateService.shareLocation();

      debugPrint('✅ Location shared via LocationStateService');
    } catch (e) {
      debugPrint('❌ Error sharing location: $e');
      _errorMessage = 'Failed to share location: $e';
      notifyListeners();
    }
  }

  Future<void> updateOfflineMap() async {
    if (_isDownloadingOfflineMap || !hasOfflineMap) return;

    try {
      _isDownloadingOfflineMap = true;
      notifyListeners();

      debugPrint('🔄 Updating offline maps...');

      // Use your existing download functionality but as an update
      if (_currentLocation != null) {
        final params = {
          'radius': 5.0, // 5km radius
          'minZoom': 8,
          'maxZoom': 16,
        };

        await downloadOfflineMaps(params);
      }

      _offlineMapLastUpdated = DateTime.now();
      await _saveOfflineMapStatus();

      debugPrint('✅ Offline map update completed');
    } catch (e) {
      debugPrint('❌ Error updating offline map: $e');
    } finally {
      _isDownloadingOfflineMap = false;
      notifyListeners();
    }
  }

  // Method to delete offline maps
  Future<void> deleteOfflineMap() async {
    if (_isDownloadingOfflineMap) return;

    try {
      debugPrint('🗑️ Deleting offline maps...');

      // Clear the cache using your existing map service
      await PhilippinesMapService.instance.clearCache(null);

      // Reset all offline map state
      _hasOfflineMap = false;
      _hasDownloadedMaps = false;
      _offlineMapSizeInMB = 0.0;
      _offlineMapLastUpdated = null;
      _cacheInfo.clear();

      await _saveOfflineMapStatus();
      await updateCacheInfo();

      debugPrint('✅ Offline maps deleted');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error deleting offline map: $e');
    }
  }

  // Helper method to save offline map status to SharedPreferences
  Future<void> _saveOfflineMapStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_offline_map', _hasOfflineMap);
      await prefs.setDouble('offline_map_size', _offlineMapSizeInMB);

      if (_offlineMapLastUpdated != null) {
        await prefs.setString(
          'offline_map_last_updated',
          _offlineMapLastUpdated!.toIso8601String(),
        );
      } else {
        await prefs.remove('offline_map_last_updated');
      }
    } catch (e) {
      debugPrint('❌ Error saving offline map status: $e');
    }
  }

  // Helper method to load offline map status from SharedPreferences
  Future<void> _loadOfflineMapStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasOfflineMap = prefs.getBool('has_offline_map') ?? false;
      _offlineMapSizeInMB = prefs.getDouble('offline_map_size') ?? 0.0;

      final lastUpdatedString = prefs.getString('offline_map_last_updated');
      if (lastUpdatedString != null) {
        _offlineMapLastUpdated = DateTime.parse(lastUpdatedString);
      }

      debugPrint(
        '📱 Loaded offline map status: hasMap=$_hasOfflineMap, size=${_offlineMapSizeInMB}MB',
      );
    } catch (e) {
      debugPrint('❌ Error loading offline map status: $e');
    }
  }

  // Override the existing downloadOfflineMap method to work with the new system:
  Future<void> downloadOfflineMap() async {
    if (_currentLocation == null) {
      _errorMessage = 'No location available for map download';
      notifyListeners();
      return;
    }

    if (_isDownloadingOfflineMap) return;

    try {
      _isDownloadingOfflineMap = true;
      notifyListeners();

      debugPrint('🗺️ Starting offline map download...');

      // Use your existing downloadOfflineMaps method
      final params = {
        'radius': 5.0, // 5km radius
        'minZoom': 8,
        'maxZoom': 16,
      };

      await downloadOfflineMaps(params);

      _hasOfflineMap = true;
      _offlineMapSizeInMB = double.parse(_cacheInfo['storageSizeMB'] ?? '0.0');
      _offlineMapLastUpdated = DateTime.now();

      await _saveOfflineMapStatus();

      debugPrint('✅ Offline map download completed');
    } catch (e) {
      debugPrint('❌ Error downloading offline map: $e');
      _errorMessage = 'Failed to download offline map: $e';
    } finally {
      _isDownloadingOfflineMap = false;
      notifyListeners();
    }
  }

  Future<void> shareLocation(LocationModel location) async {
    if (onLocationShare != null) {
      onLocationShare!(location);
    }
  }

  Future<void> deleteLocation(LocationModel location) async {
    // Implementation to delete from database
    await _loadSavedLocations();
  }

  void clearAllLocations() async {
    await LocationService.clearAllLocations();
    await _loadSavedLocations();
  }

  void toggleLocationService() async {
    await checkLocationPermission();
  }

  void toggleAutoSave() {
    _autoSaveEnabled = !_autoSaveEnabled;
    notifyListeners();
  }

  void toggleEmergencyBroadcast() {
    _emergencyBroadcastEnabled = !_emergencyBroadcastEnabled;
    notifyListeners();
  }

  void toggleTrackingPath() {
    _showTrackingPath = !_showTrackingPath;
    notifyListeners();
  }

  void toggleEmergencyZones() {
    _showEmergencyZones = !_showEmergencyZones;
    notifyListeners();
  }

  void toggleCriticalInfrastructure() {
    _showCriticalInfrastructure = !_showCriticalInfrastructure;
    notifyListeners();
  }

  Future<void> requestLocationPermission() async {
    await checkLocationPermission();
  }

  Future<void> checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Location services are disabled';
        _isLocationServiceEnabled = false;
        _locationStateService.updateLocationServiceStatus(false);
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Location permissions are denied';
          _isLocationServiceEnabled = false;
          _locationStateService.updateLocationServiceStatus(false);
          notifyListeners();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Location permission is permanently denied';
        _isLocationServiceEnabled = false;
        _locationStateService.updateLocationServiceStatus(false);
        notifyListeners();
        return;
      }

      _isLocationServiceEnabled = true;
      _errorMessage = '';
      _locationStateService.updateLocationServiceStatus(true);
      notifyListeners();
      await _startLocationTracking();
    } catch (e) {
      _errorMessage = 'Error: $e';
      _isLocationServiceEnabled = false;
      _locationStateService.updateLocationServiceStatus(false);
      notifyListeners();
    }
  }

  Future<void> _loadLastKnownLocation() async {
    try {
      final lastLocation = await LocationService.getLastKnownLocation();
      if (lastLocation != null) {
        _lastKnownLocation = lastLocation;
        _currentLocation = LatLng(
          lastLocation.latitude,
          lastLocation.longitude,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading last location: $e');
    }
  }

  Future<void> _loadSavedLocations() async {
    try {
      final locations = await LocationService.getLocations();
      final unsyncedCount = await LocationService.getUnsyncedCount();

      savedLocations.clear();
      savedLocations.addAll(locations);

      _locationStateService.updateUnsyncedCount(unsyncedCount);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading locations: $e');
      savedLocations.clear();
      notifyListeners();
    }
  }

  Future<void> _checkConnectivity() async {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final wasConnected = _isConnected;
      _isConnected = results.any((result) => result != ConnectivityResult.none);
      notifyListeners();

      if (!wasConnected && _isConnected) {
        await _syncLocationsToFirebase();
        final unsyncedCount = await LocationService.getUnsyncedCount();
        if (unsyncedCount == 0) {
          // Connection restored and synced
        }
      }
    });
  }

  Future<void> _startBatteryMonitoring() async {
    _checkBatteryLevel();
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _checkBatteryLevel();
    });
  }

  Future<void> _checkBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      final oldLevel = _batteryLevel;
      _batteryLevel = level;
      notifyListeners();

      if ((oldLevel - level).abs() >= 10) {
        _optimizeLocationUpdates();
      }
    } catch (e) {
      debugPrint('Error checking battery level: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    if (!_isLocationServiceEnabled) {
      await checkLocationPermission();
      if (!_isLocationServiceEnabled) return;
    }

    try {
      await getCurrentLocation();
      final distanceFilter = _batteryLevel < 20
          ? 20
          : 5; // Reduced from 10 to 5 for better accuracy
      final accuracy = _batteryLevel < 20
          ? LocationAccuracy.medium
          : LocationAccuracy
                .bestForNavigation; // Changed from high to bestForNavigation
      final locationSettings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );

      _positionStream?.cancel();
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              _updateCurrentLocation(position);
            },
            onError: (error) {
              debugPrint('Position stream error: $error');
              _errorMessage = 'GPS tracking error: $error';
              notifyListeners();
              Future.delayed(Duration(seconds: 5), () {
                if (_isLocationServiceEnabled) {
                  _startLocationTracking();
                }
              });
            },
          );

      final updateInterval = _batteryLevel < 20
          ? Duration(minutes: 2)
          : Duration(seconds: 30);
      _locationTimer?.cancel();
      _locationTimer = Timer.periodic(updateInterval, (timer) {
        if (_isLocationServiceEnabled) {
          getCurrentLocation();
        }
      });
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
      _errorMessage = 'Failed to start tracking: $e';
      notifyListeners();
    }
  }

  void _optimizeLocationUpdates() {
    final settings = LocationSettings(
      accuracy: _batteryLevel < 20
          ? LocationAccuracy.medium
          : LocationAccuracy
                .bestForNavigation, // Changed from high to bestForNavigation
      distanceFilter: _isMoving
          ? 3
          : 10, // Reduced for better accuracy (was 5 : 20)
      timeLimit: Duration(seconds: 10),
    );

    final updateInterval = _sosMode
        ? Duration(seconds: 15)
        : _isMoving
        ? Duration(seconds: 30)
        : Duration(minutes: 2);

    _applyLocationSettings(settings, updateInterval);
  }

  void _applyLocationSettings(LocationSettings settings, Duration interval) {
    _locationTimer?.cancel();
    _positionStream?.cancel();

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (Position position) {
            _updateCurrentLocation(position);
            _isMoving = position.speed > 1.0;
          },
          onError: (error) {
            debugPrint('Position stream error: $error');
          },
        );

    _locationTimer = Timer.periodic(interval, (timer) {
      if (_isLocationServiceEnabled) {
        getCurrentLocation();
      }
    });
  }

  Future<void> getCurrentLocation() async {
    if (!_isLocationServiceEnabled) return;

    try {
      final locationSettings = LocationSettings(
        accuracy: _batteryLevel < 20
            ? LocationAccuracy.medium
            : LocationAccuracy
                  .bestForNavigation, // Changed from high to bestForNavigation
        timeLimit: const Duration(
          seconds: 10,
        ), // Increased from 5 to 10 seconds for better accuracy
      );

      Position position;
      if (bool.fromEnvironment('dart.vm.product') == false) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: locationSettings,
          );
        } catch (e) {
          position = Position(
            latitude: 14.5995,
            longitude: 120.9842,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
          debugPrint('Using mock location due to emulator: $e');
        }
      } else {
        position = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
      }

      _updateCurrentLocation(position);
    } catch (e) {
      debugPrint('Error getting location: $e');
      try {
        Position? lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _updateCurrentLocation(lastPosition);
        }
      } catch (e2) {
        debugPrint('Error getting last known position: $e2');
      }
    }
  }

  void _updateCurrentLocation(Position position) {
    final newLocation = LatLng(position.latitude, position.longitude);
    final locationModel = LocationModel(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      userId: userId,
      type: _sosMode ? LocationType.sos : LocationType.normal,
      emergencyLevel: _currentEmergencyLevel,
      batteryLevel: _batteryLevel,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
    );

    _currentLocation = newLocation;
    _lastKnownLocation = locationModel;
    _errorMessage = '';

    // Update shared location state
    _locationStateService.updateCurrentLocation(locationModel);

    notifyListeners();

    if (onLocationShare != null) {
      onLocationShare!(locationModel);
    }

    if (_currentEmergencyLevel.index >= EmergencyLevel.warning.index ||
        _sosMode) {
      saveCurrentLocation(silent: true);
    }
  }

  void activateSOS() {
    _sosMode = true;
    _currentEmergencyLevel = EmergencyLevel.critical;
    notifyListeners();

    _optimizeLocationUpdates();
    _sendSOSLocation();

    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_sosMode) {
        _sendSOSLocation();
      } else {
        timer.cancel();
      }
    });
  }

  void deactivateSOS() {
    _sosMode = false;
    _currentEmergencyLevel = EmergencyLevel.safe;
    notifyListeners();

    _sosTimer?.cancel();
    _sosTimer = null;
    _optimizeLocationUpdates();
  }

  Future<void> _sendSOSLocation() async {
    if (_currentLocation == null) return;

    final sosLocation = LocationModel(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      timestamp: DateTime.now(),
      userId: userId,
      type: LocationType.sos,
      message: 'EMERGENCY SOS - Immediate assistance required!',
      emergencyLevel: EmergencyLevel.critical,
      batteryLevel: _batteryLevel,
    );

    debugPrint('💾 Saving SOS location to SQLite...');
    await LocationService.insertLocation(sosLocation);

    if (_isConnected) {
      try {
        debugPrint('🔄 Syncing SOS location to Firebase...');
        await FirebaseLocationService.syncLocation(sosLocation);
      } catch (e) {
        debugPrint('❌ Firebase sync failed: $e');
      }
    }

    try {
      debugPrint('📡 Broadcasting SOS via P2P...');
      if (onLocationShare != null) {
        onLocationShare!(sosLocation);
      }
    } catch (e) {
      debugPrint('❌ P2P broadcast failed: $e');
    }

    await _loadSavedLocations();
  }

  Future<void> saveCurrentLocation({
    bool silent = false,
    String? message,
  }) async {
    if (_currentLocation == null) return;

    final location = LocationModel(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      timestamp: DateTime.now(),
      userId: userId,
      type: _selectedLocationType,
      message: message,
      emergencyLevel: _currentEmergencyLevel,
      batteryLevel: _batteryLevel,
    );

    debugPrint('💾 Saving location to SQLite...');
    await LocationService.insertLocation(location);
    if (!silent && _context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Text(
            'Location saved as ${_getLocationTypeText(_selectedLocationType)}!',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }

    if (_isConnected) {
      try {
        debugPrint('🔄 Syncing location to Firebase...');
        await FirebaseLocationService.syncLocation(location);
      } catch (e) {
        debugPrint('❌ Firebase sync failed: $e');
      }
    }

    await _loadSavedLocations();
  }

  String _getLocationTypeText(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return 'Current Location';
      case LocationType.emergency:
        return 'Emergency Location';
      case LocationType.sos:
        return 'SOS Location';
      case LocationType.safezone:
        return 'Safe Zone';
      case LocationType.hazard:
        return 'Hazard Area';
      case LocationType.evacuationPoint:
        return 'Evacuation Point';
      case LocationType.medicalAid:
        return 'Medical Aid';
      case LocationType.supplies:
        return 'Supplies';
    }
  }

  Future<void> markLocation(LocationType type) async {
    if (_currentLocation == null) return;

    final location = LocationModel(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      timestamp: DateTime.now(),
      userId: userId,
      type: type,
      emergencyLevel: _currentEmergencyLevel,
      batteryLevel: _batteryLevel,
    );

    await LocationService.insertLocation(location);

    if (_isConnected) {
      try {
        await FirebaseLocationService.syncLocation(location);
      } catch (e) {
        debugPrint('Firebase sync failed: $e');
      }
    }

    await _loadSavedLocations();
  }

  Future<void> _syncLocationsToFirebase() async {
    try {
      await FirebaseLocationService.syncAllUnsyncedLocations();
      await _loadSavedLocations(); // Refresh local data

      debugPrint('✅ All locations synced to Firebase');
    } catch (e) {
      debugPrint('❌ Firebase sync error: $e');
    }
  }

  Future<void> downloadOfflineMaps(Map<String, dynamic> params) async {
    if (_currentLocation == null) return;

    _isDownloadingMaps = true;
    _downloadProgress = 0.0;
    _downloadStatus = 'Preparing download...';
    _downloadedTiles = 0;
    _totalTiles = 0;
    notifyListeners();

    try {
      final radiusKm = params['radius'];
      final minZoom = params['minZoom'];
      final maxZoom = params['maxZoom'];
      final bounds = _calculateBounds(_currentLocation!, radiusKm);

      _totalTiles = _estimateTotalTiles(bounds, minZoom, maxZoom);
      _downloadStatus = 'Downloading $_totalTiles tiles...';
      notifyListeners();

      final downloadProgress = await PhilippinesMapService.instance.cacheArea(
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        regionName: 'Current Area Download',
        isEmergencyCache: false,
      );

      _downloadProgressSubscription?.cancel();
      _downloadProgressSubscription = downloadProgress.percentageStream.listen(
        (progress) {
          _downloadProgress = progress / 100.0;
          _downloadedTiles = (_totalTiles * _downloadProgress).round();
          _downloadStatus =
              'Downloaded $_downloadedTiles of $_totalTiles tiles (${progress.toStringAsFixed(1)}%)';
          notifyListeners();
        },
        onDone: () {
          _isDownloadingMaps = false;
          _downloadProgress = 1.0;
          _downloadStatus = 'Download completed!';
          _hasDownloadedMaps = true; // Mark as downloaded
          notifyListeners();
          updateCacheInfo();

          Timer(Duration(seconds: 3), () {
            _downloadStatus = 'Maps available offline';
            _downloadProgress = 0.0;
            notifyListeners();
          });
        },
        onError: (error) {
          debugPrint('❌ Download error: $error');
          _isDownloadingMaps = false;
          _downloadProgress = 0.0;
          _downloadStatus = 'Download failed';
          notifyListeners();

          Timer(Duration(seconds: 3), () {
            _downloadStatus = 'Ready to download';
            notifyListeners();
          });
        },
      );
    } catch (e) {
      _isDownloadingMaps = false;
      _downloadProgress = 0.0;
      _downloadStatus = 'Download failed';
      notifyListeners();
    }
  }

  LatLngBounds _calculateBounds(LatLng center, double radiusKm) {
    final latOffset = radiusKm / 111.0;
    final lngOffset =
        radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180));

    return LatLngBounds(
      LatLng(center.latitude - latOffset, center.longitude - lngOffset),
      LatLng(center.latitude + latOffset, center.longitude + lngOffset),
    );
  }

  int _estimateTotalTiles(LatLngBounds bounds, int minZoom, int maxZoom) {
    int totalTiles = 0;

    for (int zoom = minZoom; zoom <= maxZoom; zoom++) {
      final scale = math.pow(2, zoom);
      final minTileX = ((bounds.west + 180) / 360 * scale).floor();
      final maxTileX = ((bounds.east + 180) / 360 * scale).floor();
      final minTileY =
          ((1 -
                      math.log(
                            math.tan(bounds.north * math.pi / 180) +
                                1 / math.cos(bounds.north * math.pi / 180),
                          ) /
                          math.pi) /
                  2 *
                  scale)
              .floor();
      final maxTileY =
          ((1 -
                      math.log(
                            math.tan(bounds.south * math.pi / 180) +
                                1 / math.cos(bounds.south * math.pi / 180),
                          ) /
                          math.pi) /
                  2 *
                  scale)
              .floor();

      final tilesAtZoom = (maxTileX - minTileX + 1) * (maxTileY - minTileY + 1);
      totalTiles += tilesAtZoom;
    }

    return totalTiles;
  }

  Future<void> updateCacheInfo() async {
    try {
      final stats = await PhilippinesMapService.instance.getCacheStats();
      final totalSize = stats.values.fold(
        0,
        (total, stat) => total + stat.sizeBytes,
      );
      final totalTiles = stats.values.fold(
        0,
        (total, stat) => total + stat.tileCount,
      );
      _cacheInfo = {
        'cachedTiles': totalTiles,
        'storageSize': totalSize,
        'storageSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      };

      if (totalTiles > 0) {
        _hasDownloadedMaps = true;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error updating cache info: $e');
    }
  }

  static void resetInstance() {
    _instance = null;
    _isInitialized = false;
  }

  Future<void> clearCache() async {
    await PhilippinesMapService.instance.clearCache(null);
    await updateCacheInfo();
  }

  // Diagnostics
  Future<Map<String, dynamic>> runDiagnostics() async {
    final results = <String, dynamic>{};

    try {
      // Test SQLite
      final testLocation = LocationModel(
        latitude: 14.5995,
        longitude: 120.9842,
        timestamp: DateTime.now(),
        userId: userId,
        type: LocationType.normal,
        message: 'Test location',
      );

      final locationId = await LocationService.insertLocation(testLocation);
      results['sqlite'] = (locationId! > 0);

      // Test Firebase
      final firebaseConnected =
          await FirebaseLocationService.testFirebaseConnection();
      results['firebase'] = firebaseConnected;

      // Test Offline Maps
      final offlineReady = await PhilippinesMapService.instance
          .testOfflineCapability();
      results['offline'] = offlineReady;

      // Test P2P
      results['p2p'] = p2pService.isConnected;

      // Check unsynced count
      final unsyncedCount = await LocationService.getUnsyncedCount();
      results['unsynced'] = unsyncedCount;

      return results;
    } catch (e) {
      debugPrint('Diagnostics error: $e');
      return {'error': e.toString()};
    }
  }

  void setMapReady(bool ready) {
    _isMapReady = ready;
    notifyListeners();
  }

  void retryInitialization() {
    _initialize();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _sosTimer?.cancel();
    _batteryTimer?.cancel();
    _downloadProgressSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }
}
