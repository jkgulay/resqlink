import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';
import '../models/message_model.dart';
import 'p2p_services.dart';

class DatabaseService {
  static Database? _database;

  // User table
  static const String _userTable = 'users';
  // Messages table
  static const String _messagesTable = 'messages';
  // Known devices table
  static const String _knownDevicesTable = 'known_devices';
  // Pending messages table
  static const String _pendingMessagesTable = 'pending_messages';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'resqlink_combined.db');
    return await openDatabase(
      path,
      version: 3,
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

    // Enhanced messages table with status
    await db.execute('''
    CREATE TABLE $_messagesTable (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      endpoint_id TEXT NOT NULL,
      from_user TEXT NOT NULL,
      message TEXT NOT NULL,
      is_me BOOLEAN NOT NULL,
      is_emergency BOOLEAN NOT NULL,
      timestamp INTEGER NOT NULL,
      type TEXT DEFAULT 'message',
      latitude REAL,
      longitude REAL,
      synced BOOLEAN DEFAULT 0,
      message_id TEXT UNIQUE,
      synced_to_firebase BOOLEAN DEFAULT 0,
      status INTEGER DEFAULT 0,
      retry_count INTEGER DEFAULT 0,
      last_retry_at INTEGER
    )
  ''');

    // Add indexes for better performance (FIXED - removed duplicate)
    await db.execute(
      'CREATE INDEX idx_messages_endpoint ON messages(endpoint_id)',
    );
    await db.execute('CREATE INDEX idx_messages_status ON messages(status)');
    await db.execute(
      'CREATE INDEX idx_messages_timestamp ON messages(timestamp)',
    );
    await db.execute('CREATE INDEX idx_messages_synced ON messages(synced)');

    // Create known devices table
    await db.execute('''
    CREATE TABLE $_knownDevicesTable (
      device_id TEXT PRIMARY KEY,
      ssid TEXT NOT NULL,
      psk TEXT NOT NULL,
      is_host INTEGER NOT NULL,
      last_seen INTEGER NOT NULL,
      user_name TEXT
    )
  ''');

    // Create pending messages table
    await db.execute('''
    CREATE TABLE $_pendingMessagesTable (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      message_json TEXT NOT NULL,
      queued_at INTEGER NOT NULL,
      attempts INTEGER DEFAULT 0
    )
  ''');

    // Index for pending messages (FIXED - corrected table name)
    await db.execute(
      'CREATE INDEX idx_pending_device ON pending_messages(device_id)',
    );
  }

  static Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN type TEXT DEFAULT "message"',
      );
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE $_messagesTable ADD COLUMN longitude REAL');
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN synced INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE $_messagesTable ADD COLUMN message_id TEXT',
      );
    }
  }

  // User operations
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
      print('Error creating user: $e');
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
      print('Error logging in user: $e');
      return null;
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
      print('Error checking user existence: $e');
      return false;
    }
  }

  static Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await database;
      final result = await db.query(_userTable);
      return result.map((map) => UserModel.fromMap(map)).toList();
    } catch (e) {
      print('Error getting all users: $e');
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
      print('Error syncing online user: $e');
    }
  }

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
      print('Error getting user by email: $e');
      return null;
    }
  }

  static Future<void> clearUsers() async {
    final db = await database;
    await db.delete(_userTable);
  }

  static Future<void> deleteDatabaseFile() async {
    final path = join(await getDatabasesPath(), 'resqlink_combined.db');
    await deleteDatabase(path);
  }

  // Message operations
  static Future<int> insertMessage(MessageModel message) async {
    final db = await database;
    return await db.insert('messages', message.toMap());
  }

  static Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status,
  ) async {
    final db = await database;
    await db.update(
      'messages',
      {
        'status': status.index,
        'synced': status == MessageStatus.synced ? 1 : 0,
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  static Future<List<MessageModel>> getMessages(String endpointId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'endpoint_id = ?',
      whereArgs: [endpointId],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
  }

  static Future<List<MessageModel>> getAllMessages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
  }

  static Future<List<MessageModel>> getUnsyncedMessages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'synced_to_firebase = 0 AND status != ?',
      whereArgs: [MessageStatus.failed.index],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => MessageModel.fromMap(map)).toList();
  }

  static Future<void> incrementRetryCount(String messageId) async {
    final db = await database;
    await db.rawUpdate(
      '''
    UPDATE messages 
    SET retry_count = retry_count + 1, 
        last_retry_at = ?,
        status = ?
    WHERE message_id = ?
  ''',
      [
        DateTime.now().millisecondsSinceEpoch,
        MessageStatus.failed.index,
        messageId,
      ],
    );
  }

  static Future<void> markMessageSynced(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {'synced_to_firebase': 1, 'status': MessageStatus.synced.index},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  // Device operations
  static Future<void> saveDeviceCredentials(
    DeviceCredentials credentials, {
    String? userName,
  }) async {
    final db = await database;
    await db.insert(_knownDevicesTable, {
      'device_id': credentials.deviceId,
      'ssid': credentials.ssid,
      'psk': credentials.psk,
      'is_host': credentials.isHost ? 1 : 0,
      'last_seen': credentials.lastSeen.millisecondsSinceEpoch,
      'user_name': userName, // Add this
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<DeviceCredentials>> getKnownDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'known_devices',
      orderBy: 'last_seen DESC',
    );
    return maps
        .map(
          (map) => DeviceCredentials(
            deviceId: map['device_id'],
            ssid: map['ssid'],
            psk: map['psk'],
            isHost: map['is_host'] == 1,
            lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen']),
          ),
        )
        .toList();
  }

  // Pending messages operations
  static Future<void> savePendingMessages(
    Map<String, List<PendingMessage>> pendingMessages,
  ) async {
    final db = await database;

    // Clear existing pending messages
    await db.delete('pending_messages');

    final batch = db.batch();
    for (var entry in pendingMessages.entries) {
      final deviceId = entry.key;
      final messages = entry.value;

      for (var pendingMsg in messages) {
        batch.insert('pending_messages', {
          'device_id': deviceId,
          'message_data': jsonEncode(pendingMsg.toJson()),
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    await batch.commit();
  }

  static Future<void> markFirebaseSynced(String messageId) async {
    final db = await database;
    await db.update(
      _messagesTable,
      {'synced_to_firebase': 1},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  static Future<List<P2PMessage>> getUnsyncedToFirebase() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _messagesTable,
      where: 'synced_to_firebase = 0',
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) {
      return P2PMessage(
        id: map['message_id'] ?? 'legacy_${map['id']}',
        senderId: map['endpoint_id'],
        senderName: map['from_user'],
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
  }

  static Future<Map<String, List<PendingMessage>>>
  getPendingMessagesMap() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pending_messages');

    final Map<String, List<PendingMessage>> result = {};

    for (var map in maps) {
      final deviceId = map['device_id'] as String;
      final messageData = jsonDecode(map['message_data'] as String);
      final pendingMessage = PendingMessage.fromJson(messageData);

      result.putIfAbsent(deviceId, () => []).add(pendingMessage);
    }

    return result;
  }

  static Future<List<MessageModel>> getPendingMessages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'status = ? OR status = ?',
      whereArgs: [MessageStatus.pending.index, MessageStatus.failed.index],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => MessageModel.fromMap(maps[i]));
  }

  // Clean up old data
  static Future<void> cleanupOldData() async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: 7))
        .millisecondsSinceEpoch;
    await db.delete(
      'messages',
      where: 'timestamp < ? AND synced = 1',
      whereArgs: [cutoff],
    );
    await db.delete(
      'pending_messages',
      where: 'queued_at < ?',
      whereArgs: [cutoff],
    );
  }

  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('known_devices');
    await db.delete('pending_messages');
  }
}
