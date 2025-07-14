import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

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
          title: const Text('Clear All Locations'),
          content: const Text(
            'Are you sure you want to clear all saved locations? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _confirmClearLocations();
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearLocations() async {
    await LocationService.clearAllLocations();
    await _loadSavedLocations();

    if (!mounted) return; // ✅ Safe to use `context` now

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
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latitude: ${location.latitude.toStringAsFixed(6)}'),
            Text('Longitude: ${location.longitude.toStringAsFixed(6)}'),
            Text('Time: ${location.timestamp.toString().substring(0, 19)}'),
            Text('Type: ${location.type.name.toUpperCase()}'),
            Text('Synced: ${location.synced ? 'Yes' : 'No'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Tracker'),
        actions: [
          // Emergency mode toggle
          IconButton(
            icon: Icon(
              _emergencyMode ? Icons.emergency : Icons.emergency_outlined,
              color: _emergencyMode ? Colors.red : Colors.grey,
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
              const PopupMenuItem<String>(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear All Locations'),
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
                      strokeWidth: 4.0,
                      color: Colors.orange,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Current location marker (blue dot)
                  if (_currentLocation != null)
                    Marker(
                      width: 80,
                      height: 80,
                      point: _currentLocation!,
                      rotate: false,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  // Saved locations markers (color-coded by recency and type)
                  for (final location in savedLocations)
                    Marker(
                      width: 80,
                      height: 80,
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
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Status indicator
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
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
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isLocationServiceEnabled ? 'GPS ON' : 'GPS OFF',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_emergencyMode)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emergency, color: Colors.red, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'EMERGENCY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  if (_lastKnownLocation != null)
                    Text(
                      'Last: ${_lastKnownLocation!.timestamp.toString().substring(0, 19)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  Text(
                    'Saved: ${savedLocations.length} locations',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          // Legend
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
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
                  const Text(
                    'Legend',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
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
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "emergency_toggle",
            onPressed: _toggleEmergencyMode,
            tooltip: _emergencyMode
                ? 'Disable Emergency Mode'
                : 'Enable Emergency Mode',
            backgroundColor: _emergencyMode ? Colors.red : Colors.grey,
            child: Icon(
              _emergencyMode ? Icons.emergency : Icons.emergency_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "share_location",
            onPressed: _shareCurrentLocation,
            tooltip: 'Share Current Location',
            child: const Icon(Icons.share_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "center_location",
            onPressed: _centerOnCurrentLocation,
            tooltip: 'Center on Current Location',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
