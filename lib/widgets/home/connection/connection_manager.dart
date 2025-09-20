import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/models/message_model.dart';

class ConnectionManager {
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

  void navigateToChat(
    BuildContext context,
    Map<String, dynamic> device,
    Function(Map<String, dynamic>)? onDeviceChatTap,
  ) async {
    if (!context.mounted) return;
    final currentContext = context;

    final deviceId = device['deviceAddress'] ?? device['deviceId'] ?? '';
    final deviceName = device['deviceName'] ?? 'Unknown Device';

    if (deviceId.isEmpty) {
      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Cannot start chat: Device ID not available'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      if (onDeviceChatTap != null) {
        onDeviceChatTap(device);
      } else {
        Navigator.of(currentContext).pushNamed(
          '/chat',
          arguments: {
            'deviceId': deviceId,
            'deviceName': deviceName,
            'connectionType': device['connectionType'],
          },
        );
      }

      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Chat with $deviceName is ready'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error opening chat: $e');
      if (currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Failed to open chat: ${e.toString()}'),
            backgroundColor: Colors.red,
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
                DateTime.fromMillisecondsSinceEpoch(device['lastSeen']).toString(),
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
  void _showConnectingMessage(BuildContext context, Map<String, dynamic> device) {
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

      final success = await controller.p2pService.wifiDirectService
              ?.connectToPeer(deviceAddress) ??
          false;

      if (success) {
        debugPrint('✅ WiFi Direct connection initiated');
        await Future.delayed(Duration(seconds: 3));

        final connectionInfo = await controller
            .p2pService.wifiDirectService
            ?.getConnectionInfo();
        final isConnected = connectionInfo?['isConnected'] ?? false;

        if (isConnected) {
          controller.p2pService.updateConnectionStatus(true);
          await controller.p2pService.wifiDirectService
              ?.establishSocketConnection();
          debugPrint('✅ WiFi Direct connection and socket established');
          return true;
        }
      }

      return false;
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
      case 'wifi_direct': return 'WiFi Direct';
      case 'hotspot': return 'Hotspot';
      case 'hotspot_enhanced': return 'Hotspot+';
      case 'mdns': return 'mDNS';
      case 'mdns_enhanced': return 'mDNS+';
      default: return 'Unknown';
    }
  }
}