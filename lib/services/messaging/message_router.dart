import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../models/chat_session_model.dart';
import '../../features/database/repositories/message_repository.dart';
import '../../features/database/repositories/chat_repository.dart';

import '../chat/session_deduplication_service.dart';
import '../../utils/session_consistency_checker.dart';

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
  
  // Track device connections for proper routing
  final Map<String, String> _deviceConnections = {};

  // Message deduplication to prevent duplicate processing
  final Set<String> _processedMessageIds = {};
  final Map<String, DateTime> _messageTimestamps = {};
  static const Duration _deduplicationWindow = Duration(minutes: 5); 

  void registerDeviceConnection(String deviceId, String socketId) {
    _deviceConnections[socketId] = deviceId;
    debugPrint('🔗 Registered device connection: $deviceId -> $socketId');
  }

  /// Register a listener for a specific device
  void registerDeviceListener(String deviceId, Function(MessageModel) listener) {
    _deviceListeners[deviceId] = listener;
    debugPrint('📱 Registered listener for device: $deviceId');

    // Process queued messages
    _processQueuedMessages(deviceId);
  }

  /// Unregister device listener
  void unregisterDeviceListener(String deviceId) {
    _deviceListeners.remove(deviceId);
    debugPrint('🔕 Unregistered listener for device: $deviceId');
  }

  /// Set global message listener
  void setGlobalListener(Function(MessageModel) listener) {
    _globalListener = listener;
  }

  Future<void> routeMessage(MessageModel message) async {
    try {
      final messageId = message.messageId ?? 'unknown';

      // Check for duplicate messages
      if (_processedMessageIds.contains(messageId)) {
        debugPrint('⚠️ Duplicate message blocked by MessageRouter: $messageId');
        return;
      }

      // Clean up old entries periodically
      _cleanupOldEntries();

      // Mark as processed
      _processedMessageIds.add(messageId);
      _messageTimestamps[messageId] = DateTime.now();

      debugPrint('📨 Routing message:');
      debugPrint('  From: ${message.fromUser} (${message.deviceId})');
      debugPrint('  To: ${message.endpointId}');
      debugPrint('  Message: ${message.message}');

      await MessageRepository.insertMessage(message);

      // CRITICAL FIX: Update lastConnectionAt to keep session showing as "online"
      // This prevents the "disconnected" status when messages are actively being exchanged
      if (message.chatSessionId != null) {
        try {
          await ChatRepository.updateConnection(
            sessionId: message.chatSessionId!,
            connectionType: ConnectionType.wifiDirect,
            connectionTime: DateTime.now(),
          );
        } catch (e) {
          debugPrint('⚠️ Failed to update connection time: $e');
        }
      }

      _globalListener?.call(message);

      final senderDeviceId = message.deviceId;
      
      if (!message.isMe && senderDeviceId != null) {
        final senderListener = _deviceListeners[senderDeviceId];
        if (senderListener != null) {
          debugPrint('✅ Routing to sender chat: $senderDeviceId');
          senderListener(message);
        } else {
          // Queue for sender's chat if not open
          _queueMessage(senderDeviceId, message);
        }
      }
      
      // Handle targeted messages (both sent and received)
      if (message.targetDeviceId != null && message.targetDeviceId != 'broadcast') {
        final targetListener = _deviceListeners[message.targetDeviceId!];
        if (targetListener != null) {
          // Show all messages (sent and received) in target's chat
          debugPrint('✅ Routing message to target chat: ${message.targetDeviceId}');
          targetListener(message);
        } else if (message.isMe) {
          // Queue sent messages for target's chat if not open
          _queueMessage(message.targetDeviceId!, message);
        }
      }

      // Broadcast to all listeners for broadcast messages
      if (message.isBroadcast) {
        debugPrint('📢 Broadcasting message to all listeners');
        _deviceListeners.forEach((deviceId, listener) {
          listener(message);
        });
      }
    } catch (e) {
      debugPrint('❌ Error routing message: $e');
    }
  }

  /// Queue message for offline device
  void _queueMessage(String deviceId, MessageModel message) {
    _messageQueue.putIfAbsent(deviceId, () => []).add(message);
    debugPrint('📦 Message queued for device: $deviceId');
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
        debugPrint('✅ Processed ${messages.length} queued messages for $deviceId');
      }
    }
  }

  /// Clean up old deduplication entries
  void _cleanupOldEntries() {
    final cutoff = DateTime.now().subtract(_deduplicationWindow);
    final toRemove = <String>[];

    _messageTimestamps.forEach((messageId, timestamp) {
      if (timestamp.isBefore(cutoff)) {
        toRemove.add(messageId);
      }
    });

    for (final messageId in toRemove) {
      _processedMessageIds.remove(messageId);
      _messageTimestamps.remove(messageId);
    }

    if (toRemove.isNotEmpty) {
      debugPrint('🧹 Cleaned up ${toRemove.length} old message entries from MessageRouter');
    }
  }

  Future<void> routeRawMessage(String rawMessage, String? fromDevice) async {
    try {
      debugPrint('🔄 Parsing raw message from device: $fromDevice');
      final data = jsonDecode(rawMessage);

      // Handle different message types
      final messageType = data['type'] as String?;
      
      if (messageType == 'handshake' || messageType == 'handshake_response') {
        // Don't route handshake messages as chat messages
        debugPrint('🤝 Ignoring handshake message');
        return;
      }
      
      if (messageType == 'heartbeat' || messageType == 'ack') {
        // Don't route system messages as chat messages
        debugPrint('💓 Ignoring system message: $messageType');
        return;
      }

      // Extract sender information - CRITICAL: use the actual sender's device ID
      final senderDeviceId = data['deviceId'] ?? 
                            data['senderDeviceId'] ?? 
                            fromDevice ?? 
                            'unknown';
      
      final senderName = data['senderName'] ?? 
                        data['from'] ?? 
                        data['fromUser'] ?? 
                        data['userName'] ?? 
                        'Unknown';

      // Extract target information
      final targetDeviceId = data['targetDeviceId'] ?? 
                            data['endpointId'] ?? 
                            'broadcast';

      // CRITICAL: Generate session ID from MAC address (deviceId), NOT display names
      // This ensures messages always go to the correct stable session
      String? chatSessionId = data['chatSessionId'];
      if (chatSessionId == null || chatSessionId.isEmpty) {
        // Use MAC address-based session ID
        chatSessionId = 'chat_${senderDeviceId.replaceAll(':', '_')}';
        debugPrint('📍 Generated MAC-based session ID: $chatSessionId for device: $senderDeviceId');
      }

      // Create message model with proper sender/target mapping
      final messageModel = MessageModel(
        messageId: data['messageId'] ?? MessageModel.generateMessageId(senderDeviceId),
        // CRITICAL: endpointId should be the conversation partner
        // For incoming messages, that's the sender
        endpointId: senderDeviceId, // This is who the message is FROM
        deviceId: senderDeviceId,   // The sender's device ID
        targetDeviceId: targetDeviceId, // Who it was sent TO
        fromUser: senderName,
        message: data['message'] ?? '',
        isMe: false, // This is an incoming message
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
        chatSessionId: chatSessionId,
      );

      debugPrint('📨 Created message model:');
      debugPrint('  Sender: $senderName ($senderDeviceId)');
      debugPrint('  Target: $targetDeviceId');
      debugPrint('  Message: ${messageModel.message}');

      await routeMessage(messageModel);
    } catch (e) {
      debugPrint('❌ Error parsing raw message: $e');
      debugPrint('  Raw message: $rawMessage');
    }
  }

  /// Clear all queued messages
  void clearQueues() {
    _messageQueue.clear();
    _deviceConnections.clear();
    debugPrint('🧹 Cleared all message queues and connections');
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
    debugPrint('🧹 Cleared queue for device: $deviceId');
  }
  
  /// Debug: Print current routing state
  void debugPrintState() {
    debugPrint('📊 MessageRouter State:');
    debugPrint('  Active Listeners: ${_deviceListeners.keys.toList()}');
    debugPrint('  Device Connections: $_deviceConnections');
    debugPrint('  Queued Messages: ${_messageQueue.keys.map((k) => '$k: ${_messageQueue[k]?.length}')}');
  }

  /// Trigger session deduplication (can be called from UI)
  static Future<void> runSessionDeduplication() async {
    try {
      debugPrint('🔧 Starting session deduplication from MessageRouter...');
      final mergedCount = await SessionDeduplicationService.deduplicateAllSessions();
      debugPrint('✅ Session deduplication completed. Merged $mergedCount sessions.');
    } catch (e) {
      debugPrint('❌ Error during session deduplication: $e');
    }
  }

  /// Check session consistency (can be called from UI for debugging)
  static Future<void> checkSessionConsistency() async {
    try {
      debugPrint('🔍 Running session consistency check...');
      final results = await SessionConsistencyChecker.runConsistencyCheck();
      SessionConsistencyChecker.printReport(results);

      final healthScore = results['healthScore'] as Map<String, dynamic>?;
      final totalIssues = healthScore?['totalIssues'] as int? ?? 0;

      if (totalIssues > 0) {
        debugPrint('⚠️ Found $totalIssues consistency issues. Consider running fixSessionInconsistencies()');
      } else {
        debugPrint('✅ All sessions are consistent!');
      }
    } catch (e) {
      debugPrint('❌ Error during consistency check: $e');
    }
  }

  /// Fix session inconsistencies (can be called from UI)
  static Future<void> fixSessionInconsistencies() async {
    try {
      debugPrint('🔧 Fixing session inconsistencies...');
      final success = await SessionConsistencyChecker.fixInconsistencies();

      if (success) {
        debugPrint('✅ All session inconsistencies fixed!');
      } else {
        debugPrint('❌ Some issues could not be fixed automatically');
      }
    } catch (e) {
      debugPrint('❌ Error fixing inconsistencies: $e');
    }
  }
}

/// Extension to add isBroadcast getter to MessageModel
extension MessageModelExtensions on MessageModel {
  /// Check if this is a broadcast message
  bool get isBroadcast => 
      endpointId == 'broadcast' || 
      targetDeviceId == 'broadcast' ||
      endpointId == 'unknown';
}