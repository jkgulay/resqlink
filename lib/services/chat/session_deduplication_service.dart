import 'package:flutter/foundation.dart';
import '../../features/database/repositories/chat_repository.dart';
import '../../features/database/core/database_manager.dart';
import '../../utils/session_id_helper.dart';

/// Service to identify and merge duplicate chat sessions
/// UPDATED: Now uses MAC address-based deduplication (deviceAddress)
class SessionDeduplicationService {
  /// Run comprehensive deduplication of chat sessions
  /// CRITICAL: Uses MAC address (deviceAddress) as stable identifier
  static Future<int> deduplicateAllSessions() async {
    try {
      debugPrint('🔍 Starting MAC address-based session deduplication...');

      // The ChatRepository.cleanupDuplicateSessions() now uses MAC address-based logic
      // This handles ALL deduplication scenarios including:
      // - Multiple sessions with same deviceAddress
      // - Old display name-based session IDs
      // - Sessions without deviceAddress set
      final totalMerged = await ChatRepository.cleanupDuplicateSessions();

      if (totalMerged > 0) {
        debugPrint(
          '✅ Session deduplication completed: $totalMerged sessions merged',
        );
      } else {
        debugPrint('ℹ️ No duplicate sessions found');
      }

      return totalMerged;
    } catch (e) {
      debugPrint('❌ Error during session deduplication: $e');
      return 0;
    }
  }

  /// Check if a specific device has duplicate sessions by MAC address
  static Future<List<String>> findDuplicateSessionsForDevice(
    String deviceAddress,
  ) async {
    try {
      final db = await DatabaseManager.database;

      // Find all sessions with the same device address
      final sessions = await db.query(
        'chat_sessions',
        where: 'device_address = ? OR device_id = ?',
        whereArgs: [deviceAddress, deviceAddress],
      );

      return sessions.map((s) => s['id'] as String).toList();
    } catch (e) {
      debugPrint('❌ Error finding duplicates for device: $e');
      return [];
    }
  }

  /// Generate stats about current session state based on MAC addresses
  static Future<Map<String, dynamic>> getSessionStats() async {
    try {
      final db = await DatabaseManager.database;

      final totalSessions = await db.rawQuery(
        'SELECT COUNT(*) as count FROM chat_sessions',
      );
      final totalMessages = await db.rawQuery(
        'SELECT COUNT(*) as count FROM messages',
      );

      // Find potential duplicates by device address (MAC address)
      final deviceGroups = await db.rawQuery('''
        SELECT device_address, COUNT(*) as count
        FROM chat_sessions
        WHERE device_address IS NOT NULL AND device_address != ''
        GROUP BY device_address
        HAVING count > 1
      ''');

      // Find sessions without proper MAC address-based IDs
      final sessions = await db.query('chat_sessions');
      int needsMigration = 0;

      for (final session in sessions) {
        final currentId = session['id'] as String;
        final deviceAddress = session['device_address'] as String?;
        final deviceId = session['device_id'] as String?;

        final stableId = deviceAddress ?? deviceId;
        if (stableId != null) {
          final correctId = SessionIdHelper.buildSessionId(stableId);
          if (currentId != correctId) {
            needsMigration++;
          }
        }
      }

      return {
        'totalSessions': (totalSessions.first['count'] as int?) ?? 0,
        'totalMessages': (totalMessages.first['count'] as int?) ?? 0,
        'potentialDuplicates': deviceGroups.length,
        'sessionsNeedingMigration': needsMigration,
        'duplicateGroups': deviceGroups,
      };
    } catch (e) {
      debugPrint('❌ Error getting session stats: $e');
      return {};
    }
  }
}
