import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:resqlink/services/p2p_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'dart:async';
import '../utils/resqlink_theme.dart';
import 'services/map_service.dart';

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
  // Add these missing fields:
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;

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
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
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
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
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
      accuracy: map['accuracy']?.toDouble(),
      altitude: map['altitude']?.toDouble(),
      speed: map['speed']?.toDouble(),
      heading: map['heading']?.toDouble(),
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
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
    };
  }

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

// Enhanced Location Service (same as your existing one)
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
      debugPrint(
        '🔄 Syncing location to Firebase: ${location.latitude}, ${location.longitude}',
      );

      final docRef = await _firestore
          .collection(_collection)
          .add(location.toFirestore());
      debugPrint('✅ Location synced to Firebase with ID: ${docRef.id}');

      if (location.id != null) {
        await LocationService.markLocationSynced(location.id!);
        debugPrint('✅ Local location marked as synced');
      }
    } catch (e) {
      debugPrint('❌ Error syncing location to Firebase: $e');
      rethrow;
    }
  }

  static Future<void> syncAllUnsyncedLocations() async {
    try {
      debugPrint('🔄 Starting bulk sync of unsynced locations...');
      final unsyncedLocations = await LocationService.getUnsyncedLocations();
      debugPrint('📊 Found ${unsyncedLocations.length} unsynced locations');

      for (final location in unsyncedLocations) {
        try {
          await syncLocation(location);
          debugPrint('✅ Synced location ${location.id}');
        } catch (e) {
          debugPrint('❌ Failed to sync location ${location.id}: $e');
        }
      }

      debugPrint('✅ Bulk sync completed');
    } catch (e) {
      debugPrint('❌ Error during bulk sync: $e');
      rethrow;
    }
  }

  static Future<bool> testFirebaseConnection() async {
    try {
      await _firestore.collection('test').doc('connection').set({
        'timestamp': FieldValue.serverTimestamp(),
        'test': true,
      });
      debugPrint('✅ Firebase connection test successful');
      return true;
    } catch (e) {
      debugPrint('❌ Firebase connection test failed: $e');
      return false;
    }
  }
}

class GpsPage extends StatefulWidget {
  final String? userId;
  final Function(LocationModel)? onLocationShare;
  final P2PConnectionService p2pService;

  const GpsPage({
    super.key,
    this.userId,
    this.onLocationShare,
    required this.p2pService, // Add this parameter
  });
  @override
  State<GpsPage> createState() => _GpsPageState();
}

class _GpsPageState extends State<GpsPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final List<LocationModel> savedLocations = [];
  final MapController _mapController = MapController();
  final Battery _battery = Battery();
  bool _isMapReady = false;
  bool _isMoving = false;
  LocationModel? _lastKnownLocation;
  LatLng? _currentLocation;
  bool _isLocationServiceEnabled = false;
  bool _isConnected = false;

  EmergencyLevel _currentEmergencyLevel = EmergencyLevel.safe;
  bool _sosMode = false;
  int _batteryLevel = 100;

  bool _isLoading = true;
  String _errorMessage = '';
  bool _showMapTypeSelector = false;
  int _selectedMapType = 0;

  // Offline map features
  bool _isDownloadingMaps = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = 'Ready to download';
  int _totalTiles = 0;
  int _downloadedTiles = 0;
  bool _offlineMode = false;
  Map<String, dynamic> _cacheInfo = {};

  Timer? _locationTimer;
  Timer? _sosTimer;
  Timer? _batteryTimer;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<double>? _downloadProgressSubscription;

  late AnimationController _pulseController;
  late AnimationController _sosAnimationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _sosAnimation;

  final List<String> _mapTypes = ['Street', 'Satellite', 'Terrain'];

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
    debugPrint('🔧 GpsPage: Starting disposal...');

    _locationTimer?.cancel();
    _sosTimer?.cancel();
    _batteryTimer?.cancel();
    _downloadProgressSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _positionStream?.cancel();

    _locationTimer = null;
    _sosTimer = null;
    _batteryTimer = null;
    _downloadProgressSubscription = null;
    _connectivitySubscription = null;
    _positionStream = null;

    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      debugPrint('Error removing WidgetsBindingObserver: $e');
    }

    try {
      if (_pulseController.isAnimating) _pulseController.stop();
      if (_sosAnimationController.isAnimating) _sosAnimationController.stop();
      _pulseController.dispose();
      _sosAnimationController.dispose();
    } catch (e) {
      debugPrint('Animation disposal error: $e');
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationPermission();
      _checkBatteryLevel();
      _updateCacheInfo();
      _optimizeLocationUpdates();
    }
  }

  void _optimizeLocationUpdates() {
    final settings = LocationSettings(
      accuracy: _batteryLevel < 20
          ? LocationAccuracy.medium
          : LocationAccuracy.high,
      distanceFilter: _isMoving ? 5 : 20,
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
            if (mounted) {
              _updateCurrentLocation(position);
              _isMoving = position.speed > 1.0;
            }
          },
          onError: (error) {
            debugPrint('Position stream error: $error');
          },
        );

    _locationTimer = Timer.periodic(interval, (timer) {
      if (mounted && _isLocationServiceEnabled) {
        _getCurrentLocation();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Initialize offline maps
      try {
        await PhilippinesMapService.instance.initialize();
        await _updateCacheInfo();
      } catch (e) {
        debugPrint('Map service init error: $e');
        // Continue even if map service fails
      }

      if (!mounted) return;

      await _initializeServices();
      if (!mounted) return;

      await _loadSavedLocations();
      if (!mounted) return;

      await _checkConnectivity();
      if (!mounted) return;

      await _startBatteryMonitoring();
      if (!mounted) return;

      await _startLocationTracking();
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize GPS: $e';
        });
      }
      debugPrint('Initialization error: $e');
    }
  }

  Widget _buildDownloadDialog() {
    double radius = 5.0; // km
    int minZoom = 10;
    int maxZoom = 16;

    return StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: ResQLinkTheme.cardDark,
          title: const Text(
            'Download Offline Maps',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Download maps for offline use around your current location',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Radius: ', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: radius,
                      min: 1.0,
                      max: 20.0,
                      divisions: 19,
                      label: '${radius.toInt()} km',
                      onChanged: (value) => setState(() => radius = value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('Min Zoom: ', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: minZoom.toDouble(),
                      min: 8,
                      max: 18,
                      divisions: 10,
                      label: minZoom.toString(),
                      onChanged: (value) =>
                          setState(() => minZoom = value.toInt()),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('Max Zoom: ', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: maxZoom.toDouble(),
                      min: minZoom.toDouble(),
                      max: 18,
                      divisions: 18 - minZoom,
                      label: maxZoom.toString(),
                      onChanged: (value) =>
                          setState(() => maxZoom = value.toInt()),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'radius': radius,
                'minZoom': minZoom,
                'maxZoom': maxZoom,
              }),
              child: const Text(
                'Download',
                style: TextStyle(color: ResQLinkTheme.primaryRed),
              ),
            ),
          ],
        );
      },
    );
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
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Location Services Disabled'),
            content: Text(
              'Location services are required for this app to work. '
              'Please enable location services in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Geolocator.openLocationSettings();
                },
                child: Text('Open Settings'),
              ),
            ],
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Location Permission Required'),
            content: Text(
              'Location permission is permanently denied. '
              'Please enable it in app settings to use this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Geolocator.openAppSettings();
                },
                child: Text('Open Settings'),
              ),
            ],
          ),
        );
        return;
      }

      if (mounted) {
        setState(() {
          _isLocationServiceEnabled = true;
          _errorMessage = '';
        });
      }

      await _startLocationTracking();
    } catch (e) {
      _showLocationError('Error: $e');
    }
  }

  void _showLocationError(String message) {
    if (!mounted) return;
    setState(() {
      _isLocationServiceEnabled = false;
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: _checkLocationPermission,
        ),
      ),
    );
  }

  Future<void> _updateCacheInfo() async {
    try {
      final stats = await PhilippinesMapService.instance.getCacheStats();
      final totalSize = stats.values.fold(
        0,
        (total, stat) => total + stat.sizeBytes, // Changed 'sum' to 'total'
      );
      final totalTiles = stats.values.fold(
        0,
        (total, stat) => total + stat.tileCount, // Changed 'sum' to 'total'
      );
      final info = {
        'cachedTiles': totalTiles,
        'storageSize': totalSize,
        'storageSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      };

      if (mounted) {
        setState(() {
          _cacheInfo = info;
        });
      }
    } catch (e) {
      debugPrint('Error updating cache info: $e');
    }
  }

  LatLngBounds _calculateBounds(LatLng center, double radiusKm) {
    // Approximate conversion: 1 degree ≈ 111 km
    final latOffset = radiusKm / 111.0;
    final lngOffset =
        radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180));

    return LatLngBounds(
      LatLng(center.latitude - latOffset, center.longitude - lngOffset), // SW
      LatLng(center.latitude + latOffset, center.longitude + lngOffset), // NE
    );
  }

  Future<void> _downloadOfflineMaps() async {
    if (_currentLocation == null) {
      _showMessage('No location available for download', isWarning: true);
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _buildDownloadDialog(),
    );

    if (result == null) return;

    setState(() {
      _isDownloadingMaps = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Preparing download...';
      _downloadedTiles = 0;
      _totalTiles = 0;
    });

    try {
      // Calculate bounds and estimate total tiles
      final radiusKm = result['radius'];
      final minZoom = result['minZoom'];
      final maxZoom = result['maxZoom'];
      final bounds = _calculateBounds(_currentLocation!, radiusKm);

      // Estimate total tiles for progress calculation
      _totalTiles = _estimateTotalTiles(bounds, minZoom, maxZoom);

      setState(() {
        _downloadStatus = 'Downloading $_totalTiles tiles...';
      });

      debugPrint('📊 Estimated total tiles: $_totalTiles');

      // Start download with progress tracking
      final downloadProgress = await PhilippinesMapService.instance.cacheArea(
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        regionName: 'Current Area Download',
        isEmergencyCache: false,
      );

      // Cancel any existing subscription
      _downloadProgressSubscription?.cancel();

      // Listen to download progress with proper error handling
      _downloadProgressSubscription = downloadProgress.percentageStream.listen(
        (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress / 100.0; // Convert to 0-1 range
              _downloadedTiles = (_totalTiles * _downloadProgress).round();
              _downloadStatus =
                  'Downloaded $_downloadedTiles of $_totalTiles tiles (${progress.toStringAsFixed(1)}%)';
            });
            debugPrint(
              '📊 Download progress: ${progress.toStringAsFixed(1)}% ($_downloadedTiles/$_totalTiles tiles)',
            );
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isDownloadingMaps = false;
              _downloadProgress = 1.0;
              _downloadStatus = 'Download completed!';
            });
            _showMessage(
              'Offline maps downloaded successfully!\n$_totalTiles tiles cached',
              isSuccess: true,
            );
            _updateCacheInfo();

            // Reset status after 3 seconds
            Timer(Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _downloadStatus = 'Ready to download';
                  _downloadProgress = 0.0;
                });
              }
            });
          }
        },
        onError: (error) {
          debugPrint('❌ Download error: $error');
          if (mounted) {
            setState(() {
              _isDownloadingMaps = false;
              _downloadProgress = 0.0;
              _downloadStatus = 'Download failed';
            });
            _showMessage('Download failed: $error', isDanger: true);

            // Reset status after 3 seconds
            Timer(Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _downloadStatus = 'Ready to download';
                });
              }
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingMaps = false;
          _downloadProgress = 0.0;
          _downloadStatus = 'Download failed';
        });
        _showMessage('Download failed: $e', isDanger: true);
      }
    }
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
      } else if (!mounted) {
        print('⚠️ Skipping last location update - widget not mounted');
      }
    } catch (e) {
      debugPrint('Error loading last location: $e');
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
      } else {
        print('⚠️ Skipping saved locations update - widget not mounted');
      }
    } catch (e) {
      debugPrint('Error loading locations: $e');
      if (mounted) {
        setState(() {
          savedLocations.clear(); // Just show empty list
        });
      }
    }
  }

  Future<void> _checkConnectivity() async {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      if (!mounted) {
        print('⚠️ Connectivity change ignored - widget not mounted');
        return;
      }

      final wasConnected = _isConnected;
      setState(() {
        _isConnected = results.any(
          (result) => result != ConnectivityResult.none,
        );
      });

      if (!wasConnected && _isConnected) {
        _showMessage('Connection restored! Syncing data...', isSuccess: true);
        await _syncLocationsToFirebase();
        final unsyncedCount = await LocationService.getUnsyncedCount();
        if (unsyncedCount == 0 && mounted) {
          _showMessage('All locations synced!', isSuccess: true);
        }
      } else if (wasConnected && !_isConnected && mounted) {
        _showMessage('OFFLINE MODE - Data saved locally', isWarning: true);
      }
    });
  }

  Future<void> _startBatteryMonitoring() async {
    _checkBatteryLevel();
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        _checkBatteryLevel();
      } else {
        print('🛑 Canceling battery timer - widget disposed');
        timer.cancel();
      }
    });
  }

  Future<void> _checkBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        final oldLevel = _batteryLevel;
        setState(() {
          _batteryLevel = level;
        });

        if ((oldLevel - level).abs() >= 10) {
          _optimizeLocationUpdates();
        }
      }
    } catch (e) {
      debugPrint('Error checking battery level: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    if (!_isLocationServiceEnabled) {
      await _checkLocationPermission();
      if (!_isLocationServiceEnabled) return;
    }

    try {
      await _getCurrentLocation();
      await _startLocationTracking();
      final distanceFilter = _batteryLevel < 20 ? 20 : 10;
      final accuracy = _batteryLevel < 20
          ? LocationAccuracy.medium
          : LocationAccuracy.high;
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
              if (mounted) {
                _updateCurrentLocation(position);
              } else {
                print('⚠️ Position update ignored - widget not mounted');
              }
            },
            onError: (error) {
              debugPrint('Position stream error: $error');
              if (mounted) {
                setState(() {
                  _errorMessage = 'GPS tracking error: $error';
                });
                Future.delayed(Duration(seconds: 5), () {
                  if (mounted && _isLocationServiceEnabled) {
                    _startLocationTracking();
                  }
                });
              }
            },
          );

      final updateInterval = _batteryLevel < 20
          ? Duration(minutes: 2)
          : Duration(seconds: 30);
      _locationTimer?.cancel();
      _locationTimer = Timer.periodic(updateInterval, (timer) {
        if (mounted && _isLocationServiceEnabled) {
          _getCurrentLocation();
        } else {
          print('🛑 Canceling location timer - widget disposed');
          timer.cancel();
        }
      });
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to start tracking: $e';
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isLocationServiceEnabled) return;

    try {
      _showMessage('Getting current location...', isSuccess: false);

      final locationSettings = LocationSettings(
        accuracy: _batteryLevel < 20
            ? LocationAccuracy.medium
            : LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
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
      _showMessage('Location updated!', isSuccess: true);
    } catch (e) {
      debugPrint('Error getting location: $e');
      try {
        Position? lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _updateCurrentLocation(lastPosition);
          _showMessage('Using last known location', isWarning: true);
        } else {
          _showMessage('Unable to get location', isDanger: true);
        }
      } catch (e2) {
        debugPrint('Error getting last known position: $e2');
        _showMessage('Location service error', isDanger: true);
      }
    }
  }

  void _updateCurrentLocation(Position position) {
    if (!mounted) {
      print('⚠️ Skipping location update - widget not mounted');
      return;
    }

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

    if (widget.onLocationShare != null) {
      widget.onLocationShare!(locationModel);
    }

    if (_currentEmergencyLevel.index >= EmergencyLevel.warning.index ||
        _sosMode) {
      _saveCurrentLocation(silent: true);
    }
  }

  void _activateSOS() {
    if (!mounted) {
      print('⚠️ Skipping SOS activation - widget not mounted');
      return;
    }

    setState(() {
      _sosMode = true;
      _currentEmergencyLevel = EmergencyLevel.critical;
    });

    _sosAnimationController.repeat(reverse: true);
    _showMessage('SOS ACTIVATED! Broadcasting location...', isDanger: true);
    _optimizeLocationUpdates();

    _sendSOSLocation();

    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_sosMode && mounted) {
        _sendSOSLocation();
      } else {
        timer.cancel();
      }
    });
  }

  void _deactivateSOS() {
    if (!mounted) return;

    setState(() {
      _sosMode = false;
      _currentEmergencyLevel = EmergencyLevel.safe;
    });

    _sosTimer?.cancel();
    _sosTimer = null;
    _sosAnimationController.stop();
    _sosAnimationController.reset();

    _optimizeLocationUpdates();
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

    debugPrint('💾 Saving SOS location to SQLite...');
    await LocationService.insertLocation(sosLocation);

    if (_isConnected) {
      try {
        debugPrint('🔄 Syncing SOS location to Firebase...');
        await FirebaseLocationService.syncLocation(sosLocation);
        _showMessage('SOS location broadcast to cloud!', isDanger: true);
      } catch (e) {
        debugPrint('❌ Firebase sync failed: $e');
        _showMessage(
          'SOS saved locally - will sync when online',
          isWarning: true,
        );
      }
    } else {
      _showMessage('SOS saved locally - offline mode', isWarning: true);
    }

    try {
      debugPrint('📡 Broadcasting SOS via P2P...');
      if (widget.onLocationShare != null) {
        widget.onLocationShare!(sosLocation);
        _showMessage('SOS broadcast via P2P network!', isDanger: true);
      }
    } catch (e) {
      debugPrint('❌ P2P broadcast failed: $e');
      _showMessage('P2P broadcast failed', isDanger: true);
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

    debugPrint('💾 Saving location to SQLite...');
    await LocationService.insertLocation(location);
    if (!silent) _showMessage('Location saved locally!', isSuccess: true);

    if (_isConnected) {
      try {
        debugPrint('🔄 Syncing location to Firebase...');
        await FirebaseLocationService.syncLocation(location);
        if (!silent) _showMessage('Location synced to cloud!', isSuccess: true);
      } catch (e) {
        debugPrint('❌ Firebase sync failed: $e');
        if (!silent) {
          _showMessage('Location saved, sync pending', isWarning: true);
        }
      }
    }

    await _loadSavedLocations();
  }

  Future<void> _syncLocationsToFirebase() async {
    try {
      await FirebaseLocationService.syncAllUnsyncedLocations();
      await _loadSavedLocations();
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }

  void _showMessage(
    String message, {
    bool isSuccess = false,
    bool isWarning = false,
    bool isDanger = false,
  }) {
    if (!mounted) {
      print('⚠️ Message ignored - widget not mounted: $message');
      return;
    }

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
    if (!mounted) return;
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
    if (_currentLocation != null && _isMapReady) {
      _mapController.move(_currentLocation!, 16.0);
    } else if (_currentLocation == null) {
      _showMessage('No location available', isWarning: true);
    } else {
      _showMessage('Map not ready yet', isWarning: true);
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

            // Add stats section positioned at the left side
            Positioned(
              left: 0,
              top:
                  MediaQuery.of(context).size.height *
                  0.3, // Position it in the middle-left
              child: _buildStatsAndControls(),
            ),
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
        initialCenter: _currentLocation ?? const LatLng(14.5995, 120.9842),
        initialZoom: _currentLocation != null ? 15.0 : 13.0,
        maxZoom: 18.0,
        minZoom: 5.0,
        onLongPress: (tapPos, latLng) => _showLocationTypeDialog(),
        onMapReady: () {
          debugPrint('🗺️ Map is ready');
          setState(() {
            _isMapReady = true;
          });

          // Now safely use MapController
          if (_currentLocation != null) {
            _mapController.move(_currentLocation!, 15.0);
          }
        },
      ),
      children: [
        _buildTileLayer(),

        if (savedLocations.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: savedLocations
                    .take(50)
                    .map((loc) => LatLng(loc.latitude, loc.longitude))
                    .toList(),
                strokeWidth: 3.0,
                color: ResQLinkTheme.emergencyOrange.withAlpha(
                  (255 * 0.7).toInt(),
                ),
                pattern: StrokePattern.dashed(segments: [6.0, 4.0]),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_currentLocation != null)
              Marker(
                width: 80,
                height: 80,
                point: _currentLocation!,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
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
            ...savedLocations
                .take(50)
                .map(
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
                              color: location.getMarkerColor().withAlpha(
                                (255 * 0.5).toInt(),
                              ),
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

  Widget _buildTileLayer() {
    try {
      // Get current zoom level safely
      int currentZoom = 13; // Default zoom
      if (_isMapReady && _mapController.camera != null) {
        currentZoom = _mapController.camera.zoom.round();
      }

      // Get tile layer from map service with proper error handling
      final tileLayer = PhilippinesMapService.instance.getTileLayer(
        zoom: currentZoom,
      );

      debugPrint(
        '🗺️ Using tile layer with zoom: $currentZoom, online: $_isConnected',
      );
      return tileLayer;
    } catch (e) {
      debugPrint('❌ Error getting tile layer: $e');
      // Fallback to basic OpenStreetMap
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.resqlink.app',
        maxZoom: 19,
      );
    }
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Enhanced status panel with download info
            IntrinsicWidth(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.cardDark.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.cloud_done : Icons.cloud_off,
                          color: _isConnected
                              ? ResQLinkTheme.safeGreen
                              : ResQLinkTheme.offlineGray,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isConnected ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _isDownloadingMaps
                              ? Icons.download
                              : (_cacheInfo['cachedTiles'] > 0
                                    ? Icons.offline_pin
                                    : Icons.map),
                          color: _isDownloadingMaps
                              ? ResQLinkTheme.emergencyOrange
                              : (_cacheInfo['cachedTiles'] > 0
                                    ? ResQLinkTheme.safeGreen
                                    : Colors.white70),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _isDownloadingMaps
                                ? '${(_downloadProgress * 100).toInt()}%'
                                : 'Maps: ${_cacheInfo['cachedTiles'] ?? 0} tiles',
                            style: TextStyle(
                              color: _isDownloadingMaps
                                  ? ResQLinkTheme.emergencyOrange
                                  : Colors.white70,
                              fontSize: 10,
                              fontWeight: _isDownloadingMaps
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Download status indicator
                    if (_isDownloadingMaps) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 150,
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            ResQLinkTheme.emergencyOrange,
                          ),
                          minHeight: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_downloadedTiles/$_totalTiles tiles',
                        style: TextStyle(color: Colors.white70, fontSize: 8),
                      ),
                    ],

                    if (_batteryLevel < 20) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.battery_alert,
                            color: ResQLinkTheme.emergencyOrange,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Low Battery',
                            style: TextStyle(
                              color: ResQLinkTheme.emergencyOrange,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Control buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildControlButton(
                  icon: Icons.my_location,
                  onPressed: _centerOnCurrentLocation,
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.download,
                  onPressed: _downloadOfflineMaps,
                  isActive: _isDownloadingMaps,
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.info_outline,
                  onPressed: _showOfflineMapInfo,
                ),
                const SizedBox(height: 8),
                _buildControlButton(
                  icon: Icons.bug_report,
                  onPressed: _runFullDiagnostics,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runFullDiagnostics() async {
    debugPrint('🔍 === STARTING GPS DIAGNOSTICS ===');

    setState(() => _isLoading = true);

    try {
      // 1. Test SQLite
      debugPrint('💾 Testing SQLite...');
      final testLocation = LocationModel(
        latitude: 14.5995,
        longitude: 120.9842,
        timestamp: DateTime.now(),
        userId: widget.userId,
        type: LocationType.normal,
        message: 'Test location',
      );

      final locationId = await LocationService.insertLocation(testLocation);
      debugPrint('✅ SQLite: Location inserted with ID $locationId');

      final retrievedLocation = await LocationService.getLastKnownLocation();
      if (retrievedLocation != null) {
        debugPrint('✅ SQLite: Location retrieved successfully');
      } else {
        debugPrint('❌ SQLite: Failed to retrieve location');
      }

      // 2. Test Firebase
      debugPrint('☁️ Testing Firebase...');
      final firebaseConnected =
          await FirebaseLocationService.testFirebaseConnection();
      if (firebaseConnected) {
        debugPrint('✅ Firebase: Connection successful');

        try {
          await FirebaseLocationService.syncLocation(testLocation);
          debugPrint('✅ Firebase: Location sync successful');
        } catch (e) {
          debugPrint('❌ Firebase: Location sync failed: $e');
        }
      } else {
        debugPrint('❌ Firebase: Connection failed');
      }

      // 3. Test Offline Maps
      debugPrint('🗺️ Testing Offline Maps...');
      await PhilippinesMapService.instance.debugCacheStatus();
      final offlineReady = await PhilippinesMapService.instance
          .testOfflineCapability();
      debugPrint('📊 Offline maps ready: $offlineReady');

      // 4. Test P2P
      debugPrint('📡 Testing P2P...');
      final p2pConnected = widget.p2pService.isConnected;
      final p2pDevices = widget.p2pService.connectedDevices.length;
      debugPrint('📊 P2P connected: $p2pConnected, devices: $p2pDevices');

      // 5. Check unsynced count
      final unsyncedCount = await LocationService.getUnsyncedCount();
      debugPrint('📊 Unsynced locations: $unsyncedCount');

      // Show results
      _showDiagnosticResults(
        firebaseConnected,
        offlineReady,
        p2pConnected,
        unsyncedCount,
      );
    } catch (e) {
      debugPrint('❌ Diagnostics error: $e');
      _showMessage('Diagnostics failed: $e', isDanger: true);
    } finally {
      setState(() => _isLoading = false);
      debugPrint('🔍 === DIAGNOSTICS COMPLETED ===');
    }
  }

  void _showDiagnosticResults(
    bool firebase,
    bool offline,
    bool p2p,
    int unsynced,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Diagnostics Results',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDiagnosticRow('SQLite Storage', true),
            _buildDiagnosticRow('Firebase Sync', firebase),
            _buildDiagnosticRow('Offline Maps', offline),
            _buildDiagnosticRow('P2P Network', p2p),
            SizedBox(height: 8),
            Text(
              'Unsynced Locations: $unsynced',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.white)),
          ),
          if (unsynced > 0)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _forceSyncAll();
              },
              child: Text(
                'Sync All',
                style: TextStyle(color: ResQLinkTheme.primaryRed),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, bool status) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            status ? Icons.check_circle : Icons.error,
            color: status ? ResQLinkTheme.safeGreen : ResQLinkTheme.primaryRed,
            size: 16,
          ),
          SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Future<void> _forceSyncAll() async {
    try {
      _showMessage('Starting sync...', isSuccess: true);
      await FirebaseLocationService.syncAllUnsyncedLocations();
      _showMessage('All locations synced!', isSuccess: true);
    } catch (e) {
      _showMessage('Sync failed: $e', isDanger: true);
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? ResQLinkTheme.primaryRed.withValues(alpha: 0.9)
            : ResQLinkTheme.cardDark.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: _isDownloadingMaps && icon == Icons.download
                ? null
                : onPressed,
            iconSize: 24,
          ),

          // Enhanced progress indicator for download button
          if (_isDownloadingMaps && icon == Icons.download) ...[
            // Outer progress ring
            SizedBox(
              width: 45,
              height: 45,
              child: CircularProgressIndicator(
                value: _downloadProgress,
                strokeWidth: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            // Percentage text
            Positioned(
              bottom: -2,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.primaryRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(_downloadProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],

          // Download ready indicator
          if (!_isDownloadingMaps &&
              icon == Icons.download &&
              _cacheInfo['cachedTiles'] > 0)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ResQLinkTheme.safeGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Icon(Icons.check, color: Colors.white, size: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IntrinsicHeight(
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ResQLinkTheme.surfaceDark.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 12),

              // Download progress bar (only show when downloading)
              if (_isDownloadingMaps) ...[
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ResQLinkTheme.emergencyOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ResQLinkTheme.emergencyOrange.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.download,
                            color: ResQLinkTheme.emergencyOrange,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _downloadStatus,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toInt()}%',
                            style: TextStyle(
                              color: ResQLinkTheme.emergencyOrange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          ResQLinkTheme.emergencyOrange,
                        ),
                        minHeight: 4,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
              ],

              // Location info
              if (_lastKnownLocation != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Location',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${_lastKnownLocation!.latitude.toStringAsFixed(6)}, '
                            '${_lastKnownLocation!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _offlineMode ? 'OFFLINE MODE' : 'Last Update',
                            style: TextStyle(
                              color: _offlineMode
                                  ? ResQLinkTheme.emergencyOrange
                                  : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _formatTime(_lastKnownLocation!.timestamp),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Long press map to mark locations • Hold SOS for emergency',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Row(
                    children: [
                      if (_cacheInfo['cachedTiles'] > 0) ...[
                        Icon(
                          Icons.offline_pin,
                          color: ResQLinkTheme.safeGreen,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                      ],
                      GestureDetector(
                        onTap: _showOfflineMapInfo,
                        child: Icon(
                          Icons.info_outline,
                          color: Colors.white54,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOfflineMapInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Row(
          children: [
            Icon(
              _cacheInfo['cachedTiles'] > 0 ? Icons.offline_pin : Icons.map,
              color: _cacheInfo['cachedTiles'] > 0
                  ? ResQLinkTheme.safeGreen
                  : Colors.white70,
            ),
            SizedBox(width: 8),
            Text('Offline Maps', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Status', _downloadStatus),
            SizedBox(height: 8),
            _buildInfoRow('Cached Tiles', '${_cacheInfo['cachedTiles'] ?? 0}'),
            _buildInfoRow(
              'Storage Used',
              '${_cacheInfo['storageSizeMB'] ?? '0'} MB',
            ),

            if (_isDownloadingMaps) ...[
              SizedBox(height: 16),
              Text(
                'Download Progress',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  ResQLinkTheme.emergencyOrange,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${(_downloadProgress * 100).toStringAsFixed(1)}% ($_downloadedTiles/$_totalTiles tiles)',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],

            SizedBox(height: 16),
            Text(
              'Offline maps allow you to use GPS even without internet connection. '
              'Philippines base maps are pre-loaded.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (!_isDownloadingMaps) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await PhilippinesMapService.instance.clearCache(null);
                await _updateCacheInfo();
                _showMessage('User cache cleared', isSuccess: true);
              },
              child: Text(
                'Clear Cache',
                style: TextStyle(color: ResQLinkTheme.primaryRed),
              ),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusCard() {
    return Card(
      color: ResQLinkTheme.cardDark,
      elevation: 2,
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: widget.p2pService.isConnected == true
                      ? ResQLinkTheme.safeGreen
                      : ResQLinkTheme.warningYellow,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'P2P Network',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Spacer(),
                if (widget.p2pService.isDiscovering == true)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ResQLinkTheme
                          .emergencyOrange, // Use existing theme color
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                _buildStatusIndicator(
                  'Role',
                  widget.p2pService.currentRole.name.toUpperCase(),
                  widget.p2pService.isConnected == true
                      ? ResQLinkTheme.safeGreen
                      : Colors.grey,
                ),
                SizedBox(width: 16),
                _buildStatusIndicator(
                  'Devices',
                  '${widget.p2pService.connectedDevices.length}',
                  ResQLinkTheme.emergencyOrange, // Use existing theme color
                ),
              ],
            ),
            if (widget.p2pService.isConnected != true) ...[
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.search, size: 16),
                  label: Text('Find Devices'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ResQLinkTheme.primaryRed,
                    padding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: widget.p2pService.isDiscovering == true
                      ? null
                      : () async {
                          try {
                            await widget.p2pService.discoverDevices(
                              force: true,
                            );
                            if (mounted) {
                              _showMessage(
                                'Scanning for devices...',
                                isSuccess: true,
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              _showMessage(
                                'Failed to scan: $e',
                                isDanger: true,
                              );
                            }
                          }
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 4),
        Text('$label: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Add a new method for stats and controls section
  Widget _buildStatsAndControls() {
    return Column(
      children: [
        // Add P2P connection status if service is available
        _buildConnectionStatusCard(),

        // Existing battery and location stats
        Card(
          color: ResQLinkTheme.cardDark,
          elevation: 2,
          margin: EdgeInsets.all(8),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Battery status
                Row(
                  children: [
                    Icon(
                      _batteryLevel < 20
                          ? Icons.battery_alert
                          : Icons.battery_std,
                      color: _batteryLevel < 20
                          ? ResQLinkTheme.emergencyOrange
                          : ResQLinkTheme.safeGreen,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Battery: $_batteryLevel%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Location status
                Row(
                  children: [
                    Icon(
                      _isLocationServiceEnabled
                          ? Icons.location_on
                          : Icons.location_off,
                      color: _isLocationServiceEnabled
                          ? ResQLinkTheme.safeGreen
                          : ResQLinkTheme.primaryRed,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'GPS: ${_isLocationServiceEnabled ? "Active" : "Disabled"}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Saved locations count
                Row(
                  children: [
                    Icon(Icons.place, color: Colors.white70, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Saved Locations: ${savedLocations.length}',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),

                // Add emergency mode toggle if P2P service is available
                ...[
                  SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(
                      'Emergency Mode',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Auto-connect and broadcast location',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    value: widget.p2pService.emergencyMode,
                    onChanged: (value) {
                      widget.p2pService.emergencyMode = value;
                      if (mounted) {
                        setState(() {});
                        _showMessage(
                          value
                              ? 'Emergency mode activated'
                              : 'Emergency mode deactivated',
                          isSuccess: value,
                          isDanger: !value,
                        );
                      }
                    },
                    activeColor: ResQLinkTheme.primaryRed,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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

  void _showLocationDetails(LocationModel location) {
    if (!mounted) return;
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
                      // Check if map is ready before using MapController
                      if (_isMapReady) {
                        _mapController.move(
                          LatLng(location.latitude, location.longitude),
                          16.0,
                        );
                      } else {
                        _showMessage('Map not ready yet', isWarning: true);
                      }
                    },
                    icon: const Icon(Icons.map, color: Colors.white70),
                    label: const Text(
                      'View on Map',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      if (widget.onLocationShare != null &&
                          bool.fromEnvironment('dart.vm.product')) {
                        widget.onLocationShare!(location);
                        Navigator.pop(context);
                        _showMessage('Location shared!', isSuccess: true);
                      } else {
                        Navigator.pop(context);
                        _showMessage(
                          'P2P sharing disabled on emulator',
                          isWarning: true,
                        );
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
