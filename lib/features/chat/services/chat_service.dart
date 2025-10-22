import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../models/chat_session_model.dart';
import '../../../models/message_model.dart';
import '../../database/repositories/chat_repository.dart';
import '../../database/repositories/message_repository.dart';
import '../../p2p/events/p2p_event_bus.dart';

/// Service for managing chat operations with state management
class ChatService extends ChangeNotifier {
  // Singleton
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal() {
    _initializeEventListeners();
  }

  // State
  final Map<String, ChatSession> _sessions = {};
  final Map<String, List<MessageModel>> _sessionMessages = {};
  final Map<String, StreamController<MessageModel>> _messageStreamControllers = {};

  ChatSession? _currentSession;
  bool _isLoading = false;
  String? _error;

  // Event subscriptions
  late StreamSubscription<DeviceConnectionEvent> _deviceConnectedSub;
  late StreamSubscription<MessageReceivedEvent> _messageReceivedSub;
  late StreamSubscription<MessageSendStatusEvent> _messageSendStatusSub;

  // Getters
  List<ChatSessionSummary> get sessions => _sessionSummaries;
  ChatSession? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ChatSessionSummary> _sessionSummaries = [];

  // Get messages for a specific session
  List<MessageModel> getMessagesForSession(String sessionId) {
    return List.from(_sessionMessages[sessionId] ?? []);
  }

  // Get message stream for real-time updates
  Stream<MessageModel> getMessageStreamForSession(String sessionId) {
    _messageStreamControllers.putIfAbsent(
      sessionId,
      () => StreamController<MessageModel>.broadcast(),
    );
    return _messageStreamControllers[sessionId]!.stream;
  }

  // Initialize event listeners
  void _initializeEventListeners() {
    final eventBus = P2PEventBus();

    _deviceConnectedSub = eventBus.onDeviceConnectedListen((event) {
      _handleDeviceConnected(event);
    });

    _messageReceivedSub = eventBus.onMessageReceivedListen((event) {
      _handleMessageReceived(event);
    });

    _messageSendStatusSub = eventBus.onMessageSendStatusListen((event) {
      _handleMessageSendStatus(event);
    });
  }

  // Load all chat sessions
  Future<void> loadSessions() async {
    try {
      _setLoading(true);
      _setError(null);

      _sessionSummaries = await ChatRepository.getAllSessions();

      // Load sessions into memory
      for (final summary in _sessionSummaries) {
        final session = await ChatRepository.getSession(summary.sessionId);
        if (session != null) {
          _sessions[session.id] = session;
        }
      }

      debugPrint('✅ Loaded ${_sessionSummaries.length} chat sessions');
    } catch (e) {
      _setError('Failed to load chat sessions: $e');
      debugPrint('❌ Error loading sessions: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Load messages for a specific session
  Future<void> loadMessagesForSession(String sessionId) async {
    try {
      final messages = await MessageRepository.getMessagesForSession(sessionId);
      _sessionMessages[sessionId] = messages;

      // Notify listeners about new messages
      for (final message in messages) {
        _messageStreamControllers[sessionId]?.add(message);
      }

      debugPrint('✅ Loaded ${messages.length} messages for session $sessionId');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading messages for session: $e');
    }
  }

  // Create or get existing chat session
  Future<String?> createOrGetSession({
    required String deviceId,
    required String deviceName,
    String? deviceAddress,
    String? currentUserId,
    String? currentUserName,
    String? peerUserName,
  }) async {
    try {
      final sessionId = await ChatRepository.createOrUpdate(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceAddress: deviceAddress,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        peerUserName: peerUserName,
      );

      if (sessionId.isNotEmpty) {
        // Load session data
        final session = await ChatRepository.getSession(sessionId);
        if (session != null) {
          _sessions[sessionId] = session;
          await loadMessagesForSession(sessionId);
        }

        // Refresh session list
        await loadSessions();
      }

      return sessionId.isNotEmpty ? sessionId : null;
    } catch (e) {
      _setError('Failed to create chat session: $e');
      debugPrint('❌ Error creating session: $e');
      return null;
    }
  }

  // Set current active session
  Future<void> setCurrentSession(String sessionId) async {
    try {
      final session = _sessions[sessionId] ?? await ChatRepository.getSession(sessionId);

      if (session != null) {
        _currentSession = session;
        _sessions[sessionId] = session;

        // Load messages if not already loaded
        if (!_sessionMessages.containsKey(sessionId)) {
          await loadMessagesForSession(sessionId);
        }

        // Mark messages as read
        await ChatRepository.markMessagesAsRead(sessionId);

        notifyListeners();
        debugPrint('✅ Set current session: $sessionId');
      }
    } catch (e) {
      debugPrint('❌ Error setting current session: $e');
    }
  }

  // Send a message
  Future<bool> sendMessage({
    required String sessionId,
    required String message,
    required MessageType type,
    required String fromUser,
    required String targetDeviceId,
    String? connectionType,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // UUID-based system - validate target device ID is not empty
      if (targetDeviceId.isEmpty) {
        debugPrint('❌ Cannot send message: Empty target device ID');
        debugPrint('   fromUser (Display Name): $fromUser');
        return false;
      }

      debugPrint('📤 ChatService sending message:');
      debugPrint('   From (Display): $fromUser');
      debugPrint('   To (UUID): $targetDeviceId');
      debugPrint('   Message: "$message"');

      final messageId = MessageModel.generateMessageId(targetDeviceId);
      final timestamp = DateTime.now();

      final messageModel = MessageModel(
        messageId: messageId,
        endpointId: targetDeviceId, // MAC address for routing
        fromUser: fromUser, // Display name for UI
        message: message,
        isMe: true,
        isEmergency: type == MessageType.emergency || type == MessageType.sos,
        timestamp: timestamp.millisecondsSinceEpoch,
        messageType: type,
        type: type.name,
        status: MessageStatus.pending,
        chatSessionId: sessionId,
        connectionType: connectionType,
        latitude: latitude,
        longitude: longitude,
        deviceId: targetDeviceId, // MAC address as device identifier
      );

      // Save to database
      final success = await MessageRepository.insert(messageModel);

      if (success > 0) {
        // Add to local cache
        _sessionMessages.putIfAbsent(sessionId, () => []).add(messageModel);

        // Notify stream listeners
        _messageStreamControllers[sessionId]?.add(messageModel);

        // Update session summary
        await loadSessions();

        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }

  // Delete a chat session
  Future<bool> deleteSession(String sessionId) async {
    try {
      final success = await ChatRepository.delete(sessionId);

      if (success) {
        _sessions.remove(sessionId);
        _sessionMessages.remove(sessionId);
        _messageStreamControllers[sessionId]?.close();
        _messageStreamControllers.remove(sessionId);

        if (_currentSession?.id == sessionId) {
          _currentSession = null;
        }

        await loadSessions();
        notifyListeners();
      }

      return success;
    } catch (e) {
      debugPrint('❌ Error deleting session: $e');
      return false;
    }
  }

  // Archive a chat session
  Future<bool> archiveSession(String sessionId) async {
    try {
      final success = await ChatRepository.archive(sessionId);

      if (success) {
        await loadSessions();
        notifyListeners();
      }

      return success;
    } catch (e) {
      debugPrint('❌ Error archiving session: $e');
      return false;
    }
  }

  // Get session statistics
  Future<Map<String, dynamic>> getSessionStats(String sessionId) async {
    try {
      return await MessageRepository.getMessageStats(sessionId);
    } catch (e) {
      debugPrint('❌ Error getting session stats: $e');
      return {};
    }
  }

  // Export session messages
  Future<Map<String, dynamic>> exportSession(String sessionId) async {
    try {
      return await MessageRepository.exportMessages(sessionId);
    } catch (e) {
      debugPrint('❌ Error exporting session: $e');
      return {};
    }
  }

  // Handle device connection events
  void _handleDeviceConnected(DeviceConnectionEvent event) async {
    debugPrint('📱 ========== DEVICE CONNECTED ==========');
    debugPrint('   Device ID (should be MAC): ${event.deviceId}');
    debugPrint('   Device Name (Display): ${event.deviceName}');
    debugPrint('   Connection Type: ${event.connectionType}');

    // UUID-based system - validate device ID is not empty
    if (event.deviceId.isEmpty) {
      debugPrint('   ❌ Rejecting connection: Empty device ID');
      debugPrint('   Device Name: ${event.deviceName}');
      debugPrint('========================================');
      return;
    }

    debugPrint('   ✅ Device UUID validated');

    // UUID-based session IDs
    final sessionId = await createOrGetSession(
      deviceId: event.deviceId, // UUID as identifier
      deviceName: event.deviceName, // Display name for UI
      deviceAddress: event.deviceId, // Use deviceId as the stable MAC address
      currentUserId: 'local', // This should come from user service
      currentUserName: event.currentUserName, // From landing page (display name)
      peerUserName: event.deviceName, // Peer's display name (for UI)
    );

    if (sessionId != null) {
      debugPrint('   ✅ Session created/updated: $sessionId');

      // Update connection info
      await ChatRepository.updateConnection(
        sessionId: sessionId,
        connectionType: _parseConnectionType(event.connectionType),
        connectionTime: event.timestamp,
      );

      await loadSessions();
    } else {
      debugPrint('   ❌ Failed to create session');
    }
    debugPrint('========================================');
  }

  // Handle message received events
  void _handleMessageReceived(MessageReceivedEvent event) async {
    debugPrint('📨 Message received from: ${event.fromDeviceId}');

    // Validate sender has some device ID
    if (event.fromDeviceId.isEmpty) {
      debugPrint('❌ Rejecting message: No sender device ID');
      return;
    }

    // UUID-based system - all device IDs are valid UUIDs
    debugPrint('ℹ️ Message from device UUID: ${event.fromDeviceId}');

    final message = event.message;

    // Determine the correct session ID for this message
    String sessionId;

    if (message.chatSessionId != null && message.chatSessionId!.isNotEmpty) {
      // Message already has a session ID
      sessionId = message.chatSessionId!;
    } else {
      // Find existing session for this device OR create new session ID
      final existingSession = await ChatRepository.getSessionByDeviceId(event.fromDeviceId);

      if (existingSession != null) {
        sessionId = existingSession.id;
        debugPrint('📍 Found existing session: $sessionId for device (MAC): ${event.fromDeviceId}');
      } else {
        // Create MAC-based session ID for new conversation
        sessionId = 'chat_${event.fromDeviceId.replaceAll(':', '_')}';
        debugPrint('📍 Creating new session: $sessionId for device (MAC): ${event.fromDeviceId}');

        // Create the session
        await createOrGetSession(
          deviceId: event.fromDeviceId, // MAC address
          deviceName: message.fromUser, // Display name
          deviceAddress: event.fromDeviceId, // MAC address
        );
      }
    }

    // Ensure message has the correct session ID
    final updatedMessage = message.chatSessionId == sessionId
        ? message
        : message.copyWith(chatSessionId: sessionId);

    // Insert/update message in database
    await MessageRepository.insert(updatedMessage);

    // Add to local cache
    _sessionMessages.putIfAbsent(sessionId, () => []).add(updatedMessage);
    _messageStreamControllers[sessionId]?.add(updatedMessage);

    // Update sessions
    await loadSessions();
    notifyListeners();
  }

  // Handle message send status events
  void _handleMessageSendStatus(MessageSendStatusEvent event) async {
    debugPrint('📤 Message status update: ${event.messageId} -> ${event.status}');

    // Update message status in database
    await MessageRepository.updateStatus(event.messageId, event.status);

    // Update local cache
    for (final messages in _sessionMessages.values) {
      final messageIndex = messages.indexWhere((m) => m.messageId == event.messageId);
      if (messageIndex != -1) {
        final updatedMessage = messages[messageIndex].copyWith(status: event.status);
        messages[messageIndex] = updatedMessage;
        break;
      }
    }

    notifyListeners();
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  ConnectionType _parseConnectionType(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct':
        return ConnectionType.wifiDirect;
      default:
        return ConnectionType.unknown;
    }
  }

  // Cleanup methods
  Future<void> cleanupOldData() async {
    try {
      // Clean up old messages (older than 30 days)
      await MessageRepository.deleteOldMessages(const Duration(days: 30));

      // Clean up old failed messages (older than 7 days)
      await MessageRepository.cleanupFailedMessages();

      // Clean up old archived sessions (older than 90 days)
      await ChatRepository.cleanupOldSessions();

      // Reload sessions after cleanup
      await loadSessions();

      debugPrint('🧹 Chat data cleanup completed');
    } catch (e) {
      debugPrint('❌ Error during cleanup: $e');
    }
  }

  @override
  void dispose() {
    _deviceConnectedSub.cancel();
    _messageReceivedSub.cancel();
    _messageSendStatusSub.cancel();

    for (final controller in _messageStreamControllers.values) {
      controller.close();
    }
    _messageStreamControllers.clear();

    super.dispose();
    debugPrint('🧹 Chat service disposed');
  }
}