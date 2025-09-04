import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:resqlink/gps_page.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';
import '../models/message_model.dart';
import 'p2p_service.dart';

class DatabaseService {
  static Database? _database;
  static bool _isInitializing = false;
  static final List<Completer<Database>> _pendingConnections = [];

  // Table names
  static const String _userTable = 'users';
  static const String _messagesTable = 'messages';
  static const String _knownDevicesTable = 'known_devices';
  static const String _pendingMessagesTable = 'pending_messages';

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;

    // ✅ FIX: Handle concurrent access
    if (_isInitializing) {
      final completer = Completer<Database>();
      _pendingConnections.add(completer);
      return completer.future;
    }

    _isInitializing = true;
    try {
      _database = await _initDB();

      // Complete all pending connections
      for (final completer in _pendingConnections) {
        completer.complete(_database!);
      }
      _pendingConnections.clear();

      return _database!;
    } finally {
      _isInitializing = false;
    }
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'resqlink_combined.db');
    return await openDatabase(
      path,
      version: 4, // Increased version for schema fixes
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  static Future<void> _createDB(Database db, int version) async {
    // Create user table
    await db.execute('''
      CREATE TABLE $_userTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        display_name TEXT,
        created_at TEXT NOT NULL,
        last_login TEXT NOT NULL,
        is_online_user INTEGER DEFAULT 0
      )
    ''');

    // Fixed messages table with consistent column names
    await db.execute('''
      CREATE TABLE $_messagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        messageId TEXT UNIQUE,
        endpointId TEXT NOT NULL,
        fromUser TEXT NOT NULL,
        message TEXT NOT NULL,
        isMe INTEGER NOT NULL,
        isEmergency INTEGER DEFAULT 0,
        timestamp INTEGER NOT NULL,
        latitude REAL,
        longitude REAL,
        type TEXT DEFAULT 'text',
        status TEXT DEFAULT 'pending',
        synced INTEGER DEFAULT 0,
        syncedToFirebase INTEGER DEFAULT 0,
        retryCount INTEGER DEFAULT 0,
        lastRetryTime INTEGER DEFAULT 0
      )
    ''');

    // Add indexes for better performance
    await db.execute(
      'CREATE INDEX idx_messages_endpoint ON $_messagesTable(endpointId)',
    );
    await db.execute(
      'CREATE INDEX idx_messages_status ON $_messagesTable(status)',
    );
    await db.execute(
      'CREATE INDEX idx_messages_timestamp ON $_messagesTable(timestamp)',
    );
    await db.execute(
      'CREATE INDEX idx_messages_synced ON $_messagesTable(synced)',
    );
    await db.execute(
      'CREATE INDEX idx_messages_id ON $_messagesTable(messageId)',
    );

    // Create known devices table
    await db.execute('''
      CREATE TABLE $_knownDevicesTable (
        deviceId TEXT PRIMARY KEY,
        ssid TEXT NOT NULL,
        psk TEXT NOT NULL,
        isHost INTEGER NOT NULL,
        lastSeen INTEGER NOT NULL,
        userName TEXT
      )
    ''');

    // Create pending messages table
    await db.execute('''
      CREATE TABLE $_pendingMessagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT NOT NULL,
        messageData TEXT NOT NULL,
        queuedAt INTEGER NOT NULL,
        attempts INTEGER DEFAULT 0
      )
    ''');

    // Index for pending messages
    await db.execute(
      'CREATE INDEX idx_pending_device ON $_pendingMessagesTable(deviceId)',
    );
  }

  static Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN type TEXT DEFAULT "text"',
      );
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN longitude REAL');
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN synced INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN messageId TEXT');
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN retryCount INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN lastRetryTime INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      // Fix column naming consistency
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN syncedToFirebase INTEGER DEFAULT 0',
      );

      // Update existing data if any
      await db.execute(
        'UPDATE $_messagesTable SET status = "pending" WHERE status IS NULL',
      );
    }
  }

  // **FIXED MISSING METHODS WITH CORRECT COLUMN NAMES**

  // Get message by ID
  static Future<MessageModel?> getMessageById(String messageId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'messageId = ?',
        whereArgs: [messageId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return MessageModel.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting message by ID: $e');
      return null;
    }
  }

  // Get failed messages
  static Future<List<MessageModel>> getFailedMessages() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'status = ?',
        whereArgs: ['failed'],
        orderBy: 'timestamp ASC',
      );
      return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
    } catch (e) {
      debugPrint('❌ Error getting failed messages: $e');
      return [];
    }
  }

  // Mark message as synced
  static Future<void> markMessageSynced(String messageId) async {
    try {
      final db = await database;
      await db.update(
        _messagesTable,
        {'synced': 1, 'syncedToFirebase': 1, 'status': 'synced'},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error marking message as synced: $e');
    }
  }

  // Update message status
  static Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status,
  ) async {
    try {
      final db = await database;
      await db.update(
        _messagesTable,
        {
          'status': status.name,
          'synced': status == MessageStatus.synced ? 1 : 0,
        },
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error updating message status: $e');
    }
  }

  // Get retry count
  static Future<int> getRetryCount(String messageId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        columns: ['retryCount'],
        where: 'messageId = ?',
        whereArgs: [messageId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return maps.first['retryCount'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ Error getting retry count: $e');
      return 0;
    }
  }

  // Get last retry time
  static Future<int> getLastRetryTime(String messageId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        columns: ['lastRetryTime'],
        where: 'messageId = ?',
        whereArgs: [messageId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return maps.first['lastRetryTime'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ Error getting last retry time: $e');
      return 0;
    }
  }

  // Update last retry time
  static Future<void> updateLastRetryTime(
    String messageId,
    int timestamp,
  ) async {
    try {
      final db = await database;
      await db.update(
        _messagesTable,
        {'lastRetryTime': timestamp},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error updating last retry time: $e');
    }
  }

  // Increment retry count
  static Future<void> incrementRetryCount(String messageId) async {
    try {
      final db = await database;
      await db.rawUpdate(
        '''
        UPDATE $_messagesTable 
        SET retryCount = retryCount + 1, 
            lastRetryTime = ?,
            status = ?
        WHERE messageId = ?
        ''',
        [DateTime.now().millisecondsSinceEpoch, 'failed', messageId],
      );
    } catch (e) {
      debugPrint('❌ Error incrementing retry count: $e');
    }
  }

  // Get pending messages
  static Future<List<MessageModel>> getPendingMessages() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'status = ? OR status = ?',
        whereArgs: ['pending', 'failed'],
        orderBy: 'timestamp ASC',
      );
      return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
    } catch (e) {
      debugPrint('❌ Error getting pending messages: $e');
      return [];
    }
  }

  // User operations (password hashing)
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<UserModel?> createUser(
    String email,
    String password, {
    bool isOnlineUser = false,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now();
      final user = UserModel(
        email: email.toLowerCase(),
        passwordHash: _hashPassword(password),
        createdAt: now,
        lastLogin: now,
        isOnlineUser: isOnlineUser,
      );
      final id = await db.insert(_userTable, user.toMap());
      return user.copyWith(id: id);
    } catch (e) {
      debugPrint('❌ Error creating user: $e');
      return null;
    }
  }

  static Future<UserModel?> loginUser(String email, String password) async {
    try {
      final db = await database;
      final hashedPassword = _hashPassword(password);
      final result = await db.query(
        _userTable,
        where: 'email = ? AND password_hash = ?',
        whereArgs: [email.toLowerCase(), hashedPassword],
      );

      if (result.isNotEmpty) {
        final user = UserModel.fromMap(result.first);
        await db.update(
          _userTable,
          {'last_login': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [user.id],
        );
        return user;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error logging in user: $e');
      return null;
    }
  }

  static Future<List<LocationModel>> getLocationsByUserId(String userId) async {
    try {
      // Since you already have LocationService, let's integrate with your message system
      final db = await database;

      // Query messages with location data
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'type = ? AND latitude IS NOT NULL AND longitude IS NOT NULL',
        whereArgs: ['location'],
        orderBy: 'timestamp DESC',
      );

      // Convert to LocationModel objects
      return maps.map((map) {
        return LocationModel(
          id: map['id'],
          latitude: map['latitude'],
          longitude: map['longitude'],
          timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
          userId: map['fromUser'],
          type: LocationType.normal,
          message: map['message'],
          synced: map['synced'] == 1,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error getting locations by user ID: $e');
      return [];
    }
  }

  // Save location as message for P2P sharing
  static Future<void> saveLocationAsMessage(
    LocationModel location,
    String endpointId,
  ) async {
    try {
      final db = await database;

      final messageMap = {
        'messageId': 'loc_${DateTime.now().millisecondsSinceEpoch}',
        'endpointId': endpointId,
        'fromUser': location.userId ?? 'Unknown',
        'message':
            '📍 Location: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
        'isMe': 1,
        'isEmergency':
            location.type == LocationType.emergency ||
                location.type == LocationType.sos
            ? 1
            : 0,
        'timestamp': location.timestamp.millisecondsSinceEpoch,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'type': 'location',
        'status': 'sent',
        'synced': location.synced ? 1 : 0,
      };

      await db.insert(_messagesTable, messageMap);
      debugPrint('✅ Location saved as message to database');
    } catch (e) {
      debugPrint('❌ Error saving location as message: $e');
    }
  }

  static Future<bool> userExists(String email) async {
    try {
      final db = await database;
      final result = await db.query(
        _userTable,
        where: 'email = ?',
        whereArgs: [email.toLowerCase()],
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking user existence: $e');
      return false;
    }
  }

  // Message operations with fixed column names
  static Future<int> insertMessage(MessageModel message) async {
    try {
      final db = await database;
      return await db.insert(_messagesTable, message.toMap());
    } catch (e) {
      debugPrint('❌ Error inserting message: $e');
      return -1;
    }
  }

  static Future<List<MessageModel>> getMessages(String endpointId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'endpointId = ?',
        whereArgs: [endpointId],
        orderBy: 'timestamp ASC',
      );
      return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
    } catch (e) {
      debugPrint('❌ Error getting messages: $e');
      return [];
    }
  }

  static Future<List<MessageModel>> getAllMessages() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        orderBy: 'timestamp DESC',
      );
      return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
    } catch (e) {
      debugPrint('❌ Error getting all messages: $e');
      return [];
    }
  }

  static Future<List<MessageModel>> getUnsyncedMessages() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'syncedToFirebase = 0 AND status != ?',
        whereArgs: ['failed'],
        orderBy: 'timestamp ASC',
      );
      return maps.map((map) => MessageModel.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced messages: $e');
      return [];
    }
  }

  // Device operations with fixed column names
  static Future<void> saveDeviceCredentials(
    DeviceCredentials credentials, {
    String? userName,
  }) async {
    try {
      final db = await database;
      await db.insert(_knownDevicesTable, {
        'deviceId': credentials.deviceId,
        'ssid': credentials.ssid,
        'psk': credentials.psk,
        'isHost': credentials.isHost ? 1 : 0,
        'lastSeen': credentials.lastSeen.millisecondsSinceEpoch,
        'userName': userName,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('❌ Error saving device credentials: $e');
    }
  }

  static Future<List<DeviceCredentials>> getKnownDevices() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _knownDevicesTable,
        orderBy: 'lastSeen DESC',
      );
      return maps
          .map(
            (map) => DeviceCredentials(
              deviceId: map['deviceId'],
              ssid: map['ssid'],
              psk: map['psk'],
              isHost: map['isHost'] == 1,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(map['lastSeen']),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting known devices: $e');
      return [];
    }
  }

  // Pending messages operations with fixed column names
  static Future<void> savePendingMessages(
    Map<String, List<PendingMessage>> pendingMessages,
  ) async {
    try {
      final db = await database;

      // Clear existing pending messages
      await db.delete(_pendingMessagesTable);

      final batch = db.batch();
      for (var entry in pendingMessages.entries) {
        final deviceId = entry.key;
        final messages = entry.value;

        for (var pendingMsg in messages) {
          batch.insert(_pendingMessagesTable, {
            'deviceId': deviceId,
            'messageData': jsonEncode(pendingMsg.toJson()),
            'queuedAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ Error saving pending messages: $e');
    }
  }

  static Future<Map<String, List<PendingMessage>>>
  getPendingMessagesMap() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _pendingMessagesTable,
      );

      final Map<String, List<PendingMessage>> result = {};

      for (var map in maps) {
        final deviceId = map['deviceId'] as String;
        final messageData = jsonDecode(map['messageData'] as String);
        final pendingMessage = PendingMessage.fromJson(messageData);

        result.putIfAbsent(deviceId, () => []).add(pendingMessage);
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error getting pending messages map: $e');
      return {};
    }
  }

  // Firebase sync operations
  static Future<void> markFirebaseSynced(String messageId) async {
    try {
      final db = await database;
      await db.update(
        _messagesTable,
        {'syncedToFirebase': 1},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error marking Firebase synced: $e');
    }
  }

  static Future<List<P2PMessage>> getUnsyncedToFirebase() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _messagesTable,
        where: 'syncedToFirebase = 0',
        orderBy: 'timestamp ASC',
      );

      return maps.map((map) {
        return P2PMessage(
          id: map['messageId'] ?? 'legacy_${map['id']}',
          senderId: map['endpointId'],
          senderName: map['fromUser'],
          message: map['message'],
          type: MessageType.values.firstWhere(
            (e) => e.name == map['type'],
            orElse: () => MessageType.text,
          ),
          timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
          ttl: 0,
          latitude: map['latitude'],
          longitude: map['longitude'],
          routePath: [],
          synced: false,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced to Firebase: $e');
      return [];
    }
  }

  // Utility operations
  static Future<void> cleanupOldData() async {
    try {
      final db = await database;
      final cutoff = DateTime.now()
          .subtract(Duration(days: 7))
          .millisecondsSinceEpoch;
      await db.delete(
        _messagesTable,
        where: 'timestamp < ? AND synced = 1',
        whereArgs: [cutoff],
      );
      await db.delete(
        _pendingMessagesTable,
        where: 'queuedAt < ?',
        whereArgs: [cutoff],
      );
    } catch (e) {
      debugPrint('❌ Error cleaning up old data: $e');
    }
  }

  static Future<void> clearAllData() async {
    try {
      final db = await database;
      await db.delete(_messagesTable);
      await db.delete(_pendingMessagesTable);
      await db.delete(_knownDevicesTable);
      debugPrint('✅ All data cleared successfully');
    } catch (e) {
      debugPrint('❌ Error clearing data: $e');
      rethrow;
    }
  }

  // Additional helper methods for other services
  static Future<UserModel?> getUserByEmail(String email) async {
    try {
      final db = await database;
      final result = await db.query(
        _userTable,
        where: 'email = ?',
        whereArgs: [email.toLowerCase()],
      );

      if (result.isNotEmpty) {
        return UserModel.fromMap(result.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting user by email: $e');
      return null;
    }
  }

  static Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await database;
      final result = await db.query(_userTable);
      return result.map((map) => UserModel.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting all users: $e');
      return [];
    }
  }

  static Future<void> syncOnlineUser(UserModel user) async {
    try {
      final db = await database;
      await db.insert(
        _userTable,
        user.copyWith(isOnlineUser: true).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('❌ Error syncing online user: $e');
    }
  }

  static Future<void> clearUsers() async {
    try {
      final db = await database;
      await db.delete(_userTable);
    } catch (e) {
      debugPrint('❌ Error clearing users: $e');
    }
  }

  static Future<void> deleteDatabaseFile() async {
    try {
      final path = join(await getDatabasesPath(), 'resqlink_combined.db');
      await deleteDatabase(path);
    } catch (e) {
      debugPrint('❌ Error deleting database file: $e');
    }
  }
}
