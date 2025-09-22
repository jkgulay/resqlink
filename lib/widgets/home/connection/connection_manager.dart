import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/models/message_model.dart';
import 'package:resqlink/services/chat/chat_navigation_service.dart';

class ConnectionManager {
  final ChatNavigationService _chatNavigationService = ChatNavigationService();
  Future<bool> connectToDevice(
    Map<String, dynamic> device,
    BuildContext context,
    HomeController controller,
  ) async {
    if (!context.mounted) return false;
    final currentContext = context;

    try {
      debugPrint('🔗 Connecting to device: ${device['deviceName']}');

      _showConnectingMessage(currentContext, device);

      final connectionType = device['connectionType'] as String?;
      bool success = false;

      switch (connectionType) {
        case 'wifi_direct':
          success = await _connectViaWifiDirect(device, controller);
        case 'hotspot':
        case 'hotspot_enhanced':
          success = await _connectViaHotspot(device, controller);
        default:
          await controller.connectToDevice(device);
          success = true;
      }

      if (currentContext.mounted) {
        _showConnectionResult(currentContext, device, success);
      }

      return success;
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      if (currentContext.mounted) {
        _showConnectionError(currentContext, e);
      }
      return false;
    }
  }

  Future<void> disconnectDevice(
    Map<String, dynamic> device,
    BuildContext context,
    HomeController controller,
  ) async {
    if (!context.mounted) return;
    final currentContext = context;

    try {
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final connectionType = device['connectionType'] as String? ?? 'unknown';

      if (connectionType == 'wifi_direct') {
        await controller.p2pService.wifiDirectService?.removeGroup();
      } else {
        await controller.p2pService.disconnect();
      }

      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Disconnected from $deviceName'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to disconnect: $e');
    }
  }

  Future<void> sendTestMessage(
    Map<String, dynamic> device,
    BuildContext context,
    HomeController controller,
  ) async {
    if (!context.mounted) return;
    final currentContext = context;

    try {
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final testMessage = 'Hello from ResQLink! This is a test message.';

      await controller.p2pService.sendMessage(
        message: testMessage,
        type: MessageType.text,
        targetDeviceId: device['deviceId'],
        senderName: controller.p2pService.userName ?? 'User',
      );

      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Test message sent to $deviceName'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to send test message: $e');
      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> navigateToChat(
    BuildContext context,
    Map<String, dynamic> device,
    Function(Map<String, dynamic>)? onDeviceChatTap,
  ) async {
    if (!context.mounted) return;

    try {
      if (onDeviceChatTap != null) {
        onDeviceChatTap(device);
        return;
      }

      final controller = context.read<HomeController>();
      await _chatNavigationService.navigateToDeviceChat(
        context,
        device,
        controller.p2pService,
      );

      debugPrint('✅ Chat navigation completed for: ${device['deviceName']}');
    } catch (e) {
      debugPrint('❌ Error navigating to chat: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open chat: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void showDeviceDetails(BuildContext context, Map<String, dynamic> device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Device Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Name', device['deviceName'] ?? 'Unknown'),
            _buildDetailRow('Address', device['deviceAddress'] ?? 'Unknown'),
            _buildDetailRow(
              'Type',
              _getConnectionTypeLabel(device['connectionType'] ?? 'unknown'),
            ),
            _buildDetailRow(
              'Signal',
              '${device['signalLevel'] ?? 'Unknown'} dBm',
            ),
            _buildDetailRow(
              'Status',
              device['isConnected'] == true ? 'Connected' : 'Available',
            ),
            if (device['lastSeen'] != null)
              _buildDetailRow(
                'Last Seen',
                DateTime.fromMillisecondsSinceEpoch(
                  device['lastSeen'],
                ).toString(),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  // Private helper methods
  void _showConnectingMessage(
    BuildContext context,
    Map<String, dynamic> device,
  ) {
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
            Text('Connecting to ${device['deviceName']}...'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _showConnectionResult(
    BuildContext context,
    Map<String, dynamic> device,
    bool success,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              success
                  ? 'Connected to ${device['deviceName']}'
                  : 'Failed to connect to ${device['deviceName']}',
            ),
          ],
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showConnectionError(BuildContext context, dynamic error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connection error: ${error.toString()}'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _connectViaWifiDirect(
    Map<String, dynamic> device,
    HomeController controller,
  ) async {
    final deviceAddress = device['deviceAddress'] as String?;
    if (deviceAddress == null) return false;

    try {
      debugPrint('📡 Connecting via WiFi Direct to: $deviceAddress');

      final success =
          await controller.p2pService.wifiDirectService?.connectToPeer(
            deviceAddress,
          ) ??
          false;

      if (success) {
        debugPrint('✅ WiFi Direct connection initiated');

        await Future.delayed(Duration(seconds: 2));

        final connectionInfo = await controller.p2pService.wifiDirectService
            ?.getConnectionInfo();

        if (connectionInfo != null && connectionInfo['isConnected'] == true) {
          debugPrint('✅ WiFi Direct group formed successfully');

          controller.p2pService.updateConnectionStatus(true);

          await Future.delayed(Duration(seconds: 1));
          final socketEstablished =
              connectionInfo['socketEstablished'] ?? false;

          if (socketEstablished) {
            debugPrint('🔌 Socket communication confirmed');
          } else {
            debugPrint('⚠️ Socket may still be establishing...');
          }

          debugPrint('✅ WiFi Direct fully connected with socket ready');
          return true;
        } else {
          debugPrint('❌ WiFi Direct group formation failed');
          return false;
        }
      } else {
        debugPrint('❌ WiFi Direct connection initiation failed');
        return false;
      }
    } catch (e) {
      debugPrint('❌ WiFi Direct connection failed: $e');
      return false;
    }
  }

  Future<bool> _connectViaHotspot(
    Map<String, dynamic> device,
    HomeController controller,
  ) async {
    final ssid = device['deviceName'] as String?;
    if (ssid == null) return false;

    return await controller.p2pService.connectToResQLinkNetwork(ssid);
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: value.contains(':') ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getConnectionTypeLabel(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct':
        return 'WiFi Direct';
      case 'hotspot':
        return 'Hotspot';
      case 'hotspot_enhanced':
        return 'Hotspot+';
      case 'mdns':
        return 'mDNS';
      case 'mdns_enhanced':
        return 'mDNS+';
      default:
        return 'Unknown';
    }
  }

  /// Check if device is currently connected
  bool isDeviceConnected(
    Map<String, dynamic> device,
    HomeController controller,
  ) {
    final deviceId = device['deviceId'] ?? device['deviceAddress'];
    return controller.p2pService.connectedDevices.containsKey(deviceId);
  }

  Future<bool> quickConnectAndChat(
    BuildContext context,
    Map<String, dynamic> device,
    HomeController controller,
  ) async {
    if (!context.mounted) return false;

    try {
      final connected = await connectToDevice(device, context, controller);

      if (connected && context.mounted) {
        await Future.delayed(Duration(milliseconds: 500));

        if (context.mounted) {
          await navigateToChat(context, device, null);
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('❌ Quick connect and chat failed: $e');
      return false;
    }
  }

  /// Get connection status text for UI
  String getConnectionStatusText(Map<String, dynamic> device) {
    final isConnected = device['isConnected'] == true;
    final isAvailable = device['isAvailable'] == true;
    final connectionType = device['connectionType'] as String? ?? '';

    if (isConnected) {
      return 'Connected via ${_getConnectionTypeLabel(connectionType)}';
    } else if (isAvailable) {
      return 'Available for connection';
    } else {
      return 'Not available';
    }
  }

  /// Get chat navigation service for external access
  ChatNavigationService get chatNavigationService => _chatNavigationService;

  /// Dispose resources
  void dispose() {
    // Add any cleanup if needed
    debugPrint('🗑️ ConnectionManager disposed');
  }
}
