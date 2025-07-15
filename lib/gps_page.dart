import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

// Responsive utilities class
class ResponsiveUtils {
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1024.0;

  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static double getResponsiveFontSize(
    BuildContext context,
    double baseFontSize,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < mobileBreakpoint) {
      return baseFontSize * 0.9;
    } else if (screenWidth < tabletBreakpoint) {
      return baseFontSize * 1.1;
    } else {
      return baseFontSize * 1.2;
    }
  }

  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < mobileBreakpoint) {
      return baseSpacing * 0.8;
    } else if (screenWidth < tabletBreakpoint) {
      return baseSpacing * 1.0;
    } else {
      return baseSpacing * 1.2;
    }
  }

  static double getResponsiveButtonWidth(
    BuildContext context,
    double maxWidth,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isMobile(context)) {
      return screenWidth * 0.8;
    } else if (isTablet(context)) {
      return screenWidth * 0.6;
    } else {
      return maxWidth;
    }
  }

  static double getResponsiveDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isMobile(context)) {
      return screenWidth * 0.9;
    } else if (isTablet(context)) {
      return screenWidth * 0.7;
    } else {
      return 500.0;
    }
  }

  static EdgeInsets getResponsivePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(12.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(16.0);
    } else {
      return const EdgeInsets.all(20.0);
    }
  }

  static EdgeInsets getResponsiveMargin(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0);
    } else {
      return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
    }
  }

  static double getResponsiveIconSize(BuildContext context, double baseSize) {
    if (isMobile(context)) {
      return baseSize * 0.9;
    } else if (isTablet(context)) {
      return baseSize * 1.1;
    } else {
      return baseSize * 1.2;
    }
  }

  static double getResponsiveMarkerSize(BuildContext context) {
    if (isMobile(context)) {
      return 60.0;
    } else if (isTablet(context)) {
      return 80.0;
    } else {
      return 100.0;
    }
  }

  static double getResponsiveFloatingActionButtonSize(BuildContext context) {
    if (isMobile(context)) {
      return 48.0;
    } else if (isTablet(context)) {
      return 56.0;
    } else {
      return 64.0;
    }
  }
}

enum LocationType { normal, emergency }

class LocationModel {
  final int? id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool synced;
  final String? userId;
  final LocationType type;

  LocationModel({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.synced = false,
    this.userId,
    this.type = LocationType.normal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'synced': synced ? 1 : 0,
      'userId': userId,
      'type': type.index,
    };
  }

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      synced: map['synced'] == 1,
      userId: map['userId'],
      type: LocationType.values[map['type'] ?? 0],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
      'type': type.name,
    };
  }

  // Helper method to get color based on recency and type
  Color getMarkerColor() {
    final now = DateTime.now();
    final age = now.difference(timestamp);

    if (type == LocationType.emergency) {
      return Colors.red;
    }

    if (age.inMinutes < 5) {
      return Colors.green;
    } else if (age.inMinutes < 30) {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }

  // Helper method to get icon based on type
  IconData getMarkerIcon() {
    return type == LocationType.emergency ? Icons.warning : Icons.location_on;
  }
}

class LocationService {
  static Database? _database;
  static const String _tableName = 'locations';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String path = p.join(await getDatabasesPath(), 'locations.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_tableName(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            userId TEXT,
            type INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) {
        if (oldVersion < 2) {
          db.execute(
            'ALTER TABLE $_tableName ADD COLUMN type INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  static Future<int> insertLocation(LocationModel location) async {
    final db = await database;
    return await db.insert(_tableName, location.toMap());
  }

  static Future<List<LocationModel>> getLocations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => LocationModel.fromMap(maps[i]));
  }

  static Future<List<LocationModel>> getUnsyncedLocations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'synced = ?',
      whereArgs: [0],
    );
    return List.generate(maps.length, (i) => LocationModel.fromMap(maps[i]));
  }

  static Future<void> markLocationSynced(int id) async {
    final db = await database;
    await db.update(
      _tableName,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<LocationModel?> getLastKnownLocation() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return LocationModel.fromMap(maps.first);
    }
    return null;
  }

  static Future<void> clearAllLocations() async {
    final db = await database;
    await db.delete(_tableName);
  }
}

class FirebaseLocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'user_locations';

  static Future<void> syncLocation(LocationModel location) async {
    try {
      await _firestore.collection(_collection).add(location.toFirestore());
      if (location.id != null) {
        await LocationService.markLocationSynced(location.id!);
      }
    } catch (e) {
      print('Error syncing location: $e');
    }
  }

  static Future<void> syncAllUnsyncedLocations() async {
    try {
      final unsyncedLocations = await LocationService.getUnsyncedLocations();
      for (final location in unsyncedLocations) {
        await syncLocation(location);
      }
    } catch (e) {
      print('Error syncing all locations: $e');
    }
  }
}

class GpsPage extends StatefulWidget {
  final String? userId;
  final Function(LocationModel)? onLocationShare;

  const GpsPage({super.key, this.userId, this.onLocationShare});

  @override
  State<GpsPage> createState() => _GpsPageState();
}

class _GpsPageState extends State<GpsPage> {
  final List<LocationModel> savedLocations = [];
  final MapController _mapController = MapController();
  LocationModel? _lastKnownLocation;
  LatLng? _currentLocation;
  bool _isLocationServiceEnabled = false;
  bool _isConnected = false;
  bool _emergencyMode = false;
  String _statusMessage = '';
  Timer? _locationTimer;
  Timer? _emergencyTimer;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadSavedLocations();
    _checkConnectivity();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _emergencyTimer?.cancel();
    _positionStream?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _showMessage(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
      // Clear message after 3 seconds
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _statusMessage = '';
          });
        }
      });
    }
  }

  Future<void> _initializeServices() async {
    await _checkLocationPermission();
    await _loadLastKnownLocation();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _isLocationServiceEnabled = false;
        });
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _isLocationServiceEnabled = false;
          });
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _isLocationServiceEnabled = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLocationServiceEnabled = true;
      });
    }
  }

  Future<void> _loadLastKnownLocation() async {
    final lastLocation = await LocationService.getLastKnownLocation();
    if (lastLocation != null && mounted) {
      setState(() {
        _lastKnownLocation = lastLocation;
        _currentLocation = LatLng(
          lastLocation.latitude,
          lastLocation.longitude,
        );
      });
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  Future<void> _loadSavedLocations() async {
    final locations = await LocationService.getLocations();
    if (mounted) {
      setState(() {
        savedLocations.clear();
        savedLocations.addAll(locations);
      });
    }
  }

  void _checkConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      if (mounted) {
        final wasConnected = _isConnected;
        setState(() {
          _isConnected = result != ConnectivityResult.none;
        });

        // When coming back online, sync all unsynced locations
        if (!wasConnected && _isConnected) {
          _syncLocationsToFirebase();
          _showMessage('Back online! Syncing saved locations...');
        } else if (wasConnected && !_isConnected) {
          _showMessage('Offline mode - locations will be saved locally');
        }
      }
    });
  }

  void _startLocationTracking() {
    if (!_isLocationServiceEnabled) return;

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          if (mounted) {
            _updateCurrentLocation(position);
          }
        });

    // Also update location every 30 seconds when app is active
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _getCurrentLocation();
      }
    });
  }

  void _toggleEmergencyMode() {
    setState(() {
      _emergencyMode = !_emergencyMode;
    });

    if (_emergencyMode) {
      _startEmergencyTracking();
      _showMessage(
        'Emergency mode activated! Location sharing every 2 minutes.',
      );
    } else {
      _stopEmergencyTracking();
      _showMessage('Emergency mode deactivated.');
    }
  }

  void _startEmergencyTracking() {
    _emergencyTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_emergencyMode && mounted) {
        _shareEmergencyLocation();
      }
    });
  }

  void _stopEmergencyTracking() {
    _emergencyTimer?.cancel();
    _emergencyTimer = null;
  }

  void _shareEmergencyLocation() async {
    if (_currentLocation != null) {
      final emergencyLocation = LocationModel(
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        timestamp: DateTime.now(),
        userId: widget.userId,
        type: LocationType.emergency,
      );

      // Always save to local SQLite database first (works offline)
      await LocationService.insertLocation(emergencyLocation);

      // Only sync to Firebase if connected
      if (_isConnected) {
        await FirebaseLocationService.syncLocation(emergencyLocation);
      }

      // Share via callback
      if (widget.onLocationShare != null) {
        widget.onLocationShare!(emergencyLocation);
      }

      // Reload saved locations to show the new emergency marker
      await _loadSavedLocations();

      // Show notification
      _showMessage(
        _isConnected
            ? 'Emergency location shared and synced!'
            : 'Emergency location saved! Will sync when online.',
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isLocationServiceEnabled) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _updateCurrentLocation(position);
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  void _updateCurrentLocation(Position position) {
    if (!mounted) return;

    final newLocation = LatLng(position.latitude, position.longitude);
    final locationModel = LocationModel(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      userId: widget.userId,
      type: LocationType.normal,
    );

    setState(() {
      _currentLocation = newLocation;
      _lastKnownLocation = locationModel;
    });

    // Always save to local SQLite database first (works offline)
    LocationService.insertLocation(locationModel).then((_) {
      // Only sync to Firebase if connected
      if (_isConnected) {
        FirebaseLocationService.syncLocation(locationModel);
      }
    });
  }

  Future<void> _syncLocationsToFirebase() async {
    try {
      await FirebaseLocationService.syncAllUnsyncedLocations();
    } catch (e) {
      print('Error syncing locations to Firebase: $e');
    }
  }

  void _saveLocation(TapPosition tapPosition, LatLng latLng) {
    if (!mounted) return;

    final locationModel = LocationModel(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      timestamp: DateTime.now(),
      userId: widget.userId,
      type: LocationType.normal,
    );

    setState(() {
      savedLocations.add(locationModel);
    });

    // Always save to local SQLite database first (works offline)
    LocationService.insertLocation(locationModel).then((_) {
      // Only sync to Firebase if connected
      if (_isConnected) {
        FirebaseLocationService.syncLocation(locationModel);
      }
    });
  }

  void _shareCurrentLocation() {
    if (_lastKnownLocation != null && widget.onLocationShare != null) {
      widget.onLocationShare!(_lastKnownLocation!);
      _showMessage('Location shared!');
    } else {
      _showMessage('No location available to share');
    }
  }

  void _centerOnCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  void _clearAllLocations() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            'Clear All Locations',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 18),
            ),
          ),
          content: SizedBox(
            width: ResponsiveUtils.getResponsiveDialogWidth(context),
            child: Text(
              'Are you sure you want to clear all saved locations? This action cannot be undone.',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _confirmClearLocations();
              },
              child: Text(
                'Clear',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearLocations() async {
    await LocationService.clearAllLocations();
    await _loadSavedLocations();

    if (!mounted) return;

    _showMessage('All locations cleared!');
  }

  void _showConnectivityStatus() {
    _showMessage(_isConnected ? 'Online' : 'Offline');
  }

  List<LatLng> _getRoutePoints() {
    return savedLocations
        .map((loc) => LatLng(loc.latitude, loc.longitude))
        .toList();
  }

  void _showLocationDetails(LocationModel location) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          location.type == LocationType.emergency
              ? 'Emergency Location'
              : 'Saved Location',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 18),
          ),
        ),
        content: SizedBox(
          width: ResponsiveUtils.getResponsiveDialogWidth(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Latitude: ${location.latitude.toStringAsFixed(6)}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
              Text(
                'Longitude: ${location.longitude.toStringAsFixed(6)}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
              Text(
                'Time: ${location.timestamp.toString().substring(0, 19)}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
              Text(
                'Type: ${location.type.name.toUpperCase()}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
              Text(
                'Synced: ${location.synced ? 'Yes' : 'No'}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Close',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveUtils.isMobile(context);
    final responsivePadding = ResponsiveUtils.getResponsivePadding(context);
    final responsiveSpacing = ResponsiveUtils.getResponsiveSpacing(context, 10);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'GPS Tracker',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
        ),
        actions: [
          // Emergency mode toggle
          IconButton(
            icon: Icon(
              _emergencyMode ? Icons.emergency : Icons.emergency_outlined,
              color: _emergencyMode ? Colors.red : Colors.grey,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onPressed: _toggleEmergencyMode,
            tooltip: _emergencyMode
                ? 'Disable Emergency Mode'
                : 'Enable Emergency Mode',
          ),
          // Connectivity status
          IconButton(
            icon: Icon(
              _isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _isConnected ? Colors.green : Colors.red,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
            onPressed: _showConnectivityStatus,
          ),
          // Clear all locations
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _clearAllLocations();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.clear_all,
                      color: Colors.red,
                      size: ResponsiveUtils.getResponsiveIconSize(context, 20),
                    ),
                    SizedBox(width: responsiveSpacing),
                    Text(
                      'Clear All Locations',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(
                          context,
                          14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentLocation ?? const LatLng(37.4219983, -122.084),
              initialZoom: 13.0,
              onLongPress: _saveLocation,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
              ),
              // Route line (polyline connecting all saved locations)
              if (savedLocations.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _getRoutePoints(),
                      strokeWidth: ResponsiveUtils.isMobile(context)
                          ? 3.0
                          : 4.0,
                      color: Colors.orange,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Current location marker (blue dot)
                  if (_currentLocation != null)
                    Marker(
                      width: ResponsiveUtils.getResponsiveMarkerSize(context),
                      height: ResponsiveUtils.getResponsiveMarkerSize(context),
                      point: _currentLocation!,
                      rotate: false,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: ResponsiveUtils.getResponsiveIconSize(
                            context,
                            30,
                          ),
                        ),
                      ),
                    ),
                  // Saved locations markers (color-coded by recency and type)
                  for (final location in savedLocations)
                    Marker(
                      width: ResponsiveUtils.getResponsiveMarkerSize(context),
                      height: ResponsiveUtils.getResponsiveMarkerSize(context),
                      point: LatLng(location.latitude, location.longitude),
                      rotate: false,
                      child: GestureDetector(
                        onTap: () => _showLocationDetails(location),
                        child: Container(
                          decoration: BoxDecoration(
                            color: location.getMarkerColor(),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            location.getMarkerIcon(),
                            color: Colors.white,
                            size: ResponsiveUtils.getResponsiveIconSize(
                              context,
                              30,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Status indicator - responsive positioning
          Positioned(
            top: responsiveSpacing,
            left: responsiveSpacing,
            child: Container(
              padding: responsivePadding,
              constraints: BoxConstraints(maxWidth: isMobile ? 200 : 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLocationServiceEnabled
                            ? Icons.gps_fixed
                            : Icons.gps_off,
                        color: _isLocationServiceEnabled
                            ? Colors.green
                            : Colors.red,
                        size: ResponsiveUtils.getResponsiveIconSize(
                          context,
                          16,
                        ),
                      ),
                      SizedBox(
                        width: ResponsiveUtils.getResponsiveSpacing(context, 4),
                      ),
                      Text(
                        _isLocationServiceEnabled ? 'GPS ON' : 'GPS OFF',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(
                            context,
                            12,
                          ),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_emergencyMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emergency,
                          color: Colors.red,
                          size: ResponsiveUtils.getResponsiveIconSize(
                            context,
                            16,
                          ),
                        ),
                        SizedBox(
                          width: ResponsiveUtils.getResponsiveSpacing(
                            context,
                            4,
                          ),
                        ),
                        Text(
                          'EMERGENCY',
                          style: TextStyle(
                            fontSize: ResponsiveUtils.getResponsiveFontSize(
                              context,
                              12,
                            ),
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  if (_lastKnownLocation != null)
                    Text(
                      'Last: ${_lastKnownLocation!.timestamp.toString().substring(0, 19)}',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(
                          context,
                          10,
                        ),
                      ),
                    ),
                  Text(
                    'Saved: ${savedLocations.length} locations',
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Legend
          Positioned(
            top: ResponsiveUtils.getResponsiveSpacing(context, 10),
            right: ResponsiveUtils.getResponsiveSpacing(context, 10),
            child: Container(
              padding: ResponsiveUtils.getResponsivePadding(context),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Legend',
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        12,
                      ),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(
                    height: ResponsiveUtils.getResponsiveSpacing(context, 4),
                  ),
                  _buildLegendItem(Icons.my_location, Colors.blue, 'Current'),
                  _buildLegendItem(
                    Icons.location_on,
                    Colors.green,
                    'Recent (<5m)',
                  ),
                  _buildLegendItem(
                    Icons.location_on,
                    Colors.orange,
                    'Old (<30m)',
                  ),
                  _buildLegendItem(Icons.warning, Colors.red, 'Emergency'),
                  _buildLegendItem(Icons.remove, Colors.orange, 'Route'),
                ],
              ),
            ),
          ),
          // Status message overlay
          if (_statusMessage.isNotEmpty)
            Positioned(
              bottom: ResponsiveUtils.isDesktop(context) ? 120 : 100,
              left: ResponsiveUtils.getResponsiveSpacing(context, 20),
              right: ResponsiveUtils.getResponsiveSpacing(context, 20),
              child: Container(
                padding: ResponsiveUtils.getResponsivePadding(context),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: ResponsiveUtils.getResponsiveFontSize(
                      context,
                      14,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: ResponsiveUtils.getResponsiveFloatingActionButtonSize(
              context,
            ),
            height: ResponsiveUtils.getResponsiveFloatingActionButtonSize(
              context,
            ),
            child: FloatingActionButton(
              heroTag: "emergency_toggle",
              onPressed: _toggleEmergencyMode,
              tooltip: _emergencyMode
                  ? 'Disable Emergency Mode'
                  : 'Enable Emergency Mode',
              backgroundColor: _emergencyMode ? Colors.red : Colors.grey,
              child: Icon(
                _emergencyMode ? Icons.emergency : Icons.emergency_outlined,
                color: Colors.white,
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
            ),
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 10)),
          SizedBox(
            width: ResponsiveUtils.getResponsiveFloatingActionButtonSize(
              context,
            ),
            height: ResponsiveUtils.getResponsiveFloatingActionButtonSize(
              context,
            ),
            child: FloatingActionButton(
              heroTag: "share_location",
              onPressed: _shareCurrentLocation,
              tooltip: 'Share Current Location',
              child: Icon(
                Icons.share_location,
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
            ),
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 10)),
          SizedBox(
            width: ResponsiveUtils.getResponsiveFloatingActionButtonSize(
              context,
            ),
            height: ResponsiveUtils.getResponsiveFloatingActionButtonSize(
              context,
            ),
            child: FloatingActionButton(
              heroTag: "center_location",
              onPressed: _centerOnCurrentLocation,
              tooltip: 'Center on Current Location',
              child: Icon(
                Icons.my_location,
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveUtils.getResponsiveSpacing(context, 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: ResponsiveUtils.getResponsiveIconSize(context, 12),
          ),
          SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 4)),
          Text(
            label,
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 10),
            ),
          ),
        ],
      ),
    );
  }
}
