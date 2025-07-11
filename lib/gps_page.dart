import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class LocationModel {
  final int? id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool synced;
  final String? userId;

  LocationModel({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.synced = false,
    this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'synced': synced ? 1 : 0,
      'userId': userId,
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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
    };
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
    String path = join(await getDatabasesPath(), 'locations.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_tableName(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            userId TEXT
          )
        ''');
      },
    );
  }

  static Future<int> insertLocation(LocationModel location) async {
    final db = await database;
    return await db.insert(_tableName, location.toMap());
  }

  static Future<List<LocationModel>> getLocations() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_tableName);
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
  final List<LatLng> savedLocations = [];
  final MapController _mapController = MapController();
  LocationModel? _lastKnownLocation;
  LatLng? _currentLocation;
  bool _isLocationServiceEnabled = false;
  bool _isConnected = false;
  Timer? _locationTimer;
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
    _positionStream?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
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
        savedLocations.addAll(
          locations.map((loc) => LatLng(loc.latitude, loc.longitude)),
        );
      });
    }
  }

  void _checkConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      if (mounted) {
        setState(() {
          _isConnected = result != ConnectivityResult.none;
        });

        if (_isConnected) {
          _syncLocationsToFirebase();
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
    );

    setState(() {
      _currentLocation = newLocation;
      _lastKnownLocation = locationModel;
    });

    // Save to local database
    LocationService.insertLocation(locationModel);

    // Sync to Firebase if connected
    if (_isConnected) {
      FirebaseLocationService.syncLocation(locationModel);
    }
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
    );

    setState(() {
      savedLocations.add(latLng);
    });

    // Save to local database
    LocationService.insertLocation(locationModel);

    // Sync to Firebase if connected
    if (_isConnected) {
      FirebaseLocationService.syncLocation(locationModel);
    }
  }

  void _shareCurrentLocation(BuildContext context) {
    if (_lastKnownLocation != null && widget.onLocationShare != null) {
      widget.onLocationShare!(_lastKnownLocation!);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Location shared!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location available to share')),
      );
    }
  }

  void _centerOnCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Tracker'),
        actions: [
          IconButton(
            icon: Icon(
              _isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _isConnected ? Colors.green : Colors.red,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_isConnected ? 'Online' : 'Offline')),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? LatLng(37.4219983, -122.084),
              initialZoom: 13.0,
              onLongPress: _saveLocation,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
              ),
              MarkerLayer(
                markers: [
                  // Current location marker
                  if (_currentLocation != null)
                    Marker(
                      width: 80,
                      height: 80,
                      point: _currentLocation!,
                      rotate: false,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  // Saved locations markers
                  for (final point in savedLocations)
                    Marker(
                      width: 80,
                      height: 80,
                      point: point,
                      rotate: false,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
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
                    color: Colors.black.withValues(alpha: 0.2),
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
                  if (_lastKnownLocation != null)
                    Text(
                      'Last: ${_lastKnownLocation!.timestamp.toString().substring(0, 19)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "share_location",
            onPressed: () => _shareCurrentLocation(context),
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
}
