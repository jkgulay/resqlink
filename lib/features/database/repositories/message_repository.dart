import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/message_model.dart';
import '../../../models/chat_session_model.dart';
import '../core/database_manager.dart';
import 'chat_repository.dart';

/// Repository for message operations
class MessageRepository {
  static const String _tableName = 'messages';

  // Global message deduplication cache to prevent duplicate insertions
  static final Set<String> _processingMessageIds = <String>{};
  static final Map<String, DateTime> _recentlyProcessed = <String, DateTime>{};

  // Emergency cleanup access
  static Set<String> get processingMessageIds => _processingMessageIds;
  static Map<String, DateTime> get recentlyProcessed => _recentlyProcessed;
  static const Duration _deduplicationWindow = Duration(minutes: 5);

  /// Insert a new message with optimized transaction handling
  static Future<int> insert(MessageModel message, {String? currentUserId}) async {
    final messageId = message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';

    // Check for duplicate processing
    if (_processingMessageIds.contains(messageId)) {
      debugPrint('⚠️ Message already being processed: $messageId');
      return -1;
    }

    // Check recently processed messages
    _cleanupOldEntries();
    if (_recentlyProcessed.containsKey(messageId)) {
      debugPrint('⚠️ Message recently processed: $messageId');
      return -1;
    }

    // Mark as processing
    _processingMessageIds.add(messageId);

    try {
      return await DatabaseManager.transaction((txn) async {
        // Generate or use existing chat session ID
        String? chatSessionId = message.chatSessionId;
        if (chatSessionId == null && message.endpointId != 'broadcast') {
          chatSessionId = ChatSession.generateSessionId(
            currentUserId ?? 'local',
            message.endpointId,
          );
        }

        final messageMap = {
          'messageId': message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
          'endpointId': message.endpointId,
          'fromUser': message.fromUser,
          'message': message.message,
          'timestamp': message.timestamp,
          'isMe': message.isMe ? 1 : 0,
          'isEmergency': message.isEmergency ? 1 : 0,
          'type': message.type,
          'status': message.status.index,
          'latitude': message.latitude,
          'longitude': message.longitude,
          'routePath': message.routePath?.join(','),
          'ttl': message.ttl,
          'connectionType': message.connectionType,
          'deviceInfo': message.deviceInfo != null ? jsonEncode(message.deviceInfo!) : null,
          'targetDeviceId': message.targetDeviceId,
          'messageType': message.messageType.index,
          'chatSessionId': chatSessionId,
          'deviceId': message.deviceId,
          'synced': message.synced ? 1 : 0,
          'syncedToFirebase': message.syncedToFirebase ? 1 : 0,
          // Database fields with defaults (optional to set)
          'retryCount': 0,
          'lastRetryTime': 0,
          'priority': message.isEmergency ? 1 : 0,
          // Note: createdAt has database default, no need to set
        };

        final id = await txn.insert(_tableName, messageMap).timeout(const Duration(seconds: 1)); // Reduced timeout

        // Update chat session counts directly in transaction to avoid separate calls
        if (chatSessionId != null) {
          // Direct update without separate query to prevent deadlocks
          await txn.rawUpdate(
            'UPDATE chat_sessions SET message_count = message_count + 1, unread_count = unread_count + ?, last_message_at = ? WHERE id = ?',
            [message.isMe ? 0 : 1, message.timestamp, chatSessionId]
          ).timeout(const Duration(seconds: 1));
        }

        // Mark as successfully processed
        _recentlyProcessed[messageId] = DateTime.now();
        return id;
      });
    } catch (e) {
      debugPrint('❌ Error inserting message: $e');
      return -1;
    } finally {
      // Always remove from processing set
      _processingMessageIds.remove(messageId);
    }
  }

  /// Clean up old entries from deduplication cache
  static void _cleanupOldEntries() {
    final cutoff = DateTime.now().subtract(_deduplicationWindow);
    _recentlyProcessed.removeWhere((messageId, timestamp) => timestamp.isBefore(cutoff));
  }

  /// Get messages for a specific chat session with pagination (optimized with timeout)
  static Future<List<MessageModel>> getMessagesForSession(
    String sessionId, {
    int? limit,
    int? offset,
    bool ascending = true,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'chatSessionId = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ${ascending ? 'ASC' : 'DESC'}',
        limit: limit,
        offset: offset,
      ).timeout(const Duration(seconds: 3));

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting messages for session: $e');
      return [];
    }
  }

  /// Get all messages (for backward compatibility)
  static Future<List<MessageModel>> getAllMessages({
    int? limit,
    int? offset,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting all messages: $e');
      return [];
    }
  }

  /// Update message status
  static Future<bool> updateStatus(String messageId, MessageStatus status) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.update(
        _tableName,
        {'status': status.index},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );

      return result > 0;
    } catch (e) {
      debugPrint('❌ Error updating message status: $e');
      return false;
    }
  }

  /// Search messages by content
  static Future<List<MessageModel>> search(
    String query, {
    String? sessionId,
    List<MessageType>? messageTypes,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      if (query.isEmpty) return [];

      final db = await DatabaseManager.database;
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      // Add text search condition
      whereConditions.add('(message LIKE ? OR fromUser LIKE ? OR type LIKE ?)');
      final searchTerm = '%$query%';
      whereArgs.addAll([searchTerm, searchTerm, searchTerm]);

      // Add session filter
      if (sessionId != null) {
        whereConditions.add('chatSessionId = ?');
        whereArgs.add(sessionId);
      }

      // Add message type filter
      if (messageTypes != null && messageTypes.isNotEmpty) {
        final typeConditions = messageTypes.map((_) => 'messageType = ?').join(' OR ');
        whereConditions.add('($typeConditions)');
        whereArgs.addAll(messageTypes.map((type) => type.index));
      }

      // Add date range filter
      if (startDate != null) {
        whereConditions.add('timestamp >= ?');
        whereArgs.add(startDate.millisecondsSinceEpoch);
      }
      if (endDate != null) {
        whereConditions.add('timestamp <= ?');
        whereArgs.add(endDate.millisecondsSinceEpoch);
      }

      final results = await db.query(
        _tableName,
        where: whereConditions.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error searching messages: $e');
      return [];
    }
  }

  /// Get messages by type (emergency, location, etc.)
  static Future<List<MessageModel>> getMessagesByType(
    MessageType type, {
    String? sessionId,
    int? limit,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final whereConditions = ['messageType = ?'];
      final whereArgs = <dynamic>[type.index];

      if (sessionId != null) {
        whereConditions.add('chatSessionId = ?');
        whereArgs.add(sessionId);
      }

      final results = await db.query(
        _tableName,
        where: whereConditions.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting messages by type: $e');
      return [];
    }
  }

  /// Get pending messages (for retry logic)
  static Future<List<MessageModel>> getPendingMessages({String? deviceId}) async {
    try {
      final db = await DatabaseManager.database;
      final whereConditions = ['status = ?'];
      final whereArgs = <dynamic>[MessageStatus.pending.index];

      if (deviceId != null) {
        whereConditions.add('endpointId = ?');
        whereArgs.add(deviceId);
      }

      final results = await db.query(
        _tableName,
        where: whereConditions.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting pending messages: $e');
      return [];
    }
  }

  /// Delete messages older than specified duration
  static Future<int> deleteOldMessages(Duration olderThan) async {
    try {
      final cutoffDate = DateTime.now().subtract(olderThan);
      final db = await DatabaseManager.database;

      final result = await db.delete(
        _tableName,
        where: 'timestamp < ? AND status != ?',
        whereArgs: [
          cutoffDate.millisecondsSinceEpoch,
          MessageStatus.pending.index, // Don't delete pending messages
        ],
      );

      debugPrint('🧹 Deleted $result old messages');
      return result;
    } catch (e) {
      debugPrint('❌ Error deleting old messages: $e');
      return 0;
    }
  }

  /// Delete all messages for a specific session
  static Future<bool> deleteMessagesForSession(String sessionId) async {
    try {
      final db = await DatabaseManager.database;
      await db.delete(
        _tableName,
        where: 'chatSessionId = ?',
        whereArgs: [sessionId],
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting messages for session: $e');
      return false;
    }
  }

  /// Get message statistics for a session
  static Future<Map<String, dynamic>> getMessageStats(String sessionId) async {
    try {
      final db = await DatabaseManager.database;

      final stats = await db.rawQuery('''
        SELECT
          COUNT(*) as total_count,
          COUNT(CASE WHEN isMe = 1 THEN 1 END) as sent_count,
          COUNT(CASE WHEN isMe = 0 THEN 1 END) as received_count,
          COUNT(CASE WHEN isEmergency = 1 THEN 1 END) as emergency_count,
          COUNT(CASE WHEN messageType = ? THEN 1 END) as location_count,
          COUNT(CASE WHEN status = ? THEN 1 END) as pending_count,
          COUNT(CASE WHEN status = ? THEN 1 END) as failed_count,
          MIN(timestamp) as first_message_time,
          MAX(timestamp) as last_message_time
        FROM $_tableName
        WHERE chatSessionId = ?
      ''', [
        MessageType.location.index,
        MessageStatus.pending.index,
        MessageStatus.failed.index,
        sessionId,
      ]);

      if (stats.isNotEmpty) {
        return Map<String, dynamic>.from(stats.first);
      }
      return {};
    } catch (e) {
      debugPrint('❌ Error getting message stats: $e');
      return {};
    }
  }

  /// Export messages to JSON format
  static Future<Map<String, dynamic>> exportMessages(String sessionId) async {
    try {
      final messages = await getMessagesForSession(sessionId);
      final session = await ChatRepository.getSession(sessionId);

      return {
        'exportDate': DateTime.now().toIso8601String(),
        'sessionId': sessionId,
        'deviceName': session?.deviceName ?? 'Unknown',
        'messageCount': messages.length,
        'messages': messages.map((m) => {
          'timestamp': m.timestamp,
          'fromUser': m.fromUser,
          'message': m.message,
          'type': m.type,
          'isMe': m.isMe,
          'isEmergency': m.isEmergency,
          'latitude': m.latitude,
          'longitude': m.longitude,
          'connectionType': m.connectionType,
        }).toList(),
      };
    } catch (e) {
      debugPrint('❌ Error exporting messages: $e');
      return {};
    }
  }

  /// Bulk update message sync status (optimized with timeout and transaction)
  static Future<bool> markMessagesAsSynced(List<String> messageIds) async {
    try {
      if (messageIds.isEmpty) return true;

      return await DatabaseManager.transaction((txn) async {
        final placeholders = List.filled(messageIds.length, '?').join(',');

        await txn.rawUpdate(
          'UPDATE $_tableName SET synced = 1 WHERE messageId IN ($placeholders)',
          messageIds,
        ).timeout(const Duration(seconds: 2));

        return true;
      });
    } catch (e) {
      debugPrint('❌ Error marking messages as synced: $e');
      return false;
    }
  }

  /// Get unread message count for a session
  static Future<int> getUnreadCount(String sessionId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM $_tableName
        WHERE chatSessionId = ? AND isMe = 0 AND synced = 0
      ''', [sessionId]);

      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Clean up failed messages older than specified duration
  static Future<int> cleanupFailedMessages({Duration? olderThan}) async {
    try {
      final cutoffDate = DateTime.now().subtract(olderThan ?? const Duration(days: 7));
      final db = await DatabaseManager.database;

      final result = await db.delete(
        _tableName,
        where: 'status = ? AND timestamp < ?',
        whereArgs: [
          MessageStatus.failed.index,
          cutoffDate.millisecondsSinceEpoch,
        ],
      );

      debugPrint('🧹 Cleaned up $result failed messages');
      return result;
    } catch (e) {
      debugPrint('❌ Error cleaning up failed messages: $e');
      return 0;
    }
  }


  static Future<MessageModel?> getById(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'messageId = ?',
        whereArgs: [messageId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return MessageModel.fromMap(results.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting message by ID: $e');
      return null;
    }
  }

  /// Get messages for a specific endpoint (backward compatibility)
  static Future<List<MessageModel>> getByEndpoint(String endpointId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'endpointId = ?',
        whereArgs: [endpointId],
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting messages by endpoint: $e');
      return [];
    }
  }

  /// Get messages by user ID
  static Future<List<MessageModel>> getByUserId(String userId, {int limit = 50}) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'fromUser = ?',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting messages by user ID: $e');
      return [];
    }
  }

  /// Get all messages with pagination
  static Future<List<MessageModel>> getAll({int limit = 100}) async {
    return getAllMessages(limit: limit);
  }

  /// Get all failed messages that need retry
  static Future<List<MessageModel>> getFailedMessages() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'status = ?',
        whereArgs: [MessageStatus.failed.index],
        orderBy: 'timestamp DESC',
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting failed messages: $e');
      return [];
    }
  }

  /// Insert multiple messages in a batch operation
  static Future<void> insertBatch(List<MessageModel> messages) async {
    try {
      await DatabaseManager.transaction((txn) async {
        for (final message in messages) {
          final messageMap = _messageToMap(message);
          await txn.insert(_tableName, messageMap, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      debugPrint('✅ Inserted ${messages.length} messages in batch');
    } catch (e) {
      debugPrint('❌ Error inserting messages batch: $e');
    }
  }

  /// Mark message as synced to cloud
  static Future<void> markSynced(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _tableName,
        {'synced': 1, 'syncedToFirebase': 1},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error marking message as synced: $e');
    }
  }

  /// Mark message as synced by database ID
  static Future<void> markSyncedById(int id) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _tableName,
        {'synced': 1, 'syncedToFirebase': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('❌ Error marking message as synced by ID: $e');
    }
  }

  /// Get retry count for a message
  static Future<int> getRetryCount(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.query(
        _tableName,
        columns: ['syncAttempts'],
        where: 'messageId = ?',
        whereArgs: [messageId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return result.first['syncAttempts'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ Error getting retry count: $e');
      return 0;
    }
  }

  /// Get last retry time for a message
  static Future<int> getLastRetryTime(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      final result = await db.query(
        _tableName,
        columns: ['lastRetryTime'],
        where: 'messageId = ?',
        whereArgs: [messageId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return result.first['lastRetryTime'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ Error getting last retry time: $e');
      return 0;
    }
  }

  /// Update last retry time for a message
  static Future<void> updateLastRetryTime(String messageId, int timestamp) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _tableName,
        {'lastRetryTime': timestamp},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error updating last retry time: $e');
    }
  }

  /// Increment retry count for a message
  static Future<void> incrementRetryCount(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      await db.rawUpdate(
        'UPDATE $_tableName SET syncAttempts = syncAttempts + 1 WHERE messageId = ?',
        [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error incrementing retry count: $e');
    }
  }

  /// Get unsynced messages for cloud sync
  static Future<List<MessageModel>> getUnsyncedMessages() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'synced = 0 OR syncedToFirebase = 0',
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced messages: $e');
      return [];
    }
  }

  /// Get unsynced messages to Firebase specifically
  static Future<List<MessageModel>> getUnsyncedToFirebase() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _tableName,
        where: 'syncedToFirebase = 0',
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => MessageModel.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced to Firebase messages: $e');
      return [];
    }
  }

  /// Mark message as synced to Firebase
  static Future<void> markFirebaseSynced(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _tableName,
        {'syncedToFirebase': 1},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error marking Firebase synced: $e');
    }
  }

  /// Save location as a message (for GPS tracking)
  static Future<void> saveLocationAsMessage({
    required String userId,
    required double latitude,
    required double longitude,
    String? description,
    bool isEmergency = false,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final messageId = 'loc_${timestamp}_$userId';

      final locationMessage = MessageModel(
        messageId: messageId,
        endpointId: 'location_tracker',
        fromUser: userId,
        message: description ?? 'Location update',
        isMe: true,
        isEmergency: isEmergency,
        timestamp: timestamp,
        messageType: MessageType.location,
        type: 'location',
        status: MessageStatus.sent,
        latitude: latitude,
        longitude: longitude,
        deviceId: null,
      );

      await insert(locationMessage);
      debugPrint('📍 Location saved as message: $latitude, $longitude');
    } catch (e) {
      debugPrint('❌ Error saving location as message: $e');
    }
  }

  /// Helper method to convert MessageModel to Map
  static Map<String, dynamic> _messageToMap(MessageModel message) {
    return {
      'messageId': message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'endpointId': message.endpointId,
      'fromUser': message.fromUser,
      'message': message.message,
      'isMe': message.isMe ? 1 : 0,
      'isEmergency': message.isEmergency ? 1 : 0,
      'timestamp': message.timestamp,
      'latitude': message.latitude,
      'longitude': message.longitude,
      'type': message.type,
      'status': message.status.index,
      'synced': message.synced ? 1 : 0,
      'syncedToFirebase': 0,
      'syncAttempts': 0,
      'routePath': message.routePath?.join(','),
      'ttl': message.ttl ?? 5,
      'connectionType': message.connectionType,
      'deviceInfo': message.deviceInfo != null ? jsonEncode(message.deviceInfo!) : null,
      'targetDeviceId': message.targetDeviceId,
      'messageType': message.messageType.index,
      'chatSessionId': message.chatSessionId,
      'deviceId': message.deviceId,
      'priority': message.isEmergency ? 1 : 0,
      'retryCount': 0,
      'lastRetryTime': 0,
    };
  }

  // Additional compatibility methods for legacy code
  static Future<void> insertMessage(MessageModel message, {String? currentUserId}) => insert(message);
  static Future<void> updateMessageStatus(String messageId, MessageStatus status) => updateStatus(messageId, status);
  static Future<void> markMessageSynced(String messageId) => markSynced(messageId);
}