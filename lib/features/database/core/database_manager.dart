import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseManager {
  static Database? _database;
  static const String _dbName = 'resqlink_enhanced.db';
  static const int _dbVersion = 10;

  // Add connection pooling and state tracking
  static bool _isInitializing = false;
  static final Set<String> _activeTransactions = {};

  // Singleton
  static DatabaseManager? _instance;
  factory DatabaseManager() => _instance ??= DatabaseManager._internal();
  DatabaseManager._internal();

  /// Get database instance with proper initialization handling
  static Future<Database> get database async {
    if (_database != null) return _database!;

    // Prevent multiple simultaneous initializations
    if (_isInitializing) {
      // Wait for initialization to complete
      int attempts = 0;
      while (_isInitializing && attempts < 100) { // 10 second timeout
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      if (_database != null) return _database!;
    }

    _isInitializing = true;
    try {
      _database = await _initDatabase();
      return _database!;
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize database with tables and migrations
  static Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);

      debugPrint('🗃️ Initializing database at: $path');

      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        onConfigure: _configureDatabase,
        onOpen: (db) async {
          debugPrint('✅ Database opened successfully');
        },
      );
    } catch (e) {
      debugPrint('❌ Error initializing database with configuration: $e');
      debugPrint('🔄 Attempting fallback database initialization...');

      try {
        return await _initDatabaseFallback();
      } catch (fallbackError) {
        debugPrint(
          '❌ Fallback database initialization also failed: $fallbackError',
        );
        rethrow;
      }
    }
  }

  /// Fallback database initialization without PRAGMA configurations
  static Future<Database> _initDatabaseFallback() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    debugPrint('🗃️ Initializing fallback database at: $path');

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
      onOpen: (db) async {
        debugPrint('✅ Fallback database opened successfully');
      },
    );
  }

  /// Configure database settings
  static Future<void> _configureDatabase(Database db) async {
    // Critical database configuration for preventing deadlocks
    try {
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('PRAGMA journal_mode = MEMORY'); // Use memory journaling to prevent locks
      await db.execute('PRAGMA synchronous = OFF'); // Fastest, less safe but prevents locks
      await db.execute('PRAGMA locking_mode = EXCLUSIVE'); // Exclusive locking mode
      await db.execute('PRAGMA cache_size = 10000');
      await db.execute('PRAGMA temp_store = MEMORY');
      await db.execute('PRAGMA busy_timeout = 5000'); // 5 second timeout instead of 30
      debugPrint('✅ Database anti-deadlock configuration applied');
    } catch (e) {
      debugPrint('⚠️ Database configuration error: $e');
    }

    // Additional optimization settings
    try {
      await db.execute('PRAGMA page_size = 4096');
      await db.execute('PRAGMA auto_vacuum = INCREMENTAL');
      debugPrint('✅ Additional database optimizations applied');
    } catch (e) {
      debugPrint('⚠️ Some additional optimizations failed: $e');
    }
  }

  /// Create all database tables
  static Future<void> _createDatabase(Database db, int version) async {
    debugPrint('🏗️ Creating database tables...');

    try {
      // Create messages table
      await db.execute('''
        CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          messageId TEXT UNIQUE,
          endpointId TEXT NOT NULL,
          fromUser TEXT NOT NULL,
          message TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          isMe INTEGER NOT NULL DEFAULT 0,
          isEmergency INTEGER NOT NULL DEFAULT 0,
          type TEXT NOT NULL DEFAULT 'message',
          status INTEGER DEFAULT 0,
          latitude REAL,
          longitude REAL,
          routePath TEXT,
          ttl INTEGER,
          connectionType TEXT,
          connection_type TEXT,
          deviceInfo TEXT,
          targetDeviceId TEXT,
          messageType INTEGER DEFAULT 0,
          chatSessionId TEXT,
          deviceId TEXT,
          synced INTEGER DEFAULT 0,
          syncedToFirebase INTEGER DEFAULT 0,
          retryCount INTEGER DEFAULT 0,
          lastRetryTime INTEGER DEFAULT 0,
          priority INTEGER DEFAULT 0,
          createdAt INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Create users table (for authentication)
      await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId TEXT UNIQUE NOT NULL,
          email TEXT UNIQUE NOT NULL,
          password TEXT NOT NULL,
          name TEXT NOT NULL,
          phoneNumber TEXT,
          createdAt INTEGER NOT NULL,
          lastLogin INTEGER,
          isActive INTEGER DEFAULT 1,
          additionalInfo TEXT,
          synced INTEGER DEFAULT 0
        )
      ''');

      // Create locations table
      await db.execute('''
        CREATE TABLE locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId TEXT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          accuracy REAL,
          timestamp INTEGER NOT NULL,
          message TEXT,
          type TEXT DEFAULT 'normal',
          emergencyLevel INTEGER,
          synced INTEGER DEFAULT 0,
          syncAttempts INTEGER DEFAULT 0,
          lastSyncAttempt INTEGER
        )
      ''');

      // Create p2p_sessions table
      await db.execute('''
        CREATE TABLE p2p_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          deviceId TEXT NOT NULL,
          deviceName TEXT NOT NULL,
          deviceAddress TEXT,
          sessionStart INTEGER NOT NULL,
          sessionEnd INTEGER,
          duration INTEGER,
          emergencySession INTEGER DEFAULT 0,
          sessionMetadata TEXT,
          status TEXT DEFAULT 'active'
        )
      ''');

      // Create sync_queue table
      await db.execute('''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          itemId TEXT NOT NULL,
          itemType TEXT NOT NULL,
          operation TEXT NOT NULL,
          data TEXT,
          created_at INTEGER NOT NULL,
          sync_attempts INTEGER DEFAULT 0,
          last_attempt INTEGER,
          error_message TEXT
        )
      ''');

      // Create device_compatibility table
      await db.execute('''
        CREATE TABLE device_compatibility (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          deviceId TEXT UNIQUE NOT NULL,
          isCompatible INTEGER NOT NULL,
          notes TEXT,
          compatibilityData TEXT,
          testDate INTEGER NOT NULL
        )
      ''');

      // Create known_devices table
      await db.execute('''
        CREATE TABLE known_devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          deviceId TEXT UNIQUE NOT NULL,
          deviceName TEXT NOT NULL,
          lastConnectionTime INTEGER,
          connectionCount INTEGER DEFAULT 1,
          trustLevel INTEGER DEFAULT 0,
          deviceInfo TEXT,
          createdAt INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Create pending_messages table
      await db.execute('''
        CREATE TABLE pending_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          messageId TEXT UNIQUE NOT NULL,
          deviceId TEXT NOT NULL,
          message TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'message',
          timestamp INTEGER NOT NULL,
          retryCount INTEGER DEFAULT 0,
          lastRetryTime INTEGER DEFAULT 0,
          priority INTEGER DEFAULT 0,
          chatSessionId TEXT,
          createdAt INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Create chat_sessions table
      await db.execute('''
        CREATE TABLE chat_sessions (
          id TEXT PRIMARY KEY,
          device_id TEXT NOT NULL,
          device_name TEXT NOT NULL,
          device_address TEXT,
          created_at INTEGER NOT NULL,
          last_message_at INTEGER NOT NULL,
          last_connection_at INTEGER,
          message_count INTEGER DEFAULT 0,
          unread_count INTEGER DEFAULT 0,
          connection_history TEXT,
          status INTEGER DEFAULT 0,
          metadata TEXT
        )
      ''');

      // Create message_queue table
      await db.execute('''
        CREATE TABLE message_queue (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          message TEXT NOT NULL,
          type TEXT NOT NULL,
          queued_at INTEGER NOT NULL,
          retry_count INTEGER DEFAULT 0,
          last_retry_at INTEGER,
          last_error TEXT,
          priority INTEGER DEFAULT 0,
          metadata TEXT
        )
      ''');

      await _createIndexes(db);
      debugPrint('✅ Database tables created successfully');
    } catch (e) {
      debugPrint('❌ Error creating database tables: $e');
      rethrow;
    }
  }

  /// Create database indexes for performance
  static Future<void> _createIndexes(Database db) async {
    try {
      // Messages indexes
      await db.execute(
        'CREATE INDEX idx_messages_endpoint ON messages (endpointId)',
      );
      await db.execute(
        'CREATE INDEX idx_messages_timestamp ON messages (timestamp)',
      );
      await db.execute(
        'CREATE INDEX idx_messages_session ON messages (chatSessionId)',
      );
      await db.execute(
        'CREATE INDEX idx_messages_type ON messages (messageType)',
      );

      // Chat sessions indexes
      await db.execute(
        'CREATE INDEX idx_chat_sessions_device_id ON chat_sessions (device_id)',
      );
      await db.execute(
        'CREATE INDEX idx_chat_sessions_last_message ON chat_sessions (last_message_at)',
      );

      // Message queue indexes
      await db.execute(
        'CREATE INDEX idx_message_queue_device ON message_queue (device_id)',
      );
      await db.execute(
        'CREATE INDEX idx_message_queue_session ON message_queue (session_id)',
      );

      // Users indexes
      await db.execute('CREATE INDEX idx_users_user_id ON users (userId)');

      // Known devices indexes
      await db.execute(
        'CREATE INDEX idx_known_devices_device_id ON known_devices (deviceId)',
      );

      // Pending messages indexes
      await db.execute(
        'CREATE INDEX idx_pending_device_id ON pending_messages (deviceId)',
      );

      debugPrint('✅ Database indexes created successfully');
    } catch (e) {
      debugPrint('⚠️ Error creating indexes (may already exist): $e');
    }
  }

  /// Handle database upgrades
  static Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint('📊 Upgrading database from v$oldVersion to v$newVersion');

    try {
      if (oldVersion < 2) {
        await _upgradeToV2(db);
      }
      if (oldVersion < 3) {
        await _upgradeToV3(db);
      }
      if (oldVersion < 4) {
        await _upgradeToV4(db);
      }
      if (oldVersion < 5) {
        await _upgradeToV5(db);
      }
      if (oldVersion < 6) {
        await _upgradeToV6(db);
      }
      if (oldVersion < 7) {
        await _upgradeToV7(db);
      }
      if (oldVersion < 8) {
        await _upgradeToV8(db);
      }
      if (oldVersion < 9) {
        await _upgradeToV9(db);
      }
      if (oldVersion < 10) {
        await _upgradeToV10(db);
      }

      debugPrint('✅ Database upgrade completed successfully');
    } catch (e) {
      debugPrint('❌ Error upgrading database: $e');
      rethrow;
    }
  }

  static Future<void> _upgradeToV2(Database db) async {
    // Add any V2 specific migrations
    debugPrint('🔄 Upgrading to database version 2...');
  }

  static Future<void> _upgradeToV3(Database db) async {
    // Add any V3 specific migrations
    debugPrint('🔄 Upgrading to database version 3...');
  }

  static Future<void> _upgradeToV4(Database db) async {
    debugPrint('🔄 Upgrading to database version 4...');

    // Add chat_session_id column to messages table
    try {
      await db.execute('ALTER TABLE messages ADD COLUMN chatSessionId TEXT');
    } catch (e) {
      debugPrint('Column chatSessionId already exists or error: $e');
    }

    // Create chat_sessions table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        device_address TEXT,
        created_at INTEGER NOT NULL,
        last_message_at INTEGER NOT NULL,
        last_connection_at INTEGER,
        message_count INTEGER DEFAULT 0,
        unread_count INTEGER DEFAULT 0,
        connection_history TEXT,
        status INTEGER DEFAULT 0,
        metadata TEXT
      )
    ''');

    // Create message_queue table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS message_queue (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        queued_at INTEGER NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_retry_at INTEGER,
        metadata TEXT
      )
    ''');

    // Create new indexes
    try {
      await db.execute(
        'CREATE INDEX idx_chat_sessions_device_id ON chat_sessions (device_id)',
      );
      await db.execute(
        'CREATE INDEX idx_chat_sessions_last_message ON chat_sessions (last_message_at)',
      );
      await db.execute(
        'CREATE INDEX idx_messages_chat_session ON messages (chatSessionId)',
      );
      await db.execute(
        'CREATE INDEX idx_message_queue_device ON message_queue (device_id)',
      );
      await db.execute(
        'CREATE INDEX idx_message_queue_session ON message_queue (session_id)',
      );
    } catch (e) {
      debugPrint('Some indexes may already exist: $e');
    }
  }

  static Future<void> _upgradeToV5(Database db) async {
    debugPrint('🔄 Upgrading to database version 5...');

    // Add missing column to messages
    try {
      await db.execute(
        'ALTER TABLE messages ADD COLUMN syncedToFirebase INTEGER DEFAULT 0',
      );
    } catch (e) {
      debugPrint('Column syncedToFirebase already exists: $e');
    }

    // Recreate users table with proper schema
    await db.execute('DROP TABLE IF EXISTS users_old');
    await db.execute('ALTER TABLE users RENAME TO users_old');
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT UNIQUE NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        name TEXT NOT NULL,
        phoneNumber TEXT,
        createdAt INTEGER NOT NULL,
        lastLogin INTEGER,
        isActive INTEGER DEFAULT 1,
        additionalInfo TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Create new tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        timestamp INTEGER NOT NULL,
        message TEXT,
        type TEXT DEFAULT 'normal',
        emergencyLevel INTEGER,
        synced INTEGER DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        lastSyncAttempt INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS p2p_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT NOT NULL,
        deviceName TEXT NOT NULL,
        deviceAddress TEXT,
        sessionStart INTEGER NOT NULL,
        sessionEnd INTEGER,
        duration INTEGER,
        emergencySession INTEGER DEFAULT 0,
        sessionMetadata TEXT,
        status TEXT DEFAULT 'active'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemId TEXT NOT NULL,
        itemType TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT,
        created_at INTEGER NOT NULL,
        sync_attempts INTEGER DEFAULT 0,
        last_attempt INTEGER,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_compatibility (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT UNIQUE NOT NULL,
        isCompatible INTEGER NOT NULL,
        notes TEXT,
        compatibilityData TEXT,
        testDate INTEGER NOT NULL
      )
    ''');

    // Create new indexes
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_locations_user ON locations (userId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations (timestamp)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_p2p_sessions_device ON p2p_sessions (deviceId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_type ON sync_queue (itemType)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_device_compatibility_device ON device_compatibility (deviceId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_users_userId ON users (userId)',
      );
    } catch (e) {
      debugPrint('Some indexes may already exist: $e');
    }
  }

  static Future<void> _upgradeToV6(Database db) async {
    debugPrint('🔄 Upgrading to database version 6...');
    // V6 upgrades were handled in existing V5 logic
  }

  static Future<void> _upgradeToV7(Database db) async {
    debugPrint('🔄 Upgrading to database version 7...');

    // Add priority column to message_queue table
    try {
      await db.execute(
        'ALTER TABLE message_queue ADD COLUMN priority INTEGER DEFAULT 0',
      );
      debugPrint('✅ Added priority column to message_queue table');
    } catch (e) {
      debugPrint('⚠️ Priority column may already exist: $e');
    }
  }

  static Future<void> _upgradeToV8(Database db) async {
    debugPrint('🔄 Upgrading to database version 8...');

    // Add deviceId column to messages table
    try {
      await db.execute('ALTER TABLE messages ADD COLUMN deviceId TEXT');
      debugPrint('✅ Added deviceId column to messages table');
    } catch (e) {
      debugPrint('⚠️ DeviceId column may already exist: $e');
    }
  }

  /// Check database health and recover if needed
  static Future<bool> checkDatabaseHealth() async {
    try {
      final db = await database;

      // Test basic operations
      await db.rawQuery('SELECT COUNT(*) FROM messages LIMIT 1');
      await db.rawQuery('SELECT COUNT(*) FROM chat_sessions LIMIT 1');

      return true;
    } catch (e) {
      debugPrint('❌ Database health check failed: $e');
      return await _recoverDatabase();
    }
  }

  /// Attempt to recover corrupted database
  static Future<bool> _recoverDatabase() async {
    try {
      debugPrint('🔧 Attempting database recovery...');

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);

      // Close existing connection
      await _database?.close();
      _database = null;

      // Delete corrupted database
      await deleteDatabase(path);

      // Recreate database
      _database = await _initDatabase();

      debugPrint('✅ Database recovered successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Database recovery failed: $e');
      return false;
    }
  }

  /// Get database statistics
  static Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final db = await database;

      final messageCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM messages'),
          ) ??
          0;

      final sessionCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM chat_sessions'),
          ) ??
          0;

      final queueSize =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM message_queue'),
          ) ??
          0;

      final dbSize = await _getDatabaseSize();

      return {
        'messageCount': messageCount,
        'sessionCount': sessionCount,
        'queueSize': queueSize,
        'databaseSize': dbSize,
        'version': _dbVersion,
      };
    } catch (e) {
      debugPrint('❌ Error getting database stats: $e');
      return {};
    }
  }

  static Future<void> _upgradeToV9(Database db) async {
    debugPrint('🔄 Upgrading to database version 9...');

    try {
      // Add missing last_error column to message_queue table
      await db.execute(
        'ALTER TABLE message_queue ADD COLUMN last_error TEXT',
      );
      debugPrint('✅ Added last_error column to message_queue table');
    } catch (e) {
      debugPrint('⚠️ last_error column may already exist: $e');
    }

    try {
      // Add missing deviceId column to messages table
      await db.execute(
        'ALTER TABLE messages ADD COLUMN deviceId TEXT',
      );
      debugPrint('✅ Added deviceId column to messages table');
    } catch (e) {
      debugPrint('⚠️ deviceId column may already exist: $e');
    }

    debugPrint('✅ Database upgrade to version 9 completed');
  }

  static Future<void> _upgradeToV10(Database db) async {
    debugPrint('🔄 Upgrading to database version 10...');

    try {
      // Add missing connection_type column to messages table
      await db.execute(
        'ALTER TABLE messages ADD COLUMN connection_type TEXT',
      );
      debugPrint('✅ Added connection_type column to messages table');
    } catch (e) {
      debugPrint('⚠️ connection_type column may already exist: $e');
    }

    debugPrint('✅ Database upgrade to version 10 completed');
  }

  static Future<int> _getDatabaseSize() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);
      final file = await File(path).stat();
      return file.size;
    } catch (e) {
      return 0;
    }
  }

  /// Close database connection
  static Future<void> dispose() async {
    try {
      await _database?.close();
      _database = null;
      _instance = null;
      debugPrint('🗃️ Database connection closed');
    } catch (e) {
      debugPrint('❌ Error closing database: $e');
    }
  }

  /// Execute a transaction safely with deadlock prevention
  static Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    String? debugTag,
  }) async {
    final transactionId = debugTag ?? DateTime.now().millisecondsSinceEpoch.toString();

    // Check if we already have too many active transactions
    if (_activeTransactions.length > 3) {
      debugPrint('⚠️ Too many active transactions (${_activeTransactions.length}), waiting...');
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _activeTransactions.add(transactionId);

    try {
      final db = await database;
      final result = await db.transaction(action).timeout(
        const Duration(seconds: 5), // Shorter timeout to prevent deadlocks
        onTimeout: () {
          debugPrint('⚠️ Database transaction timeout after 5 seconds: $transactionId');
          throw TimeoutException('Database transaction timeout: $transactionId', const Duration(seconds: 5));
        },
      );
      return result;
    } finally {
      _activeTransactions.remove(transactionId);
    }
  }

  /// Execute raw query with error handling
  static Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      final db = await database;
      return await db.rawQuery(sql, arguments);
    } catch (e) {
      debugPrint('❌ Database query error: $e');
      debugPrint('SQL: $sql');
      debugPrint('Args: $arguments');
      rethrow;
    }
  }
}
