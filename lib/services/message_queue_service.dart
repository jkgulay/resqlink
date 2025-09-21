import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import '../services/database_service.dart';
import '../services/p2p/p2p_main_service.dart';

class QueuedMessage {
  final String id;
  final String sessionId;
  final String deviceId;
  final String message;
  final MessageType type;
  final DateTime queuedAt;
  final int retryCount;
  final DateTime? lastRetryAt;
  final Map<String, dynamic>? metadata;

  QueuedMessage({
    required this.id,
    required this.sessionId,
    required this.deviceId,
    required this.message,
    required this.type,
    required this.queuedAt,
    this.retryCount = 0,
    this.lastRetryAt,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'deviceId': deviceId,
      'message': message,
      'type': type.name,
      'queuedAt': queuedAt.millisecondsSinceEpoch,
      'retryCount': retryCount,
      'lastRetryAt': lastRetryAt?.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  factory QueuedMessage.fromJson(Map<String, dynamic> json) {
    return QueuedMessage(
      id: json['id'],
      sessionId: json['sessionId'],
      deviceId: json['deviceId'],
      message: json['message'],
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      queuedAt: DateTime.fromMillisecondsSinceEpoch(json['queuedAt']),
      retryCount: json['retryCount'] ?? 0,
      lastRetryAt: json['lastRetryAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastRetryAt'])
          : null,
      metadata: json['metadata'],
    );
  }

  QueuedMessage copyWith({
    int? retryCount,
    DateTime? lastRetryAt,
    Map<String, dynamic>? metadata,
  }) {
    return QueuedMessage(
      id: id,
      sessionId: sessionId,
      deviceId: deviceId,
      message: message,
      type: type,
      queuedAt: queuedAt,
      retryCount: retryCount ?? this.retryCount,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

class MessageQueueService {
  static final MessageQueueService _instance = MessageQueueService._internal();
  factory MessageQueueService() => _instance;
  MessageQueueService._internal();

  final Map<String, List<QueuedMessage>> _messageQueue = {};
  Timer? _processTimer;
  P2PMainService? _p2pService;

  static const String _queueTableName = 'message_queue';
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 30);
  static const Duration _processInterval = Duration(seconds: 15);

  bool get isProcessing => _processTimer?.isActive ?? false;

  void initialize(P2PMainService p2pService) {
    _p2pService = p2pService;
    _loadQueueFromDatabase();
    _startProcessing();
    _setupConnectionListener();
  }

  void dispose() {
    _processTimer?.cancel();
    _p2pService = null;
    _messageQueue.clear();
  }

  void _setupConnectionListener() {
    _p2pService?.onDeviceConnected = _onDeviceConnected;
    _p2pService?.onDeviceDisconnected = _onDeviceDisconnected;
  }

  void _onDeviceConnected(String deviceId, String deviceName) {
    debugPrint('📱 Device connected: $deviceId, processing queue...');
    _processQueueForDevice(deviceId);
  }

  void _onDeviceDisconnected(String deviceId) {
    debugPrint('📱 Device disconnected: $deviceId');
  }

  Future<void> _loadQueueFromDatabase() async {
    try {
      final db = await DatabaseService.database;

      // Create table if it doesn't exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_queueTableName (
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

      final results = await db.query(_queueTableName);

      for (final row in results) {
        final queuedMessage = QueuedMessage.fromJson({
          'id': row['id'],
          'sessionId': row['session_id'],
          'deviceId': row['device_id'],
          'message': row['message'],
          'type': row['type'],
          'queuedAt': row['queued_at'],
          'retryCount': row['retry_count'],
          'lastRetryAt': row['last_retry_at'],
          'metadata': row['metadata'] != null ? jsonDecode(row['metadata'] as String) : null,
        });

        _messageQueue.putIfAbsent(queuedMessage.deviceId, () => []).add(queuedMessage);
      }

      debugPrint('📤 Loaded ${results.length} queued messages from database');
    } catch (e) {
      debugPrint('❌ Error loading message queue from database: $e');
    }
  }

  Future<void> _saveQueueToDatabase() async {
    try {
      final db = await DatabaseService.database;

      // Clear existing queue
      await db.delete(_queueTableName);

      // Save current queue
      for (final deviceMessages in _messageQueue.values) {
        for (final message in deviceMessages) {
          await db.insert(_queueTableName, {
            'id': message.id,
            'session_id': message.sessionId,
            'device_id': message.deviceId,
            'message': message.message,
            'type': message.type.name,
            'queued_at': message.queuedAt.millisecondsSinceEpoch,
            'retry_count': message.retryCount,
            'last_retry_at': message.lastRetryAt?.millisecondsSinceEpoch,
            'metadata': message.metadata != null ? jsonEncode(message.metadata!) : null,
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error saving message queue to database: $e');
    }
  }

  void _startProcessing() {
    _processTimer?.cancel();
    _processTimer = Timer.periodic(_processInterval, (_) {
      _processQueue();
    });
  }

  Future<String> queueMessage({
    required String sessionId,
    required String deviceId,
    required String message,
    required MessageType type,
    Map<String, dynamic>? metadata,
  }) async {
    final messageId = 'queued_${DateTime.now().millisecondsSinceEpoch}_${deviceId.hashCode}';

    final queuedMessage = QueuedMessage(
      id: messageId,
      sessionId: sessionId,
      deviceId: deviceId,
      message: message,
      type: type,
      queuedAt: DateTime.now(),
      metadata: metadata,
    );

    _messageQueue.putIfAbsent(deviceId, () => []).add(queuedMessage);
    await _saveQueueToDatabase();

    debugPrint('📥 Message queued for $deviceId: $message');

    // Try to send immediately if device is connected
    if (_p2pService?.isConnectedToDevice(deviceId) ?? false) {
      _processQueueForDevice(deviceId);
    }

    return messageId;
  }

  Future<void> _processQueue() async {
    if (_messageQueue.isEmpty || _p2pService == null) return;

    for (final deviceId in _messageQueue.keys.toList()) {
      if (_p2pService!.isConnectedToDevice(deviceId)) {
        await _processQueueForDevice(deviceId);
      }
    }
  }

  Future<void> _processQueueForDevice(String deviceId) async {
    final messages = _messageQueue[deviceId];
    if (messages == null || messages.isEmpty || _p2pService == null) return;

    final messagesToRemove = <QueuedMessage>[];

    for (final queuedMessage in messages.toList()) {
      // Skip if too many retries
      if (queuedMessage.retryCount >= _maxRetries) {
        debugPrint('❌ Message failed after max retries: ${queuedMessage.id}');
        messagesToRemove.add(queuedMessage);
        await _markMessageAsFailed(queuedMessage);
        continue;
      }

      // Skip if retry delay not elapsed
      if (queuedMessage.lastRetryAt != null) {
        final timeSinceLastRetry = DateTime.now().difference(queuedMessage.lastRetryAt!);
        if (timeSinceLastRetry < _retryDelay) {
          continue;
        }
      }

      try {
        // Attempt to send the message
        final success = await _sendQueuedMessage(queuedMessage);

        if (success) {
          debugPrint('✅ Queued message sent successfully: ${queuedMessage.id}');
          messagesToRemove.add(queuedMessage);
          await _markMessageAsSent(queuedMessage);
        } else {
          // Update retry count
          final updatedMessage = queuedMessage.copyWith(
            retryCount: queuedMessage.retryCount + 1,
            lastRetryAt: DateTime.now(),
          );

          final index = messages.indexOf(queuedMessage);
          if (index != -1) {
            messages[index] = updatedMessage;
          }

          debugPrint('⚠️ Message send failed, retry ${updatedMessage.retryCount}/$_maxRetries: ${queuedMessage.id}');
        }
      } catch (e) {
        debugPrint('❌ Error processing queued message: $e');

        // Update retry count on error
        final updatedMessage = queuedMessage.copyWith(
          retryCount: queuedMessage.retryCount + 1,
          lastRetryAt: DateTime.now(),
        );

        final index = messages.indexOf(queuedMessage);
        if (index != -1) {
          messages[index] = updatedMessage;
        }
      }
    }

    // Remove successfully sent messages
    for (final message in messagesToRemove) {
      messages.remove(message);
    }

    // Clean up empty device queues
    if (messages.isEmpty) {
      _messageQueue.remove(deviceId);
    }

    // Save updated queue
    await _saveQueueToDatabase();
  }

  Future<bool> _sendQueuedMessage(QueuedMessage queuedMessage) async {
    if (_p2pService == null) return false;

    try {
      await _p2pService!.sendMessage(
        message: queuedMessage.message,
        type: queuedMessage.type,
        targetDeviceId: queuedMessage.deviceId,
        senderName: _p2pService!.userName ?? 'Unknown',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send queued message: $e');
      return false;
    }
  }

  Future<void> _markMessageAsSent(QueuedMessage queuedMessage) async {
    try {
      // Find the corresponding message in the database and mark as sent
      final messages = await DatabaseService.getChatSessionMessages(queuedMessage.sessionId);
      final matchingMessage = messages.where((m) =>
        m.message == queuedMessage.message &&
        m.messageType == queuedMessage.type &&
        m.status == MessageStatus.pending
      ).firstOrNull;

      if (matchingMessage?.messageId != null) {
        await DatabaseService.updateMessageStatus(
          matchingMessage!.messageId!,
          MessageStatus.sent,
        );
      }
    } catch (e) {
      debugPrint('❌ Error marking message as sent: $e');
    }
  }

  Future<void> _markMessageAsFailed(QueuedMessage queuedMessage) async {
    try {
      // Find the corresponding message in the database and mark as failed
      final messages = await DatabaseService.getChatSessionMessages(queuedMessage.sessionId);
      final matchingMessage = messages.where((m) =>
        m.message == queuedMessage.message &&
        m.messageType == queuedMessage.type &&
        m.status == MessageStatus.pending
      ).firstOrNull;

      if (matchingMessage?.messageId != null) {
        await DatabaseService.updateMessageStatus(
          matchingMessage!.messageId!,
          MessageStatus.failed,
        );
      }
    } catch (e) {
      debugPrint('❌ Error marking message as failed: $e');
    }
  }

  /// Get queued message count for a specific device
  int getQueuedMessageCount(String deviceId) {
    return _messageQueue[deviceId]?.length ?? 0;
  }

  /// Get total queued message count
  int getTotalQueuedMessageCount() {
    return _messageQueue.values.fold(0, (sum, messages) => sum + messages.length);
  }

  /// Get queued messages for a specific device
  List<QueuedMessage> getQueuedMessages(String deviceId) {
    return List.from(_messageQueue[deviceId] ?? []);
  }

  /// Get all queued messages
  Map<String, List<QueuedMessage>> getAllQueuedMessages() {
    return Map.from(_messageQueue);
  }

  /// Remove a specific queued message
  Future<bool> removeQueuedMessage(String messageId) async {
    for (final deviceMessages in _messageQueue.values) {
      final message = deviceMessages.where((m) => m.id == messageId).firstOrNull;
      if (message != null) {
        deviceMessages.remove(message);
        await _saveQueueToDatabase();
        return true;
      }
    }
    return false;
  }

  /// Clear all queued messages for a device
  Future<void> clearQueueForDevice(String deviceId) async {
    _messageQueue.remove(deviceId);
    await _saveQueueToDatabase();
  }

  /// Clear all queued messages
  Future<void> clearAllQueues() async {
    _messageQueue.clear();
    try {
      final db = await DatabaseService.database;
      await db.delete(_queueTableName);
    } catch (e) {
      debugPrint('❌ Error clearing message queue: $e');
    }
  }

  /// Force process queue for a specific device
  Future<void> forceProcessDevice(String deviceId) async {
    await _processQueueForDevice(deviceId);
  }

  /// Force process all queues
  Future<void> forceProcessAll() async {
    await _processQueue();
  }
}

// Extension to check if P2P service is connected to a specific device
extension P2PConnectionCheck on P2PMainService {
  bool isConnectedToDevice(String deviceId) {
    return connectedDevices.containsKey(deviceId) && isConnected;
  }
}