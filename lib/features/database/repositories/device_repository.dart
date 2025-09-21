import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database_manager.dart';

/// Device credentials for known devices
class DeviceCredentials {
  final String deviceId;
  final String deviceName;
  final String? publicKey;
  final String? sharedSecret;
  final DateTime lastSeen;
  final int connectionCount;
  final Map<String, dynamic>? deviceInfo;

  DeviceCredentials({
    required this.deviceId,
    required this.deviceName,
    this.publicKey,
    this.sharedSecret,
    required this.lastSeen,
    this.connectionCount = 1,
    this.deviceInfo,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'publicKey': publicKey,
      'sharedSecret': sharedSecret,
      'lastSeen': lastSeen.millisecondsSinceEpoch,
      'connectionCount': connectionCount,
      'deviceInfo': deviceInfo != null ? jsonEncode(deviceInfo!) : null,
    };
  }

  factory DeviceCredentials.fromMap(Map<String, dynamic> map) {
    return DeviceCredentials(
      deviceId: map['deviceId'] ?? '',
      deviceName: map['deviceName'] ?? '',
      publicKey: map['publicKey'],
      sharedSecret: map['sharedSecret'],
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['lastSeen'] ?? 0),
      connectionCount: map['connectionCount'] ?? 1,
      deviceInfo: map['deviceInfo'] != null ? jsonDecode(map['deviceInfo']) : null,
    );
  }
}

/// P2P Session model
class P2PSession {
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final DateTime startTime;
  final DateTime? endTime;
  final int? duration;
  final bool emergencySession;
  final int messagesSent;
  final int messagesReceived;
  final String? connectionType;
  final Map<String, dynamic>? sessionData;

  P2PSession({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.startTime,
    this.endTime,
    this.duration,
    this.emergencySession = false,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.connectionType,
    this.sessionData,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'duration': duration,
      'emergencySession': emergencySession ? 1 : 0,
      'messagesSent': messagesSent,
      'messagesReceived': messagesReceived,
      'connectionType': connectionType,
      'sessionData': sessionData != null ? jsonEncode(sessionData!) : null,
    };
  }

  factory P2PSession.fromMap(Map<String, dynamic> map) {
    return P2PSession(
      sessionId: map['sessionId'] ?? '',
      deviceId: map['deviceId'] ?? '',
      deviceName: map['deviceName'] ?? '',
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] ?? 0),
      endTime: map['endTime'] != null ? DateTime.fromMillisecondsSinceEpoch(map['endTime']) : null,
      duration: map['duration'],
      emergencySession: (map['emergencySession'] ?? 0) == 1,
      messagesSent: map['messagesSent'] ?? 0,
      messagesReceived: map['messagesReceived'] ?? 0,
      connectionType: map['connectionType'],
      sessionData: map['sessionData'] != null ? jsonDecode(map['sessionData']) : null,
    );
  }
}

/// Repository for device and P2P session operations
class DeviceRepository {
  static const String _devicesTable = 'devices';
  static const String _knownDevicesTable = 'known_devices';
  static const String _compatibilityTable = 'device_compatibility';
  static const String _p2pSessionsTable = 'p2p_sessions';

  /// Insert or update device information
  static Future<int> insertOrUpdate({
    required String deviceId,
    required String deviceName,
    String? deviceAddress,
    String? deviceType,
    String? osVersion,
    String? appVersion,
    Map<String, dynamic>? capabilities,
    double? latitude,
    double? longitude,
    DateTime? lastSeen,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final deviceData = {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceAddress': deviceAddress,
        'deviceType': deviceType,
        'osVersion': osVersion,
        'appVersion': appVersion,
        'capabilities': capabilities != null ? jsonEncode(capabilities) : null,
        'latitude': latitude,
        'longitude': longitude,
        'lastSeen': (lastSeen ?? DateTime.now()).millisecondsSinceEpoch,
        'isOnline': 1,
      };

      // Try to update first
      final updateCount = await db.update(
        _devicesTable,
        deviceData,
        where: 'deviceId = ?',
        whereArgs: [deviceId],
      );

      if (updateCount == 0) {
        // Insert new device
        return await db.insert(_devicesTable, deviceData);
      }

      debugPrint('📱 Device updated: $deviceName ($deviceId)');
      return updateCount;
    } catch (e) {
      debugPrint('❌ Error inserting/updating device: $e');
      return -1;
    }
  }

  /// Save device compatibility information
  static Future<int> saveCompatibility({
    required String deviceId,
    required String deviceName,
    required bool isCompatible,
    String? osVersion,
    String? appVersion,
    List<String>? supportedFeatures,
    Map<String, dynamic>? compatibilityData,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final data = {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'isCompatible': isCompatible ? 1 : 0,
        'osVersion': osVersion,
        'appVersion': appVersion,
        'supportedFeatures': supportedFeatures?.join(','),
        'compatibilityData': compatibilityData != null ? jsonEncode(compatibilityData) : null,
        'lastChecked': DateTime.now().millisecondsSinceEpoch,
      };

      return await db.insert(
        _compatibilityTable,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('❌ Error saving device compatibility: $e');
      return -1;
    }
  }

  /// Get device compatibility information
  static Future<Map<String, dynamic>?> getCompatibility(String deviceId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _compatibilityTable,
        where: 'deviceId = ?',
        whereArgs: [deviceId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final data = results.first;
        return {
          'deviceId': data['deviceId'],
          'deviceName': data['deviceName'],
          'isCompatible': (data['isCompatible'] ?? 0) == 1,
          'osVersion': data['osVersion'],
          'appVersion': data['appVersion'],
          'supportedFeatures': data['supportedFeatures']?.toString().split(',') ?? [],
          'compatibilityData': data['compatibilityData'] != null ? jsonDecode(data['compatibilityData'] as String) : null,
          'lastChecked': data['lastChecked'] != null ? DateTime.fromMillisecondsSinceEpoch(data['lastChecked'] as int) : null,
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting device compatibility: $e');
      return null;
    }
  }

  /// Save device credentials for known devices
  static Future<void> saveCredentials({
    required String deviceId,
    required String deviceName,
    String? publicKey,
    String? sharedSecret,
    Map<String, dynamic>? deviceInfo,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final credentials = DeviceCredentials(
        deviceId: deviceId,
        deviceName: deviceName,
        publicKey: publicKey,
        sharedSecret: sharedSecret,
        lastSeen: DateTime.now(),
        deviceInfo: deviceInfo,
      );

      await db.insert(
        _knownDevicesTable,
        credentials.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('🔐 Device credentials saved: $deviceName');
    } catch (e) {
      debugPrint('❌ Error saving device credentials: $e');
    }
  }

  /// Get all known devices
  static Future<List<DeviceCredentials>> getKnownDevices() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _knownDevicesTable,
        orderBy: 'lastSeen DESC',
      );

      return results.map((row) => DeviceCredentials.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting known devices: $e');
      return [];
    }
  }

  /// Start a new P2P session
  static Future<int> startP2PSession({
    required String deviceId,
    required String deviceName,
    bool emergencySession = false,
    String? connectionType,
    Map<String, dynamic>? sessionData,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final sessionId = 'p2p_${DateTime.now().millisecondsSinceEpoch}_$deviceId';

      final session = P2PSession(
        sessionId: sessionId,
        deviceId: deviceId,
        deviceName: deviceName,
        startTime: DateTime.now(),
        emergencySession: emergencySession,
        connectionType: connectionType,
        sessionData: sessionData,
      );

      final id = await db.insert(_p2pSessionsTable, session.toMap());
      debugPrint('🔗 P2P session started: $sessionId (Emergency: $emergencySession)');
      return id;
    } catch (e) {
      debugPrint('❌ Error starting P2P session: $e');
      return -1;
    }
  }

  /// End a P2P session
  static Future<bool> endP2PSession({
    required String sessionId,
    int? messagesSent,
    int? messagesReceived,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final endTime = DateTime.now();

      // Get session start time to calculate duration
      final sessionResult = await db.query(
        _p2pSessionsTable,
        columns: ['startTime'],
        where: 'sessionId = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      int? duration;
      if (sessionResult.isNotEmpty) {
        final startTime = DateTime.fromMillisecondsSinceEpoch(sessionResult.first['startTime'] as int);
        duration = endTime.difference(startTime).inSeconds;
      }

      final updateData = {
        'endTime': endTime.millisecondsSinceEpoch,
        'duration': duration,
      };

      if (messagesSent != null) updateData['messagesSent'] = messagesSent;
      if (messagesReceived != null) updateData['messagesReceived'] = messagesReceived;

      final result = await db.update(
        _p2pSessionsTable,
        updateData,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );

      debugPrint('🔚 P2P session ended: $sessionId (Duration: ${duration}s)');
      return result > 0;
    } catch (e) {
      debugPrint('❌ Error ending P2P session: $e');
      return false;
    }
  }

  /// Update P2P session statistics
  static Future<bool> updateP2PSessionStats({
    required String sessionId,
    int? messagesSent,
    int? messagesReceived,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final db = await DatabaseManager.database;
      final updateData = <String, dynamic>{};

      if (messagesSent != null) updateData['messagesSent'] = messagesSent;
      if (messagesReceived != null) updateData['messagesReceived'] = messagesReceived;

      if (additionalData != null) {
        // Merge with existing session data
        final existingResult = await db.query(
          _p2pSessionsTable,
          columns: ['sessionData'],
          where: 'sessionId = ?',
          whereArgs: [sessionId],
          limit: 1,
        );

        if (existingResult.isNotEmpty) {
          final existingDataStr = existingResult.first['sessionData'] as String?;
          final existingData = existingDataStr != null ? jsonDecode(existingDataStr) : <String, dynamic>{};
          existingData.addAll(additionalData);
          updateData['sessionData'] = jsonEncode(existingData);
        } else {
          updateData['sessionData'] = jsonEncode(additionalData);
        }
      }

      if (updateData.isEmpty) return true;

      final result = await db.update(
        _p2pSessionsTable,
        updateData,
        where: 'sessionId = ?',
        whereArgs: [sessionId],
      );

      return result > 0;
    } catch (e) {
      debugPrint('❌ Error updating P2P session stats: $e');
      return false;
    }
  }

  /// Get P2P session statistics
  static Future<Map<String, dynamic>> getP2PSessionStats() async {
    try {
      final db = await DatabaseManager.database;

      final totalSessions = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_p2pSessionsTable'),
      ) ?? 0;

      final emergencySessions = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_p2pSessionsTable WHERE emergencySession = 1'),
      ) ?? 0;

      final avgDuration = Sqflite.firstIntValue(
        await db.rawQuery('SELECT AVG(duration) FROM $_p2pSessionsTable WHERE duration IS NOT NULL'),
      ) ?? 0;

      final totalMessagesSent = Sqflite.firstIntValue(
        await db.rawQuery('SELECT SUM(messagesSent) FROM $_p2pSessionsTable'),
      ) ?? 0;

      final totalMessagesReceived = Sqflite.firstIntValue(
        await db.rawQuery('SELECT SUM(messagesReceived) FROM $_p2pSessionsTable'),
      ) ?? 0;

      return {
        'totalSessions': totalSessions,
        'emergencySessions': emergencySessions,
        'normalSessions': totalSessions - emergencySessions,
        'averageDuration': avgDuration,
        'totalMessagesSent': totalMessagesSent,
        'totalMessagesReceived': totalMessagesReceived,
      };
    } catch (e) {
      debugPrint('❌ Error getting P2P session stats: $e');
      return {};
    }
  }

  /// Get all P2P sessions
  static Future<List<P2PSession>> getAllP2PSessions({int? limit}) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _p2pSessionsTable,
        orderBy: 'startTime DESC',
        limit: limit,
      );

      return results.map((row) => P2PSession.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting P2P sessions: $e');
      return [];
    }
  }

  /// Get P2P sessions for a specific device
  static Future<List<P2PSession>> getP2PSessionsForDevice(String deviceId) async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _p2pSessionsTable,
        where: 'deviceId = ?',
        whereArgs: [deviceId],
        orderBy: 'startTime DESC',
      );

      return results.map((row) => P2PSession.fromMap(row)).toList();
    } catch (e) {
      debugPrint('❌ Error getting P2P sessions for device: $e');
      return [];
    }
  }

  /// Clean up old P2P sessions
  static Future<int> cleanupOldSessions({Duration? olderThan}) async {
    try {
      final cutoffDate = DateTime.now().subtract(olderThan ?? const Duration(days: 30));
      final db = await DatabaseManager.database;

      final result = await db.delete(
        _p2pSessionsTable,
        where: 'startTime < ? AND emergencySession = 0',
        whereArgs: [cutoffDate.millisecondsSinceEpoch],
      );

      debugPrint('🧹 Cleaned up $result old P2P sessions');
      return result;
    } catch (e) {
      debugPrint('❌ Error cleaning up old P2P sessions: $e');
      return 0;
    }
  }

  /// Get device compatibility statistics
  static Future<Map<String, dynamic>> getCompatibilityStats() async {
    try {
      final db = await DatabaseManager.database;

      final totalDevices = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_compatibilityTable'),
      ) ?? 0;

      final compatibleDevices = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_compatibilityTable WHERE isCompatible = 1'),
      ) ?? 0;

      return {
        'totalDevices': totalDevices,
        'compatibleDevices': compatibleDevices,
        'incompatibleDevices': totalDevices - compatibleDevices,
        'compatibilityRate': totalDevices > 0 ? (compatibleDevices / totalDevices * 100).toStringAsFixed(1) : '0.0',
      };
    } catch (e) {
      debugPrint('❌ Error getting compatibility stats: $e');
      return {};
    }
  }

  /// Remove device and all associated data
  static Future<bool> removeDevice(String deviceId) async {
    try {
      return await DatabaseManager.transaction((txn) async {
        // Remove from all device tables
        await txn.delete(_devicesTable, where: 'deviceId = ?', whereArgs: [deviceId]);
        await txn.delete(_knownDevicesTable, where: 'deviceId = ?', whereArgs: [deviceId]);
        await txn.delete(_compatibilityTable, where: 'deviceId = ?', whereArgs: [deviceId]);
        await txn.delete(_p2pSessionsTable, where: 'deviceId = ?', whereArgs: [deviceId]);

        debugPrint('🗑️ Device removed: $deviceId');
        return true;
      });
    } catch (e) {
      debugPrint('❌ Error removing device: $e');
      return false;
    }
  }
}