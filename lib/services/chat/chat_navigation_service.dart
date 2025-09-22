import 'package:flutter/material.dart';
import 'package:resqlink/models/message_model.dart';
import '../../models/chat_session_model.dart';
import '../../features/database/repositories/chat_repository.dart';
import '../p2p/p2p_main_service.dart';
import '../../pages/chat_session_page.dart';
import '../../pages/chat_list_page.dart';

class ChatNavigationService {
  static final ChatNavigationService _instance =
      ChatNavigationService._internal();
  factory ChatNavigationService() => _instance;
  ChatNavigationService._internal();

  BuildContext? _context;
  P2PMainService? _p2pService;

  bool _autoNavigateEnabled = true;
  bool _isNavigating = false;

  // Track active chats with deviceId mapping
  final Map<String, bool> _activeChatSessions = {};
  final Map<String, String> _sessionToDeviceMap = {}; // sessionId -> deviceId
  String? _currentChatSessionId;
  String? _currentDeviceId;

  void initialize(BuildContext context, P2PMainService p2pService) {
    _context = context;
    _p2pService = p2pService;
    _setupConnectionListener();
  }

  void dispose() {
    _context = null;
    _p2pService = null;
    _activeChatSessions.clear();
    _sessionToDeviceMap.clear();
    _currentChatSessionId = null;
    _currentDeviceId = null;
  }

  void setAutoNavigateEnabled(bool enabled) {
    _autoNavigateEnabled = enabled;
  }

  void _setupConnectionListener() {
    _p2pService?.onDeviceConnected = _onDeviceConnected;
    _p2pService?.onDeviceDisconnected = _onDeviceDisconnected;
  }

  Future<void> navigateToDeviceChat(
    BuildContext context,
    Map<String, dynamic> device,
    P2PMainService p2pService,
  ) async {
    // Prevent duplicate navigation
    if (_isNavigating) {
      debugPrint('⚠️ Navigation already in progress');
      return;
    }

    _isNavigating = true;

    try {
      final deviceId =
          device['deviceId'] as String? ??
          device['deviceAddress'] as String? ??
          'unknown';
      final deviceName = device['deviceName'] as String? ?? 'Unknown Device';

      if (_currentChatSessionId == deviceId &&
          ModalRoute.of(context)?.settings.name == '/chat_session') {
        debugPrint('👀 Already in chat with $deviceName');
        _isNavigating = false;
        return;
      }

      ChatSession? session = await ChatRepository.getSessionByDeviceId(
        deviceId,
      );

      _currentChatSessionId = session?.id;
      _activeChatSessions[session!.id] = true;

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatSessionPage(
              sessionId: session.id,
              deviceName: session.deviceName,
              p2pService: p2pService,
              deviceId: session.deviceId,
            ),
            settings: RouteSettings(name: '/chat_session'),
          ),
        );

        // Clear current session on pop
        _currentChatSessionId = null;
        _activeChatSessions[session.id] = false;
      }
    } catch (e) {
      debugPrint('❌ Error navigating to chat: $e');
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _onDeviceConnected(String deviceId, String deviceName) async {
    if (!_autoNavigateEnabled ||
        _isNavigating ||
        _context == null ||
        _p2pService == null) {
      return;
    }

    try {
      _isNavigating = true;

      // Create or update chat session
      final sessionId = await ChatRepository.createOrUpdate(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: _p2pService!.deviceId,
      );

      if (sessionId.isNotEmpty && _context != null) {
        // Track the session and device mapping
        _sessionToDeviceMap[sessionId] = deviceId;

        // Navigate to chat with the connected device
        await _navigateToChat(sessionId, deviceName, deviceId);
      }
    } catch (e) {
      debugPrint('❌ Error in _onDeviceConnected: $e');
    } finally {
      _isNavigating = false;
    }
  }

  void _onDeviceDisconnected(String deviceId) {
    // Update the chat session to mark as disconnected
    // This could also trigger a notification to the user
    debugPrint('📱 Device disconnected: $deviceId');
  }

  Future<void> _navigateToChat(
    String sessionId,
    String deviceName,
    String deviceId,
  ) async {
    if (_context == null || _p2pService == null) return;

    try {
      // Show a snackbar notification
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Connected to $deviceName',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
          action: SnackBarAction(
            label: 'CHAT',
            textColor: Colors.white,
            onPressed: () => _openChatSession(sessionId, deviceName, deviceId),
          ),
        ),
      );

      // Auto-navigate after a short delay
      await Future.delayed(Duration(seconds: 1));
      if (_context != null) {
        _openChatSession(sessionId, deviceName, deviceId);
      }
    } catch (e) {
      debugPrint('❌ Error navigating to chat: $e');
    }
  }

  void _openChatSession(String sessionId, String deviceName, String deviceId) {
    if (_context == null || _p2pService == null) return;

    // Set current session as active
    _currentChatSessionId = sessionId;
    _currentDeviceId = deviceId;
    _activeChatSessions[sessionId] = true;

    Navigator.push(
      _context!,
      MaterialPageRoute(
        builder: (context) => ChatSessionPage(
          sessionId: sessionId,
          deviceName: deviceName,
          deviceId: deviceId,
          p2pService: _p2pService!,
        ),
      ),
    ).then((_) {
      // Clear current session when chat is closed
      _currentChatSessionId = null;
      _currentDeviceId = null;
      _activeChatSessions[sessionId] = false;
    });
  }

  static Future<void> navigateToChatList(
  BuildContext context,
  P2PMainService p2pService,
) async {
  if (!context.mounted) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ChatListPage(
        p2pService: p2pService,
        onChatSelected: (sessionId, deviceName) async {
          // ✅ Store navigator reference before async gap
          final navigator = Navigator.of(context);
          
          // Close chat list first
          navigator.pop();

          try {
            // Get device ID from session
            final session = await ChatRepository.getSession(sessionId);
            final deviceId = session?.deviceId ?? 'unknown';

            // ✅ Check if context is still mounted after async operation
            if (context.mounted) {
              await navigator.push(
                MaterialPageRoute(
                  builder: (context) => ChatSessionPage(
                    sessionId: sessionId,
                    deviceName: deviceName,
                    deviceId: deviceId,
                    p2pService: p2pService,
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint('❌ Error navigating to chat session: $e');
          }
        },
      ),
    ),
  );
}

  static Future<void> navigateToChat(
    BuildContext context,
    String sessionId,
    String deviceName,
    P2PMainService p2pService, {
    String? deviceId,
  }) async {
    if (!context.mounted) return;

    String actualDeviceId = deviceId ?? 'unknown';
    if (deviceId == null) {
      final session = await ChatRepository.getSession(sessionId);
      actualDeviceId = session?.deviceId ?? 'unknown';
    }

    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatSessionPage(
          sessionId: sessionId,
          deviceName: deviceName,
          deviceId: actualDeviceId,
          p2pService: p2pService,
        ),
      ),
    );
  }

  static Future<void> createAndNavigateToChat(
    BuildContext context,
    String deviceId,
    String deviceName,
    P2PMainService p2pService,
  ) async {
    try {
      final sessionId = await ChatRepository.createOrUpdate(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: p2pService.deviceId,
      );

      if (sessionId.isNotEmpty && context.mounted) {
        await navigateToChat(
          context,
          sessionId,
          deviceName,
          p2pService,
          deviceId: deviceId,
        );
      }
    } catch (e) {
      debugPrint('❌ Error creating and navigating to chat: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create chat session'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle reconnection and resume chat
  static Future<void> handleReconnectionAndResume(
    BuildContext context,
    String deviceId,
    String deviceName,
    P2PMainService p2pService,
  ) async {
    try {
      // Generate session ID for the device pair
      final sessionId = ChatSession.generateSessionId(
        p2pService.deviceId ?? 'local',
        deviceId,
      );

      // Check if session exists
      final existingSession = await ChatRepository.getSession(sessionId);

      if (existingSession != null) {
        // Update connection time
        await ChatRepository.updateSessionConnection(
          sessionId: sessionId,
          connectionType: ConnectionType.wifiDirect, // or determine actual type
          connectionTime: DateTime.now(),
        );

        // Show reconnection notification
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Reconnected to $deviceName'),
                ],
              ),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'RESUME CHAT',
                textColor: Colors.white,
                onPressed: () {
                  if (context.mounted) {
                    navigateToChat(
                      context,
                      sessionId,
                      deviceName,
                      p2pService,
                      deviceId: deviceId,
                    );
                  }
                },
              ),
            ),
          );
        }

        // Auto-navigate to resume chat
        await Future.delayed(Duration(seconds: 1));
        if (context.mounted) {
          await navigateToChat(
            context,
            sessionId,
            deviceName,
            p2pService,
            deviceId: deviceId,
          );
        }
      } else {
        // Create new session if none exists
        if (context.mounted) {
          await createAndNavigateToChat(
            context,
            deviceId,
            deviceName,
            p2pService,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling reconnection: $e');
    }
  }

  /// Show a quick action dialog for a connected device
  static Future<void> showDeviceActionDialog(
    BuildContext context,
    String deviceId,
    String deviceName,
    P2PMainService p2pService,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(deviceName, style: TextStyle(color: Colors.white)),
        content: Text(
          'What would you like to do with this device?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              createAndNavigateToChat(
                context,
                deviceId,
                deviceName,
                p2pService,
              );
            },
            child: Text('Start Chat'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Quick emergency message
              final sessionId = await ChatRepository.createOrUpdate(
                deviceId: deviceId,
                deviceName: deviceName,
                currentUserId: p2pService.deviceId,
              );

              if (sessionId.isNotEmpty) {
                await p2pService.sendMessage(
                  message: '🚨 Emergency SOS',
                  type: MessageType.sos,
                  targetDeviceId: deviceId,
                  senderName: p2pService.userName ?? 'Unknown',
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Emergency SOS sent to $deviceName'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text('Send SOS', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Get current chat session ID
  String? get currentChatSessionId => _currentChatSessionId;

  /// Get current device ID
  String? get currentDeviceId => _currentDeviceId;

  /// Check if chat is active for a session
  bool isChatActive(String sessionId) {
    return _activeChatSessions[sessionId] ?? false;
  }

  /// Check if currently chatting with specific device
  bool isChattingWithDevice(String deviceId) {
    return _currentDeviceId == deviceId && _currentChatSessionId != null;
  }

  /// Get device ID for a session
  String? getDeviceIdForSession(String sessionId) {
    return _sessionToDeviceMap[sessionId];
  }

  /// Get all active chat sessions
  List<String> getActiveChatSessions() {
    return _activeChatSessions.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  /// Set session active state manually
  void setSessionActive(String sessionId, String deviceId, bool active) {
    _activeChatSessions[sessionId] = active;
    _sessionToDeviceMap[sessionId] = deviceId;

    if (active) {
      _currentChatSessionId = sessionId;
      _currentDeviceId = deviceId;
    } else if (_currentChatSessionId == sessionId) {
      _currentChatSessionId = null;
      _currentDeviceId = null;
    }
  }

  /// Clear all navigation state
  void clearNavigationState() {
    _currentChatSessionId = null;
    _currentDeviceId = null;
    _activeChatSessions.clear();
    _sessionToDeviceMap.clear();
    _isNavigating = false;
    debugPrint('🧹 Chat navigation state cleared');
  }
}
