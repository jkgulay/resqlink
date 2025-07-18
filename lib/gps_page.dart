import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'dart:async';

// Emergency-optimized theme colors
class ResQLinkTheme {
  static const Color primaryRed = Color(0xFFE53935);
  static const Color darkRed = Color(0xFFB71C1C);
  static const Color emergencyOrange = Color(0xFFFF6F00);
  static const Color safeGreen = Color(0xFF43A047);
  static const Color warningYellow = Color(0xFFFFD600);
  static const Color offlineGray = Color(0xFF616161);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color cardDark = Color(0xFF2C2C2C);
}

// Location types for emergency scenarios
enum LocationType {
  normal,
  emergency,
  sos,
  safezone,
  hazard,
  evacuationPoint,
  medicalAid,
  supplies,
}

// Emergency status levels
enum EmergencyLevel { safe, caution, warning, danger, critical }

class LocationModel {
  final int? id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool synced;
  final String? userId;
  final LocationType type;
  final String? message;
  final EmergencyLevel? emergencyLevel;
  final int? batteryLevel;

  LocationModel({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.synced = false,
    this.userId,
    this.type = LocationType.normal,
    this.message,
    this.emergencyLevel,
    this.batteryLevel,
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
      'message': message,
      'emergencyLevel': emergencyLevel?.index,
      'batteryLevel': batteryLevel,
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
      message: map['message'],
      emergencyLevel: map['emergencyLevel'] != null
          ? EmergencyLevel.values[map['emergencyLevel']]
          : null,
      batteryLevel: map['batteryLevel'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
      'type': type.name,
      'message': message,
      'emergencyLevel': emergencyLevel?.name,
      'batteryLevel': batteryLevel,
    };
  }

  // Get marker color based on type and emergency level
  Color getMarkerColor() {
    switch (type) {
      case LocationType.emergency:
      case LocationType.sos:
        return ResQLinkTheme.primaryRed;
      case LocationType.safezone:
      case LocationType.evacuationPoint:
        return ResQLinkTheme.safeGreen;
      case LocationType.hazard:
        return ResQLinkTheme.emergencyOrange;
      case LocationType.medicalAid:
        return Colors.blue;
      case LocationType.supplies:
        return Colors.purple;
      default:
        if (emergencyLevel == EmergencyLevel.critical) {
          return ResQLinkTheme.darkRed;
        }
        final now = DateTime.now();
        final age = now.difference(timestamp);
        if (age.inMinutes < 5) {
          return ResQLinkTheme.safeGreen;
        } else if (age.inHours < 1) {
          return ResQLinkTheme.warningYellow;
        } else {
          return ResQLinkTheme.offlineGray;
        }
    }
  }

  IconData getMarkerIcon() {
    switch (type) {
      case LocationType.emergency:
      case LocationType.sos:
        return Icons.warning_rounded;
      case LocationType.safezone:
        return Icons.shield;
      case LocationType.evacuationPoint:
        return Icons.exit_to_app;
      case LocationType.hazard:
        return Icons.dangerous;
      case LocationType.medicalAid:
        return Icons.medical_services;
      case LocationType.supplies:
        return Icons.inventory_2;
      default:
        return Icons.location_on;
    }
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
    String path = p.join(await getDatabasesPath(), 'resqlink_locations.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_tableName(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            userId TEXT,
            type INTEGER NOT NULL DEFAULT 0,
            message TEXT,
            emergencyLevel INTEGER,
            batteryLevel INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN type INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $_tableName ADD COLUMN message TEXT');
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN emergencyLevel INTEGER',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN batteryLevel INTEGER',
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
      orderBy: 'timestamp DESC',
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

  static Future<int> getUnsyncedCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> clearAllLocations() async {
    final db = await database;
    await db.delete(_tableName);
  }
}

class FirebaseLocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'emergency_locations';

  static Future<void> syncLocation(LocationModel location) async {
    try {
      await _firestore.collection(_collection).add(location.toFirestore());
      if (location.id != null) {
        await LocationService.markLocationSynced(location.id!);
      }
    } catch (e) {
      print('Error syncing location to Firebase: $e');
      rethrow;
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
      rethrow;
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

class _GpsPageState extends State<GpsPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Core variables
  final List<LocationModel> savedLocations = [];
  final MapController _mapController = MapController();
  final Battery _battery = Battery();

  // Location and connectivity
  LocationModel? _lastKnownLocation;
  LatLng? _currentLocation;
  bool _isLocationServiceEnabled = false;
  bool _isConnected = false;

  // Emergency states
  EmergencyLevel _currentEmergencyLevel = EmergencyLevel.safe;
  bool _sosMode = false;
  int _batteryLevel = 100;
  bool _isOnBatteryPowerSaving = false;

  // UI states
  bool _isLoading = true;
  String _errorMessage = '';
  bool _showMapTypeSelector = false;
  int _selectedMapType = 0; // 0: Street, 1: Satellite, 2: Terrain

  // Timers and streams
  Timer? _locationTimer;
  Timer? _sosTimer;
  Timer? _batteryTimer;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _sosAnimationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _sosAnimation;

  // Map tile sources
  final List<String> _mapTypes = ['Street', 'Satellite', 'Terrain'];
  final List<String> _tileUrls = [
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _initializeApp();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _sosAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _sosAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _sosAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
    _sosTimer?.cancel();
    _batteryTimer?.cancel();
    _positionStream?.cancel();
    _connectivitySubscription?.cancel();
    _pulseController.dispose();
    _sosAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationPermission();
      _checkBatteryLevel();
    }
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      await _initializeServices();
      await _loadSavedLocations();
      _checkConnectivity();
      _startBatteryMonitoring();
      await _startLocationTracking();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to initialize GPS: $e';
      });
    }
  }

  Future<void> _initializeServices() async {
    await _checkLocationPermission();
    await _loadLastKnownLocation();
    await _checkBatteryLevel();
  }

  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLocationServiceEnabled = false;
          _errorMessage = 'Location services disabled. Enable in settings.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLocationServiceEnabled = false;
            _errorMessage = 'Location permission denied.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLocationServiceEnabled = false;
          _errorMessage = 'Location permissions permanently denied.';
        });
        return;
      }

      setState(() {
        _isLocationServiceEnabled = true;
        _errorMessage = '';
      });
    } catch (e) {
      setState(() {
        _isLocationServiceEnabled = false;
        _errorMessage = 'Error checking permissions: $e';
      });
    }
  }

  Future<void> _loadLastKnownLocation() async {
    try {
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
    } catch (e) {
      print('Error loading last location: $e');
    }
  }

  Future<void> _loadSavedLocations() async {
    try {
      final locations = await LocationService.getLocations();
      if (mounted) {
        setState(() {
          savedLocations.clear();
          savedLocations.addAll(locations);
        });
      }
    } catch (e) {
      print('Error loading locations: $e');
    }
  }

  void _checkConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      if (mounted) {
        final wasConnected = _isConnected;
        setState(() {
          _isConnected = result != ConnectivityResult.none;
        });

        if (!wasConnected && _isConnected) {
          _showMessage('Connection restored! Syncing data...', isSuccess: true);
          await _syncLocationsToFirebase();
          final unsyncedCount = await LocationService.getUnsyncedCount();
          if (unsyncedCount == 0) {
            _showMessage('All locations synced!', isSuccess: true);
          }
        } else if (wasConnected && !_isConnected) {
          _showMessage('OFFLINE MODE - Data saved locally', isWarning: true);
        }
      }
    });
  }

  void _startBatteryMonitoring() {
    _checkBatteryLevel();
    _batteryTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _checkBatteryLevel();
    });
  }

  Future<void> _checkBatteryLevel() async {
    try {
      // Get current battery level
      final level = await _battery.batteryLevel;

      // Check if battery saving mode is enabled
      final batteryState = await _battery.batteryState;
      final isInPowerSaving =
          batteryState == BatteryState.connectedNotCharging || level < 20;

      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _isOnBatteryPowerSaving = isInPowerSaving;
        });

        // Show warning if battery is critically low
        if (level < 10 && !_sosMode) {
          _showMessage(
            'Low battery warning! Consider activating SOS mode.',
            isWarning: true,
          );
        }
      }

      // Listen to battery state changes
      _battery.onBatteryStateChanged.listen((BatteryState state) {
        if (mounted) {
          _checkBatteryLevel(); // Recheck when state changes
        }
      });
    } catch (e) {
      print('Error checking battery level: $e');
      // Fallback to 100% if battery info unavailable
      if (mounted) {
        setState(() {
          _batteryLevel = 100;
        });
      }
    }
  }

  Future<void> _startLocationTracking() async {
    if (!_isLocationServiceEnabled) {
      await _checkLocationPermission();
      if (!_isLocationServiceEnabled) return;
    }

    try {
      // First, try to get current location immediately
      await _getCurrentLocation();

      // Adjust tracking frequency based on battery level
      final distanceFilter = _batteryLevel < 20 ? 20 : 10; // meters
      final accuracy = _batteryLevel < 20
          ? LocationAccuracy.medium
          : LocationAccuracy.high;

      // Use the distanceFilter and accuracy in LocationSettings
      final locationSettings = LocationSettings(
        accuracy: accuracy, // Use the accuracy variable
        distanceFilter: distanceFilter, // Use the distanceFilter variable
      );

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              if (mounted) {
                _updateCurrentLocation(position);
              }
            },
            onError: (error) {
              print('Position stream error: $error');
              setState(() {
                _errorMessage = 'GPS tracking error: $error';
              });

              // Try to restart tracking after error
              Future.delayed(Duration(seconds: 5), () {
                if (mounted && _isLocationServiceEnabled) {
                  _startLocationTracking();
                }
              });
            },
          );

      // Update location periodically (less frequent if low battery)
      final updateInterval = _batteryLevel < 20
          ? Duration(minutes: 2)
          : Duration(seconds: 30);

      _locationTimer = Timer.periodic(updateInterval, (timer) {
        if (mounted && _isLocationServiceEnabled) {
          _getCurrentLocation();
        }
      });
    } catch (e) {
      print('Error starting location tracking: $e');
      setState(() {
        _errorMessage = 'Failed to start tracking: $e';
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isLocationServiceEnabled) return;

    try {
      // Show loading indicator
      _showMessage('Getting current location...', isSuccess: false);

      // Configure location settings based on battery level
      final locationSettings = LocationSettings(
        accuracy: _batteryLevel < 20
            ? LocationAccuracy.medium
            : LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      _updateCurrentLocation(position);
      _showMessage('Location updated!', isSuccess: true);
    } catch (e) {
      print('Error getting location: $e');

      // Try to get last known position as fallback
      try {
        Position? lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _updateCurrentLocation(lastPosition);
          _showMessage('Using last known location', isWarning: true);
        } else {
          _showMessage('Unable to get location', isDanger: true);
        }
      } catch (e2) {
        print('Error getting last known position: $e2');
        _showMessage('Location service error', isDanger: true);
      }
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
      type: _sosMode ? LocationType.sos : LocationType.normal,
      emergencyLevel: _currentEmergencyLevel,
      batteryLevel: _batteryLevel,
    );

    setState(() {
      _currentLocation = newLocation;
      _lastKnownLocation = locationModel;
      _errorMessage = '';
    });

    // Auto-save location in emergency situations
    if (_currentEmergencyLevel.index >= EmergencyLevel.warning.index ||
        _sosMode) {
      _saveCurrentLocation(silent: true);
    }
  }

  void _activateSOS() {
    setState(() {
      _sosMode = true;
      _currentEmergencyLevel = EmergencyLevel.critical;
    });

    _sosAnimationController.repeat(reverse: true);
    _showMessage('SOS ACTIVATED! Broadcasting location...', isDanger: true);

    // Send immediate SOS location
    _sendSOSLocation();

    // Send SOS signal every 30 seconds
    _sosTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_sosMode && mounted) {
        _sendSOSLocation();
      }
    });
  }

  void _deactivateSOS() {
    setState(() {
      _sosMode = false;
      _currentEmergencyLevel = EmergencyLevel.safe;
    });

    _sosTimer?.cancel();
    _sosTimer = null;
    _sosAnimationController.stop();
    _sosAnimationController.reset();

    _showMessage('SOS deactivated', isSuccess: true);
  }

  Future<void> _sendSOSLocation() async {
    if (_currentLocation == null) return;

    final sosLocation = LocationModel(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      timestamp: DateTime.now(),
      userId: widget.userId,
      type: LocationType.sos,
      message: 'EMERGENCY SOS - Immediate assistance required!',
      emergencyLevel: EmergencyLevel.critical,
      batteryLevel: _batteryLevel,
    );

    await LocationService.insertLocation(sosLocation);

    if (_isConnected) {
      try {
        await FirebaseLocationService.syncLocation(sosLocation);
        _showMessage('SOS location broadcast!', isDanger: true);
      } catch (e) {
        _showMessage(
          'SOS saved locally - will sync when online',
          isWarning: true,
        );
      }
    }

    if (widget.onLocationShare != null) {
      widget.onLocationShare!(sosLocation);
    }

    await _loadSavedLocations();
  }

  Future<void> _saveCurrentLocation({bool silent = false}) async {
    if (_currentLocation == null) return;

    final location = LocationModel(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      timestamp: DateTime.now(),
      userId: widget.userId,
      type: _sosMode ? LocationType.sos : LocationType.normal,
      emergencyLevel: _currentEmergencyLevel,
      batteryLevel: _batteryLevel,
    );

    await LocationService.insertLocation(location);

    if (_isConnected) {
      try {
        await FirebaseLocationService.syncLocation(location);
        if (!silent) _showMessage('Location saved & synced!', isSuccess: true);
      } catch (e) {
        if (!silent) _showMessage('Location saved locally', isWarning: true);
      }
    } else {
      if (!silent) _showMessage('Location saved offline', isWarning: true);
    }

    await _loadSavedLocations();
  }

  Future<void> _syncLocationsToFirebase() async {
    try {
      await FirebaseLocationService.syncAllUnsyncedLocations();
      await _loadSavedLocations();
    } catch (e) {
      print('Sync error: $e');
    }
  }

  void _showMessage(
    String message, {
    bool isSuccess = false,
    bool isWarning = false,
    bool isDanger = false,
  }) {
    if (!mounted) return;

    final color = isDanger
        ? ResQLinkTheme.primaryRed
        : isWarning
        ? ResQLinkTheme.emergencyOrange
        : isSuccess
        ? ResQLinkTheme.safeGreen
        : Colors.black87;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showLocationTypeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: ResQLinkTheme.cardDark,
          title: const Text(
            'Mark Location Type',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLocationTypeOption(
                  LocationType.safezone,
                  'Safe Zone',
                  Icons.shield,
                  ResQLinkTheme.safeGreen,
                ),
                _buildLocationTypeOption(
                  LocationType.hazard,
                  'Hazard Area',
                  Icons.dangerous,
                  ResQLinkTheme.emergencyOrange,
                ),
                _buildLocationTypeOption(
                  LocationType.evacuationPoint,
                  'Evacuation Point',
                  Icons.exit_to_app,
                  ResQLinkTheme.safeGreen,
                ),
                _buildLocationTypeOption(
                  LocationType.medicalAid,
                  'Medical Aid',
                  Icons.medical_services,
                  Colors.blue,
                ),
                _buildLocationTypeOption(
                  LocationType.supplies,
                  'Supplies/Resources',
                  Icons.inventory_2,
                  Colors.purple,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationTypeOption(
    LocationType type,
    String label,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      leading: Icon(icon, color: color, size: 30),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.of(context).pop();
        _markLocation(type);
      },
    );
  }

  Future<void> _markLocation(LocationType type) async {
    if (_currentLocation == null) return;

    final location = LocationModel(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      timestamp: DateTime.now(),
      userId: widget.userId,
      type: type,
      emergencyLevel: _currentEmergencyLevel,
      batteryLevel: _batteryLevel,
    );

    await LocationService.insertLocation(location);

    if (_isConnected) {
      try {
        await FirebaseLocationService.syncLocation(location);
        _showMessage('${type.name} marked & synced!', isSuccess: true);
      } catch (e) {
        _showMessage('${type.name} marked locally', isWarning: true);
      }
    } else {
      _showMessage('${type.name} marked offline', isWarning: true);
    }

    await _loadSavedLocations();
  }

  void _centerOnCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
    } else {
      _showMessage('No location available', isWarning: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingScreen();
    }

    if (_errorMessage.isNotEmpty && !_isLocationServiceEnabled) {
      return _buildErrorScreen();
    }

    return Theme(
      data: ThemeData.dark().copyWith(
        primaryColor: ResQLinkTheme.primaryRed,
        scaffoldBackgroundColor: ResQLinkTheme.backgroundDark,
      ),
      child: Scaffold(
        backgroundColor: ResQLinkTheme.backgroundDark,
        body: Stack(
          children: [
            _buildMap(),
            _buildTopControls(),
            _buildEmergencyButton(),
            if (_showMapTypeSelector) _buildMapTypeSelector(),
            _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: ResQLinkTheme.backgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/resqlink_logo.png',
              width: 120,
              height: 120,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.emergency,
                  size: 80,
                  color: ResQLinkTheme.primaryRed,
                );
              },
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: ResQLinkTheme.primaryRed),
            const SizedBox(height: 16),
            const Text(
              'Initializing Emergency GPS...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: ResQLinkTheme.backgroundDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off,
                size: 80,
                color: ResQLinkTheme.primaryRed,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _retryInitialization,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ResQLinkTheme.primaryRed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Geolocator.openAppSettings(),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(
                    color: ResQLinkTheme.primaryRed,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _retryInitialization() {
    _initializeApp();
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            _currentLocation ??
            const LatLng(14.5995, 120.9842), // Manila, Philippines default
        initialZoom: 13.0,
        maxZoom: 18.0,
        minZoom: 5.0,
        onLongPress: (tapPos, latLng) => _showLocationTypeDialog(),
        onMapReady: () {
          // Center on current location when map is ready
          if (_currentLocation != null) {
            _mapController.move(_currentLocation!, 15.0);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrls[_selectedMapType],
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.resqlink.app',
        ),
        // Route lines for saved locations
        if (savedLocations.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: savedLocations
                    .map((loc) => LatLng(loc.latitude, loc.longitude))
                    .toList(),
                strokeWidth: 3.0,
                color: ResQLinkTheme.emergencyOrange.withAlpha(
                  (255 * 0.7).toInt(),
                ),
                pattern: StrokePattern.dashed(
                  segments: [6.0, 4.0],
                ), // Use pattern instead of isDotted
              ),
            ],
          ),
        // Markers layer
        MarkerLayer(
          markers: [
            // Current location marker
            if (_currentLocation != null)
              Marker(
                width: 80,
                height: 80,
                point: _currentLocation!,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulse animation for current location
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _sosMode
                                  ? ResQLinkTheme.primaryRed.withAlpha(
                                      (255 * 0.3).toInt(),
                                    )
                                  : Colors.blue.withAlpha((255 * 0.3).toInt()),
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _sosMode
                            ? ResQLinkTheme.primaryRed
                            : Colors.blue,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_sosMode
                                        ? ResQLinkTheme.primaryRed
                                        : Colors.blue)
                                    .withAlpha((255 * 0.5).toInt()),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _sosMode ? Icons.emergency : Icons.my_location,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            // Saved location markers
            ...savedLocations.map(
              (location) => Marker(
                width: 60,
                height: 60,
                point: LatLng(location.latitude, location.longitude),
                child: GestureDetector(
                  onTap: () => _showLocationDetails(location),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: location.getMarkerColor(),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: location.getMarkerColor().withAlpha((255 * 0.5).toInt()),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      location.getMarkerIcon(),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ResQLinkTheme.cardDark.withAlpha((255 * 0.9).toInt()),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((255 * 0.3).toInt()),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: _isConnected
                            ? ResQLinkTheme.safeGreen
                            : ResQLinkTheme.emergencyOrange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isConnected ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                          color: _isConnected
                              ? ResQLinkTheme.safeGreen
                              : ResQLinkTheme.emergencyOrange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.battery_full,
                        color: _batteryLevel > 20
                            ? ResQLinkTheme.safeGreen
                            : ResQLinkTheme.primaryRed,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_batteryLevel%',
                        style: TextStyle(
                          color: _batteryLevel > 20
                              ? Colors.white70
                              : ResQLinkTheme.primaryRed,
                          fontSize: 12,
                          fontWeight: _batteryLevel <= 20
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (_isOnBatteryPowerSaving) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.power_settings_new,
                          color: ResQLinkTheme.warningYellow,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<int>(
                    future: LocationService.getUnsyncedCount(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Row(
                        children: [
                          Icon(
                            Icons.sync,
                            color: count > 0
                                ? ResQLinkTheme.warningYellow
                                : ResQLinkTheme.safeGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            count > 0 ? '$count pending' : 'Synced',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            // Control buttons
            Column(
              children: [
                _buildControlButton(
                  icon: Icons.layers,
                  onPressed: () {
                    setState(() {
                      _showMapTypeSelector = !_showMapTypeSelector;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.my_location,
                  onPressed: _centerOnCurrentLocation,
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.save_alt,
                  onPressed: () => _saveCurrentLocation(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: ResQLinkTheme.cardDark.withAlpha((255 * 0.9).toInt()),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.3).toInt()),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        iconSize: 24,
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return Positioned(
      bottom: 100,
      right: 20,
      child: GestureDetector(
        onLongPress: () {
          if (!_sosMode) {
            _activateSOS();
          } else {
            _deactivateSOS();
          }
        },
        child: AnimatedBuilder(
          animation: _sosMode ? _sosAnimation : _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _sosMode ? _sosAnimation.value : 1.0,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _sosMode
                      ? ResQLinkTheme.primaryRed
                      : ResQLinkTheme.darkRed,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_sosMode
                                  ? ResQLinkTheme.primaryRed
                                  : ResQLinkTheme.darkRed)
                              .withAlpha((255 * 0.6).toInt()),
                      blurRadius: 20,
                      spreadRadius: _sosMode ? 5 : 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.emergency,
                      color: Colors.white,
                      size: _sosMode ? 40 : 35,
                    ),
                    Text(
                      _sosMode ? 'ACTIVE' : 'SOS',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMapTypeSelector() {
    return Positioned(
      top: 150,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: ResQLinkTheme.cardDark.withAlpha((255 * 0.9).toInt()),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((255 * 0.3).toInt()),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: List.generate(_mapTypes.length, (index) {
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedMapType = index;
                  _showMapTypeSelector = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _selectedMapType == index
                      ? ResQLinkTheme.primaryRed.withAlpha((255 * 0.3).toInt())
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _mapTypes[index],
                  style: TextStyle(
                    color: _selectedMapType == index
                        ? Colors.white
                        : Colors.white70,
                    fontWeight: _selectedMapType == index
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ResQLinkTheme.surfaceDark.withAlpha((255 * 0.95).toInt()),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((255 * 0.3).toInt()),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            if (_lastKnownLocation != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Location',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_lastKnownLocation!.latitude.toStringAsFixed(6)}, '
                        '${_lastKnownLocation!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Last Update',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(_lastKnownLocation!.timestamp),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Long press map to mark locations • Hold SOS for emergency',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationDetails(LocationModel location) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ResQLinkTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    location.getMarkerIcon(),
                    color: location.getMarkerColor(),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getLocationTypeLabel(location.type),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatTime(location.timestamp),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildDetailRow(
                'Coordinates',
                '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
              ),
              if (location.message != null)
                _buildDetailRow('Message', location.message!),
              if (location.emergencyLevel != null)
                _buildDetailRow(
                  'Emergency Level',
                  location.emergencyLevel!.name.toUpperCase(),
                ),
              _buildDetailRow(
                'Status',
                location.synced ? 'Synced' : 'Pending sync',
              ),
              if (location.batteryLevel != null)
                _buildDetailRow('Battery', '${location.batteryLevel}%'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _mapController.move(
                        LatLng(location.latitude, location.longitude),
                        16.0,
                      );
                    },
                    icon: const Icon(Icons.map, color: Colors.white70),
                    label: const Text(
                      'View on Map',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      // Share location functionality
                      if (widget.onLocationShare != null) {
                        widget.onLocationShare!(location);
                        Navigator.pop(context);
                        _showMessage('Location shared!', isSuccess: true);
                      }
                    },
                    icon: const Icon(
                      Icons.share,
                      color: ResQLinkTheme.primaryRed,
                    ),
                    label: const Text(
                      'Share',
                      style: TextStyle(color: ResQLinkTheme.primaryRed),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getLocationTypeLabel(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return 'Location Pin';
      case LocationType.emergency:
        return 'Emergency';
      case LocationType.sos:
        return 'SOS Signal';
      case LocationType.safezone:
        return 'Safe Zone';
      case LocationType.hazard:
        return 'Hazard Area';
      case LocationType.evacuationPoint:
        return 'Evacuation Point';
      case LocationType.medicalAid:
        return 'Medical Aid Station';
      case LocationType.supplies:
        return 'Supplies/Resources';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
