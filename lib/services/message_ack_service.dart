import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import 'p2p/p2p_main_service.dart';
import 'database_service.dart';

class MessageAcknowledgmentService {
  static final MessageAcknowledgmentService _instance = 
      MessageAcknowledgmentService._internal();
  factory MessageAcknowledgmentService() => _instance;
  MessageAcknowledgmentService._internal();

  final Map<String, DateTime> _pendingAcks = {};
  final Map<String, Timer> _ackTimeouts = {};
  static const Duration _ackTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;

  // Initialize with P2P service
  void initialize(P2PConnectionService p2pService) {
    p2pService.onMessageReceived = (message) {
      _handleIncomingMessage(message as P2PMessage, p2pService);
    };
  }

  // Send message with acknowledgment tracking
  Future<String> sendMessageWithAck(
    P2PConnectionService p2pService, {
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
  }) async {
    final messageId = _generateMessageId();
    
    try {
      // Send the actual message
      await p2pService.sendMessage(
        message: message,
        type: type,
        targetDeviceId: targetDeviceId,
        latitude: latitude,
        longitude: longitude, senderName: '',
      );

      // Track for acknowledgment
      _pendingAcks[messageId] = DateTime.now();
      await DatabaseService.updateMessageStatus(messageId, MessageStatus.sent);

      // Set timeout for retry
      _ackTimeouts[messageId] = Timer(_ackTimeout, () {
        _handleAckTimeout(messageId, p2pService);
      });

      debugPrint("📤 Message sent with ACK tracking: $messageId");
      return messageId;
    } catch (e) {
      await DatabaseService.updateMessageStatus(messageId, MessageStatus.failed);
      rethrow;
    }
  }

  void _handleIncomingMessage(P2PMessage message, P2PConnectionService p2pService) {
    // Send acknowledgment for received messages
    if (message.type != MessageType.system) {
      _sendAcknowledgment(message, p2pService);
    }

    // Handle acknowledgment messages
    if (message.message.startsWith('ACK:')) {
      _handleAcknowledgment(message);
    }
  }

  Future<void> _sendAcknowledgment(
    P2PMessage originalMessage, 
    P2PConnectionService p2pService,
  ) async {
    try {
      final ackMessage = 'ACK:${originalMessage.id}';
      
      await p2pService.sendMessage(
        message: ackMessage,
        type: MessageType.system,
        targetDeviceId: originalMessage.senderId, senderName: '',
      );

      debugPrint("📨 ACK sent for message: ${originalMessage.id}");
    } catch (e) {
      debugPrint("❌ Failed to send ACK: $e");
    }
  }

  void _handleAcknowledgment(P2PMessage ackMessage) {
    final messageId = ackMessage.message.substring(4); // Remove 'ACK:' prefix
    
    if (_pendingAcks.containsKey(messageId)) {
      _pendingAcks.remove(messageId);
      _ackTimeouts[messageId]?.cancel();
      _ackTimeouts.remove(messageId);

      // Update message status to delivered
      DatabaseService.updateMessageStatus(messageId, MessageStatus.delivered);
      
      debugPrint("✅ ACK received for message: $messageId");
    }
  }

  void _handleAckTimeout(String messageId, P2PConnectionService p2pService) {
    debugPrint("⏰ ACK timeout for message: $messageId");
    
    _pendingAcks.remove(messageId);
    _ackTimeouts.remove(messageId);
    
    // Retry logic could be implemented here
    _retryMessage(messageId, p2pService);
  }

  Future<void> _retryMessage(String messageId, P2PConnectionService p2pService) async {
    try {
      final retryCount = await DatabaseService.getRetryCount(messageId);
      
      if (retryCount < _maxRetries) {
        await DatabaseService.incrementRetryCount(messageId);
        
        // Get original message and resend
        final originalMessage = await DatabaseService.getMessageById(messageId);
        if (originalMessage != null) {
          // Implement exponential backoff
          final delay = Duration(seconds: 2 * (retryCount + 1));
          Timer(delay, () async {
            await sendMessageWithAck(
              p2pService,
              message: originalMessage.message,
              type: MessageType.values.firstWhere(
                (e) => e.name == originalMessage.type,
                orElse: () => MessageType.text,
              ),
              latitude: originalMessage.latitude,
              longitude: originalMessage.longitude,
            );
          });
        }
      } else {
        // Max retries reached, mark as failed
        await DatabaseService.updateMessageStatus(messageId, MessageStatus.failed);
        debugPrint("❌ Message failed after $retryCount retries: $messageId");
      }
    } catch (e) {
      debugPrint("❌ Error retrying message: $e");
    }
  }

  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return 'msg_$timestamp-$random';
  }

  // Get pending acknowledgments for debugging
  Map<String, DateTime> get pendingAcks => Map.from(_pendingAcks);
  
  void dispose() {
    for (var timer in _ackTimeouts.values) {
      timer.cancel();
    }
    _ackTimeouts.clear();
    _pendingAcks.clear();
  }
}