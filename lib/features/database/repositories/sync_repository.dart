import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/message_model.dart';
import '../../../models/location_model.dart';
import '../../../models/user_model.dart';
import '../core/database_manager.dart';
import 'message_repository.dart';
import 'location_repository.dart';
import 'user_repository.dart';

/// Repository for cloud synchronization operations
class SyncRepository {
  static const String _syncQueueTable = 'sync_queue';

  // Firebase integration
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static StreamSubscription? _connectivitySubscription;
  static bool _isOnline = false;
  static bool _syncInProgress = false;
  static Timer? _syncTimer;

  /// Initialize sync service
  static Future<void> initialize() async {
    await _createSyncTables();
    await _startConnectivityMonitoring();
    _startPeriodicSync();
    debugPrint('🔄 Sync Repository initialized');
  }

  /// Create sync-related tables
  static Future<void> _createSyncTables() async {
    try {
      final db = await DatabaseManager.database;

      // Create sync queue table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_syncQueueTable (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id INTEGER NOT NULL,
          operation TEXT NOT NULL,
          data TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          sync_attempts INTEGER DEFAULT 0,
          last_attempt INTEGER,
          error_message TEXT
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_queue_table ON $_syncQueueTable (table_name)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_queue_attempts ON $_syncQueueTable (sync_attempts)');
    } catch (e) {
      debugPrint('❌ Error creating sync tables: $e');
    }
  }

  /// Start connectivity monitoring
  static Future<void> _startConnectivityMonitoring() async {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
        final wasOnline = _isOnline;
        _isOnline = !result.contains(ConnectivityResult.none);

        if (!wasOnline && _isOnline) {
          debugPrint('📶 Internet connection restored, triggering sync');
          _triggerSync();
        } else if (wasOnline && !_isOnline) {
          debugPrint('📵 Internet connection lost');
        }
      });

      // Check initial connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      _isOnline = !connectivityResult.contains(ConnectivityResult.none);
      debugPrint('📶 Initial connectivity: ${_isOnline ? "Online" : "Offline"}');
    } catch (e) {
      debugPrint('❌ Error starting connectivity monitoring: $e');
    }
  }

  /// Start periodic sync
  static void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (_isOnline && !_syncInProgress) {
        _triggerSync();
      }
    });
  }

  /// Trigger sync manually
  static void _triggerSync() {
    if (!_syncInProgress && _isOnline) {
      syncToFirebase();
    }
  }

  /// Main sync to Firebase
  static Future<void> syncToFirebase() async {
    if (_syncInProgress || !_isOnline) return;

    _syncInProgress = true;
    try {
      debugPrint('🔄 Starting Firebase sync...');

      await _syncMessages();
      await _syncLocations();
      await _processSyncQueue();

      debugPrint('✅ Firebase sync completed');
    } catch (e) {
      debugPrint('❌ Firebase sync error: $e');
    } finally {
      _syncInProgress = false;
    }
  }

  /// Sync messages to Firebase
  static Future<void> _syncMessages() async {
    try {
      final unsyncedMessages = await MessageRepository.getUnsyncedMessages();

      for (final message in unsyncedMessages) {
        try {
          final messageData = {
            'messageId': message.messageId,
            'endpointId': message.endpointId,
            'fromUser': message.fromUser,
            'message': message.message,
            'timestamp': message.timestamp,
            'isEmergency': message.isEmergency,
            'latitude': message.latitude,
            'longitude': message.longitude,
            'type': message.type,
            'connectionType': message.connectionType,
            'chatSessionId': message.chatSessionId,
            'syncedAt': FieldValue.serverTimestamp(),
          };

          await _firestore
              .collection('messages')
              .doc(message.messageId)
              .set(messageData, SetOptions(merge: true));

          await MessageRepository.markSynced(message.messageId!);
          debugPrint('📤 Message synced: ${message.messageId}');
        } catch (e) {
          debugPrint('❌ Error syncing message ${message.messageId}: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error in _syncMessages: $e');
    }
  }

  /// Sync locations to Firebase
  static Future<void> _syncLocations() async {
    try {
      final unsyncedLocations = await LocationRepository.getUnsyncedLocations();

      for (final location in unsyncedLocations) {
        try {
          final locationData = {
            'userId': location.userId,
            'latitude': location.latitude,
            'longitude': location.longitude,
            'accuracy': location.accuracy,
            'timestamp': location.timestamp.millisecondsSinceEpoch,
            'message': location.message,
            'type': location.type.toString(),
            'emergencyLevel': location.emergencyLevel?.index,
            'syncedAt': FieldValue.serverTimestamp(),
          };

          final docId = '${location.userId}_${location.timestamp.millisecondsSinceEpoch}';
          await _firestore
              .collection('locations')
              .doc(docId)
              .set(locationData, SetOptions(merge: true));

          await LocationRepository.markLocationSynced(location.timestamp);
          debugPrint('📍 Location synced: ${location.userId}');
        } catch (e) {
          debugPrint('❌ Error syncing location: $e');
          await LocationRepository.incrementLocationSyncAttempts(location.timestamp);
        }
      }
    } catch (e) {
      debugPrint('❌ Error in _syncLocations: $e');
    }
  }

  /// Process sync queue
  static Future<void> _processSyncQueue() async {
    try {
      final db = await DatabaseManager.database;
      const maxAttempts = 3;

      final queueItems = await db.query(
        _syncQueueTable,
        where: 'sync_attempts < ?',
        whereArgs: [maxAttempts],
        orderBy: 'created_at ASC',
        limit: 50,
      );

      for (final item in queueItems) {
        await _processSyncItem(item);
      }

      // Clean up old failed items
      await db.delete(
        _syncQueueTable,
        where: 'sync_attempts >= ? AND created_at < ?',
        whereArgs: [
          maxAttempts,
          DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch,
        ],
      );
    } catch (e) {
      debugPrint('❌ Error processing sync queue: $e');
    }
  }

  /// Process individual sync item
  static Future<void> _processSyncItem(Map<String, dynamic> item) async {
    try {
      final tableName = item['table_name'] as String;
      final operation = item['operation'] as String;
      final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;

      bool success = false;

      switch (tableName) {
        case 'messages':
          success = await _syncMessageToFirebase(data, operation);
        case 'locations':
          success = await _syncLocationToFirebase(data, operation);
        case 'users':
          success = await _syncUserToFirebase(data, operation);
        default:
          debugPrint('⚠️ Unknown table in sync queue: $tableName');
          success = true; 
      }

      if (success) {
        await _removeSyncItem(item['id'] as int);
      } else {
        await _incrementSyncAttempts(item['id'] as int);
      }
    } catch (e) {
      debugPrint('❌ Error processing sync item: $e');
      await _incrementSyncAttempts(item['id'] as int, e.toString());
    }
  }

  /// Sync individual message to Firebase
  static Future<bool> _syncMessageToFirebase(Map<String, dynamic> data, String operation) async {
    try {
      switch (operation) {
        case 'insert':
        case 'update':
          await _firestore
              .collection('messages')
              .doc(data['messageId'])
              .set(data, SetOptions(merge: true));
        case 'delete':
          await _firestore
              .collection('messages')
              .doc(data['messageId'])
              .delete();
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error syncing message to Firebase: $e');
      return false;
    }
  }

  /// Sync individual location to Firebase
  static Future<bool> _syncLocationToFirebase(Map<String, dynamic> data, String operation) async {
    try {
      final docId = '${data['userId']}_${data['timestamp']}';

      switch (operation) {
        case 'insert':
        case 'update':
          await _firestore
              .collection('locations')
              .doc(docId)
              .set(data, SetOptions(merge: true));
        case 'delete':
          await _firestore
              .collection('locations')
              .doc(docId)
              .delete();
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error syncing location to Firebase: $e');
      return false;
    }
  }

  /// Sync individual user to Firebase
  static Future<bool> _syncUserToFirebase(Map<String, dynamic> data, String operation) async {
    try {
      switch (operation) {
        case 'insert':
        case 'update':
          // Remove sensitive data before syncing
          final syncData = Map<String, dynamic>.from(data);
          syncData.remove('password'); // Never sync passwords

          await _firestore
              .collection('users')
              .doc(data['userId'])
              .set(syncData, SetOptions(merge: true));
        case 'delete':
          await _firestore
              .collection('users')
              .doc(data['userId'])
              .delete();
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error syncing user to Firebase: $e');
      return false;
    }
  }

  /// Remove sync item from queue
  static Future<void> _removeSyncItem(int id) async {
    try {
      final db = await DatabaseManager.database;
      await db.delete(_syncQueueTable, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('❌ Error removing sync item: $e');
    }
  }

  /// Increment sync attempts
  static Future<void> _incrementSyncAttempts(int id, [String? errorMessage]) async {
    try {
      final db = await DatabaseManager.database;
      await db.rawUpdate(
        'UPDATE $_syncQueueTable SET sync_attempts = sync_attempts + 1, last_attempt = ?, error_message = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch, errorMessage, id],
      );
    } catch (e) {
      debugPrint('❌ Error incrementing sync attempts: $e');
    }
  }

  /// Download data from Firebase
  static Future<void> downloadFromFirebase({String? userId}) async {
    if (!_isOnline) {
      debugPrint('📵 Cannot download: offline');
      return;
    }

    try {
      debugPrint('📥 Starting Firebase download...');

      // Download messages
      await _downloadMessages(userId);

      // Download locations
      await _downloadLocations(userId);

      // Download users (if admin)
      if (userId == null) {
        await _downloadUsers();
      }

      debugPrint('✅ Firebase download completed');
    } catch (e) {
      debugPrint('❌ Firebase download error: $e');
    }
  }

  /// Download messages from Firebase
  static Future<void> _downloadMessages(String? userId) async {
    try {
      Query query = _firestore.collection('messages');

      if (userId != null) {
        query = query.where('fromUser', isEqualTo: userId);
      }

      final snapshot = await query.get();
      final messages = <MessageModel>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          // Convert Firebase data to MessageModel
          final message = MessageModel(
            messageId: data['messageId'],
            endpointId: data['endpointId'] ?? '',
            fromUser: data['fromUser'] ?? '',
            message: data['message'] ?? '',
            isMe: false, // Assuming downloaded messages are from others
            isEmergency: data['isEmergency'] ?? false,
            timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            messageType: MessageType.values.firstWhere(
              (e) => e.name == data['type'],
              orElse: () => MessageType.text,
            ),
            type: data['type'] ?? 'text',
            status: MessageStatus.sent,
            latitude: data['latitude']?.toDouble(),
            longitude: data['longitude']?.toDouble(),
            connectionType: data['connectionType'],
            chatSessionId: data['chatSessionId'],
            synced: true,
          );

          messages.add(message);
        } catch (e) {
          debugPrint('❌ Error parsing message from Firebase: $e');
        }
      }

      if (messages.isNotEmpty) {
        await MessageRepository.insertBatch(messages);
        debugPrint('📥 Downloaded ${messages.length} messages');
      }
    } catch (e) {
      debugPrint('❌ Error downloading messages: $e');
    }
  }

  /// Download locations from Firebase
  static Future<void> _downloadLocations(String? userId) async {
    try {
      Query query = _firestore.collection('locations');

      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      final snapshot = await query.get();
      final locations = <LocationModel>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          final location = LocationModel(
            id: 0, // Will be assigned by database
            userId: data['userId'] ?? '',
            latitude: data['latitude']?.toDouble() ?? 0.0,
            longitude: data['longitude']?.toDouble() ?? 0.0,
            timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0),
            type: _parseLocationType(data['type']),
            message: data['message'],
            synced: true,
            accuracy: data['accuracy']?.toDouble() ?? 0.0,
          );

          locations.add(location);
        } catch (e) {
          debugPrint('❌ Error parsing location from Firebase: $e');
        }
      }

      if (locations.isNotEmpty) {
        await LocationRepository.insertBatchLocations(locations);
        debugPrint('📥 Downloaded ${locations.length} locations');
      }
    } catch (e) {
      debugPrint('❌ Error downloading locations: $e');
    }
  }

  /// Download users from Firebase
  static Future<void> _downloadUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();

          final user = UserModel(
            userId: data['userId'] ?? '',
            email: data['email'] ?? '',
            passwordHash: data['passwordHash'] ?? '',
            name: data['name'] ?? '',
            phoneNumber: data['phoneNumber'],
            createdAt: data['createdAt'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
                : DateTime.now(),
            lastLogin: data['lastLogin'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['lastLogin'])
                : null,
            isActive: data['isActive'] ?? true,
            additionalInfo: data['additionalInfo'],
          );

          await UserRepository.syncOnlineUser(user);
        } catch (e) {
          debugPrint('❌ Error parsing user from Firebase: $e');
        }
      }

      debugPrint('📥 Users downloaded from Firebase');
    } catch (e) {
      debugPrint('❌ Error downloading users: $e');
    }
  }

  /// Get sync statistics
  static Future<Map<String, dynamic>> getSyncStats() async {
    try {
      final db = await DatabaseManager.database;

      final queueSize = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_syncQueueTable'),
      ) ?? 0;

      final failedItems = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_syncQueueTable WHERE sync_attempts >= 3'),
      ) ?? 0;

      final pendingMessages = (await MessageRepository.getUnsyncedMessages()).length;
      final pendingLocations = (await LocationRepository.getUnsyncedLocations()).length;

      return {
        'isOnline': _isOnline,
        'syncInProgress': _syncInProgress,
        'queueSize': queueSize,
        'failedItems': failedItems,
        'pendingMessages': pendingMessages,
        'pendingLocations': pendingLocations,
        'lastSyncAttempt': _syncTimer?.isActive == true ? 'Active' : 'Inactive',
      };
    } catch (e) {
      debugPrint('❌ Error getting sync stats: $e');
      return {'error': e.toString()};
    }
  }

  /// Force sync now
  static Future<bool> forceSyncNow() async {
    if (!_isOnline) {
      debugPrint('📵 Cannot force sync: offline');
      return false;
    }

    try {
      await syncToFirebase();
      return true;
    } catch (e) {
      debugPrint('❌ Force sync failed: $e');
      return false;
    }
  }

  /// Clear sync queue
  static Future<void> clearSyncQueue() async {
    try {
      final db = await DatabaseManager.database;
      await db.delete(_syncQueueTable);
      debugPrint('🧹 Sync queue cleared');
    } catch (e) {
      debugPrint('❌ Error clearing sync queue: $e');
    }
  }

  /// Dispose sync service
  static Future<void> dispose() async {
    _syncTimer?.cancel();
    await _connectivitySubscription?.cancel();
    _syncInProgress = false;
    debugPrint('🧹 Sync Repository disposed');
  }
}

/// Helper function to parse LocationType from dynamic data
LocationType _parseLocationType(dynamic type) {
  if (type == null) return LocationType.normal;

  if (type is String) {
    try {
      return LocationType.values.firstWhere(
        (e) => e.toString() == type,
        orElse: () => LocationType.normal,
      );
    } catch (e) {
      return LocationType.normal;
    }
  }

  if (type is int && type >= 0 && type < LocationType.values.length) {
    return LocationType.values[type];
  }

  return LocationType.normal;
}