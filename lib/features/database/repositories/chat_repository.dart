import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../models/chat_session_model.dart';
import '../../../models/message_model.dart';
import '../core/database_manager.dart';

/// Repository for chat session operations
class ChatRepository {
  static const String _tableName = 'chat_sessions';

  /// Create or update a chat session with enhanced deduplication
  /// CRITICAL: Uses deviceAddress (MAC address) as the stable identifier
  static Future<String> createOrUpdate({
    required String deviceId,
    required String deviceName,
    String? deviceAddress,
    String? currentUserId,
    String? currentUserName,
    String? peerUserName,
  }) async {
    try {
      final db = await DatabaseManager.database;

      final stableDeviceId = deviceAddress ?? deviceId;

      // Session ID is now based on the stable device identifier (MAC address)
      final sessionId = 'chat_${stableDeviceId.replaceAll(':', '_')}';

      final now = DateTime.now();

      // First, merge ALL duplicate sessions with the same deviceAddress
      await _mergeAllDuplicateSessionsByDeviceAddress(
        stableDeviceId,
        sessionId,
      );

      // Check for existing session using ONLY deviceAddress (MAC address)
      final existingSession = await db.query(
        _tableName,
        where: 'device_address = ? OR device_id = ? OR id = ?',
        whereArgs: [stableDeviceId, stableDeviceId, sessionId],
        limit: 1,
      );

      if (existingSession.isNotEmpty) {
        final existing = existingSession.first;
        final existingId = existing['id'] as String;
        final existingDeviceName = existing['device_name'] as String?;

        // Prepare update data
        final updateData = <String, dynamic>{
          'last_connection_at': now.millisecondsSinceEpoch,
          'device_address': stableDeviceId, // Ensure address is stored
        };

        // ALWAYS update device name to reflect current displayName
        if (existingDeviceName != deviceName) {
          updateData['device_name'] = deviceName;
          debugPrint(
            '🔄 Updating device name from "$existingDeviceName" to "$deviceName" for session $existingId',
          );
        }

        // If the session ID doesn't match our stable ID, update it
        if (existingId != sessionId) {
          debugPrint(
            '🔄 Migrating session ID from "$existingId" to "$sessionId"',
          );

          // Update the session ID to use stable identifier
          await db.update(
            _tableName,
            {'id': sessionId, ...updateData},
            where: 'id = ?',
            whereArgs: [existingId],
          );

          // Update any messages that reference the old session ID
          await db.update(
            'messages',
            {'chatSessionId': sessionId},
            where: 'chatSessionId = ?',
            whereArgs: [existingId],
          );

          debugPrint(
            '✅ Session ID migrated and updated: $existingId -> $sessionId',
          );
        } else {
          // Just update the existing session
          await db.update(
            _tableName,
            updateData,
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          debugPrint('✅ Chat session updated: $sessionId');
        }

        return sessionId;
      } else {
        // Create new session with stable identifier
        final session = ChatSession(
          id: sessionId,
          deviceId: stableDeviceId,
          deviceName: deviceName,
          deviceAddress: stableDeviceId,
          createdAt: now,
          lastMessageAt: now,
          lastConnectionAt: now,
        );

        await db.insert(_tableName, session.toMap());
        debugPrint(
          '✅ NEW chat session created with stable ID: $sessionId for device: $deviceName',
        );
        return sessionId;
      }
    } catch (e) {
      debugPrint('❌ Error creating/updating chat session: $e');
      return '';
    }
  }

  /// Merge all duplicate sessions that have the same deviceAddress
  static Future<void> _mergeAllDuplicateSessionsByDeviceAddress(
    String deviceAddress,
    String targetSessionId,
  ) async {
    try {
      final db = await DatabaseManager.database;

      // Find all sessions with this device address
      final duplicates = await db.query(
        _tableName,
        where: 'device_address = ? OR device_id = ?',
        whereArgs: [deviceAddress, deviceAddress],
      );

      if (duplicates.length <= 1) return; // No duplicates

      debugPrint(
        '🔍 Found ${duplicates.length} sessions for device $deviceAddress - merging...',
      );

      for (final dup in duplicates) {
        final dupId = dup['id'] as String;
        if (dupId == targetSessionId) continue; // Skip target

        // Migrate messages from this duplicate session to target
        await db.update(
          'messages',
          {'chatSessionId': targetSessionId},
          where: 'chatSessionId = ?',
          whereArgs: [dupId],
        );

        // Delete the duplicate session
        await db.delete(_tableName, where: 'id = ?', whereArgs: [dupId]);

        debugPrint('🧹 Merged and deleted duplicate session: $dupId');
      }

      debugPrint(
        '✅ Merged ${duplicates.length - 1} duplicate sessions into $targetSessionId',
      );
    } catch (e) {
      debugPrint('❌ Error merging duplicate sessions: $e');
    }
  }

  /// Get session by device ID (which should be the MAC address)
  /// Also checks device_address for backward compatibility
  static Future<ChatSession?> getSessionByDeviceId(String deviceId) async {
    try {
      final db = await DatabaseManager.database;

      // Check both device_id and device_address to find the session
      final results = await db.query(
        _tableName,
        where: 'device_id = ? OR device_address = ?',
        whereArgs: [deviceId, deviceId],
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
    String? currentUserName,
    String? peerUserName,
  }) async {
    try {
      // First try to get existing session
      ChatSession? session = await getSessionByDeviceId(deviceId);

      if (session != null) {
        // Update connection time for existing session
        await updateConnection(
          sessionId: session.id,
          connectionType:
              ConnectionType.unknown, // You can determine this based on context
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
        currentUserName: currentUserName,
        peerUserName: peerUserName,
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
        final sessions = await txn
            .query(_tableName, orderBy: 'last_message_at DESC')
            .timeout(const Duration(seconds: 3));

        final List<ChatSessionSummary> summaries = [];

        for (final sessionRow in sessions) {
          // Get last message for each session separately with timeout
          final lastMessageResult = await txn
              .query(
                'messages',
                where: 'chatSessionId = ?',
                whereArgs: [sessionRow['id']],
                orderBy: 'timestamp DESC',
                limit: 1,
              )
              .timeout(const Duration(seconds: 1));

          final lastMessage = lastMessageResult.isNotEmpty
              ? lastMessageResult.first
              : null;

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

          summaries.add(
            ChatSessionSummary(
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
            ),
          );
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
        final messageCountResult = await txn
            .rawQuery(
              '''
          SELECT
            COUNT(*) as total_messages,
            COUNT(CASE WHEN synced = 0 AND isMe = 0 THEN 1 END) as unread_count,
            MAX(timestamp) as last_message_time
          FROM messages
          WHERE chatSessionId = ?
        ''',
              [sessionId],
            )
            .timeout(const Duration(seconds: 2));

        if (messageCountResult.isNotEmpty) {
          final row = messageCountResult.first;
          final messageCount = row['total_messages'] as int? ?? 0;
          final unreadCount = row['unread_count'] as int? ?? 0;
          final lastMessageTime = row['last_message_time'] as int?;

          await txn
              .update(
                _tableName,
                {
                  'message_count': messageCount,
                  'unread_count': unreadCount,
                  if (lastMessageTime != null)
                    'last_message_at': lastMessageTime,
                },
                where: 'id = ?',
                whereArgs: [sessionId],
              )
              .timeout(const Duration(seconds: 1));

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
  /// This method merges all duplicate sessions based on deviceAddress
  static Future<int> cleanupDuplicateSessions() async {
    try {
      final db = await DatabaseManager.database;
      int mergedCount = 0;

      debugPrint('🧹 Starting comprehensive duplicate session cleanup...');

      // Find all unique device addresses/IDs
      final allSessions = await db.query(_tableName);
      final Map<String, List<Map<String, dynamic>>> sessionsByDevice = {};

      // Group sessions by device address, device ID, AND device name
      // This handles old sessions that may have different IDs but same name
      for (final session in allSessions) {
        final deviceAddress = session['device_address'] as String?;
        final deviceId = session['device_id'] as String?;
        final deviceName = session['device_name'] as String?;

        // CRITICAL: For old sessions without device_address, group by device_name
        // This consolidates sessions like "John (device_123)", "John (device_456)", "John (02:00:00:00:00:00)"
        String key;

        // Check if this is a placeholder MAC address
        final isPlaceholderMac = deviceAddress == '02:00:00:00:00:00' ||
                                 deviceId == '02:00:00:00:00:00';

        if (isPlaceholderMac && deviceName != null && deviceName.isNotEmpty) {
          // For placeholder MACs, ALWAYS group by device name
          key = 'name:$deviceName';
        } else if (deviceAddress != null && deviceAddress.isNotEmpty && deviceAddress != '02:00:00:00:00:00') {
          // Use real device address as primary key (MAC address format like fa:12:4d:33:db:56)
          key = deviceAddress;
        } else if (deviceId != null && deviceId.contains(':') && deviceId != '02:00:00:00:00:00') {
          // If deviceId looks like a real MAC address, use it
          key = deviceId;
        } else if (deviceName != null && deviceName.isNotEmpty) {
          // Fallback: group by device name to merge old duplicates
          key = 'name:$deviceName';
        } else {
          key = deviceId ?? 'unknown';
        }

        if (!sessionsByDevice.containsKey(key)) {
          sessionsByDevice[key] = [];
        }
        sessionsByDevice[key]!.add(session);
      }

      // Process each device's sessions
      for (final entry in sessionsByDevice.entries) {
        final deviceKey = entry.key;
        final sessions = entry.value;

        if (sessions.length <= 1) continue; // No duplicates for this device

        debugPrint(
          '🔍 Found ${sessions.length} sessions for device: $deviceKey',
        );

        sessions.sort((a, b) {
          final aAddress = a['device_address'] as String? ?? '';
          final bAddress = b['device_address'] as String? ?? '';
          final aIsPlaceholder = aAddress == '02:00:00:00:00:00' || aAddress.isEmpty;
          final bIsPlaceholder = bAddress == '02:00:00:00:00:00' || bAddress.isEmpty;

          if (aIsPlaceholder != bIsPlaceholder) {
            return aIsPlaceholder ? 1 : -1; 
          }

          final aConnection = a['last_connection_at'] as int? ?? 0;
          final bConnection = b['last_connection_at'] as int? ?? 0;
          if (aConnection != bConnection) {
            return bConnection.compareTo(aConnection);
          }

          final aMessages = a['message_count'] as int? ?? 0;
          final bMessages = b['message_count'] as int? ?? 0;
          if (aMessages != bMessages) return bMessages.compareTo(aMessages);

          final aCreated = a['created_at'] as int? ?? 0;
          final bCreated = b['created_at'] as int? ?? 0;
          return aCreated.compareTo(bCreated);
        });

        final keepSession = sessions.first;
        final latestDeviceName = keepSession['device_name'] as String;


        String stableSessionId;
        String? finalDeviceAddress;

        if (deviceKey.startsWith('name:')) {
          String? foundSessionId;
          for (final session in sessions) {
            final addr = session['device_address'] as String?;
            final id = session['device_id'] as String?;
            if (addr != null && addr.isNotEmpty && addr.contains(':')) {
              finalDeviceAddress = addr;
              foundSessionId = 'chat_${addr.replaceAll(':', '_')}';
              break;
            } else if (id != null && id.contains(':')) {
              finalDeviceAddress = id;
              foundSessionId = 'chat_${id.replaceAll(':', '_')}';
              break;
            }
          }
          stableSessionId = foundSessionId ?? (keepSession['id'] as String);
        } else {
          finalDeviceAddress = deviceKey;
          stableSessionId =
              'chat_${deviceKey.replaceAll(':', '_').replaceAll('name:', '')}';
        }

        final existingId = keepSession['id'] as String;
        bool needsIdMigration = existingId != stableSessionId;

        if (needsIdMigration) {
          debugPrint(
            '🔄 Migrating session ID from "$existingId" to stable "$stableSessionId"',
          );

          await db.update(
            _tableName,
            {
              'id': stableSessionId,
              'device_address': finalDeviceAddress ?? deviceKey,
            },
            where: 'id = ?',
            whereArgs: [existingId],
          );

          // Migrate messages from old ID to stable ID
          await db.update(
            'messages',
            {'chatSessionId': stableSessionId},
            where: 'chatSessionId = ?',
            whereArgs: [existingId],
          );
        }

        // Merge all other duplicate sessions
        for (int i = 1; i < sessions.length; i++) {
          final duplicateSession = sessions[i];
          final duplicateId = duplicateSession['id'] as String;

          // Migrate messages from duplicate to stable session
          await db.update(
            'messages',
            {'chatSessionId': stableSessionId},
            where: 'chatSessionId = ?',
            whereArgs: [duplicateId],
          );

          // Delete the duplicate session
          await db.delete(
            _tableName,
            where: 'id = ?',
            whereArgs: [duplicateId],
          );

          mergedCount++;
          debugPrint('🧹 Merged and deleted duplicate session: $duplicateId');
        }

        debugPrint(
          '✅ Consolidated ${sessions.length} sessions into: $stableSessionId ($latestDeviceName)',
        );
      }

      if (mergedCount > 0) {
        debugPrint(
          '✅ Total duplicate sessions merged and cleaned: $mergedCount',
        );
      } else {
        debugPrint('ℹ️ No duplicate sessions found to clean up');
      }
      return mergedCount;
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
