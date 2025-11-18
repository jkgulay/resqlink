import 'package:flutter/foundation.dart';
import '../features/database/core/database_manager.dart';
import '../services/chat/session_deduplication_service.dart';
import 'session_id_helper.dart';

/// Utility to check and ensure session consistency across the codebase
class SessionConsistencyChecker {
  /// Run comprehensive consistency check
  static Future<Map<String, dynamic>> runConsistencyCheck() async {
    try {
      debugPrint('🔍 Running session consistency check...');

      final results = <String, dynamic>{};
      final db = await DatabaseManager.database;

      // 1. Check session ID format consistency (MAC address-based)
      final sessions = await db.query('chat_sessions');

      int correctFormatCount = 0;
      int oldFormatCount = 0;
      final List<Map<String, dynamic>> inconsistentSessions = [];

      for (final session in sessions) {
        final sessionId = session['id'] as String;
        final deviceAddress = session['device_address'] as String?;
        final deviceId = session['device_id'] as String?;
        final deviceName = session['device_name'] as String;

        // Expected ID is based on MAC address (deviceAddress or deviceId)
        final stableId = deviceAddress ?? deviceId;
        final expectedId = stableId != null
            ? SessionIdHelper.buildSessionId(stableId)
            : null;

        if (expectedId != null && sessionId == expectedId) {
          correctFormatCount++;
        } else {
          oldFormatCount++;
          inconsistentSessions.add({
            'currentId': sessionId,
            'expectedId': expectedId ?? 'N/A (no MAC address)',
            'deviceName': deviceName,
            'deviceAddress': deviceAddress ?? deviceId ?? 'N/A',
          });
        }
      }

      results['sessionFormatCheck'] = {
        'totalSessions': sessions.length,
        'correctFormat': correctFormatCount,
        'needsMigration': oldFormatCount,
        'inconsistentSessions': inconsistentSessions,
      };

      // 2. Check for orphaned messages
      final orphanedMessages = await db.rawQuery('''
        SELECT m.messageId, m.chatSessionId, m.fromUser
        FROM messages m
        LEFT JOIN chat_sessions cs ON m.chatSessionId = cs.id
        WHERE cs.id IS NULL AND m.chatSessionId IS NOT NULL
      ''');

      results['orphanedMessages'] = {
        'count': orphanedMessages.length,
        'messages': orphanedMessages,
      };

      // 3. Check for duplicate device sessions
      final duplicateDevices = await db.rawQuery('''
        SELECT device_id, COUNT(*) as count, GROUP_CONCAT(id) as session_ids
        FROM chat_sessions
        GROUP BY device_id
        HAVING count > 1
      ''');

      results['duplicateDevices'] = {
        'count': duplicateDevices.length,
        'duplicates': duplicateDevices,
      };

      // 4. Check messages without session IDs
      final messagesWithoutSession = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM messages
        WHERE chatSessionId IS NULL OR chatSessionId = ""
      ''');

      results['messagesWithoutSession'] = {
        'count': (messagesWithoutSession.first['count'] as int?) ?? 0,
      };

      // 5. Check for sessions with no messages
      final emptySessions = await db.rawQuery('''
        SELECT cs.id, cs.device_name
        FROM chat_sessions cs
        LEFT JOIN messages m ON cs.id = m.chatSessionId
        WHERE m.chatSessionId IS NULL
      ''');

      results['emptySessions'] = {
        'count': emptySessions.length,
        'sessions': emptySessions,
      };

      // 6. Overall health score
      final totalIssues =
          oldFormatCount +
          orphanedMessages.length +
          duplicateDevices.length +
          (messagesWithoutSession.first['count'] as int? ?? 0);

      results['healthScore'] = {
        'totalIssues': totalIssues,
        'severity': _calculateSeverity(totalIssues, sessions.length),
        'recommendations': _getRecommendations(results),
      };

      debugPrint('✅ Consistency check completed. Total issues: $totalIssues');
      return results;
    } catch (e) {
      debugPrint('❌ Error during consistency check: $e');
      return {'error': e.toString()};
    }
  }

  /// Fix all detected inconsistencies
  static Future<bool> fixInconsistencies() async {
    try {
      debugPrint('🔧 Starting automatic inconsistency fixes...');

      // 1. Run session deduplication
      final mergedCount =
          await SessionDeduplicationService.deduplicateAllSessions();
      debugPrint('🔄 Merged $mergedCount duplicate sessions');

      // 2. Fix orphaned messages
      await _fixOrphanedMessages();

      // 3. Clean up empty sessions
      await _cleanupEmptySessions();

      // 4. Update message session IDs
      await _updateMessageSessionIds();

      debugPrint('✅ All inconsistencies fixed');
      return true;
    } catch (e) {
      debugPrint('❌ Error fixing inconsistencies: $e');
      return false;
    }
  }

  /// Fix orphaned messages by assigning them to correct sessions based on MAC address
  static Future<void> _fixOrphanedMessages() async {
    try {
      final db = await DatabaseManager.database;

      final orphanedMessages = await db.rawQuery('''
        SELECT m.id, m.messageId, m.chatSessionId, m.fromUser, m.endpointId, m.deviceId
        FROM messages m
        LEFT JOIN chat_sessions cs ON m.chatSessionId = cs.id
        WHERE cs.id IS NULL AND m.chatSessionId IS NOT NULL
      ''');

      for (final message in orphanedMessages) {
        final deviceId =
            message['deviceId'] as String? ?? message['endpointId'] as String?;
        if (deviceId == null) continue;

        // Generate correct session ID from MAC address
        final correctSessionId = SessionIdHelper.buildSessionId(deviceId);

        await db.update(
          'messages',
          {'chatSessionId': correctSessionId},
          where: 'id = ?',
          whereArgs: [message['id']],
        );
      }

      debugPrint('🔧 Fixed ${orphanedMessages.length} orphaned messages');
    } catch (e) {
      debugPrint('❌ Error fixing orphaned messages: $e');
    }
  }

  /// Clean up empty sessions
  static Future<void> _cleanupEmptySessions() async {
    try {
      final db = await DatabaseManager.database;

      final result = await db.rawDelete('''
        DELETE FROM chat_sessions
        WHERE id IN (
          SELECT cs.id
          FROM chat_sessions cs
          LEFT JOIN messages m ON cs.id = m.chatSessionId
          WHERE m.chatSessionId IS NULL
        )
      ''');

      debugPrint('🧹 Cleaned up $result empty sessions');
    } catch (e) {
      debugPrint('❌ Error cleaning up empty sessions: $e');
    }
  }

  /// Update messages without session IDs based on MAC address
  static Future<void> _updateMessageSessionIds() async {
    try {
      final db = await DatabaseManager.database;

      final messagesWithoutSession = await db.query(
        'messages',
        where: 'chatSessionId IS NULL OR chatSessionId = ""',
      );

      for (final message in messagesWithoutSession) {
        final deviceId =
            message['deviceId'] as String? ?? message['endpointId'] as String?;
        if (deviceId == null) continue;

        // Generate session ID from MAC address
        final sessionId = SessionIdHelper.buildSessionId(deviceId);

        await db.update(
          'messages',
          {'chatSessionId': sessionId},
          where: 'id = ?',
          whereArgs: [message['id']],
        );
      }

      debugPrint(
        '🔧 Updated ${messagesWithoutSession.length} messages with session IDs',
      );
    } catch (e) {
      debugPrint('❌ Error updating message session IDs: $e');
    }
  }

  /// Calculate severity based on number of issues
  static String _calculateSeverity(int totalIssues, int totalSessions) {
    if (totalIssues == 0) return 'PERFECT';

    final ratio = totalIssues / (totalSessions + 1);
    if (ratio > 0.5) return 'CRITICAL';
    if (ratio > 0.2) return 'HIGH';
    if (ratio > 0.1) return 'MEDIUM';
    return 'LOW';
  }

  /// Get recommendations based on results
  static List<String> _getRecommendations(Map<String, dynamic> results) {
    final recommendations = <String>[];

    final sessionFormatCheck =
        results['sessionFormatCheck'] as Map<String, dynamic>?;
    if ((sessionFormatCheck?['oldFormat'] as int? ?? 0) > 0) {
      recommendations.add(
        'Run SessionDeduplicationService.deduplicateAllSessions() to fix session ID formats',
      );
    }

    final orphanedMessages =
        results['orphanedMessages'] as Map<String, dynamic>?;
    if ((orphanedMessages?['count'] as int? ?? 0) > 0) {
      recommendations.add(
        'Fix orphaned messages by running SessionConsistencyChecker.fixInconsistencies()',
      );
    }

    final duplicateDevices =
        results['duplicateDevices'] as Map<String, dynamic>?;
    if ((duplicateDevices?['count'] as int? ?? 0) > 0) {
      recommendations.add('Merge duplicate device sessions');
    }

    final messagesWithoutSession =
        results['messagesWithoutSession'] as Map<String, dynamic>?;
    if ((messagesWithoutSession?['count'] as int? ?? 0) > 0) {
      recommendations.add('Assign session IDs to messages without sessions');
    }

    if (recommendations.isEmpty) {
      recommendations.add('All sessions are consistent! 🎉');
    }

    return recommendations;
  }

  /// Print formatted report
  static void printReport(Map<String, dynamic> results) {
    debugPrint('\n📊 SESSION CONSISTENCY REPORT');
    debugPrint('=' * 50);

    final healthScore = results['healthScore'] as Map<String, dynamic>?;
    if (healthScore != null) {
      debugPrint(
        '🏥 Health Score: ${healthScore['severity']} (${healthScore['totalIssues']} issues)',
      );
      debugPrint('');
    }

    final sessionFormatCheck =
        results['sessionFormatCheck'] as Map<String, dynamic>?;
    if (sessionFormatCheck != null) {
      debugPrint('📝 Session Format Check:');
      debugPrint('  - Total Sessions: ${sessionFormatCheck['totalSessions']}');
      debugPrint('  - Correct Format: ${sessionFormatCheck['correctFormat']}');
      debugPrint('  - Old Format: ${sessionFormatCheck['oldFormat']}');
      debugPrint('');
    }

    final recommendations =
        results['healthScore']?['recommendations'] as List<String>?;
    if (recommendations != null && recommendations.isNotEmpty) {
      debugPrint('💡 Recommendations:');
      for (final rec in recommendations) {
        debugPrint('  • $rec');
      }
      debugPrint('');
    }

    debugPrint('=' * 50);
  }
}
