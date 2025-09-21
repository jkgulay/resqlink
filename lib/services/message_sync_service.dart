import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import '../models/message_model.dart';
import 'p2p/p2p_main_service.dart';

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

  // Device identifier for unique message IDs
  late String _deviceId;

  // Initialize sync service
  Future<void> initialize() async {
    await _initializeDeviceId();
    _monitorConnectivity();
    _startPeriodicSync();
    _startRetryTimer();

    // Check initial connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult.any(
      (result) => result != ConnectivityResult.none,
    );

    if (_isOnline) {
      unawaited(syncPendingMessages());
    }
  }

  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id') ?? _generateDeviceId();
    await prefs.setString('device_id', _deviceId);
  }

  String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    return 'device_${timestamp}_$random';
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

      debugPrint('📶 Connectivity changed: online=$_isOnline');

      if (!wasOnline && _isOnline) {
        // Just came online, sync immediately
        debugPrint('📶 Connection restored, syncing messages...');
        unawaited(syncPendingMessages());
      }
    });
  }

  // Start periodic sync every 30 seconds when online
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline && !_isSyncing) {
        unawaited(syncPendingMessages());
      }
    });
  }

  // Retry failed messages every 2 minutes
  void _startRetryTimer() {
    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_isOnline) {
        unawaited(retryFailedMessages());
      }
    });
  }

  // Generate truly unique message ID
  String _generateUniqueMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final microsecond = DateTime.now().microsecond;
    final random = Random().nextInt(999999);

    // Create unique string and hash it
    final uniqueString = '$_deviceId-$timestamp-$microsecond-$random';
    final bytes = utf8.encode(uniqueString);
    final digest = sha256.convert(bytes);

    return digest.toString().substring(0, 20); // Use first 20 chars
  }

  // Check if message ID already exists in database
  Future<bool> _messageExists(String messageId) async {
    try {
      final existing = await MessageRepository.getById(messageId);
      return existing != null;
    } catch (e) {
      debugPrint('Error checking message existence: $e');
      return false;
    }
  }

  // Send message with proper status tracking and collision prevention
  Future<String> sendMessage({
    required String endpointId,
    required String message,
    required String fromUser,
    required bool isEmergency,
    required MessageType messageType,
    double? latitude,
    double? longitude,
    P2PMainService? p2pService,
  }) async {
    // Generate unique message ID with collision check
    String messageId = _generateUniqueMessageId();
    int attempts = 0;
    const maxAttempts = 5;

    while (await _messageExists(messageId) && attempts < maxAttempts) {
      attempts++;
      messageId = _generateUniqueMessageId();
      debugPrint(
        '🔄 Message ID collision, generating new ID (attempt $attempts)',
      );
    }

    if (attempts >= maxAttempts) {
      throw Exception(
        'Failed to generate unique message ID after $maxAttempts attempts',
      );
    }

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
      synced: false,
      syncedToFirebase: false,
    );

    try {
      // Save to local database immediately
      await MessageRepository.insertMessage(messageModel);
      debugPrint('💾 Message saved locally: $messageId');

      // Try to send via Firebase if online
      if (_isOnline) {
        final success = await _sendToFirebase(messageModel);
        if (success) {
          await MessageRepository.updateMessageStatus(
            messageId,
            MessageStatus.sent,
          );
          await MessageRepository.markMessageSynced(messageId);
        } else {
          await MessageRepository.updateMessageStatus(
            messageId,
            MessageStatus.failed,
          );
        }
      } else if (p2pService != null && p2pService.isConnected) {
        // Try P2P if offline but P2P is available
        final success = await _sendViaP2P(messageModel, p2pService);
        if (success) {
          await MessageRepository.updateMessageStatus(
            messageId,
            MessageStatus.sent,
          );
        } else {
          await MessageRepository.updateMessageStatus(
            messageId,
            MessageStatus.failed,
          );
        }
      } else {
        // No connectivity, keep as pending
        debugPrint('📭 No connectivity, message queued for later sync');
      }
    } catch (e) {
      debugPrint('❌ Error in sendMessage: $e');
      await MessageRepository.updateMessageStatus(
        messageId,
        MessageStatus.failed,
      );
    }

    return messageId;
  }

  // Send to Firebase with better error handling
  Future<bool> _sendToFirebase(MessageModel message) async {
    if (!_isUserAuthenticated()) {
      debugPrint('📄 Skipping Firebase send - user not authenticated');
      return false;
    }

    try {
      // Check if message already exists in Firebase
      final doc = await _firestore
          .collection('messages')
          .doc(message.messageId)
          .get();

      if (doc.exists) {
        debugPrint(
          '📄 Message already exists in Firebase: ${message.messageId}',
        );
        return true;
      }

      await _firestore
          .collection('messages')
          .doc(message.messageId)
          .set(message.toFirebaseJson());

      debugPrint('🔥 Message sent to Firebase: ${message.messageId}');
      return true;
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        debugPrint(
          '⚠️ Firebase permission denied - user may need to log in again',
        );
        _stopPeriodicSync(); // Stop sync attempts
      } else {
        debugPrint('❌ Firebase send failed: $e');
      }
      return false;
    }
  }

  // Send via P2P multi-hop
  Future<bool> _sendViaP2P(
    MessageModel message,
    P2PMainService p2pService,
  ) async {
    try {
      await p2pService.sendMessage(
        message: message.message,
        type: message.messageType,
        targetDeviceId: message.endpointId,
        latitude: message.latitude,
        longitude: message.longitude,
        senderName: message.fromUser,
        id: message.messageId,
      );
      debugPrint('📡 Message sent via P2P: ${message.messageId}');
      return true;
    } catch (e) {
      debugPrint('❌ P2P send failed: $e');
      return false;
    }
  }

  // Sync all pending messages
  Future<void> syncPendingMessages() async {
    if (_isSyncing || !_isOnline) {
      debugPrint('⏸️ Sync skipped: syncing=$_isSyncing, online=$_isOnline');
      return;
    }

    // Check authentication before proceeding
    if (!_isUserAuthenticated()) {
      debugPrint('⏸️ Sync skipped: user not authenticated');
      return;
    }

    _isSyncing = true;
    try {
      final pendingMessages = await MessageRepository.getPendingMessages();
      debugPrint('🔄 Syncing ${pendingMessages.length} pending messages...');

      int successCount = 0;
      for (final message in pendingMessages) {
        if (message.messageId != null) {
          final success = await _sendToFirebase(message);
          if (success) {
            await MessageRepository.updateMessageStatus(
              message.messageId!,
              MessageStatus.synced,
            );
            await MessageRepository.markMessageSynced(message.messageId!);
            successCount++;
            debugPrint('✅ Message ${message.messageId} synced');
          } else {
            await MessageRepository.incrementRetryCount(message.messageId!);
            debugPrint('❌ Message ${message.messageId} sync failed');
          }
        }
      }

      debugPrint(
        '📊 Sync complete: $successCount/${pendingMessages.length} messages synced',
      );

      // Only pull if we have authentication
      if (_isUserAuthenticated()) {
        await _pullMessagesFromFirebase();
      }
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void _stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('🛑 Stopped periodic Firebase sync');
  }

  // Pull new messages from Firebase with duplicate prevention
  Future<void> _pullMessagesFromFirebase() async {
    // Check if user is authenticated before attempting Firebase operations
    if (!_isUserAuthenticated()) {
      debugPrint('📥 Skipping Firebase pull - user not authenticated');
      return;
    }

    try {
      final lastSyncTime = await _getLastSyncTime();
      debugPrint('📥 Pulling messages newer than: $lastSyncTime');

      final query = _firestore
          .collection('messages')
          .where('timestamp', isGreaterThan: lastSyncTime)
          .orderBy('timestamp')
          .limit(100);

      final snapshot = await query.get();

      int newMessagesCount = 0;
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final messageId = data['messageId'] ?? doc.id;

          if (await _messageExists(messageId)) {
            continue;
          }

          // Create MessageModel from Firebase data
          final messageModel = MessageModel(
            endpointId: data['endpointId'] ?? 'unknown',
            fromUser: data['fromUser'] ?? 'Unknown User',
            message: data['message'] ?? '',
            isMe: false, // Messages from Firebase are from other users
            isEmergency: data['isEmergency'] ?? false,
            timestamp:
                data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            type: data['type'] ?? 'message',
            latitude: data['latitude']?.toDouble(),
            longitude: data['longitude']?.toDouble(),
            messageId: messageId,
            status: MessageStatus.delivered,
            synced: true,
            syncedToFirebase: true,
          );

          await MessageRepository.insertMessage(messageModel);
          newMessagesCount++;
        } catch (e) {
          debugPrint('❌ Error processing message ${doc.id}: $e');
        }
      }

      if (newMessagesCount > 0) {
        await _updateLastSyncTime();
        debugPrint('📥 Pulled $newMessagesCount new messages');
      } else {
        debugPrint('📥 No new messages to pull');
      }
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        debugPrint('❌ Firebase permission denied - stopping sync attempts');
        _stopPeriodicSync(); // Stop the sync timer
      } else {
        debugPrint('❌ Pull failed: $e');
      }
    }
  }

  // Add authentication check method
  bool _isUserAuthenticated() {
    try {
      // Check if Firebase user is authenticated
      final user = FirebaseAuth.instance.currentUser;
      return user != null && user.uid.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Retry failed messages with exponential backoff
  Future<void> retryFailedMessages() async {
    if (!_isOnline) return;

    try {
      final failedMessages = await MessageRepository.getFailedMessages();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final message in failedMessages) {
        if (message.messageId != null) {
          // Get retry count from database
          final retryCount = await MessageRepository.getRetryCount(
            message.messageId!,
          );

          // Exponential backoff: 1, 2, 4, 8, 16, 32, 60 minutes max
          final backoffMinutes = (1 << retryCount).clamp(1, 60);
          final lastRetry = await MessageRepository.getLastRetryTime(
            message.messageId!,
          );

          if (now - lastRetry > backoffMinutes * 60 * 1000) {
            debugPrint(
              '🔄 Retrying failed message: ${message.messageId} (attempt ${retryCount + 1})',
            );

            final success = await _sendToFirebase(message);
            if (success) {
              await MessageRepository.updateMessageStatus(
                message.messageId!,
                MessageStatus.synced,
              );
              await MessageRepository.markMessageSynced(message.messageId!);
              debugPrint('✅ Retry successful: ${message.messageId}');
            } else {
              await MessageRepository.incrementRetryCount(message.messageId!);
              await MessageRepository.updateLastRetryTime(
                message.messageId!,
                now,
              );
              debugPrint('❌ Retry failed: ${message.messageId}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Retry failed messages error: $e');
    }
  }

  // Get last sync time from SharedPreferences
  Future<int> _getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('last_sync_time') ?? 0;
    } catch (e) {
      debugPrint('Error getting last sync time: $e');
      return 0;
    }
  }

  // Update last sync time
  Future<void> _updateLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_sync_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Error updating last sync time: $e');
    }
  }

  // Get sync status
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  // Force sync (for manual sync from UI)
  Future<void> forcSync() async {
    if (!_isOnline) {
      throw Exception('Cannot sync while offline');
    }

    await syncPendingMessages();
  }
}
