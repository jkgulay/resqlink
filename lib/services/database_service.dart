import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:resqlink/pages/gps_page.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/message_model.dart';
import '../models/device_model.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'resqlink_enhanced.db';
  static const int _dbVersion = 3;

  // Table names
  static const String _messagesTable = 'messages';
  static const String _locationsTable = 'locations';
  static const String _devicesTable = 'devices';
  static const String _syncQueueTable = 'sync_queue';
  static const String _compatibilityTable = 'device_compatibility';
  static const String _p2pSessionsTable = 'p2p_sessions';
  static const String _userTable = 'users';
  static const String _knownDevicesTable = 'known_devices';
  static const String _pendingMessagesTable = 'pending_messages';

  // Singleton
  static DatabaseService? _instance;
  factory DatabaseService() => _instance ??= DatabaseService._internal();
  DatabaseService._internal();

  // Firebase integration
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static StreamSubscription? _connectivitySubscription;
  static bool _isOnline = false;
  static bool _syncInProgress = false;
  static Timer? _syncTimer;
  static Timer? _healthCheckTimer;

  // Database initialization
  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      _startHealthCheck();
      return _database!;
    }

    _database = await _initDB();
    await _startConnectivityMonitoring();
    _startPeriodicSync();
    return _database!;
  }

  static Future<Database> _initDB() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);

      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onOpen: (db) {
          debugPrint('📂 Enhanced database opened successfully');
        },
      );
    } catch (e) {
      debugPrint('❌ Database initialization error: $e');
      rethrow;
    }
  }

static Future<void> _createDB(Database db, int version) async {
  try {
    // Enhanced Messages table (WITHOUT any inline indexes)
    await db.execute('''
      CREATE TABLE $_messagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        messageId TEXT UNIQUE NOT NULL,
        endpointId TEXT NOT NULL,
        fromUser TEXT NOT NULL,
        message TEXT NOT NULL,
        isMe INTEGER NOT NULL DEFAULT 0,
        isEmergency INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        latitude REAL,
        longitude REAL,
        type TEXT DEFAULT 'text',
        status TEXT DEFAULT 'sent',
        synced INTEGER NOT NULL DEFAULT 0,
        syncedToFirebase INTEGER NOT NULL DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        routePath TEXT,
        ttl INTEGER DEFAULT 5,
        connectionType TEXT,
        deviceInfo TEXT,
        retryCount INTEGER DEFAULT 0,
        lastRetryTime INTEGER DEFAULT 0,
        priority INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for messages table separately
    await db.execute('CREATE INDEX idx_messages_timestamp ON $_messagesTable (timestamp)');
    await db.execute('CREATE INDEX idx_messages_synced ON $_messagesTable (synced)');
    await db.execute('CREATE INDEX idx_messages_emergency ON $_messagesTable (isEmergency)');
    await db.execute('CREATE INDEX idx_messages_status ON $_messagesTable (status)');
    await db.execute('CREATE INDEX idx_messages_endpoint ON $_messagesTable (endpointId)');

    // Enhanced Locations table
    await db.execute('''
      CREATE TABLE $_locationsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        type TEXT DEFAULT 'normal',
        message TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        accuracy REAL,
        altitude REAL,
        speed REAL,
        heading REAL,
        source TEXT DEFAULT 'gps',
        batteryLevel INTEGER,
        connectionType TEXT,
        emergencyLevel INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for locations table
    await db.execute('CREATE INDEX idx_locations_user_timestamp ON $_locationsTable (userId, timestamp)');
    await db.execute('CREATE INDEX idx_locations_synced ON $_locationsTable (synced)');
    await db.execute('CREATE INDEX idx_locations_emergency ON $_locationsTable (emergencyLevel)');

    // Enhanced Connected devices table
    await db.execute('''
      CREATE TABLE $_devicesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT UNIQUE NOT NULL,
        deviceName TEXT NOT NULL,
        macAddress TEXT,
        ipAddress TEXT,
        lastSeen INTEGER NOT NULL,
        connectionType TEXT DEFAULT 'unknown',
        isHost INTEGER NOT NULL DEFAULT 0,
        trustLevel INTEGER DEFAULT 0,
        totalMessages INTEGER DEFAULT 0,
        totalConnections INTEGER DEFAULT 1,
        avgConnectionDuration INTEGER DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0,
        androidVersion INTEGER,
        deviceModel TEXT,
        capabilities TEXT,
        preferredConnectionMethod TEXT,
        emergencyCapable INTEGER DEFAULT 1,
        lastLatitude REAL,
        lastLongitude REAL,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for devices table
    await db.execute('CREATE INDEX idx_devices_last_seen ON $_devicesTable (lastSeen)');
    await db.execute('CREATE INDEX idx_devices_trust ON $_devicesTable (trustLevel)');
    await db.execute('CREATE INDEX idx_devices_device_id ON $_devicesTable (deviceId)');

    // Enhanced Sync queue table
    await db.execute('''
      CREATE TABLE $_syncQueueTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tableName TEXT NOT NULL,
        recordId INTEGER NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        priority INTEGER DEFAULT 0,
        attempts INTEGER DEFAULT 0,
        lastAttempt INTEGER,
        error TEXT,
        retryAfter INTEGER,
        batchId TEXT,
        dependencies TEXT,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for sync queue table
    await db.execute('CREATE INDEX idx_sync_priority ON $_syncQueueTable (priority, createdAt)');
    await db.execute('CREATE INDEX idx_sync_table_record ON $_syncQueueTable (tableName, recordId)');
    await db.execute('CREATE INDEX idx_sync_batch ON $_syncQueueTable (batchId)');

    // Device compatibility tracking
    await db.execute('''
      CREATE TABLE $_compatibilityTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT UNIQUE NOT NULL,
        androidVersion INTEGER,
        deviceModel TEXT,
        deviceManufacturer TEXT,
        supportsWifiDirect INTEGER DEFAULT 0,
        canCreateHotspot INTEGER DEFAULT 0,
        supportedFeatures TEXT,
        connectionSuccess TEXT,
        lastUpdated INTEGER NOT NULL,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for compatibility table
    await db.execute('CREATE INDEX idx_compatibility_device ON $_compatibilityTable (deviceId)');
    await db.execute('CREATE INDEX idx_compatibility_android_version ON $_compatibilityTable (androidVersion)');

    // P2P session tracking
    await db.execute('''
      CREATE TABLE $_p2pSessionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId TEXT UNIQUE NOT NULL,
        deviceId TEXT NOT NULL,
        connectionType TEXT NOT NULL,
        role TEXT NOT NULL,
        startTime INTEGER NOT NULL,
        endTime INTEGER,
        duration INTEGER,
        messagesSent INTEGER DEFAULT 0,
        messagesReceived INTEGER DEFAULT 0,
        emergencySession INTEGER DEFAULT 0,
        connectionQuality INTEGER DEFAULT 0,
        disconnectReason TEXT,
        synced INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for P2P sessions table
    await db.execute('CREATE INDEX idx_p2p_device_id ON $_p2pSessionsTable (deviceId)');
    await db.execute('CREATE INDEX idx_p2p_session_id ON $_p2pSessionsTable (sessionId)');
    await db.execute('CREATE INDEX idx_p2p_start_time ON $_p2pSessionsTable (startTime)');

    // Users table - FIX: Remove display_name column
    await db.execute('''
      CREATE TABLE $_userTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_login TEXT NOT NULL,
        is_online_user INTEGER DEFAULT 0
      )
    ''');

    // Create indexes for users table
    await db.execute('CREATE INDEX idx_users_email ON $_userTable (email)');

    // Known devices table
    await db.execute('''
      CREATE TABLE $_knownDevicesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT UNIQUE NOT NULL,
        ssid TEXT NOT NULL,
        psk TEXT NOT NULL,
        isHost INTEGER NOT NULL DEFAULT 0,
        lastSeen INTEGER NOT NULL,
        userName TEXT
      )
    ''');

    // Create indexes for known devices table
    await db.execute('CREATE INDEX idx_known_devices_device_id ON $_knownDevicesTable (deviceId)');

    // Pending messages table
    await db.execute('''
      CREATE TABLE $_pendingMessagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT NOT NULL,
        messageData TEXT NOT NULL,
        queuedAt INTEGER NOT NULL
      )
    ''');

    // Create indexes for pending messages table
    await db.execute('CREATE INDEX idx_pending_device_id ON $_pendingMessagesTable (deviceId)');

    debugPrint('✅ Enhanced database tables created successfully');
  } catch (e) {
    debugPrint('❌ Error creating enhanced database tables: $e');
    rethrow;
  }
}
  static Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    try {
      debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion');

      if (oldVersion < 2) {
        // Add enhanced columns to existing tables
        try {
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN connectionType TEXT',
          );
        } catch (e) {
          debugPrint('Column connectionType already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN deviceInfo TEXT',
          );
        } catch (e) {
          debugPrint('Column deviceInfo already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN retryCount INTEGER DEFAULT 0',
          );
        } catch (e) {
          debugPrint('Column retryCount already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN lastRetryTime INTEGER DEFAULT 0',
          );
        } catch (e) {
          debugPrint('Column lastRetryTime already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN priority INTEGER DEFAULT 0',
          );
        } catch (e) {
          debugPrint('Column priority already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN syncedToFirebase INTEGER DEFAULT 0',
          );
        } catch (e) {
          debugPrint('Column syncedToFirebase already exists or error: $e');
        }

        // Location table enhancements
        try {
          await db.execute(
            'ALTER TABLE $_locationsTable ADD COLUMN source TEXT DEFAULT "gps"',
          );
        } catch (e) {
          debugPrint('Column source already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_locationsTable ADD COLUMN batteryLevel INTEGER',
          );
        } catch (e) {
          debugPrint('Column batteryLevel already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_locationsTable ADD COLUMN connectionType TEXT',
          );
        } catch (e) {
          debugPrint('Column connectionType already exists or error: $e');
        }

        try {
          await db.execute(
            'ALTER TABLE $_locationsTable ADD COLUMN emergencyLevel INTEGER DEFAULT 0',
          );
        } catch (e) {
          debugPrint('Column emergencyLevel already exists or error: $e');
        }
      }

      if (oldVersion < 3) {
        // Create new tables for version 3
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_compatibilityTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT UNIQUE NOT NULL,
            androidVersion INTEGER,
            deviceModel TEXT,
            deviceManufacturer TEXT,
            supportsWifiDirect INTEGER DEFAULT 0,
            canCreateHotspot INTEGER DEFAULT 0,
            supportedFeatures TEXT,
            connectionSuccess TEXT,
            lastUpdated INTEGER NOT NULL,
            createdAt INTEGER DEFAULT (strftime('%s', 'now'))
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_p2pSessionsTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sessionId TEXT UNIQUE NOT NULL,
            deviceId TEXT NOT NULL,
            connectionType TEXT NOT NULL,
            role TEXT NOT NULL,
            startTime INTEGER NOT NULL,
            endTime INTEGER,
            duration INTEGER,
            messagesSent INTEGER DEFAULT 0,
            messagesReceived INTEGER DEFAULT 0,
            emergencySession INTEGER DEFAULT 0,
            connectionQuality INTEGER DEFAULT 0,
            disconnectReason TEXT,
            synced INTEGER DEFAULT 0,
            createdAt INTEGER DEFAULT (strftime('%s', 'now'))
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_userTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            last_login TEXT NOT NULL,
            is_online_user INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_knownDevicesTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT UNIQUE NOT NULL,
            ssid TEXT NOT NULL,
            psk TEXT NOT NULL,
            isHost INTEGER NOT NULL DEFAULT 0,
            lastSeen INTEGER NOT NULL,
            userName TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_pendingMessagesTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            messageData TEXT NOT NULL,
            queuedAt INTEGER NOT NULL
          )
        ''');

        // Add enhanced device tracking columns
        final deviceColumns = [
          'androidVersion INTEGER',
          'deviceModel TEXT',
          'capabilities TEXT',
          'preferredConnectionMethod TEXT',
          'emergencyCapable INTEGER DEFAULT 1',
          'lastLatitude REAL',
          'lastLongitude REAL',
        ];

        for (final column in deviceColumns) {
          try {
            await db.execute('ALTER TABLE $_devicesTable ADD COLUMN $column');
          } catch (e) {
            debugPrint('Column $column already exists or error: $e');
          }
        }
      }

      debugPrint('✅ Database upgrade completed successfully');
    } catch (e) {
      debugPrint('❌ Error upgrading database: $e');
      rethrow;
    }
  }

  // Connectivity monitoring for automatic sync
  static Future<void> _startConnectivityMonitoring() async {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        final wasOnline = _isOnline;
        _isOnline = !results.contains(ConnectivityResult.none);

        if (!wasOnline && _isOnline) {
          debugPrint('🌐 Connection restored - starting sync');
          _triggerSync();
        } else if (wasOnline && !_isOnline) {
          debugPrint('📵 Connection lost - sync disabled');
        }
      });

      // Check initial connectivity
      final results = await Connectivity().checkConnectivity();
      _isOnline = !results.contains(ConnectivityResult.none);

      if (_isOnline) {
        _triggerSync();
      }
    } catch (e) {
      debugPrint('❌ Error setting up connectivity monitoring: $e');
    }
  }

  static void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (_isOnline && !_syncInProgress) {
        _triggerSync();
      }
    });
  }

  static void _triggerSync() {
    if (!_syncInProgress) {
      syncToFirebase();
    }
  }

  // Sync queue operations
  static Future<int> _addToSyncQueue(
    String tableName,
    int recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    try {
      final db = await database;

      return await db.insert(_syncQueueTable, {
        'tableName': tableName,
        'recordId': recordId,
        'operation': operation,
        'data': jsonEncode(data),
        'priority': operation == 'insert' ? 1 : 0,
        'attempts': 0,
      });
    } catch (e) {
      debugPrint('❌ Error adding to sync queue: $e');
      return -1;
    }
  }

  // Firebase synchronization
  static Future<void> syncToFirebase() async {
    if (_syncInProgress || !_isOnline) {
      debugPrint('🔄 Sync already in progress or offline');
      return;
    }

    try {
      _syncInProgress = true;
      debugPrint('🔄 Starting Firebase synchronization...');

      await _syncMessages();
      await _syncLocations();
      await _processSyncQueue();

      debugPrint('✅ Firebase synchronization completed');
    } catch (e) {
      debugPrint('❌ Error during Firebase sync: $e');
    } finally {
      _syncInProgress = false;
    }
  }

  static Future<void> _syncMessages() async {
    try {
      final unsyncedMessages = await getUnsyncedMessages();
      debugPrint('📤 Syncing ${unsyncedMessages.length} messages to Firebase');

      for (final message in unsyncedMessages) {
        try {
          await _firestore
              .collection('messages')
              .doc(message.messageId)
              .set(message.toFirebaseJson());

          await markMessageSynced(message.messageId ?? '');
          debugPrint('✅ Message ${message.messageId} synced successfully');
        } catch (e) {
          debugPrint('❌ Error syncing message ${message.messageId}: $e');
          await _incrementSyncAttempts(_messagesTable, message.messageId ?? '');
        }
      }
    } catch (e) {
      debugPrint('❌ Error in message sync: $e');
    }
  }

  static Future<void> _syncLocations() async {
    try {
      final unsyncedLocations = await getUnsyncedLocations();
      debugPrint(
        '📤 Syncing ${unsyncedLocations.length} locations to Firebase',
      );

      for (final location in unsyncedLocations) {
        try {
          // Convert LocationModel to Firebase format
          final locationData = {
            'userId': location.userId,
            'latitude': location.latitude,
            'longitude': location.longitude,
            'timestamp': location.timestamp.millisecondsSinceEpoch,
            'type': location.type.toString(),
            'message': location.message,
            'accuracy': location.accuracy ?? 0.0,
            'altitude': location.altitude ?? 0.0,
            'speed': location.speed ?? 0.0,
            'heading': location.heading ?? 0.0,
            'source': 'gps',
            'batteryLevel': location.batteryLevel ?? 0.0,
            'emergencyLevel': location.type == LocationType.emergency ? 1 : 0,
            'createdAt': FieldValue.serverTimestamp(),
          };

          await _firestore.collection('locations').add(locationData);

          await _markLocationSynced(location.timestamp);
          debugPrint('✅ Location synced successfully');
        } catch (e) {
          debugPrint('❌ Error syncing location: $e');
          await _incrementLocationSyncAttempts(location.timestamp);
        }
      }
    } catch (e) {
      debugPrint('❌ Error in location sync: $e');
    }
  }

  static Future<void> _processSyncQueue() async {
    try {
      final db = await database;
      final queueItems = await db.query(
        _syncQueueTable,
        where: 'attempts < 3',
        orderBy: 'priority DESC, createdAt ASC',
        limit: 50,
      );

      for (final item in queueItems) {
        try {
          await _processSyncItem(item);
          await db.delete(
            _syncQueueTable,
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        } catch (e) {
          debugPrint('❌ Error processing sync item ${item['id']}: $e');
          await db.update(
            _syncQueueTable,
            {
              'attempts': (item['attempts'] as int) + 1,
              'lastAttempt': DateTime.now().millisecondsSinceEpoch,
              'error': e.toString(),
            },
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error processing sync queue: $e');
    }
  }

  static Future<void> _processSyncItem(Map<String, dynamic> item) async {
    final tableName = item['tableName'] as String;
    final data = jsonDecode(item['data'] as String);

    switch (tableName) {
      case 'messages':
        await _firestore.collection('messages').add(data);
      case 'locations':
        await _firestore.collection('locations').add(data);
      case 'devices':
        await _firestore.collection('devices').add(data);
    }
  }

  static Future<void> _incrementSyncAttempts(
    String table,
    String messageId,
  ) async {
    try {
      final db = await database;
      await db.rawUpdate(
        'UPDATE $table SET syncAttempts = syncAttempts + 1 WHERE messageId = ?',
        [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error incrementing sync attempts: $e');
    }
  }

  static Future<void> _markLocationSynced(DateTime timestamp) async {
    try {
      final db = await database;
      await db.update(
        _locationsTable,
        {'synced': 1},
        where: 'timestamp = ?',
        whereArgs: [timestamp.millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('❌ Error marking location synced: $e');
    }
  }

  static Future<void> _incrementLocationSyncAttempts(DateTime timestamp) async {
    try {
      final db = await database;
      await db.rawUpdate(
        'UPDATE $_locationsTable SET syncAttempts = syncAttempts + 1 WHERE timestamp = ?',
        [timestamp.millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('❌ Error incrementing location sync attempts: $e');
    }
  }

  static void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      try {
        if (_database != null && _database!.isOpen) {
          // Simple health check query
          await _database!.rawQuery('SELECT 1');
        }
      } catch (e) {
        debugPrint('❌ Database health check failed: $e');
        // Reset database connection
        _database = null;
        timer.cancel();
      }
    });
  }

  // Get database stats
  static Future<Map<String, int>> getDatabaseStats() async {
    try {
      final db = await database;

      final messagesCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_messagesTable'),
          ) ??
          0;

      final locationsCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_locationsTable'),
          ) ??
          0;

      final devicesCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_devicesTable'),
          ) ??
          0;

      final unsyncedMessages =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $_messagesTable WHERE synced = 0',
            ),
          ) ??
          0;

      final unsyncedLocations =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $_locationsTable WHERE synced = 0',
            ),
          ) ??
          0;

      return {
        'totalMessages': messagesCount,
        'totalLocations': locationsCount,
        'totalDevices': devicesCount,
        'unsyncedMessages': unsyncedMessages,
        'unsyncedLocations': unsyncedLocations,
        'isOnline': _isOnline ? 1 : 0,
        'syncInProgress': _syncInProgress ? 1 : 0,
      };
    } catch (e) {
      debugPrint('❌ Error getting database stats: $e');
      return {};
    }
  }

  // Get unsynced locations
  static Future<List<LocationModel>> getUnsyncedLocations() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _locationsTable,
        where: 'synced = 0 AND syncAttempts < 3',
        orderBy: 'timestamp ASC',
      );

      return maps.map((map) => LocationModel.fromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced locations: $e');
      return [];
    }
  }

  // Enhanced device compatibility tracking
  static Future<int> saveDeviceCompatibility({
    required String deviceId,
    int? androidVersion,
    String? deviceModel,
    String? deviceManufacturer,
    bool supportsWifiDirect = false,
    bool canCreateHotspot = false,
    List<String>? supportedFeatures,
    Map<String, bool>? connectionSuccess,
  }) async {
    try {
      final db = await database;

      final compatibilityMap = {
        'deviceId': deviceId,
        'androidVersion': androidVersion,
        'deviceModel': deviceModel,
        'deviceManufacturer': deviceManufacturer,
        'supportsWifiDirect': supportsWifiDirect ? 1 : 0,
        'canCreateHotspot': canCreateHotspot ? 1 : 0,
        'supportedFeatures': supportedFeatures != null
            ? jsonEncode(supportedFeatures)
            : null,
        'connectionSuccess': connectionSuccess != null
            ? jsonEncode(connectionSuccess)
            : null,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };

      final id = await db.insert(
        _compatibilityTable,
        compatibilityMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Device compatibility saved: $deviceId');
      return id;
    } catch (e) {
      debugPrint('❌ Error saving device compatibility: $e');
      return -1;
    }
  }

  static Future<Map<String, dynamic>?> getDeviceCompatibility(
    String deviceId,
  ) async {
    try {
      final db = await database;
      final results = await db.query(
        _compatibilityTable,
        where: 'deviceId = ?',
        whereArgs: [deviceId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final data = Map<String, dynamic>.from(results.first);

        // Parse JSON fields
        if (data['supportedFeatures'] != null) {
          data['supportedFeatures'] = jsonDecode(data['supportedFeatures']);
        }
        if (data['connectionSuccess'] != null) {
          data['connectionSuccess'] = jsonDecode(data['connectionSuccess']);
        }

        return data;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting device compatibility: $e');
      return null;
    }
  }

  // Enhanced P2P session tracking
  static Future<int> startP2PSession({
    required String sessionId,
    required String deviceId,
    required String connectionType,
    required String role,
    bool emergencySession = false,
  }) async {
    try {
      final db = await database;

      final sessionMap = {
        'sessionId': sessionId,
        'deviceId': deviceId,
        'connectionType': connectionType,
        'role': role,
        'startTime': DateTime.now().millisecondsSinceEpoch,
        'emergencySession': emergencySession ? 1 : 0,
        'connectionQuality': 5, // Default good quality
      };

      final id = await db.insert(_p2pSessionsTable, sessionMap);
      debugPrint('📊 P2P session started: $sessionId');
      return id;
    } catch (e) {
      debugPrint('❌ Error starting P2P session: $e');
      return -1;
    }
  }

  static Future<bool> endP2PSession({
    required String sessionId,
    String? disconnectReason,
    int? connectionQuality,
  }) async {
    try {
      final db = await database;
      final endTime = DateTime.now().millisecondsSinceEpoch;

      // Get start time to calculate duration
      final session = await db.query(
        _p2pSessionsTable,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      if (session.isEmpty) return false;

      final startTime = session.first['startTime'] as int;
      final duration = endTime - startTime;

      final updateMap = {
        'endTime': endTime,
        'duration': duration,
        'disconnectReason': disconnectReason,
      };

      if (connectionQuality != null) {
        updateMap['connectionQuality'] = connectionQuality;
      }

      final count = await db.update(
        _p2pSessionsTable,
        updateMap,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );

      debugPrint('📊 P2P session ended: $sessionId (${duration}ms)');
      return count > 0;
    } catch (e) {
      debugPrint('❌ Error ending P2P session: $e');
      return false;
    }
  }

  static Future<bool> updateP2PSessionStats({
    required String sessionId,
    int? messagesSent,
    int? messagesReceived,
    int? connectionQuality,
  }) async {
    try {
      final db = await database;
      final updateMap = <String, dynamic>{};

      if (messagesSent != null) updateMap['messagesSent'] = messagesSent;
      if (messagesReceived != null) {
        updateMap['messagesReceived'] = messagesReceived;
      }
      if (connectionQuality != null) {
        updateMap['connectionQuality'] = connectionQuality;
      }

      if (updateMap.isEmpty) return false;

      final count = await db.update(
        _p2pSessionsTable,
        updateMap,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );

      return count > 0;
    } catch (e) {
      debugPrint('❌ Error updating P2P session stats: $e');
      return false;
    }
  }

  // Enhanced message operations
  static Future<int> insertMessage(MessageModel message) async {
    try {
      final db = await database;

      final messageMap = {
        'messageId':
            message.messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        'endpointId': message.endpointId,
        'fromUser': message.fromUser,
        'message': message.message,
        'isMe': message.isMe ? 1 : 0,
        'isEmergency': message.isEmergency ? 1 : 0,
        'timestamp': message.timestamp,
        'latitude': message.latitude,
        'longitude': message.longitude,
        'type': message.type,
        'status': message.status.name,
        'synced': 0,
        'syncedToFirebase': 0,
        'syncAttempts': 0,
        'routePath': message.routePath != null
            ? jsonEncode(message.routePath!)
            : null,
        'ttl': message.ttl ?? 5,
        'connectionType': message.connectionType,
        'deviceInfo': message.deviceInfo != null
            ? jsonEncode(message.deviceInfo!)
            : null,
        'priority': message.isEmergency ? 1 : 0,
      };

      final id = await db.insert(
        _messagesTable,
        messageMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Add to sync queue if online
      if (_isOnline) {
        await _addToSyncQueue(_messagesTable, id, 'insert', messageMap);
      }

      debugPrint('💬 Message inserted with ID: $id');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting message: $e');
      return -1;
    }
  }

  static Future<Map<String, dynamic>> getEnhancedDatabaseStats() async {
    try {
      final db = await database;

      final stats = await getDatabaseStats();

      // Add P2P-specific stats
      final p2pSessions =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_p2pSessionsTable'),
          ) ??
          0;

      final emergencySessions =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $_p2pSessionsTable WHERE emergencySession = 1',
            ),
          ) ??
          0;

      final avgSessionDuration =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT AVG(duration) FROM $_p2pSessionsTable WHERE duration IS NOT NULL',
            ),
          ) ??
          0;

      final compatibilityEntries =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_compatibilityTable'),
          ) ??
          0;

      // Connection type distribution
      final connectionTypes = await db.rawQuery('''
        SELECT connectionType, COUNT(*) as count 
        FROM $_devicesTable 
        WHERE connectionType IS NOT NULL 
        GROUP BY connectionType
      ''');

      final enhancedStats = Map<String, dynamic>.from(stats);
      enhancedStats.addAll({
        'totalP2PSessions': p2pSessions,
        'emergencySessions': emergencySessions,
        'avgSessionDuration': avgSessionDuration,
        'compatibilityEntries': compatibilityEntries,
        'connectionTypeStats': connectionTypes,
        'databaseVersion': _dbVersion,
      });

      return enhancedStats;
    } catch (e) {
      debugPrint('❌ Error getting enhanced database stats: $e');
      return {};
    }
  }

  // Continue with all other existing methods...
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

  static Future<void> insertMessagesBatch(List<MessageModel> messages) async {
    if (messages.isEmpty) return;

    final db = await database;
    final batch = db.batch();

    for (final message in messages) {
      batch.insert(_messagesTable, message.toMap());
    }

    try {
      await batch.commit(noResult: true);
      debugPrint('✅ Batch inserted ${messages.length} messages');
    } catch (e) {
      debugPrint('❌ Batch insert failed: $e');
      // Fallback to individual inserts
      for (final message in messages) {
        try {
          await insertMessage(message);
        } catch (e2) {
          debugPrint('❌ Individual insert failed: $e2');
        }
      }
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

  // Continue with remaining methods...
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

  static Future<int> insertOrUpdateDevice({
    required String deviceId,
    required String deviceName,
    String? macAddress,
    String? ipAddress,
    required String connectionType,
    bool isHost = false,
    int trustLevel = 0,
    int? androidVersion,
    String? deviceModel,
    List<String>? capabilities,
    String? preferredConnectionMethod,
    bool emergencyCapable = true,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final db = await database;

      // Get existing device to preserve stats
      final existing = await db.query(
        _devicesTable,
        where: 'deviceId = ?',
        whereArgs: [deviceId],
        limit: 1,
      );

      final deviceMap = {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'macAddress': macAddress,
        'ipAddress': ipAddress,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
        'connectionType': connectionType,
        'isHost': isHost ? 1 : 0,
        'trustLevel': trustLevel,
        'androidVersion': androidVersion,
        'deviceModel': deviceModel,
        'capabilities': capabilities != null ? jsonEncode(capabilities) : null,
        'preferredConnectionMethod': preferredConnectionMethod,
        'emergencyCapable': emergencyCapable ? 1 : 0,
        'lastLatitude': latitude,
        'lastLongitude': longitude,
        'synced': 0,
      };

      // Preserve existing stats
      if (existing.isNotEmpty) {
        final existingData = existing.first;
        deviceMap['totalMessages'] = existingData['totalMessages'];
        deviceMap['totalConnections'] =
            (existingData['totalConnections'] as int) + 1;
      } else {
        deviceMap['totalMessages'] = 0;
        deviceMap['totalConnections'] = 1;
        deviceMap['avgConnectionDuration'] = 0;
      }

      final id = await db.insert(
        _devicesTable,
        deviceMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('📱 Device updated: $deviceId');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting/updating device: $e');
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
          isEmergency: map['isEmergency'] == 1,
          latitude: map['latitude']?.toDouble(),
          longitude: map['longitude']?.toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error getting unsynced to Firebase: $e');
      return [];
    }
  }

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
      final path = join(await getDatabasesPath(), _dbName);
      await deleteDatabase(path);
    } catch (e) {
      debugPrint('❌ Error deleting database file: $e');
    }
  }

  static Future<void> dispose() async {
    try {
      _syncTimer?.cancel();
      _healthCheckTimer?.cancel();
      await _connectivitySubscription?.cancel();
      await _database?.close();
      _database = null;
      _instance = null;
      debugPrint('✅ Database service disposed');
    } catch (e) {
      debugPrint('❌ Error disposing database service: $e');
    }
  }
}
