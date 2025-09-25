import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/message_model.dart';
import '../p2p/p2p_main_service.dart';
import '../../features/database/repositories/message_repository.dart';

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
    // DO NOT override onMessageReceived - use MessageRouter system instead
    // This prevents conflicts with the centralized message handling
    debugPrint('⚠️ MessageAcknowledgmentService initialized - using MessageRouter for message handling');
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
      await MessageRepository.updateStatus(messageId, MessageStatus.sent);

      // Set timeout for retry
      _ackTimeouts[messageId] = Timer(_ackTimeout, () {
        _handleAckTimeout(messageId, p2pService);
      });

      debugPrint("📤 Message sent with ACK tracking: $messageId");
      return messageId;
    } catch (e) {
      await MessageRepository.updateStatus(messageId, MessageStatus.failed);
      rethrow;
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
      final retryCount = await MessageRepository.getRetryCount(messageId);
      
      if (retryCount < _maxRetries) {
        await MessageRepository.incrementRetryCount(messageId);
        
        // Get original message and resend
        final originalMessage = await MessageRepository.getById(messageId);
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
        await MessageRepository.updateStatus(messageId, MessageStatus.failed);
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