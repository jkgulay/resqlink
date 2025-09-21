import 'package:flutter/material.dart';
import 'package:resqlink/models/message_model.dart';
import '../models/chat_session_model.dart';
import '../services/database_service.dart';
import '../services/p2p/p2p_main_service.dart';
import '../pages/chat_session_page.dart';
import '../pages/chat_list_page.dart';

class ChatNavigationService {
  static final ChatNavigationService _instance = ChatNavigationService._internal();
  factory ChatNavigationService() => _instance;
  ChatNavigationService._internal();

  BuildContext? _context;
  P2PMainService? _p2pService;

  bool _autoNavigateEnabled = true;
  bool _isNavigating = false;

  void initialize(BuildContext context, P2PMainService p2pService) {
    _context = context;
    _p2pService = p2pService;
    _setupConnectionListener();
  }

  void dispose() {
    _context = null;
    _p2pService = null;
  }

  void setAutoNavigateEnabled(bool enabled) {
    _autoNavigateEnabled = enabled;
  }

  void _setupConnectionListener() {
    _p2pService?.onDeviceConnected = _onDeviceConnected;
    _p2pService?.onDeviceDisconnected = _onDeviceDisconnected;
  }

  Future<void> _onDeviceConnected(String deviceId, String deviceName) async {
    if (!_autoNavigateEnabled || _isNavigating || _context == null || _p2pService == null) {
      return;
    }

    try {
      _isNavigating = true;

      // Create or update chat session
      final sessionId = await DatabaseService.createOrUpdateChatSession(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: _p2pService!.deviceId,
      );

      if (sessionId.isNotEmpty && _context != null) {
        // Navigate to chat with the connected device
        await _navigateToChat(sessionId, deviceName);
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

  Future<void> _navigateToChat(String sessionId, String deviceName) async {
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
            onPressed: () => _openChatSession(sessionId, deviceName),
          ),
        ),
      );

      // Auto-navigate after a short delay
      await Future.delayed(Duration(seconds: 1));
      if (_context != null) {
        _openChatSession(sessionId, deviceName);
      }
    } catch (e) {
      debugPrint('❌ Error navigating to chat: $e');
    }
  }

  void _openChatSession(String sessionId, String deviceName) {
    if (_context == null || _p2pService == null) return;

    Navigator.push(
      _context!,
      MaterialPageRoute(
        builder: (context) => ChatSessionPage(
          sessionId: sessionId,
          deviceName: deviceName,
          p2pService: _p2pService!,
        ),
      ),
    );
  }

  /// Navigate to chat list page
  static Future<void> navigateToChatList(
    BuildContext context,
    P2PMainService p2pService,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatListPage(
          p2pService: p2pService,
          onChatSelected: (sessionId, deviceName) {
            Navigator.pop(context); // Close chat list
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatSessionPage(
                  sessionId: sessionId,
                  deviceName: deviceName,
                  p2pService: p2pService,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Navigate directly to a specific chat session
  static Future<void> navigateToChat(
    BuildContext context,
    String sessionId,
    String deviceName,
    P2PMainService p2pService,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatSessionPage(
          sessionId: sessionId,
          deviceName: deviceName,
          p2pService: p2pService,
        ),
      ),
    );
  }

  /// Create a new chat session and navigate to it
  static Future<void> createAndNavigateToChat(
    BuildContext context,
    String deviceId,
    String deviceName,
    P2PMainService p2pService,
  ) async {
    try {
      final sessionId = await DatabaseService.createOrUpdateChatSession(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: p2pService.deviceId,
      );

      if (sessionId.isNotEmpty && context.mounted) {
        await navigateToChat(context, sessionId, deviceName, p2pService);
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
      final existingSession = await DatabaseService.getChatSession(sessionId);

      if (existingSession != null) {
        // Update connection time
        await DatabaseService.updateChatSessionConnection(
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
                    navigateToChat(context, sessionId, deviceName, p2pService);
                  }
                },
              ),
            ),
          );
        }

        // Auto-navigate to resume chat
        await Future.delayed(Duration(seconds: 1));
        if (context.mounted) {
          await navigateToChat(context, sessionId, deviceName, p2pService);
        }
      } else {
        // Create new session if none exists
        if (context.mounted) {
          await createAndNavigateToChat(context, deviceId, deviceName, p2pService);
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
        title: Text(
          deviceName,
          style: TextStyle(color: Colors.white),
        ),
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
              createAndNavigateToChat(context, deviceId, deviceName, p2pService);
            },
            child: Text('Start Chat'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Quick emergency message
              final sessionId = await DatabaseService.createOrUpdateChatSession(
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
            child: Text(
              'Send SOS',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}