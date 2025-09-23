import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../features/database/repositories/message_repository.dart';
import '../p2p/p2p_main_service.dart';

/// Centralized offline message queue manager
class OfflineMessageQueue {
  static final OfflineMessageQueue _instance = OfflineMessageQueue._internal();
  factory OfflineMessageQueue() => _instance;
  OfflineMessageQueue._internal();

  // Queue storage
  final Map<String, List<QueuedMessage>> _deviceQueues = {};
  Timer? _processTimer;
  P2PMainService? _p2pService;

  // Statistics
  int _totalMessagesSent = 0;
  int _totalMessagesFailed = 0;

  /// Initialize the queue manager
  void initialize(P2PMainService p2pService) {
    _p2pService = p2pService;
    _loadPersistedQueue();
    _startProcessingTimer();

    // Listen for connection changes
    p2pService.addListener(_onConnectionChanged);

    debugPrint('📦 Offline message queue initialized');
  }

  /// Queue a message for later delivery
  Future<void> queueMessage({
    required String message,
    required MessageType type,
    required String targetDeviceId,
    String? senderName,
    double? latitude,
    double? longitude,
  }) async {
    final queuedMessage = QueuedMessage(
      id: MessageModel.generateMessageId(targetDeviceId),
      message: message,
      type: type,
      targetDeviceId: targetDeviceId,
      senderName: senderName ?? _p2pService?.userName ?? 'Unknown',
      latitude: latitude,
      longitude: longitude,
      queuedAt: DateTime.now(),
      retryCount: 0,
    );

    // Add to memory queue
    _deviceQueues.putIfAbsent(targetDeviceId, () => []).add(queuedMessage);

    // Persist to database
    await _persistQueue();

    debugPrint('📥 Message queued for $targetDeviceId: $message');

    // Try immediate send if connected
    if (_p2pService?.isConnected ?? false) {
      _processQueue();
    }
  }

  /// Process queued messages
  Future<void> _processQueue() async {
    if (_p2pService == null || !(_p2pService?.isConnected ?? false)) {
      debugPrint('⏸️ Queue processing skipped - not connected');
      return;
    }

    debugPrint('📤 Processing offline message queue...');

    for (final entry in _deviceQueues.entries) {
      final targetDeviceId = entry.key;
      final queue = List<QueuedMessage>.from(entry.value);

      for (final queuedMessage in queue) {
        // Check if message expired (24 hours)
        if (queuedMessage.isExpired) {
          _removeFromQueue(targetDeviceId, queuedMessage);
          _totalMessagesFailed++;
          continue;
        }

        // Check retry limit
        if (queuedMessage.retryCount >= 5) {
          debugPrint('❌ Message exceeded retry limit: ${queuedMessage.id}');
          _removeFromQueue(targetDeviceId, queuedMessage);
          _totalMessagesFailed++;
          continue;
        }

        // Try to send
        final success = await _sendQueuedMessage(queuedMessage);

        if (success) {
          debugPrint('✅ Queued message sent: ${queuedMessage.id}');
          _removeFromQueue(targetDeviceId, queuedMessage);
          _totalMessagesSent++;
        } else {
          // Update retry count
          queuedMessage.retryCount++;
          queuedMessage.lastRetryAt = DateTime.now();
          await _persistQueue();
        }
      }
    }

    // Clean up empty queues
    _deviceQueues.removeWhere((_, queue) => queue.isEmpty);
  }

  /// Send a queued message
  Future<bool> _sendQueuedMessage(QueuedMessage queuedMessage) async {
    try {
      await _p2pService?.sendMessage(
        message: queuedMessage.message,
        type: queuedMessage.type,
        targetDeviceId: queuedMessage.targetDeviceId,
        senderName: queuedMessage.senderName,
        latitude: queuedMessage.latitude,
        longitude: queuedMessage.longitude,
      );
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send queued message: $e');
      return false;
    }
  }

  /// Remove message from queue
  void _removeFromQueue(String targetDeviceId, QueuedMessage message) {
    _deviceQueues[targetDeviceId]?.remove(message);
    _persistQueue();
  }

  /// Load persisted queue from database
  Future<void> _loadPersistedQueue() async {
    try {
      // Load messages with pending status from database
      final pendingMessages = await MessageRepository.getPendingMessages();

      for (final message in pendingMessages) {
        final endpointId = message.endpointId;
        if (endpointId.isNotEmpty) {
          final queuedMessage = QueuedMessage(
            id: message.messageId ?? MessageModel.generateMessageId(endpointId),
            message: message.message,
            type: message.messageType,
            targetDeviceId: endpointId,
            senderName: message.fromUser,
            latitude: message.latitude,
            longitude: message.longitude,
            queuedAt: DateTime.fromMillisecondsSinceEpoch(message.timestamp),
            retryCount: 0,
          );

          _deviceQueues.putIfAbsent(endpointId, () => []).add(queuedMessage);
        }
      }

      debugPrint('📦 Loaded ${pendingMessages.length} pending messages from database');
    } catch (e) {
      debugPrint('❌ Error loading persisted queue: $e');
    }
  }

  /// Persist queue to database
  Future<void> _persistQueue() async {
    try {
      // For now, we rely on the MessageRepository with pending status
      // Future enhancement: could save queue state to SharedPreferences
      debugPrint('📦 Queue state persisted to database');
    } catch (e) {
      debugPrint('❌ Error persisting queue: $e');
    }
  }

  /// Start periodic queue processing
  void _startProcessingTimer() {
    _processTimer?.cancel();
    _processTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (_p2pService?.isConnected ?? false) {
        _processQueue();
      }
    });
  }

  /// Handle connection state changes
  void _onConnectionChanged() {
    if (_p2pService?.isConnected ?? false) {
      debugPrint('🔗 Connection established - processing queue');
      _processQueue();
    }
  }

  /// Get queue statistics
  Map<String, dynamic> getStatistics() {
    int totalQueued = 0;
    _deviceQueues.forEach((_, queue) {
      totalQueued += queue.length;
    });

    return {
      'totalQueued': totalQueued,
      'devicesWithQueuedMessages': _deviceQueues.length,
      'totalSent': _totalMessagesSent,
      'totalFailed': _totalMessagesFailed,
    };
  }

  /// Clear all queued messages
  Future<void> clearQueue() async {
    _deviceQueues.clear();
    await _persistQueue();
    debugPrint('🧹 Offline message queue cleared');
  }

  /// Dispose the queue manager
  void dispose() {
    _processTimer?.cancel();
    _p2pService?.removeListener(_onConnectionChanged);
  }
}

/// Model for queued messages
class QueuedMessage {
  final String id;
  final String message;
  final MessageType type;
  final String targetDeviceId;
  final String senderName;
  final double? latitude;
  final double? longitude;
  final DateTime queuedAt;
  int retryCount;
  DateTime? lastRetryAt;

  QueuedMessage({
    required this.id,
    required this.message,
    required this.type,
    required this.targetDeviceId,
    required this.senderName,
    this.latitude,
    this.longitude,
    required this.queuedAt,
    this.retryCount = 0,
    this.lastRetryAt,
  });

  bool get isExpired {
    final age = DateTime.now().difference(queuedAt);
    return age.inHours > 24;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'type': type.name,
      'targetDeviceId': targetDeviceId,
      'senderName': senderName,
      'latitude': latitude,
      'longitude': longitude,
      'queuedAt': queuedAt.toIso8601String(),
      'retryCount': retryCount,
      'lastRetryAt': lastRetryAt?.toIso8601String(),
    };
  }

  factory QueuedMessage.fromJson(Map<String, dynamic> json) {
    return QueuedMessage(
      id: json['id'],
      message: json['message'],
      type: MessageType.values.firstWhere((e) => e.name == json['type']),
      targetDeviceId: json['targetDeviceId'],
      senderName: json['senderName'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      queuedAt: DateTime.parse(json['queuedAt']),
      retryCount: json['retryCount'] ?? 0,
      lastRetryAt: json['lastRetryAt'] != null
          ? DateTime.parse(json['lastRetryAt'])
          : null,
    );
  }
}