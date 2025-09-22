import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../features/database/repositories/message_repository.dart';

class MessageRouter {
  static final MessageRouter _instance = MessageRouter._internal();
  factory MessageRouter() => _instance;
  MessageRouter._internal();

  // Message listeners by device ID
  final Map<String, Function(MessageModel)> _deviceListeners = {};

  // Global message listener
  Function(MessageModel)? _globalListener;

  // Message queue for offline devices
  final Map<String, List<MessageModel>> _messageQueue = {};

  /// Register a listener for a specific device
  void registerDeviceListener(String deviceId, Function(MessageModel) listener) {
    _deviceListeners[deviceId] = listener;
    debugPrint('=ñ Registered listener for device: $deviceId');

    // Process queued messages
    _processQueuedMessages(deviceId);
  }

  /// Unregister device listener
  void unregisterDeviceListener(String deviceId) {
    _deviceListeners.remove(deviceId);
    debugPrint('= Unregistered listener for device: $deviceId');
  }

  /// Set global message listener
  void setGlobalListener(Function(MessageModel) listener) {
    _globalListener = listener;
  }

  /// Route incoming message to appropriate handler
  Future<void> routeMessage(MessageModel message) async {
    try {
      debugPrint('=è Routing message from ${message.fromUser} to ${message.endpointId}');

      // Save to database first
      await MessageRepository.insertMessage(message);

      // Notify global listener
      _globalListener?.call(message);

      // Route to specific device listener
      final targetDevice = message.endpointId != 'broadcast' ? message.endpointId : null;
      if (targetDevice != null) {
        final listener = _deviceListeners[targetDevice];
        if (listener != null) {
          listener(message);
        } else {
          // Queue message if no listener available
          _queueMessage(targetDevice, message);
        }
      }

      // Broadcast to all listeners for broadcast messages
      if (message.endpointId == 'broadcast' || message.isBroadcast) {
        _deviceListeners.forEach((deviceId, listener) {
          listener(message);
        });
      }
    } catch (e) {
      debugPrint('L Error routing message: $e');
    }
  }

  /// Queue message for offline device
  void _queueMessage(String deviceId, MessageModel message) {
    _messageQueue.putIfAbsent(deviceId, () => []).add(message);
    debugPrint('=æ Message queued for device: $deviceId');
  }

  /// Process queued messages for a device
  void _processQueuedMessages(String deviceId) {
    final messages = _messageQueue[deviceId];
    if (messages != null && messages.isNotEmpty) {
      final listener = _deviceListeners[deviceId];
      if (listener != null) {
        for (final message in messages) {
          listener(message);
        }
        _messageQueue.remove(deviceId);
        debugPrint(' Processed ${messages.length} queued messages for $deviceId');
      }
    }
  }

  /// Parse and route raw message data
  Future<void> routeRawMessage(String rawMessage, String? fromDevice) async {
    try {
      final data = jsonDecode(rawMessage);

      // Extract message details
      final messageModel = MessageModel(
        messageId: data['messageId'] ?? MessageModel.generateMessageId(fromDevice ?? 'unknown'),
        endpointId: data['targetDeviceId'] ?? data['endpointId'] ?? fromDevice ?? 'unknown',
        deviceId: data['deviceId'] ?? fromDevice,
        fromUser: data['senderName'] ?? data['from'] ?? data['fromUser'] ?? 'Unknown',
        message: data['message'] ?? '',
        isMe: false,
        isEmergency: data['isEmergency'] ?? false,
        timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        messageType: MessageType.values.firstWhere(
          (t) => t.name == (data['messageType'] ?? data['type'] ?? 'text'),
          orElse: () => MessageType.text,
        ),
        type: data['type'] ?? 'text',
        status: MessageStatus.received,
        latitude: data['latitude']?.toDouble(),
        longitude: data['longitude']?.toDouble(),
        targetDeviceId: data['targetDeviceId'],
      );

      await routeMessage(messageModel);
    } catch (e) {
      debugPrint('L Error parsing raw message: $e');
    }
  }

  /// Clear all queued messages
  void clearQueues() {
    _messageQueue.clear();
    debugPrint('>ù Cleared all message queues');
  }

  /// Get active device listeners
  List<String> getActiveDevices() {
    return _deviceListeners.keys.toList();
  }

  /// Check if device has active listener
  bool hasListener(String deviceId) {
    return _deviceListeners.containsKey(deviceId);
  }

  /// Get queued message count for device
  int getQueuedMessageCount(String deviceId) {
    return _messageQueue[deviceId]?.length ?? 0;
  }

  /// Clear queue for specific device
  void clearDeviceQueue(String deviceId) {
    _messageQueue.remove(deviceId);
    debugPrint('>ù Cleared queue for device: $deviceId');
  }
}

/// Extension to add isBroadcast getter to MessageModel
extension MessageModelExtensions on MessageModel {
  /// Check if this is a broadcast message
  bool get isBroadcast => endpointId == 'broadcast' || targetDeviceId == 'broadcast';
}