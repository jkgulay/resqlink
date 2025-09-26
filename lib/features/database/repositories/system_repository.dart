import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../../models/message_model.dart';
import '../core/database_manager.dart';
import 'message_repository.dart';
import 'location_repository.dart';
import 'device_repository.dart';
import 'user_repository.dart';
import 'chat_repository.dart';
import 'sync_repository.dart';

/// Repository for system operations, health monitoring, and statistics
class SystemRepository {
  static Timer? _healthCheckTimer;
  static const Duration _healthCheckInterval = Duration(minutes: 5);

  /// Start health monitoring
  static void startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      _performHealthCheck();
    });
    debugPrint('🏥 System health monitoring started');
  }

  /// Stop health monitoring
  static void stopHealthCheck() {
    _healthCheckTimer?.cancel();
    debugPrint('🏥 System health monitoring stopped');
  }

  /// Perform comprehensive health check
  static Future<void> _performHealthCheck() async {
    try {
      final healthStatus = await getSystemHealth();

      if (!healthStatus['database']['healthy']) {
        debugPrint('🚨 Database health check failed!');
        // Attempt recovery
        await DatabaseManager.checkDatabaseHealth();
      }

      if (healthStatus['storage']['usage'] > 90) {
        debugPrint('⚠️ Storage usage critical: ${healthStatus['storage']['usage']}%');
        await performSystemCleanup();
      }

      debugPrint('🏥 Health check completed');
    } catch (e) {
      debugPrint('❌ Health check error: $e');
    }
  }

  /// Get comprehensive database statistics
  static Future<Map<String, int>> getDatabaseStats() async {
    try {
      final db = await DatabaseManager.database;

      final messageCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM messages'),
      ) ?? 0;

      final locationCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM locations'),
      ) ?? 0;

      final userCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM users'),
      ) ?? 0;

      final deviceCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM devices'),
      ) ?? 0;

      final chatSessionCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM chat_sessions'),
      ) ?? 0;

      final syncQueueCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM sync_queue'),
      ) ?? 0;

      return {
        'messages': messageCount,
        'locations': locationCount,
        'users': userCount,
        'devices': deviceCount,
        'chatSessions': chatSessionCount,
        'syncQueue': syncQueueCount,
      };
    } catch (e) {
      debugPrint('❌ Error getting database stats: $e');
      return {};
    }
  }

  /// Get enhanced database statistics with performance metrics
  static Future<Map<String, dynamic>> getEnhancedDatabaseStats() async {
    try {
      final basicStats = await getDatabaseStats();
      final db = await DatabaseManager.database;

      // P2P-specific stats
      final p2pSessions = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM p2p_sessions'),
      ) ?? 0;

      final emergencySessions = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM p2p_sessions WHERE emergencySession = 1'),
      ) ?? 0;

      final avgSessionDuration = Sqflite.firstIntValue(
        await db.rawQuery('SELECT AVG(duration) FROM p2p_sessions WHERE duration IS NOT NULL'),
      ) ?? 0;

      final compatibilityEntries = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM device_compatibility'),
      ) ?? 0;

      // Message stats by type
      final emergencyMessages = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM messages WHERE isEmergency = 1'),
      ) ?? 0;

      final unsyncedMessages = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM messages WHERE synced = 0'),
      ) ?? 0;

      final failedMessages = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM messages WHERE status = ?', [MessageStatus.failed.index]),
      ) ?? 0;

      // Storage information
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'resqlink_enhanced.db'));
      final dbSize = await dbFile.exists() ? await dbFile.length() : 0;

      // Memory usage (approximate)
      final tableStats = await _getTableSizes(db);

      return {
        ...basicStats,
        'p2pSessions': p2pSessions,
        'emergencySessions': emergencySessions,
        'normalSessions': p2pSessions - emergencySessions,
        'avgSessionDuration': avgSessionDuration,
        'compatibilityEntries': compatibilityEntries,
        'emergencyMessages': emergencyMessages,
        'unsyncedMessages': unsyncedMessages,
        'failedMessages': failedMessages,
        'databaseSize': dbSize,
        'databaseSizeMB': (dbSize / (1024 * 1024)).toStringAsFixed(2),
        'tableStats': tableStats,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Error getting enhanced database stats: $e');
      return {};
    }
  }

  /// Get table sizes for storage analysis
  static Future<Map<String, int>> _getTableSizes(Database db) async {
    final tables = ['messages', 'locations', 'users', 'devices', 'chat_sessions', 'p2p_sessions', 'sync_queue'];
    final sizes = <String, int>{};

    for (final table in tables) {
      try {
        final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        ) ?? 0;
        sizes[table] = count;
      } catch (e) {
        sizes[table] = 0;
      }
    }

    return sizes;
  }

  /// Get system health status
  static Future<Map<String, dynamic>> getSystemHealth() async {
    try {
      final health = <String, dynamic>{};

      // Database health
      final dbHealthy = await DatabaseManager.checkDatabaseHealth();
      health['database'] = {
        'healthy': dbHealthy,
        'lastCheck': DateTime.now().toIso8601String(),
      };

      // Storage health
      final storageInfo = await _getStorageInfo();
      health['storage'] = storageInfo;

      // Sync health
      final syncStats = await SyncRepository.getSyncStats();
      health['sync'] = {
        'healthy': !(syncStats['failedItems'] > 10 || syncStats['queueSize'] > 100),
        'stats': syncStats,
      };

      // Memory health (basic check)
      health['memory'] = {
        'healthy': true, // Flutter doesn't provide easy memory stats
        'note': 'Memory monitoring limited in Flutter',
      };

      // Performance metrics
      final startTime = DateTime.now();
      await DatabaseManager.rawQuery('SELECT 1');
      final dbLatency = DateTime.now().difference(startTime).inMilliseconds;

      health['performance'] = {
        'dbLatency': dbLatency,
        'healthy': dbLatency < 100, // Consider healthy if DB responds in < 100ms
      };

      return health;
    } catch (e) {
      debugPrint('❌ Error getting system health: $e');
      return {
        'error': e.toString(),
        'healthy': false,
      };
    }
  }

  /// Get storage information
  static Future<Map<String, dynamic>> _getStorageInfo() async {
    try {
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'resqlink_enhanced.db'));

      if (!await dbFile.exists()) {
        return {
          'healthy': true,
          'usage': 0,
          'size': 0,
          'note': 'Database file not found',
        };
      }

      final dbSize = await dbFile.length();
      final directory = Directory(dbPath);

      // Get available space (approximation)
      await directory.stat(); // Check if directory exists
      const maxSize = 100 * 1024 * 1024; // Assume 100MB max for mobile apps
      final usage = (dbSize / maxSize * 100).round();

      return {
        'healthy': usage < 80,
        'usage': usage,
        'size': dbSize,
        'sizeMB': (dbSize / (1024 * 1024)).toStringAsFixed(2),
        'maxSizeMB': (maxSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('❌ Error getting storage info: $e');
      return {
        'healthy': false,
        'error': e.toString(),
      };
    }
  }

  /// Perform comprehensive system cleanup
  static Future<Map<String, int>> performSystemCleanup() async {
    final results = <String, int>{};

    try {
      debugPrint('🧹 Starting system cleanup...');

      // Clean old messages (older than 30 days)
      results['oldMessages'] = await MessageRepository.deleteOldMessages(Duration(days: 30));

      // Clean failed messages (older than 7 days)
      results['failedMessages'] = await MessageRepository.cleanupFailedMessages();

      // Clean old locations (older than 90 days, keep emergency)
      results['oldLocations'] = await LocationRepository.cleanupOldLocations();

      // Clean old P2P sessions (older than 30 days, keep emergency)
      results['oldSessions'] = await DeviceRepository.cleanupOldSessions();

      // Clean old chat sessions (older than 90 days)
      results['oldChatSessions'] = await ChatRepository.cleanupOldSessions();

      // Clear sync queue failures
      final db = await DatabaseManager.database;
      results['syncFailures'] = await db.delete(
        'sync_queue',
        where: 'sync_attempts >= 3 AND created_at < ?',
        whereArgs: [DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch],
      );

      // Vacuum database to reclaim space
      await db.execute('VACUUM');
      results['vacuum'] = 1;

      final total = results.values.fold(0, (sum, count) => sum + count);
      debugPrint('✅ System cleanup completed: $total items cleaned');

      return results;
    } catch (e) {
      debugPrint('❌ Error during system cleanup: $e');
      results['error'] = -1;
      return results;
    }
  }

  /// Clear all data (nuclear option)
  static Future<bool> clearAllData() async {
    try {
      debugPrint('🚨 Clearing ALL data...');

      final db = await DatabaseManager.database;

      // Clear all tables
      final tables = ['messages', 'locations', 'users', 'devices', 'chat_sessions', 'p2p_sessions', 'sync_queue', 'device_compatibility', 'known_devices', 'pending_messages'];

      for (final table in tables) {
        try {
          await db.delete(table);
        } catch (e) {
          debugPrint('⚠️ Error clearing table $table: $e');
        }
      }

      // Vacuum to reclaim space
      await db.execute('VACUUM');

      debugPrint('✅ All data cleared');
      return true;
    } catch (e) {
      debugPrint('❌ Error clearing all data: $e');
      return false;
    }
  }

  static Future<void> deleteDatabaseFile() async {
    try {
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'resqlink_enhanced.db'));

      if (await dbFile.exists()) {
        await dbFile.delete();
        debugPrint('🗑️ Database file deleted');
      }
    } catch (e) {
      debugPrint('❌ Error deleting database file: $e');
    }
  }

  /// Get comprehensive system report
  static Future<Map<String, dynamic>> getSystemReport() async {
    try {
      final report = <String, dynamic>{};

      // Basic stats
      report['databaseStats'] = await getDatabaseStats();

      // Enhanced stats
      report['enhancedStats'] = await getEnhancedDatabaseStats();

      // Health status
      report['health'] = await getSystemHealth();

      // Repository-specific stats
      report['messageStats'] = await MessageRepository.getMessageStats('all');
      report['locationStats'] = await LocationRepository.getLocationStats();
      report['deviceStats'] = await DeviceRepository.getP2PSessionStats();
      report['userStats'] = await UserRepository.getUserStats();
      report['chatStats'] = {'totalSessions': report['databaseStats']['chatSessions']};
      report['syncStats'] = await SyncRepository.getSyncStats();

      // System info
      report['systemInfo'] = {
        'platform': Platform.operatingSystem,
        'timestamp': DateTime.now().toIso8601String(),
        'databaseVersion': 4,
      };

      return report;
    } catch (e) {
      debugPrint('❌ Error generating system report: $e');
      return {'error': e.toString()};
    }
  }

  /// Export system report to JSON
  static Future<String> exportSystemReport() async {
    try {
      final report = await getSystemReport();
      // In a real implementation, you'd save this to a file
      // For now, return as string
      return jsonEncode(report);
    } catch (e) {
      debugPrint('❌ Error exporting system report: $e');
      return '{"error": "$e"}';
    }
  }

  /// Optimize database performance
  static Future<bool> optimizeDatabase() async {
    try {
      debugPrint('⚡ Optimizing database...');
      final db = await DatabaseManager.database;

      // Analyze tables for query optimization
      await db.execute('ANALYZE');

      // Reindex all tables
      await db.execute('REINDEX');

      // Vacuum to defragment
      await db.execute('VACUUM');

      debugPrint('✅ Database optimization completed');
      return true;
    } catch (e) {
      debugPrint('❌ Error optimizing database: $e');
      return false;
    }
  }

  /// Get database integrity check
  static Future<bool> checkDatabaseIntegrity() async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.rawQuery('PRAGMA integrity_check');

      if (result.isNotEmpty && result.first.values.first == 'ok') {
        debugPrint('✅ Database integrity check passed');
        return true;
      } else {
        debugPrint('❌ Database integrity check failed: $result');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error checking database integrity: $e');
      return false;
    }
  }

  /// Dispose system monitoring
  static void dispose() {
    stopHealthCheck();
    debugPrint('🧹 System Repository disposed');
  }
}

