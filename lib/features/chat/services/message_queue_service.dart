import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import '../../../models/message_model.dart';
import '../../database/core/database_manager.dart';
import '../../p2p/events/p2p_event_bus.dart';

class QueuedMessage {
  final String id;
  final String sessionId;
  final String deviceId;
  final String message;
  final MessageType type;
  final DateTime queuedAt;
  final int retryCount;
  final DateTime? lastRetryAt;
  final String? lastError;
  final Map<String, dynamic>? metadata;
  final int priority; 

 QueuedMessage({
    required this.id,
    required this.sessionId,
    required this.deviceId,
    required this.message,
    required this.type,
    required this.queuedAt,
    this.retryCount = 0,
    this.lastRetryAt,
    this.lastError,
    this.metadata,
    this.priority = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'device_id': deviceId,
      'message': message,
      'type': type.name,
      'queued_at': queuedAt.millisecondsSinceEpoch,
      'retry_count': retryCount,
      'last_retry_at': lastRetryAt?.millisecondsSinceEpoch,
      'last_error': lastError,
      'metadata': metadata != null ? jsonEncode(metadata!) : null,
      'priority': priority,
    };
  }

  factory QueuedMessage.fromMap(Map<String, dynamic> map) {
    return QueuedMessage(
      id: map['id'],
      sessionId: map['session_id'],
      deviceId: map['device_id'],
      message: map['message'],
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      queuedAt: DateTime.fromMillisecondsSinceEpoch(map['queued_at']),
      retryCount: map['retry_count'] ?? 0,
      lastRetryAt: map['last_retry_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_retry_at'])
          : null,
      lastError: map['last_error'],
      metadata: map['metadata'] != null ? jsonDecode(map['metadata']) : null,
      priority: map['priority'] ?? 0,
    );
  }

  QueuedMessage copyWith({
    int? retryCount,
    DateTime? lastRetryAt,
    String? lastError,
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
      lastError: lastError ?? this.lastError,
      metadata: metadata ?? this.metadata,
      priority: priority,
    );
  }

  bool get isExpired {
    final maxAge = priority >= 2 ? Duration(hours: 24) : Duration(hours: 6);
    return DateTime.now().difference(queuedAt) > maxAge;
  }

  bool get shouldRetry {
    if (isExpired || retryCount >= _getMaxRetries()) return false;

    if (lastRetryAt == null) return true;

    final retryDelay = _getRetryDelay();
    return DateTime.now().difference(lastRetryAt!) >= retryDelay;
  }

  int _getMaxRetries() {
    switch (priority) {
      case 2: return 10; // Emergency messages
      case 1: return 7;  // High priority
      default: return 5; // Normal messages
    }
  }

  Duration _getRetryDelay() {
    // Exponential backoff with jitter
    final baseDelay = Duration(seconds: 30);
    final backoffMultiplier = (retryCount * retryCount).clamp(1, 10);
    final jitter = Duration(seconds: DateTime.now().millisecond % 10);

    return baseDelay * backoffMultiplier + jitter;
  }
}

/// Improved message queue service with better error handling and limits
class MessageQueueService extends ChangeNotifier {
  static final MessageQueueService _instance = MessageQueueService._internal();
  factory MessageQueueService() => _instance;
  MessageQueueService._internal() {
    _initializeEventListeners();
  }

  // Configuration
  static const String _queueTableName = 'message_queue';
  static const int _maxQueueSizePerDevice = 100;
  static const int _maxTotalQueueSize = 500;
  static const Duration _processInterval = Duration(seconds: 10);
  static const Duration _cleanupInterval = Duration(hours: 1);

  // State
  final Map<String, List<QueuedMessage>> _deviceQueues = {};
  Timer? _processTimer;
  Timer? _cleanupTimer;
  bool _isProcessing = false;
  // Device-level processing locks to prevent duplicate queue processing
  final Map<String, bool> _deviceProcessingLocks = {};

  // Event subscriptions
  late StreamSubscription<DeviceConnectionEvent> _deviceConnectedSub;
  late StreamSubscription<DeviceDisconnectionEvent> _deviceDisconnectedSub;

  // Statistics
  int _totalMessagesQueued = 0;
  int _totalMessagesSent = 0;
  int _totalMessagesFailed = 0;

  // Getters
  bool get isProcessing => _isProcessing;
  int get totalQueueSize => _deviceQueues.values.fold(0, (sum, queue) => sum + queue.length);
  Map<String, int> get queueSizes => _deviceQueues.map((device, queue) => MapEntry(device, queue.length));

  Map<String, dynamic> get statistics => {
    'totalQueued': _totalMessagesQueued,
    'totalSent': _totalMessagesSent,
    'totalFailed': _totalMessagesFailed,
    'currentQueueSize': totalQueueSize,
    'queuesByDevice': queueSizes,
  };

  // Initialize the service
  Future<void> initialize() async {
    await _createQueueTable();
    await _loadQueueFromDatabase();
    _startProcessing();
    _startCleanupTimer();
    debugPrint('📤 Enhanced Message Queue Service initialized');
  }

  void _initializeEventListeners() {
    final eventBus = P2PEventBus();

    _deviceConnectedSub = eventBus.onDeviceConnectedListen((event) {
      debugPrint('📱 Device connected: ${event.deviceId}, processing queue...');
      _processQueueForDevice(event.deviceId);
    });

    _deviceDisconnectedSub = eventBus.onDeviceDisconnectedListen((event) {
      debugPrint('📱 Device disconnected: ${event.deviceId}');
    });
  }

  // Create enhanced queue table
  Future<void> _createQueueTable() async {
    try {
      final db = await DatabaseManager.database;
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
          last_error TEXT,
          metadata TEXT,
          priority INTEGER DEFAULT 0,
          created_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_enhanced_queue_device ON $_queueTableName (device_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_enhanced_queue_priority ON $_queueTableName (priority DESC, queued_at ASC)');
    } catch (e) {
      debugPrint('❌ Error creating enhanced queue table: $e');
    }
  }

  // Load queue from database
  Future<void> _loadQueueFromDatabase() async {
    try {
      final db = await DatabaseManager.database;
      final results = await db.query(
        _queueTableName,
        orderBy: 'priority DESC, queued_at ASC',
      );

      _deviceQueues.clear();

      for (final row in results) {
        final queuedMessage = QueuedMessage.fromMap(row);

        // Skip expired messages
        if (queuedMessage.isExpired) {
          await _removeMessageFromDatabase(queuedMessage.id);
          continue;
        }

        _deviceQueues.putIfAbsent(queuedMessage.deviceId, () => []).add(queuedMessage);
      }

      debugPrint('📤 Loaded ${results.length} messages from queue database');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading queue from database: $e');
    }
  }


  // Queue a message with enhanced options
  Future<String?> queueMessage({
    required String sessionId,
    required String deviceId,
    required String message,
    required MessageType type,
    Map<String, dynamic>? metadata,
    int priority = 0,
  }) async {
    try {
      // Check total queue size limit
      if (totalQueueSize >= _maxTotalQueueSize) {
        debugPrint('⚠️ Total queue size limit reached, removing oldest normal priority messages');
        await _removeOldestNormalPriorityMessages();
      }

      // Check per-device queue size limit
      final deviceQueue = _deviceQueues[deviceId] ?? [];
      if (deviceQueue.length >= _maxQueueSizePerDevice) {
        debugPrint('⚠️ Device queue size limit reached for $deviceId, removing oldest message');
        await _removeOldestMessageForDevice(deviceId);
      }

      final messageId = 'enhanced_${DateTime.now().millisecondsSinceEpoch}_${deviceId.hashCode}';
      final queuedMessage = QueuedMessage(
        id: messageId,
        sessionId: sessionId,
        deviceId: deviceId,
        message: message,
        type: type,
        queuedAt: DateTime.now(),
        priority: priority,
        metadata: metadata,
      );

      // Add to memory queue
      _deviceQueues.putIfAbsent(deviceId, () => []).add(queuedMessage);

      // Sort by priority
      _deviceQueues[deviceId]!.sort((a, b) {
        final priorityComparison = b.priority.compareTo(a.priority);
        if (priorityComparison != 0) return priorityComparison;
        return a.queuedAt.compareTo(b.queuedAt);
      });

      // Save to database
      await _saveMessageToDatabase(queuedMessage);

      _totalMessagesQueued++;
      notifyListeners();

      debugPrint('📥 Message queued for $deviceId (priority: $priority): $message');

      // Try to send immediately if device is available
      await _processQueueForDevice(deviceId);

      return messageId;
    } catch (e) {
      debugPrint('❌ Error queuing message: $e');
      return null;
    }
  }

  // Process queue for specific device
  Future<void> _processQueueForDevice(String deviceId) async {
    // Check if this device queue is already being processed
    if (_deviceProcessingLocks[deviceId] == true) {
      debugPrint('⚠️ Device queue already being processed for $deviceId, skipping...');
      return;
    }

    final deviceQueue = _deviceQueues[deviceId];
    if (deviceQueue == null || deviceQueue.isEmpty) return;

    // Set processing lock for this device
    _deviceProcessingLocks[deviceId] = true;

    try {
      final messagesToRemove = <QueuedMessage>[];

      for (final queuedMessage in List.from(deviceQueue)) {
        // Check if message is expired
        if (queuedMessage.isExpired) {
          debugPrint('⏰ Message expired: ${queuedMessage.id}');
          messagesToRemove.add(queuedMessage);
          continue;
        }

        // Check if message should be retried
        if (!queuedMessage.shouldRetry) {
          continue;
        }

        try {
          // Attempt to send the message
          final success = await _sendQueuedMessage(queuedMessage);

          if (success) {
            debugPrint('✅ Queued message sent successfully: ${queuedMessage.id}');
            messagesToRemove.add(queuedMessage);
            _totalMessagesSent++;

            // Emit success event
            P2PEventBus().emitMessageSendStatus(
              messageId: queuedMessage.id,
              status: MessageStatus.sent,
            );
          } else {
            // Update retry count and error
            final updatedMessage = queuedMessage.copyWith(
              retryCount: queuedMessage.retryCount + 1,
              lastRetryAt: DateTime.now(),
              lastError: 'Send failed',
            );

            final index = deviceQueue.indexOf(queuedMessage);
            if (index != -1) {
              deviceQueue[index] = updatedMessage;
              await _updateMessageInDatabase(updatedMessage);
            }

            debugPrint('⚠️ Message send failed, retry ${updatedMessage.retryCount}: ${queuedMessage.id}');
          }
        } catch (e) {
          debugPrint('❌ Error processing queued message: $e');

          // Update retry count and error
          final updatedMessage = queuedMessage.copyWith(
            retryCount: queuedMessage.retryCount + 1,
            lastRetryAt: DateTime.now(),
            lastError: e.toString(),
          );

          final index = deviceQueue.indexOf(queuedMessage);
          if (index != -1) {
            deviceQueue[index] = updatedMessage;
            await _updateMessageInDatabase(updatedMessage);
          }
        }
      }

      // Remove successfully sent or expired messages
      for (final message in messagesToRemove) {
        deviceQueue.remove(message);
        await _removeMessageFromDatabase(message.id);

        if (message.isExpired || message.retryCount >= message._getMaxRetries()) {
          _totalMessagesFailed++;

          // Emit failure event
          P2PEventBus().emitMessageSendStatus(
            messageId: message.id,
            status: MessageStatus.failed,
            error: message.lastError,
          );
        }
      }

      // Clean up empty device queues
      if (deviceQueue.isEmpty) {
        _deviceQueues.remove(deviceId);
      }

      notifyListeners();
    } finally {
      // Always release the processing lock for this device
      _deviceProcessingLocks[deviceId] = false;
    }
  }

  // Start periodic processing
  void _startProcessing() {
    _processTimer?.cancel();
    _processTimer = Timer.periodic(_processInterval, (_) {
      if (!_isProcessing) {
        _processAllQueues();
      }
    });
  }

  // Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  // Process all device queues
  Future<void> _processAllQueues() async {
    if (_isProcessing) return;

    _isProcessing = true;
    try {
      for (final deviceId in _deviceQueues.keys.toList()) {
        await _processQueueForDevice(deviceId);
      }
    } finally {
      _isProcessing = false;
    }
  }

  // Perform cleanup of old and failed messages
  Future<void> _performCleanup() async {
    try {
      debugPrint('🧹 Performing message queue cleanup...');

      // Remove expired messages
      var removedCount = 0;
      for (final deviceId in _deviceQueues.keys.toList()) {
        final queue = _deviceQueues[deviceId]!;
        final toRemove = queue.where((msg) => msg.isExpired).toList();

        for (final msg in toRemove) {
          queue.remove(msg);
          await _removeMessageFromDatabase(msg.id);
          removedCount++;
        }

        if (queue.isEmpty) {
          _deviceQueues.remove(deviceId);
        }
      }

      // Cleanup database
      final db = await DatabaseManager.database;
      final dbRemovedCount = await db.delete(
        _queueTableName,
        where: 'queued_at < ?',
        whereArgs: [DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch],
      );

      debugPrint('🧹 Cleanup completed: $removedCount from memory, $dbRemovedCount from database');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error during cleanup: $e');
    }
  }

  // P2P service reference for sending messages
  static dynamic _p2pService;

  // Setter to inject P2P service dependency
  static void setP2PService(dynamic p2pService) {
    _p2pService = p2pService;
  }

  // Send queued message using actual P2P service
  Future<bool> _sendQueuedMessage(QueuedMessage queuedMessage) async {
    if (_p2pService == null) {
      debugPrint('❌ P2P service not available for sending queued message');
      return false;
    }

    try {
      // Check if we're connected to the target device
      final connectedDevices = _p2pService.connectedDevices ?? <String, dynamic>{};
      if (!connectedDevices.containsKey(queuedMessage.deviceId)) {
        debugPrint('❌ Device ${queuedMessage.deviceId} not connected, cannot send queued message');
        return false;
      }

      // Get sender name from P2P service
      final senderName = _p2pService.userName ?? 'Unknown User';

      // Send the message using P2P service
      await _p2pService.sendMessage(
        message: queuedMessage.message,
        type: queuedMessage.type,
        targetDeviceId: queuedMessage.deviceId,
        senderName: senderName,
        id: queuedMessage.id,
      );

      debugPrint('✅ Successfully sent queued message: ${queuedMessage.id} to ${queuedMessage.deviceId}');
      return true;

    } catch (e) {
      debugPrint('❌ Error sending queued message ${queuedMessage.id}: $e');
      return false;
    }
  }

  // Database helper methods
  Future<void> _saveMessageToDatabase(QueuedMessage message) async {
    try {
      final db = await DatabaseManager.database;
      await db.insert(_queueTableName, message.toMap());
    } catch (e) {
      debugPrint('❌ Error saving message to database: $e');
    }
  }

  Future<void> _updateMessageInDatabase(QueuedMessage message) async {
    try {
      final db = await DatabaseManager.database;
      await db.update(
        _queueTableName,
        message.toMap(),
        where: 'id = ?',
        whereArgs: [message.id],
      );
    } catch (e) {
      debugPrint('❌ Error updating message in database: $e');
    }
  }

  Future<void> _removeMessageFromDatabase(String messageId) async {
    try {
      final db = await DatabaseManager.database;
      await db.delete(
        _queueTableName,
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Error removing message from database: $e');
    }
  }

  // Queue management methods
  Future<void> _removeOldestNormalPriorityMessages() async {
    try {
      final allMessages = <QueuedMessage>[];
      for (final queue in _deviceQueues.values) {
        allMessages.addAll(queue.where((msg) => msg.priority == 0));
      }

      if (allMessages.isNotEmpty) {
        allMessages.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
        final oldestMessage = allMessages.first;

        _deviceQueues[oldestMessage.deviceId]?.remove(oldestMessage);
        await _removeMessageFromDatabase(oldestMessage.id);

        debugPrint('🗑️ Removed oldest normal priority message: ${oldestMessage.id}');
      }
    } catch (e) {
      debugPrint('❌ Error removing oldest normal priority messages: $e');
    }
  }

  Future<void> _removeOldestMessageForDevice(String deviceId) async {
    try {
      final queue = _deviceQueues[deviceId];
      if (queue != null && queue.isNotEmpty) {
        // Find oldest non-emergency message
        final nonEmergency = queue.where((msg) => msg.priority < 2).toList();
        if (nonEmergency.isNotEmpty) {
          nonEmergency.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
          final oldestMessage = nonEmergency.first;

          queue.remove(oldestMessage);
          await _removeMessageFromDatabase(oldestMessage.id);

          debugPrint('🗑️ Removed oldest message for device $deviceId: ${oldestMessage.id}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error removing oldest message for device: $e');
    }
  }

  // Public methods for external integration
  Future<void> clearQueueForDevice(String deviceId) async {
    try {
      final queue = _deviceQueues[deviceId];
      if (queue != null) {
        for (final message in queue) {
          await _removeMessageFromDatabase(message.id);
        }
        _deviceQueues.remove(deviceId);
        notifyListeners();
        debugPrint('🧹 Cleared queue for device: $deviceId');
      }
    } catch (e) {
      debugPrint('❌ Error clearing queue for device: $e');
    }
  }

  Future<void> clearAllQueues() async {
    try {
      final db = await DatabaseManager.database;
      await db.delete(_queueTableName);
      _deviceQueues.clear();
      notifyListeners();
      debugPrint('🧹 Cleared all message queues');
    } catch (e) {
      debugPrint('❌ Error clearing all queues: $e');
    }
  }

  /// EMERGENCY: Clear message backlog and duplicate messages
  Future<void> emergencyCleanup() async {
    try {
      debugPrint('🚨 EMERGENCY CLEANUP: Starting...');

      final db = await DatabaseManager.database;

      // 1. Clear all queued messages
      await db.delete(_queueTableName);
      _deviceQueues.clear();

      // 2. Remove duplicate messages from main messages table
      await db.rawDelete('''
        DELETE FROM messages
        WHERE id NOT IN (
          SELECT MIN(id)
          FROM messages
          GROUP BY messageId
        )
      ''');

      // 3. Remove messages older than 1 hour to reduce load
      final oneHourAgo = DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch;
      await db.rawDelete('DELETE FROM messages WHERE timestamp < ?', [oneHourAgo]);

      // 4. Reset processing caches
      if (MessageRepository.processingMessageIds.isNotEmpty) {
        MessageRepository.processingMessageIds.clear();
      }
      if (MessageRepository.recentlyProcessed.isNotEmpty) {
        MessageRepository.recentlyProcessed.clear();
      }

      notifyListeners();
      debugPrint('🚨 EMERGENCY CLEANUP: Completed successfully');

    } catch (e) {
      debugPrint('❌ EMERGENCY CLEANUP FAILED: $e');
    }
  }

  List<QueuedMessage> getQueueForDevice(String deviceId) {
    return List.from(_deviceQueues[deviceId] ?? []);
  }

  /// Get total count of all queued messages across all devices
  int getTotalQueuedMessageCount() {
    int total = 0;
    for (final queue in _deviceQueues.values) {
      total += queue.length;
    }
    return total;
  }

  Future<void> processQueueForDevice(String deviceId) async {
    await _processQueueForDevice(deviceId);
  }

  /// Process all queues for all devices
  Future<void> processAllQueues() async {
    debugPrint('🔄 Processing all message queues');
    await _processAllQueues();
  }

  // Dispose
  @override
  void dispose() {
    _processTimer?.cancel();
    _cleanupTimer?.cancel();
    _deviceConnectedSub.cancel();
    _deviceDisconnectedSub.cancel();
    super.dispose();
    debugPrint('🧹 Enhanced Message Queue Service disposed');
  }
}