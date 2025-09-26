import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../models/chat_session_model.dart';
import '../../../models/message_model.dart';
import '../core/database_manager.dart';

/// Repository for chat session operations
class ChatRepository {
  static const String _tableName = 'chat_sessions';

  /// Create or update a chat session with enhanced deduplication
  static Future<String> createOrUpdate({
    required String deviceId,
    required String deviceName,
    String? deviceAddress,
    String? currentUserId,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final sessionId = ChatSession.generateSessionId(
        currentUserId ?? 'local',
        deviceId,
      );

      final now = DateTime.now();

      // Check if session exists by both ID and device_id to prevent duplicates
      final existingSession = await db.query(
        _tableName,
        where: 'id = ? OR device_id = ?',
        whereArgs: [sessionId, deviceId],
        limit: 1,
      );

      if (existingSession.isNotEmpty) {
        final existing = existingSession.first;
        final existingDeviceName = existing['device_name'] as String?;
        final existingId = existing['id'] as String;

        // Only update if device name is different or connection info changed
        bool needsUpdate = false;
        final updateData = <String, dynamic>{
          'last_connection_at': now.millisecondsSinceEpoch,
        };

        if (existingDeviceName != deviceName) {
          updateData['device_name'] = deviceName;
          needsUpdate = true;
          debugPrint('🔄 Updating device name from "$existingDeviceName" to "$deviceName"');
        }

        if (deviceAddress != null && deviceAddress != existing['device_address']) {
          updateData['device_address'] = deviceAddress;
          needsUpdate = true;
        }

        if (needsUpdate || DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(
              existing['last_connection_at'] as int? ?? 0
            )
          ).inMinutes > 1) {
          await db.update(
            _tableName,
            updateData,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          debugPrint('✅ Chat session updated: $existingId');
        } else {
          debugPrint('ℹ️ Chat session already up to date: $existingId');
        }

        return existingId;
      } else {
        // Create new session
        final session = ChatSession(
          id: sessionId,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceAddress: deviceAddress,
          createdAt: now,
          lastMessageAt: now,
          lastConnectionAt: now,
        );

        await db.insert(_tableName, session.toMap());
        debugPrint('✅ NEW chat session created: $sessionId');
        return sessionId;
      }
    } catch (e) {
      debugPrint('❌ Error creating/updating chat session: $e');
      return '';
    }
  }

  static Future<ChatSession?> getSessionByDeviceId(String deviceId) async {
  try {
    final db = await DatabaseManager.database;
    final results = await db.query(
      _tableName,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'last_message_at DESC',
      limit: 1,
    );

    if (results.isNotEmpty) {
      return ChatSession.fromMap(results.first);
    }
    return null;
  } catch (e) {
    debugPrint('❌ Error getting chat session by device ID: $e');
    return null;
  }
}

/// Get or create a chat session for a device
static Future<ChatSession> getOrCreateSessionByDeviceId(
  String deviceId, {
  String? deviceName,
  String? deviceAddress,
  String? currentUserId,
}) async {
  try {
    // First try to get existing session
    ChatSession? session = await getSessionByDeviceId(deviceId);
    
    if (session != null) {
      // Update connection time for existing session
      await updateConnection(
        sessionId: session.id,
        connectionType: ConnectionType.unknown, // You can determine this based on context
        connectionTime: DateTime.now(),
      );
      return session;
    }

    // Create new session if none exists
    final sessionId = await createOrUpdate(
      deviceId: deviceId,
      deviceName: deviceName ?? 'Unknown Device',
      deviceAddress: deviceAddress,
      currentUserId: currentUserId,
    );

    // Get the newly created session
    session = await getSession(sessionId);
    if (session == null) {
      throw Exception('Failed to create chat session');
    }

    return session;
  } catch (e) {
    debugPrint('❌ Error getting/creating chat session: $e');
    rethrow;
  }
}

  /// Get all chat sessions with summary information
  static Future<List<ChatSessionSummary>> getAllSessions() async {
    try {
      return await DatabaseManager.transaction((txn) async {
        // Use simpler queries with timeout to avoid deadlocks
        final sessions = await txn.query(
          _tableName,
          orderBy: 'last_message_at DESC',
        ).timeout(const Duration(seconds: 3));

        final List<ChatSessionSummary> summaries = [];

        for (final sessionRow in sessions) {
          // Get last message for each session separately with timeout
          final lastMessageResult = await txn.query(
            'messages',
            where: 'chatSessionId = ?',
            whereArgs: [sessionRow['id']],
            orderBy: 'timestamp DESC',
            limit: 1,
          ).timeout(const Duration(seconds: 1));

          final lastMessage = lastMessageResult.isNotEmpty ? lastMessageResult.first : null;

          ConnectionType? connectionType;
          final connTypeStr = lastMessage?['connection_type'] as String?;
          if (connTypeStr != null) {
            if (connTypeStr.toLowerCase().contains('wifi_direct')) {
              connectionType = ConnectionType.wifiDirect;
            } else if (connTypeStr.toLowerCase().contains('hotspot')) {
              connectionType = ConnectionType.hotspot;
            } else {
              connectionType = ConnectionType.unknown;
            }
          }

          final lastConnectionAt = sessionRow['last_connection_at'] as int?;
          final isOnline =
              lastConnectionAt != null &&
              DateTime.now()
                      .difference(
                        DateTime.fromMillisecondsSinceEpoch(lastConnectionAt),
                      )
                      .inMinutes <
                  5;

          summaries.add(ChatSessionSummary(
            sessionId: sessionRow['id'] as String,
            deviceId: sessionRow['device_id'] as String,
            deviceName: sessionRow['device_name'] as String,
            lastMessage: lastMessage?['message'] as String?,
            lastMessageTime: lastMessage?['timestamp'] != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    lastMessage!['timestamp'] as int,
                  )
                : null,
            unreadCount: sessionRow['unread_count'] as int? ?? 0,
            isOnline: isOnline,
            connectionType: connectionType,
          ));
        }

        return summaries;
      });
    } catch (e) {
      debugPrint('❌ Error getting chat sessions: $e');
      return [];
    }
  }

  /// Get a specific chat session by ID
  static Future<ChatSession?> getSession(String sessionId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return ChatSession.fromMap(results.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting chat session: $e');
      return null;
    }
  }

  /// Get all messages for a specific chat session
  static Future<List<MessageModel>> getSessionMessages(String sessionId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        'messages',
        where: 'chatSessionId = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting chat session messages: $e');
      return [];
    }
  }

  /// Update message count and timestamps for a session (optimized with timeout)
  static Future<bool> updateMessageCount(String sessionId) async {
    try {
      return await DatabaseManager.transaction((txn) async {
        // Use simpler query with timeout to prevent locks
        final messageCountResult = await txn.rawQuery(
          '''
          SELECT
            COUNT(*) as total_messages,
            COUNT(CASE WHEN synced = 0 AND isMe = 0 THEN 1 END) as unread_count,
            MAX(timestamp) as last_message_time
          FROM messages
          WHERE chatSessionId = ?
        ''',
          [sessionId],
        ).timeout(const Duration(seconds: 2));

        if (messageCountResult.isNotEmpty) {
          final row = messageCountResult.first;
          final messageCount = row['total_messages'] as int? ?? 0;
          final unreadCount = row['unread_count'] as int? ?? 0;
          final lastMessageTime = row['last_message_time'] as int?;

          await txn.update(
            _tableName,
            {
              'message_count': messageCount,
              'unread_count': unreadCount,
              if (lastMessageTime != null) 'last_message_at': lastMessageTime,
            },
            where: 'id = ?',
            whereArgs: [sessionId],
          ).timeout(const Duration(seconds: 1));

          return true;
        }
        return false;
      });
    } catch (e) {
      debugPrint('❌ Error updating chat session message count: $e');
      return false;
    }
  }

  /// Mark all messages in a session as read
  static Future<bool> markMessagesAsRead(String sessionId) async {
    try {
      return await DatabaseManager.transaction((txn) async {
        await txn.update(
          'messages',
          {'synced': 1},
          where: 'chatSessionId = ? AND isMe = 0 AND synced = 0',
          whereArgs: [sessionId],
        );

        await txn.update(
          _tableName,
          {'unread_count': 0},
          where: 'id = ?',
          whereArgs: [sessionId],
        );

        return true;
      });
    } catch (e) {
      debugPrint('❌ Error marking chat messages as read: $e');
      return false;
    }
  }

  /// Update connection information for a session
  static Future<bool> updateConnection({
    required String sessionId,
    required ConnectionType connectionType,
    required DateTime connectionTime,
  }) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) return false;

      final updatedHistory = List<ConnectionType>.from(
        session.connectionHistory,
      );
      if (updatedHistory.isEmpty || updatedHistory.last != connectionType) {
        updatedHistory.add(connectionType);
        // Keep only last 10 connection types
        if (updatedHistory.length > 10) {
          updatedHistory.removeAt(0);
        }
      }

      final db = await DatabaseManager.database;
      await db.update(
        _tableName,
        {
          'last_connection_at': connectionTime.millisecondsSinceEpoch,
          'connection_history': jsonEncode(
            updatedHistory.map((e) => e.index).toList(),
          ),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      return true;
    } catch (e) {
      debugPrint('❌ Error updating chat session connection: $e');
      return false;
    }
  }

  /// Archive a chat session
  static Future<bool> archive(String sessionId) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _tableName,
        {'status': ChatSessionStatus.archived.index},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error archiving chat session: $e');
      return false;
    }
  }

  /// Delete a chat session and all its messages
  static Future<bool> delete(String sessionId) async {
    try {
      return await DatabaseManager.transaction((txn) async {
        // Delete all messages in the session
        await txn.delete(
          'messages',
          where: 'chatSessionId = ?',
          whereArgs: [sessionId],
        );

        // Delete the session
        await txn.delete(_tableName, where: 'id = ?', whereArgs: [sessionId]);

        debugPrint('✅ Chat session deleted: $sessionId');
        return true;
      });
    } catch (e) {
      debugPrint('❌ Error deleting chat session: $e');
      return false;
    }
  }

  /// Search chat sessions by device name or ID
  static Future<List<ChatSessionSummary>> search(String query) async {
    try {
      if (query.isEmpty) return [];

      final sessions = await getAllSessions();
      final lowerQuery = query.toLowerCase();

      return sessions.where((session) {
        return session.deviceName.toLowerCase().contains(lowerQuery) ||
            session.deviceId.toLowerCase().contains(lowerQuery) ||
            (session.lastMessage?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    } catch (e) {
      debugPrint('❌ Error searching chat sessions: $e');
      return [];
    }
  }

  /// Get session statistics
  static Future<Map<String, dynamic>> getSessionStats(String sessionId) async {
    try {
      final db = await DatabaseManager.database;

      final stats = await db.rawQuery(
        '''
        SELECT
          COUNT(*) as total_messages,
          COUNT(CASE WHEN isMe = 1 THEN 1 END) as sent_messages,
          COUNT(CASE WHEN isMe = 0 THEN 1 END) as received_messages,
          COUNT(CASE WHEN isEmergency = 1 THEN 1 END) as emergency_messages,
          MIN(timestamp) as first_message_time,
          MAX(timestamp) as last_message_time
        FROM messages
        WHERE chatSessionId = ?
      ''',
        [sessionId],
      );

      if (stats.isNotEmpty) {
        return Map<String, dynamic>.from(stats.first);
      }
      return {};
    } catch (e) {
      debugPrint('❌ Error getting session stats: $e');
      return {};
    }
  }

  /// Clean up old archived sessions
  static Future<int> cleanupOldSessions({Duration? olderThan}) async {
    try {
      final cutoffDate = DateTime.now().subtract(
        olderThan ?? const Duration(days: 90),
      );
      final db = await DatabaseManager.database;

      final result = await db.delete(
        _tableName,
        where: 'status = ? AND last_message_at < ?',
        whereArgs: [
          ChatSessionStatus.archived.index,
          cutoffDate.millisecondsSinceEpoch,
        ],
      );

      debugPrint('🧹 Cleaned up $result old archived sessions');
      return result;
    } catch (e) {
      debugPrint('❌ Error cleaning up old sessions: $e');
      return 0;
    }
  }

  /// Clean up duplicate sessions for the same device (enhanced)
  static Future<int> cleanupDuplicateSessions() async {
    try {
      final db = await DatabaseManager.database;
      int deletedCount = 0;

      // Find all sessions grouped by device_id
      final sessions = await db.rawQuery('''
        SELECT device_id, COUNT(*) as count,
               MIN(created_at) as oldest_created,
               MAX(last_connection_at) as latest_connection
        FROM $_tableName
        GROUP BY device_id
        HAVING count > 1
      ''');

      for (final group in sessions) {
        final deviceId = group['device_id'] as String;
        final count = group['count'] as int;
        debugPrint('🔍 Found $count duplicate sessions for device: $deviceId');

        // Get all sessions for this device to find the best one to keep
        final deviceSessions = await db.query(
          _tableName,
          where: 'device_id = ?',
          whereArgs: [deviceId],
          orderBy: 'last_connection_at DESC, message_count DESC, created_at ASC',
        );

        if (deviceSessions.length > 1) {
          // Keep the session with the most recent connection and highest message count
          final sessionToKeep = deviceSessions.first;
          final keepId = sessionToKeep['id'] as String;
          final keepName = sessionToKeep['device_name'] as String;

          debugPrint('🎆 Keeping session: $keepId ($keepName)');

          // Delete all other sessions for this device
          for (int i = 1; i < deviceSessions.length; i++) {
            final sessionToDelete = deviceSessions[i];
            final deleteId = sessionToDelete['id'] as String;

            await db.delete(
              _tableName,
              where: 'id = ?',
              whereArgs: [deleteId],
            );

            deletedCount++;
            debugPrint('🧹 Deleted duplicate session: $deleteId');
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('✅ Total duplicate sessions cleaned up: $deletedCount');
      } else {
        debugPrint('ℹ️ No duplicate sessions found to clean up');
      }
      return deletedCount;
    } catch (e) {
      debugPrint('❌ Error cleaning up duplicate sessions: $e');
      return 0;
    }
  }

  // Compatibility methods for existing code
  static Future<List<ChatSessionSummary>> getChatSessions() => getAllSessions();
  static Future<bool> markSessionMessagesAsRead(String sessionId) =>
      markMessagesAsRead(sessionId);
  static Future<bool> deleteSession(String sessionId) => delete(sessionId);
  static Future<bool> archiveSession(String sessionId) => archive(sessionId);
  static Future<bool> updateSessionConnection({
    required String sessionId,
    required ConnectionType connectionType,
    required DateTime connectionTime,
  }) => updateConnection(
    sessionId: sessionId,
    connectionType: connectionType,
    connectionTime: connectionTime,
  );
}
