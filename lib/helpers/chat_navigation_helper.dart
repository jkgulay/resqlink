import 'package:flutter/material.dart';
import '../features/database/repositories/chat_repository.dart';
import '../services/p2p/p2p_main_service.dart';
import '../pages/chat_session_page.dart';
import '../pages/message_page.dart';
import '../models/chat_session_model.dart';

class ChatNavigationHelper {
  static final ChatNavigationHelper _instance =
      ChatNavigationHelper._internal();
  factory ChatNavigationHelper() => _instance;
  ChatNavigationHelper._internal();

  // Track navigation state to prevent duplicate navigations
  bool _isNavigating = false;

  /// Navigate directly to chat with a connected device
  /// This is the main method that should be called from view chat icons
  static Future<void> navigateToDeviceChat({
    required BuildContext context,
    required Map<String, dynamic> device,
    required P2PMainService p2pService,
    Function(Map<String, dynamic>)? fallbackCallback,
  }) async {
    final helper = ChatNavigationHelper();

    // Prevent duplicate navigation
    if (helper._isNavigating) {
      debugPrint('⚠️ Chat navigation already in progress');
      return;
    }

    helper._isNavigating = true;

    try {
      // Extract device information
      final deviceId = _extractDeviceId(device);
      final deviceName = device['deviceName'] as String? ?? 'Unknown Device';

      if (deviceId.isEmpty) {
        debugPrint('❌ Cannot navigate to chat: Device ID is empty');
        helper._showError(context, 'Device ID not available');
        return;
      }

      debugPrint('🧭 Navigating to chat with device: $deviceName ($deviceId)');

      // Try fallback callback first if provided (this handles the current MessagePage approach)
      if (fallbackCallback != null) {
        debugPrint('🔄 Using fallback callback for navigation');
        fallbackCallback(device);
        await Future.delayed(Duration(milliseconds: 100)); // Allow UI to update
        return;
      }

      // Create or get existing chat session using enhanced method
      final sessionId = await _createOrUpdateSession(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: p2pService.deviceId,
      );

      if (sessionId.isEmpty) {
        debugPrint('❌ Failed to create chat session');
        if (context.mounted) {
          helper._showError(context, 'Failed to create chat session');
        }
        return;
      }

      // Check if context is still mounted after async operation
      if (!context.mounted) {
        debugPrint('⚠️ Context no longer mounted, aborting navigation');
        return;
      }

      // Navigate to chat session using enhanced method
      await _navigateToChat(
        context: context,
        sessionId: sessionId,
        deviceName: deviceName,
        deviceId: deviceId,
        p2pService: p2pService,
      );

      debugPrint('✅ Successfully navigated to chat with $deviceName');
    } catch (e) {
      debugPrint('❌ Error navigating to device chat: $e');
      if (context.mounted) {
        helper._showError(context, 'Failed to open chat: ${e.toString()}');
      }
    } finally {
      helper._isNavigating = false;
    }
  }

  static Future<void> navigateToMessagesTab({
    required BuildContext context,
    required Map<String, dynamic> device,
    required Function(int) setSelectedIndex,
    GlobalKey? messagePageKey,
  }) async {
    final helper = ChatNavigationHelper();

    if (helper._isNavigating) {
      debugPrint('⚠️ Navigation already in progress');
      return;
    }

    helper._isNavigating = true;

    try {
      final deviceId = _extractDeviceId(device);
      final deviceName = device['deviceName'] as String? ?? 'Unknown Device';

      if (deviceId.isEmpty) {
        debugPrint('❌ Cannot navigate: Device ID is empty');
        helper._showError(context, 'Device ID not available');
        return;
      }

      debugPrint(
        '🧭 Navigating to Messages tab for device: $deviceName ($deviceId)',
      );

      setSelectedIndex(2);

      await Future.delayed(Duration(milliseconds: 150));

      if (messagePageKey != null && messagePageKey.currentState != null) {
        debugPrint('🎯 Using MessagePage key to select device');
        MessagePage.selectDeviceFor(messagePageKey, deviceId, deviceName);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.chat, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Opening chat with $deviceName'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      debugPrint('✅ Successfully navigated to Messages tab for $deviceName');
    } catch (e) {
      debugPrint('❌ Error navigating to Messages tab: $e');
      if (context.mounted) {
        helper._showError(context, 'Failed to open chat: ${e.toString()}');
      }
    } finally {
      helper._isNavigating = false;
    }
  }

  static Future<bool> quickConnectAndNavigateToChat({
    required BuildContext context,
    required Map<String, dynamic> device,
    required P2PMainService p2pService,
    required Future<bool> Function(Map<String, dynamic>, BuildContext, dynamic)
    connectFunction,
    required dynamic controller,
    Function(Map<String, dynamic>)? fallbackCallback,
  }) async {
    final helper = ChatNavigationHelper();

    if (helper._isNavigating) {
      debugPrint('⚠️ Quick connect navigation already in progress');
      return false;
    }

    helper._isNavigating = true;

    try {
      final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
      debugPrint('🚀 Quick connecting to $deviceName');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Connecting to $deviceName...'),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Attempt connection
      final connected = await connectFunction(device, context, controller);

      if (!connected) {
        debugPrint('❌ Quick connect failed');
        return false;
      }

      // Wait a moment for connection to stabilize
      await Future.delayed(Duration(milliseconds: 500));

      if (!context.mounted) {
        debugPrint('⚠️ Context no longer mounted after connection');
        return false;
      }

      // Navigate to chat
      await navigateToDeviceChat(
        context: context,
        device: device,
        p2pService: p2pService,
        fallbackCallback: fallbackCallback,
      );

      return true;
    } catch (e) {
      debugPrint('❌ Quick connect and navigate failed: $e');
      if (context.mounted) {
        helper._showError(context, 'Failed to connect and open chat');
      }
      return false;
    } finally {
      helper._isNavigating = false;
    }
  }

  /// Show connection and navigation feedback
  static void showConnectionSuccess({
    required BuildContext context,
    required String deviceName,
    required VoidCallback onChatTap,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Connected to $deviceName')),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OPEN CHAT',
          textColor: Colors.white,
          onPressed: onChatTap,
        ),
      ),
    );
  }

  /// Extract device ID from device data with fallbacks
  /// Enhanced version from existing services/chat_navigation_helper.dart
  static String _extractDeviceId(Map<String, dynamic> device) {
    return device['deviceId'] as String? ??
        device['deviceAddress'] as String? ??
        device['endpointId'] as String? ??
        device['id'] as String? ??
        'unknown';
  }

  /// Show error message to user
  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Check if currently navigating
  bool get isNavigating => _isNavigating;

  /// Clear navigation state (for cleanup)
  void clearNavigationState() {
    _isNavigating = false;
    debugPrint('🧹 ChatNavigationHelper state cleared');
  }

  // ========== ENHANCED METHODS FROM EXISTING SERVICES HELPER ==========

  /// Navigate directly to a chat session (from existing helper)
  static Future<void> navigateToSession({
    required BuildContext context,
    required String sessionId,
    required String deviceName,
    required String deviceId,
    required P2PMainService p2pService,
  }) async {
    if (!context.mounted) return;

    await _navigateToChat(
      context: context,
      sessionId: sessionId,
      deviceName: deviceName,
      deviceId: deviceId,
      p2pService: p2pService,
    );
  }

  /// Create a new chat and navigate to it (from existing helper)
  static Future<void> createAndNavigate({
    required BuildContext context,
    required String deviceId,
    required String deviceName,
    required P2PMainService p2pService,
  }) async {
    try {
      final sessionId = await _createOrUpdateSession(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: p2pService.deviceId,
      );

      if (context.mounted && sessionId.isNotEmpty) {
        await _navigateToChat(
          context: context,
          sessionId: sessionId,
          deviceName: deviceName,
          deviceId: deviceId,
          p2pService: p2pService,
        );
      }
    } catch (e) {
      debugPrint('❌ Error creating and navigating to chat: $e');
      if (context.mounted) {
        _showErrorMessage(context, 'Failed to create chat session');
      }
    }
  }

  /// Handle reconnection and resume existing chat (from existing helper)
  static Future<void> reconnectAndResume({
    required BuildContext context,
    required String deviceId,
    required String deviceName,
    required P2PMainService p2pService,
  }) async {
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
          connectionType: ConnectionType.wifiDirect,
          connectionTime: DateTime.now(),
        );

        // Check context before showing notification
        if (context.mounted) {
          _showReconnectionMessage(context, deviceName);
        }

        // Navigate to chat
        if (context.mounted) {
          await _navigateToChat(
            context: context,
            sessionId: sessionId,
            deviceName: deviceName,
            deviceId: deviceId,
            p2pService: p2pService,
          );
        }
      } else {
        // Create new session if none exists
        if (context.mounted) {
          await createAndNavigate(
            context: context,
            deviceId: deviceId,
            deviceName: deviceName,
            p2pService: p2pService,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling reconnection: $e');
      if (context.mounted) {
        _showErrorMessage(context, 'Failed to reconnect');
      }
    }
  }

  /// Check if currently in chat with specific device (from existing helper)
  static bool isInChatWithDevice(BuildContext context, String deviceId) {
    final route = ModalRoute.of(context);
    if (route?.settings.name == '/chat_session') {
      final args = route?.settings.arguments as Map<String, dynamic>?;
      return args?['deviceId'] == deviceId;
    }
    return false;
  }

  /// Get current chat session info (from existing helper)
  static Map<String, dynamic>? getCurrentChatInfo(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route?.settings.name == '/chat_session') {
      return route?.settings.arguments as Map<String, dynamic>?;
    }
    return null;
  }

  // ========== PRIVATE HELPER METHODS ==========

  /// Create or update chat session (from existing helper)
  static Future<String> _createOrUpdateSession({
    required String deviceId,
    required String deviceName,
    String? currentUserId,
  }) async {
    try {
      return await ChatRepository.createOrUpdate(
        deviceId: deviceId,
        deviceName: deviceName,
        currentUserId: currentUserId ?? 'local',
      );
    } catch (e) {
      debugPrint('❌ Error creating/updating session: $e');
      return '';
    }
  }

  /// Navigate to chat page with enhanced route settings (from existing helper)
  static Future<void> _navigateToChat({
    required BuildContext context,
    required String sessionId,
    required String deviceName,
    required String deviceId,
    required P2PMainService p2pService,
  }) async {
    if (!context.mounted) return;

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatSessionPage(
            sessionId: sessionId,
            deviceName: deviceName,
            deviceId: deviceId,
            p2pService: p2pService,
          ),
          settings: RouteSettings(
            name: '/chat_session',
            arguments: {
              'sessionId': sessionId,
              'deviceName': deviceName,
              'deviceId': deviceId,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
    }
  }

  /// Show error message (from existing helper)
  static void _showErrorMessage(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Show reconnection message (from existing helper)
  static void _showReconnectionMessage(
    BuildContext context,
    String deviceName,
  ) {
    if (!context.mounted) return;

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
        duration: Duration(seconds: 2),
      ),
    );
  }
}
