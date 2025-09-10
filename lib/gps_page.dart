import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

// Import your widgets and controllers
import 'controllers/gps_controller.dart';
import 'services/p2p_service.dart';
import 'utils/resqlink_theme.dart';
import 'widgets/gps/gps_enhanced_map.dart';
import 'widgets/gps/gps_action_button_card.dart';
import 'widgets/gps/gps_location_card.dart';
import 'widgets/gps/gps_button_card.dart';
import 'widgets/gps/gps_panel_card.dart';
import 'widgets/gps/gps_location_details_dialog.dart';

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

// Location Service (same as your existing one)
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
            batteryLevel INTEGER,
            accuracy REAL,
            altitude REAL,
            speed REAL,
            heading REAL
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
          await db.execute('ALTER TABLE $_tableName ADD COLUMN accuracy REAL');
          await db.execute('ALTER TABLE $_tableName ADD COLUMN altitude REAL');
          await db.execute('ALTER TABLE $_tableName ADD COLUMN speed REAL');
          await db.execute('ALTER TABLE $_tableName ADD COLUMN heading REAL');
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

// Firebase Location Service (same as your existing one)
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

// Main GPS Page Widget
class GpsPage extends StatefulWidget {
  final String? userId;
  final Function(LocationModel)? onLocationShare;
  final P2PConnectionService p2pService;

  const GpsPage({
    super.key,
    this.userId,
    this.onLocationShare,
    required this.p2pService,
  });

  @override
  State<GpsPage> createState() => _GpsPageState();
}

class _GpsPageState extends State<GpsPage> {
  final MapController _mapController = MapController();
  late GpsController _gpsController;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _gpsController = GpsController(
      widget.p2pService,
      userId: widget.userId,
      onLocationShare: widget.onLocationShare,
    );

    // Set context after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gpsController.setContext(context);
    });
  }

  @override
  void dispose() {
    _gpsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GpsController>.value(
      value: _gpsController,
      child: Consumer<GpsController>(
        builder: (context, controller, child) {
          // Handle loading state
          if (controller.isLoading) {
            return _buildLoadingScreen();
          }

          // Handle error state
          if (controller.errorMessage.isNotEmpty &&
              !controller.isLocationServiceEnabled) {
            return _buildErrorScreen(controller);
          }

          // Main GPS interface
          return _buildMainInterface(controller);
        },
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

  Widget _buildErrorScreen(GpsController controller) {
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
                controller.errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => controller.retryInitialization(),
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

  Widget _buildMainInterface(GpsController controller) {
    return Theme(
      data: ThemeData.dark().copyWith(
        primaryColor: ResQLinkTheme.primaryRed,
        scaffoldBackgroundColor: ResQLinkTheme.backgroundDark,
      ),
      child: Scaffold(
        backgroundColor: ResQLinkTheme.backgroundDark,
        body: Stack(
          children: [
            // Enhanced Map
            GpsEnhancedMap(
              mapController: _mapController,
              onMapTap: _handleMapTap,
              onMapLongPress: _handleMapLongPress,
              onLocationTap: _handleLocationTap,
              showCurrentLocation: true,
              showSavedLocations: true,
              showTrackingPath: controller.showTrackingPath,
              showEmergencyZones: controller.showEmergencyZones,
              showCriticalInfrastructure: controller.showCriticalInfrastructure,
            ),

            // Top Status Panel
            const GpsStatsPanel(),

            // Action Buttons (Right side)
            GpsActionButtons(
              onLocationDetailsRequest: _showLocationDetailsRequest,
              onCenterCurrentLocation: _centerOnCurrentLocation,
            ),

            // Emergency SOS Button
            const GpsEmergencyButton(),

            // Bottom Location List
            GpsLocationList(
              onLocationSelected: _handleLocationSelected,
              onLocationShare: _handleLocationShare,
            ),

            // Download Progress Indicator (if downloading)
            if (controller.isDownloadingMaps)
              _buildDownloadProgressOverlay(controller),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgressOverlay(GpsController controller) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ResQLinkTheme.cardDark.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ResQLinkTheme.emergencyOrange.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.download,
                  color: ResQLinkTheme.emergencyOrange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.downloadStatus,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${(controller.downloadProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: ResQLinkTheme.emergencyOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: controller.downloadProgress,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                ResQLinkTheme.emergencyOrange,
              ),
              minHeight: 4,
            ),
            const SizedBox(height: 4),
            Text(
              '${controller.downloadedTiles}/${controller.totalTiles} tiles',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Event Handlers
  void _handleMapTap(LatLng point) {
    debugPrint('Map tapped at: ${point.latitude}, ${point.longitude}');
  }

  void _handleMapLongPress(LatLng point) {
    _showLocationTypeDialog(point);
  }

  void _handleLocationTap(LocationModel location) {
    _showLocationDetails(location);
  }

  void _handleLocationSelected(LocationModel location) {
    // Move map to location and show details
    _mapController.move(LatLng(location.latitude, location.longitude), 16.0);
    _showLocationDetails(location);
  }

  void _handleLocationShare(LocationModel location) {
    _gpsController.shareLocation(location);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Location shared via P2P network'),
        backgroundColor: ResQLinkTheme.safeGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _centerOnCurrentLocation() {
    if (_gpsController.currentLocation != null) {
      _mapController.move(_gpsController.currentLocation!, 16.0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No current location available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showLocationDetailsRequest() {
    if (_gpsController.savedLocations.isNotEmpty) {
      _showLocationDetails(_gpsController.savedLocations.first);
    }
  }

  void _showLocationDetails(LocationModel location) {
    showDialog(
      context: context,
      builder: (context) => GpsLocationDetailsDialog(
        location: location,
        onLocationShare: (location) => _handleLocationShare(location),
      ),
    );
  }

  void _showLocationTypeDialog(LatLng point) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: const Text(
          'Mark Location Type',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: LocationType.values.map((type) {
              return _buildLocationTypeOption(type, point);
            }).toList(),
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
      ),
    );
  }

  Widget _buildLocationTypeOption(LocationType type, LatLng point) {
    final color = _getLocationTypeColor(type);
    final icon = _getLocationTypeIcon(type);
    final label = _getLocationTypeLabel(type);

    return ListTile(
      leading: Icon(icon, color: color, size: 30),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.of(context).pop();
        _markLocationAtPoint(type, point);
      },
    );
  }

  void _markLocationAtPoint(LocationType type, LatLng point) async {
    final location = LocationModel(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: DateTime.now(),
      userId: widget.userId,
      type: type,
      emergencyLevel: _gpsController.currentEmergencyLevel,
      batteryLevel: _gpsController.batteryLevel,
    );

    await LocationService.insertLocation(location);
    await _gpsController.shareLocation(location);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_getLocationTypeLabel(type)} marked successfully'),
          backgroundColor: ResQLinkTheme.safeGreen,
        ),
      );
    }
  }

  // Helper methods for location types
  Color _getLocationTypeColor(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return Colors.blue;
      case LocationType.emergency:
      case LocationType.sos:
        return ResQLinkTheme.primaryRed;
      case LocationType.safezone:
        return ResQLinkTheme.safeGreen;
      case LocationType.hazard:
        return Colors.orange;
      case LocationType.evacuationPoint:
        return Colors.purple;
      case LocationType.medicalAid:
        return Colors.red;
      case LocationType.supplies:
        return Colors.cyan;
    }
  }

  IconData _getLocationTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return Icons.location_on;
      case LocationType.emergency:
      case LocationType.sos:
        return Icons.emergency;
      case LocationType.safezone:
        return Icons.shield;
      case LocationType.hazard:
        return Icons.warning;
      case LocationType.evacuationPoint:
        return Icons.exit_to_app;
      case LocationType.medicalAid:
        return Icons.medical_services;
      case LocationType.supplies:
        return Icons.inventory;
    }
  }

  String _getLocationTypeLabel(LocationType type) {
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
}
