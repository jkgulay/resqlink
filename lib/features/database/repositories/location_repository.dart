import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/location_model.dart';
import '../core/database_manager.dart';

/// Repository for location and GPS operations
class LocationRepository {
  static const String _locationsTable = 'locations';

  /// Get unsynced locations for cloud sync
  static Future<List<LocationModel>> getUnsyncedLocations() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _locationsTable,
        where: 'synced = 0',
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => LocationModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced locations: $e');
      return [];
    }
  }

  /// Get locations by user ID
  static Future<List<LocationModel>> getLocationsByUserId(String userId) async {
    try {
      final db = await DatabaseManager.database;

      // Query both locations table and messages table for location data
      final locationResults = await db.query(
        _locationsTable,
        where: 'userId = ?',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
      );

      final messageResults = await db.query(
        'messages',
        where: 'fromUser = ? AND (latitude IS NOT NULL AND longitude IS NOT NULL)',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
      );

      final locations = <LocationModel>[];

      // Add from locations table
      for (final row in locationResults) {
        locations.add(LocationModel.fromMap(row));
      }

      // Add from messages table (convert message to location)
      for (final row in messageResults) {
        if (row['latitude'] != null && row['longitude'] != null) {
          final location = LocationModel(
            id: row['id'] as int? ?? 0,
            userId: userId,
            latitude: row['latitude'] as double,
            longitude: row['longitude'] as double,
            timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
            type: (row['isEmergency'] as int? ?? 0) == 1 ? LocationType.emergency : LocationType.normal,
            message: row['message'] as String?, // Use message text from message
            synced: (row['synced'] as int? ?? 0) == 1,
            accuracy: 0.0, // Default accuracy for message-based locations
          );
          locations.add(location);
        }
      }

      // Sort by timestamp (newest first) and remove duplicates
      locations.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final uniqueLocations = <LocationModel>[];
      final seenCoordinates = <String>{};

      for (final location in locations) {
        final key = '${location.latitude.toStringAsFixed(6)}_${location.longitude.toStringAsFixed(6)}';
        if (!seenCoordinates.contains(key)) {
          seenCoordinates.add(key);
          uniqueLocations.add(location);
        }
      }

      return uniqueLocations;
    } catch (e) {
      debugPrint('❌ Error getting locations by user ID: $e');
      return [];
    }
  }

  /// Save a new location
  static Future<int> saveLocation(LocationModel location) async {
    try {
      final db = await DatabaseManager.database;

      final locationMap = {
        'userId': location.userId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracy': location.accuracy,
        'timestamp': location.timestamp.millisecondsSinceEpoch,
        'message': location.message,
        'type': location.type.toString(),
        'emergencyLevel': location.emergencyLevel?.index,
        'synced': location.synced ? 1 : 0,
        'syncAttempts': 0,
        'lastSyncAttempt': null,
      };

      final id = await db.insert(_locationsTable, locationMap);
      debugPrint('📍 Location saved: ${location.latitude}, ${location.longitude}');
      return id;
    } catch (e) {
      debugPrint('❌ Error saving location: $e');
      return -1;
    }
  }

  /// Mark location as synced
  static Future<void> markLocationSynced(DateTime timestamp) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _locationsTable,
        {'synced': 1},
        where: 'timestamp = ?',
        whereArgs: [timestamp.millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('❌ Error marking location as synced: $e');
    }
  }

  /// Increment location sync attempts
  static Future<void> incrementLocationSyncAttempts(DateTime timestamp) async {
    try {
      final db = await DatabaseManager.database;
      await db.rawUpdate(
        'UPDATE $_locationsTable SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ? WHERE timestamp = ?',
        [DateTime.now().millisecondsSinceEpoch, timestamp.millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('❌ Error incrementing location sync attempts: $e');
    }
  }

  /// Get locations within a specific time range
  static Future<List<LocationModel>> getLocationsByTimeRange({
    required String userId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _locationsTable,
        where: 'userId = ? AND timestamp >= ? AND timestamp <= ?',
        whereArgs: [
          userId,
          startTime.millisecondsSinceEpoch,
          endTime.millisecondsSinceEpoch,
        ],
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => LocationModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting locations by time range: $e');
      return [];
    }
  }

  /// Get emergency locations
  static Future<List<LocationModel>> getEmergencyLocations({String? userId}) async {
    try {
      final db = await DatabaseManager.database;
      final whereConditions = ['type = ?'];
      final whereArgs = <dynamic>[LocationType.emergency.toString()];

      if (userId != null) {
        whereConditions.add('userId = ?');
        whereArgs.add(userId);
      }

      final results = await db.query(
        _locationsTable,
        where: whereConditions.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
      );

      return results.map((row) => LocationModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting emergency locations: $e');
      return [];
    }
  }

  /// Get latest location for a user
  static Future<LocationModel?> getLatestLocation(String userId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _locationsTable,
        where: 'userId = ?',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      if (results.isNotEmpty) {
        return LocationModel.fromMap(results.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting latest location: $e');
      return null;
    }
  }

  /// Get locations within a radius of a point
  static Future<List<LocationModel>> getLocationsWithinRadius({
    required double centerLatitude,
    required double centerLongitude,
    required double radiusInMeters,
    String? userId,
  }) async {
    try {
      final db = await DatabaseManager.database;

      // Calculate approximate bounds for initial filtering
      const double metersPerDegree = 111320.0; // Approximate meters per degree
      final double latitudeDelta = radiusInMeters / metersPerDegree;
      final double longitudeDelta = radiusInMeters / (metersPerDegree * cos(centerLatitude * pi / 180));

      final whereConditions = [
        'latitude >= ? AND latitude <= ?',
        'longitude >= ? AND longitude <= ?',
      ];
      final whereArgs = <dynamic>[
        centerLatitude - latitudeDelta,
        centerLatitude + latitudeDelta,
        centerLongitude - longitudeDelta,
        centerLongitude + longitudeDelta,
      ];

      if (userId != null) {
        whereConditions.add('userId = ?');
        whereArgs.add(userId);
      }

      final results = await db.query(
        _locationsTable,
        where: whereConditions.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
      );

      // Filter by exact distance
      final locations = results.map((row) => LocationModel.fromMap(row)).where((location) {
        final distance = _calculateDistance(
          centerLatitude, centerLongitude,
          location.latitude, location.longitude,
        );
        return distance <= radiusInMeters;
      }).toList();

      return locations;
    } catch (e) {
      debugPrint('❌ Error getting locations within radius: $e');
      return [];
    }
  }

  /// Calculate distance between two points in meters
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Get location statistics
  static Future<Map<String, dynamic>> getLocationStats({String? userId}) async {
    try {
      final db = await DatabaseManager.database;
      final whereCondition = userId != null ? 'WHERE userId = ?' : '';
      final whereArgs = userId != null ? [userId] : <dynamic>[];

      final totalLocations = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_locationsTable $whereCondition', whereArgs),
      ) ?? 0;

      final emergencyLocations = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $_locationsTable $whereCondition${userId != null ? " AND" : "WHERE"} type = ?',
          [...whereArgs, LocationType.emergency.toString()],
        ),
      ) ?? 0;

      final unsyncedLocations = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $_locationsTable $whereCondition${userId != null ? " AND" : "WHERE"} synced = 0',
          whereArgs,
        ),
      ) ?? 0;

      // Get date range
      final firstLocationResult = await db.rawQuery(
        'SELECT MIN(timestamp) as first FROM $_locationsTable $whereCondition',
        whereArgs,
      );
      final lastLocationResult = await db.rawQuery(
        'SELECT MAX(timestamp) as last FROM $_locationsTable $whereCondition',
        whereArgs,
      );

      final firstLocation = firstLocationResult.isNotEmpty && firstLocationResult.first['first'] != null
          ? DateTime.fromMillisecondsSinceEpoch(firstLocationResult.first['first'] as int)
          : null;
      final lastLocation = lastLocationResult.isNotEmpty && lastLocationResult.first['last'] != null
          ? DateTime.fromMillisecondsSinceEpoch(lastLocationResult.first['last'] as int)
          : null;

      return {
        'totalLocations': totalLocations,
        'emergencyLocations': emergencyLocations,
        'normalLocations': totalLocations - emergencyLocations,
        'unsyncedLocations': unsyncedLocations,
        'syncedLocations': totalLocations - unsyncedLocations,
        'firstLocation': firstLocation?.toIso8601String(),
        'lastLocation': lastLocation?.toIso8601String(),
        'trackingDays': firstLocation != null && lastLocation != null
            ? lastLocation.difference(firstLocation).inDays + 1
            : 0,
      };
    } catch (e) {
      debugPrint('❌ Error getting location stats: $e');
      return {};
    }
  }

  /// Clean up old locations
  static Future<int> cleanupOldLocations({Duration? olderThan, bool keepEmergency = true}) async {
    try {
      final cutoffDate = DateTime.now().subtract(olderThan ?? const Duration(days: 90));
      final db = await DatabaseManager.database;

      final whereCondition = keepEmergency
          ? 'timestamp < ? AND type != ?'
          : 'timestamp < ?';

      final whereArgs = keepEmergency
          ? [cutoffDate.millisecondsSinceEpoch, LocationType.emergency.toString()]
          : [cutoffDate.millisecondsSinceEpoch];

      final result = await db.delete(
        _locationsTable,
        where: whereCondition,
        whereArgs: whereArgs,
      );

      debugPrint('🧹 Cleaned up $result old locations');
      return result;
    } catch (e) {
      debugPrint('❌ Error cleaning up old locations: $e');
      return 0;
    }
  }

  /// Export locations for a user
  static Future<Map<String, dynamic>> exportLocations(String userId) async {
    try {
      final locations = await getLocationsByUserId(userId);
      final stats = await getLocationStats(userId: userId);

      return {
        'exportDate': DateTime.now().toIso8601String(),
        'userId': userId,
        'statistics': stats,
        'locationCount': locations.length,
        'locations': locations.map((location) => {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy,
          'timestamp': location.timestamp.toIso8601String(),
          'message': location.message,
          'type': location.type.toString(),
          'emergencyLevel': location.emergencyLevel?.toString(),
        }).toList(),
      };
    } catch (e) {
      debugPrint('❌ Error exporting locations: $e');
      return {};
    }
  }

  /// Batch insert locations
  static Future<void> insertBatchLocations(List<LocationModel> locations) async {
    try {
      await DatabaseManager.transaction((txn) async {
        for (final location in locations) {
          final locationMap = {
            'userId': location.userId,
            'latitude': location.latitude,
            'longitude': location.longitude,
            'accuracy': location.accuracy,
            'timestamp': location.timestamp.millisecondsSinceEpoch,
            'message': location.message,
            'type': location.type.toString(),
            'emergencyLevel': location.emergencyLevel?.index,
            'synced': location.synced ? 1 : 0,
            'syncAttempts': 0,
            'lastSyncAttempt': null,
          };

          await txn.insert(_locationsTable, locationMap);
        }
      });

      debugPrint('✅ Inserted ${locations.length} locations in batch');
    } catch (e) {
      debugPrint('❌ Error inserting location batch: $e');
    }
  }

  /// Delete all locations for a user
  static Future<bool> deleteAllLocations(String userId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.delete(
        _locationsTable,
        where: 'userId = ?',
        whereArgs: [userId],
      );

      debugPrint('🗑️ Deleted $result locations for user: $userId');
      return result > 0;
    } catch (e) {
      debugPrint('❌ Error deleting locations: $e');
      return false;
    }
  }
}

