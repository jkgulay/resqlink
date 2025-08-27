import 'dart:convert';
import 'dart:async';
import 'package:resqlink/services/p2p_service.dart';
import 'database_service.dart';

class QueuedMessage {
  final P2PMessage message;
  final DateTime timestamp;
  int retryCount;

  QueuedMessage({
    required this.message,
    required this.timestamp,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message.toJson(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retryCount': retryCount,
    };
  }

  factory QueuedMessage.fromJson(Map<String, dynamic> json) {
    return QueuedMessage(
      message: P2PMessage.fromJson(json['message']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

class EnhancedMessageQueue {
  final Map<String, List<QueuedMessage>> _deviceQueues = {};
  final Future<void> Function(String deviceId, String message)?
  _sendToDevice; // Fixed: Future<void>

  EnhancedMessageQueue({
    Future<void> Function(String deviceId, String message)?
    sendToDevice, // Fixed: Future<void>
  }) : _sendToDevice = sendToDevice;

  Future<void> queueMessage(String deviceId, P2PMessage message) async {
    _deviceQueues.putIfAbsent(deviceId, () => []);
    _deviceQueues[deviceId]!.add(
      QueuedMessage(message: message, timestamp: DateTime.now(), retryCount: 0),
    );

    // Save to database immediately
    await _savePendingMessages();
  }

  Future<void> processQueueForDevice(String deviceId) async {
    final queue = _deviceQueues[deviceId] ?? [];
    final toRemove = <QueuedMessage>[];

    for (final queuedMsg in queue) {
      try {
        if (_sendToDevice != null) {
          await _sendToDevice(
            // Fixed: removed !
            deviceId,
            jsonEncode(queuedMsg.message.toJson()),
          );
          toRemove.add(queuedMsg);
        }
      } catch (e) {
        queuedMsg.retryCount++;
        if (queuedMsg.retryCount > 3) {
          toRemove.add(queuedMsg);
        }
      }
    }

    // Remove processed/failed messages
    for (final msg in toRemove) {
      queue.remove(msg);
    }

    if (queue.isEmpty) {
      _deviceQueues.remove(deviceId);
    }

    await _savePendingMessages();
  }

  Future<void> processAllQueues() async {
    final deviceIds = List<String>.from(_deviceQueues.keys);
    for (final deviceId in deviceIds) {
      await processQueueForDevice(deviceId);
    }
  }

  int getQueueLength(String deviceId) {
    return _deviceQueues[deviceId]?.length ?? 0;
  }

  int getTotalQueuedMessages() {
    return _deviceQueues.values.fold(0, (sum, queue) => sum + queue.length);
  }

  Map<String, int> getQueueSummary() {
    return _deviceQueues.map(
      (deviceId, queue) => MapEntry(deviceId, queue.length),
    );
  }

  void clearQueue(String deviceId) {
    _deviceQueues.remove(deviceId);
    _savePendingMessages();
  }

  void clearAllQueues() {
    _deviceQueues.clear();
    _savePendingMessages();
  }

  Future<void> _savePendingMessages() async {
    try {
      // Convert to format expected by DatabaseService
      final pendingMessages = <String, List<PendingMessage>>{};

      for (final entry in _deviceQueues.entries) {
        pendingMessages[entry.key] = entry.value
            .map(
              (queuedMsg) => PendingMessage(
                message: queuedMsg.message,
                queuedAt: queuedMsg.timestamp,
                attempts: queuedMsg.retryCount,
              ),
            )
            .toList();
      }

      await DatabaseService.savePendingMessages(pendingMessages);
    } catch (e) {
      print('❌ Error saving pending messages: $e');
    }
  }

  Future<void> loadPendingMessages() async {
    try {
      final pending = await DatabaseService.getPendingMessagesMap();

      _deviceQueues.clear();

      for (final entry in pending.entries) {
        _deviceQueues[entry.key] = entry.value
            .map(
              (pendingMsg) => QueuedMessage(
                message: pendingMsg.message,
                timestamp: pendingMsg.queuedAt,
                retryCount: pendingMsg.attempts,
              ),
            )
            .toList();
      }
    } catch (e) {
      print('❌ Error loading pending messages: $e');
    }
  }
}
