import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/message_model.dart';
import '../services/database_service.dart';
import '../services/p2p_services.dart';

class MessageSyncService {
  static final MessageSyncService _instance = MessageSyncService._internal();
  factory MessageSyncService() => _instance;
  MessageSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _syncTimer;
  Timer? _retryTimer;
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = false;
  bool _isSyncing = false;

  // Initialize sync service
  void initialize() {
    _monitorConnectivity();
    _startPeriodicSync();
    _startRetryTimer();
  }

  void dispose() {
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _connectivitySubscription?.cancel();
  }

  // Monitor connectivity changes
  void _monitorConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final wasOnline = _isOnline;
      _isOnline = results.any((result) => result != ConnectivityResult.none);
      
      if (!wasOnline && _isOnline) {
        // Just came online, sync immediately
        debugPrint('📶 Connection restored, syncing messages...');
        await syncPendingMessages();
      }
    });
  }

  // Start periodic sync every 30 seconds when online
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline && !_isSyncing) {
        syncPendingMessages();
      }
    });
  }

  // Retry failed messages every 2 minutes
  void _startRetryTimer() {
    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      retryFailedMessages();
    });
  }

  // Send message with proper status tracking
  Future<String> sendMessage({
    required String endpointId,
    required String message,
    required String fromUser,
    required bool isEmergency,
    required MessageType messageType,
    double? latitude,
    double? longitude,
    P2PConnectionService? p2pService,
  }) async {
    final messageId = _generateMessageId();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    final messageModel = MessageModel(
      endpointId: endpointId,
      fromUser: fromUser,
      message: message,
      isMe: true,
      isEmergency: isEmergency,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      messageId: messageId,
      type: messageType.name,
      status: MessageStatus.pending,
    );

    // Save to local database immediately
    await DatabaseService.insertMessage(messageModel);

    // Try to send via Firebase if online
    if (_isOnline) {
      final success = await _sendToFirebase(messageModel);
      if (success) {
        await DatabaseService.updateMessageStatus(messageId, MessageStatus.sent);
      } else {
        await DatabaseService.updateMessageStatus(messageId, MessageStatus.failed);
      }
    } else if (p2pService != null) {
      // Try P2P if offline
      final success = await _sendViaP2P(messageModel, p2pService);
      if (success) {
        await DatabaseService.updateMessageStatus(messageId, MessageStatus.sent);
      } else {
        await DatabaseService.updateMessageStatus(messageId, MessageStatus.failed);
      }
    }

    return messageId;
  }

  // Send to Firebase
  Future<bool> _sendToFirebase(MessageModel message) async {
    try {
      await _firestore
          .collection('messages')
          .doc(message.messageId)
          .set(message.toFirebaseJson());
      
      await DatabaseService.updateMessageStatus(
        message.messageId!, 
        MessageStatus.synced
      );
      return true;
    } catch (e) {
      debugPrint('❌ Firebase send failed: $e');
      return false;
    }
  }

  // Send via P2P multi-hop
  Future<bool> _sendViaP2P(MessageModel message, P2PConnectionService p2pService) async {
    try {
      await p2pService.sendMessage(
        message: message.message,
        type: MessageType.values.firstWhere(
          (e) => e.name == message.type,
          orElse: () => MessageType.text,
        ),
        targetDeviceId: message.endpointId,
        latitude: message.latitude,
        longitude: message.longitude,
      );
      return true;
    } catch (e) {
      debugPrint('❌ P2P send failed: $e');
      return false;
    }
  }

  // Sync all pending messages
  Future<void> syncPendingMessages() async {
    if (_isSyncing || !_isOnline) return;
    
    _isSyncing = true;
    try {
      final pendingMessages = await DatabaseService.getPendingMessages();
      debugPrint('🔄 Syncing ${pendingMessages.length} pending messages...');

      for (final message in pendingMessages) {
        if (message.messageId != null) {
          final success = await _sendToFirebase(message);
          if (success) {
            debugPrint('✅ Message ${message.messageId} synced');
          } else {
            await DatabaseService.incrementRetryCount(message.messageId!);
          }
        }
      }

      // Pull new messages from Firebase
      await _pullMessagesFromFirebase();
      
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // Pull new messages from Firebase
  Future<void> _pullMessagesFromFirebase() async {
    try {
      final lastSyncTime = await _getLastSyncTime();
      final query = _firestore
          .collection('messages')
          .where('timestamp', isGreaterThan: lastSyncTime)
          .orderBy('timestamp');

      final snapshot = await query.get();
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final message = MessageModel(
          endpointId: data['endpointId'] ?? '',
          fromUser: data['fromUser'] ?? '',
          message: data['message'] ?? '',
          isMe: false, // These are received messages
          isEmergency: data['isEmergency'] ?? false,
          timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          latitude: data['latitude']?.toDouble(),
          longitude: data['longitude']?.toDouble(),
          messageId: data['messageId'] ?? doc.id,
          type: data['type'] ?? 'message',
          status: MessageStatus.delivered,
          syncedToFirebase: true,
        );

        await DatabaseService.insertMessage(message);
      }

      await _updateLastSyncTime();
      debugPrint('📥 Pulled ${snapshot.docs.length} new messages');
      
    } catch (e) {
      debugPrint('❌ Pull failed: $e');
    }
  }

  // Retry failed messages with exponential backoff
  Future<void> retryFailedMessages() async {
    if (!_isOnline) return;

    final failedMessages = await DatabaseService.getPendingMessages();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final message in failedMessages) {
      if (message.messageId != null && message.status == MessageStatus.failed) {
        // Exponential backoff: wait longer for each retry
        final retryCount = 0; // You'd need to track this in the database
        final backoffMinutes = (1 << retryCount).clamp(1, 60); // 1, 2, 4, 8... up to 60 minutes
        final lastRetry = 0; // You'd need to track this too
        
        if (now - lastRetry > backoffMinutes * 60 * 1000) {
          await _sendToFirebase(message);
        }
      }
    }
  }

  Future<int> _getLastSyncTime() async {
    // Implement this to store/retrieve last sync timestamp
    return 0;
  }

  Future<void> _updateLastSyncTime() async {
    // Implement this to update last sync timestamp
  }

  String _generateMessageId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }
}