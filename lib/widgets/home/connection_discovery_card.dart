import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:resqlink/services/p2p/wifi_direct_service.dart';
import '../../controllers/home_controller.dart';
import '../../models/message_model.dart';

class ConnectionDiscoveryCard extends StatelessWidget {
  final HomeController controller;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const ConnectionDiscoveryCard({
    super.key,
    required this.controller,
    this.onDeviceChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.08),
              Color(0xFF1E3A5F).withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 400;
              return _buildConnectionContent(context, isNarrow);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionContent(BuildContext context, bool isNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConnectionHeader(isNarrow),
        SizedBox(height: 20),
        _buildConnectionStats(isNarrow),
        if (controller.discoveredDevices.isNotEmpty) ...[
          SizedBox(height: 24),
          _buildDevicesList(isNarrow),
        ],
        if (controller.isConnected) ...[
          SizedBox(height: 20),
          _buildConnectedDevices(isNarrow),
        ],
      ],
    );
  }

  Widget _buildConnectionHeader(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Color(0xFF1E3A5F).withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: controller.isConnected
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: controller.isConnected
                    ? Colors.green.withValues(alpha: 0.4)
                    : Colors.blue.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              Icons.network_wifi,
              color: controller.isConnected ? Colors.green : Colors.blue,
              size: isNarrow ? 24 : 28,
            ),
          ),
          SizedBox(width: isNarrow ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network Connection',
                  style: TextStyle(
                    fontSize: isNarrow ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _getConnectionStatusText(controller),
                  style: TextStyle(
                    fontSize: isNarrow ? 13 : 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  String _getConnectionStatusText(HomeController controller) {
    if (controller.p2pService.isHotspotEnabled) {
      return 'Hosting hotspot - ${controller.p2pService.connectedDevices.length} connected';
    }

    if (controller.p2pService.wifiDirectService?.connectionState ==
        WiFiDirectConnectionState.connected) {
      return 'WiFi Direct active - ${controller.p2pService.connectedDevices.length} connected';
    }

    if (controller.isConnected) {
      return 'Connected to ${controller.p2pService.connectedDevices.length} device(s)';
    }

    if (controller.isScanning) {
      return 'Scanning for devices...';
    }

    return 'Ready to connect';
  }



  Widget _buildConnectionStats(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNetworkStat(
            'Discovered',
            '${controller.discoveredDevices.length}',
            Icons.radar,
            Colors.blue,
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.blue.withValues(alpha: 0.3),
          ),
          _buildNetworkStat(
            'Connected',
            '${controller.p2pService.connectedDevices.length}',
            Icons.link,
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDevicesList(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.devices,
                  color: Colors.green,
                  size: isNarrow ? 18 : 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Found ${controller.discoveredDevices.length} device${controller.discoveredDevices.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: isNarrow ? 15 : 16,
                ),
              ),
            ],
          ),
          SizedBox(height: isNarrow ? 16 : 20),
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: controller.discoveredDevices.length,
            separatorBuilder: (context, index) =>
                SizedBox(height: isNarrow ? 8 : 12),
            itemBuilder: (context, index) {
              final device = controller.discoveredDevices[index];
              return _buildDeviceItem(context, device, isNarrow);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(BuildContext context, Map<String, dynamic> device, bool isNarrow) {
    // CRITICAL FIX: Better connection status detection for WiFi Direct
    final deviceStatus = device['status'] as String? ?? 'unknown';
    final isWiFiDirectConnected = deviceStatus == 'connected';
    final isGenerallyConnected = device['isConnected'] as bool? ?? false;
    final isConnected = isWiFiDirectConnected || isGenerallyConnected;

    // ENHANCED: Better signal strength parsing
    final signalStrength = _parseSignalStrength(device);
    final signalLevel = _getSignalLevel(signalStrength);
    final signalColor = _getSignalColor(signalLevel);

    // Get connection type
    final connectionType = device['connectionType'] as String? ?? 'unknown';
    final isAvailable = device['isAvailable'] as bool? ?? !isConnected;

    return Container(
      padding: EdgeInsets.all(isNarrow ? 16 : 18),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? Colors.green.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: signalColor.withValues(alpha: 0.2),
                radius: 24,
                child: Icon(
                  _getConnectionTypeIcon(connectionType),
                  color: signalColor,
                  size: 22,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: isConnected ? () => _navigateToChat(context, device) : null,
                            child: Text(
                              device['deviceName'] ?? 'Unknown Device',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isConnected ? Colors.green : Colors.white,
                                decoration: isConnected ? TextDecoration.underline : null,
                              ),
                            ),
                          ),
                        ),
                        _buildConnectionStatusBadge(isConnected, deviceStatus),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      device['deviceAddress'] ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        _buildConnectionTypeBadge(connectionType),
                        SizedBox(width: 8),
                        _buildSignalBadge(
                          signalLevel,
                          signalStrength,
                          signalColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isConnected) ...[
            SizedBox(height: 12),
            _buildActionButtons(context, device, isAvailable),
          ] else ...[
            SizedBox(height: 12),
            _buildConnectedActions(context, device),
          ],
        ],
      ),
    );
  }

  int _parseSignalStrength(Map<String, dynamic> device) {
    // Try different signal strength fields
    if (device['signalLevel'] != null) {
      return device['signalLevel'] as int;
    }
    if (device['rssi'] != null) {
      return device['rssi'] as int;
    }
    if (device['level'] != null) {
      return device['level'] as int;
    }

    // Generate reasonable fallback based on connection type
    final connectionType = device['connectionType'] as String? ?? 'unknown';
    switch (connectionType) {
      case 'wifi_direct':
        return -45; // Strong signal for direct connection
      case 'hotspot':
        return -55; // Medium signal for hotspot
      default:
        return -65; // Weak signal for unknown
    }
  }

  Widget _buildConnectionStatusBadge(bool isConnected, String deviceStatus) {
    if (!isConnected) return SizedBox.shrink();

    Color badgeColor;
    String badgeText;

    if (deviceStatus == 'connected') {
      badgeColor = Colors.green;
      badgeText = 'CONNECTED';
    } else {
      badgeColor = Colors.orange;
      badgeText = 'LINKED';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          fontSize: 10,
          color: badgeColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// NEW: Build connection type badge
  Widget _buildConnectionTypeBadge(String connectionType) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getConnectionTypeColor(connectionType).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getConnectionTypeColor(connectionType).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        _getConnectionTypeLabel(connectionType),
        style: TextStyle(
          fontSize: 10,
          color: _getConnectionTypeColor(connectionType),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// NEW: Build signal strength badge
  Widget _buildSignalBadge(
    int signalLevel,
    int signalStrength,
    Color signalColor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: signalColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: signalColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSignalBars(signalLevel, signalColor),
          SizedBox(width: 4),
          Text(
            '$signalStrength dBm',
            style: TextStyle(
              fontSize: 10,
              color: signalColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> device, bool isAvailable) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isAvailable ? () => _connectToDevice(device) : null,
            icon: Icon(Icons.link, size: 16),
            label: Text(isAvailable ? 'Connect' : 'Unavailable'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAvailable ? Colors.blue : Colors.grey,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        IconButton(
          onPressed: () => _showDeviceDetails(context, device),
          icon: Icon(Icons.info_outline, color: Colors.blue, size: 20),
          tooltip: 'Device Details',
        ),
      ],
    );
  }

  /// NEW: Build actions for connected devices
  Widget _buildConnectedActions(BuildContext context, Map<String, dynamic> device) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _navigateToChat(context, device),
            icon: Icon(Icons.chat, size: 16),
            label: Text('Chat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        IconButton(
          onPressed: () => _sendTestMessage(device),
          icon: Icon(Icons.send, color: Colors.blue, size: 20),
          tooltip: 'Send Test Message',
        ),
        IconButton(
          onPressed: () => _disconnectDevice(device),
          icon: Icon(Icons.link_off, color: Colors.red, size: 20),
          tooltip: 'Disconnect',
        ),
        IconButton(
          onPressed: () => _showDeviceDetails(context, device),
          icon: Icon(Icons.info_outline, color: Colors.grey, size: 20),
          tooltip: 'Device Details',
        ),
      ],
    );
  }

  IconData _getConnectionTypeIcon(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct':
        return Icons.wifi;
      case 'hotspot':
      case 'hotspot_enhanced':
        return Icons.router;
      case 'mdns':
      case 'mdns_enhanced':
        return Icons.broadcast_on_personal;
      default:
        return Icons.devices;
    }
  }

  Color _getConnectionTypeColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct':
        return Colors.blue;
      case 'hotspot':
      case 'hotspot_enhanced':
        return Colors.purple;
      case 'mdns':
      case 'mdns_enhanced':
        return Colors.orange;
      default:
        return Colors.grey;
    }
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

  void _showDeviceDetails(BuildContext context, Map<String, dynamic> device) {
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

  Widget _buildConnectedDevices(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: isNarrow ? 18 : 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Connected Devices',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: isNarrow ? 15 : 16,
                ),
              ),
            ],
          ),
          SizedBox(height: isNarrow ? 12 : 16),
          ...controller.p2pService.connectedDevices.values.map(
            (device) => Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_tethering,
                    size: isNarrow ? 16 : 18,
                    color: Colors.green,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      device.userName,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: isNarrow ? 14 : 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      device.isHost ? 'HOST' : 'CLIENT',
                      style: TextStyle(
                        fontSize: isNarrow ? 10 : 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBars(int level, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isActive = index < level;
        final barHeight = 8.0 + (index * 2);
        return Container(
          width: 3,
          height: barHeight,
          margin: EdgeInsets.only(right: 1.5),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }

  int _getSignalLevel(int dbm) {
    if (dbm >= -50) return 5;
    if (dbm >= -60) return 4;
    if (dbm >= -70) return 3;
    if (dbm >= -80) return 2;
    if (dbm >= -90) return 1;
    return 0;
  }

  Color _getSignalColor(int level) {
    switch (level) {
      case 5:
      case 4:
        return Colors.green;
      case 3:
        return Colors.amber;
      case 2:
      case 1:
        return Colors.orange;
      default:
        return Colors.red;
    }
  }



  Future<void> _connectToDevice(Map<String, dynamic> device) async {
    try {
      debugPrint('🔗 Connecting to device: ${device['deviceName']}');

      final connectionType = device['connectionType'] as String?;

      // Show connecting state
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
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

      bool success = false;

      switch (connectionType) {
        case 'wifi_direct':
          success = await _connectViaWifiDirect(device);
        case 'hotspot':
        case 'hotspot_enhanced':
          success = await _connectViaHotspot(device);
        default:
          await controller.connectToDevice(device);
          success = true;
      }

      // Show result
      if (success) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Connected to ${device['deviceName']}'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Failed to connect to ${device['deviceName']}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Connection error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<bool> _connectViaHotspot(Map<String, dynamic> device) async {
    final ssid = device['deviceName'] as String?;
    if (ssid == null) return false;

    return await controller.p2pService.connectToResQLinkNetwork(ssid);
  }

  Future<bool> _connectViaWifiDirect(Map<String, dynamic> device) async {
    final deviceAddress = device['deviceAddress'] as String?;
    if (deviceAddress == null) return false;

    try {
      debugPrint('📡 Connecting via WiFi Direct to: $deviceAddress');

      // Use WiFiDirectService for actual connection
      final success = await controller.p2pService.wifiDirectService
          ?.connectToPeer(deviceAddress) ?? false;

      if (success) {
        debugPrint('✅ WiFi Direct connection initiated');

        // Wait for connection to establish
        await Future.delayed(Duration(seconds: 3));

        // Check connection status
        final connectionInfo = await controller.p2pService.wifiDirectService
            ?.getConnectionInfo();
        final isConnected = connectionInfo?['isConnected'] ?? false;

        if (isConnected) {
          // Update P2P service state
          controller.p2pService.updateConnectionStatus(true);

          // Try to establish socket communication
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

  Future<void> _sendTestMessage(Map<String, dynamic> device) async {
    try {
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final testMessage = 'Hello from ResQLink! This is a test message.';

      await controller.p2pService.sendMessage(
        message: testMessage,
        type: MessageType.text,
        targetDeviceId: device['deviceId'],
        senderName: controller.p2pService.userName ?? 'User',
      );

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Test message sent to $deviceName'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to send test message: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Failed to send message'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _navigateToChat(BuildContext context, Map<String, dynamic> device) {
    if (onDeviceChatTap != null) {
      onDeviceChatTap!(device);
    } else {
      // Fallback: Show a message if no navigation callback is provided
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat with ${device['deviceName'] ?? 'device'}'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _disconnectDevice(Map<String, dynamic> device) async {
    try {
      final deviceName = device['deviceName'] ?? 'Unknown Device';
      final connectionType = device['connectionType'] as String? ?? 'unknown';

      if (connectionType == 'wifi_direct') {
        await controller.p2pService.wifiDirectService?.removeGroup();
      } else {
        await controller.p2pService.disconnect();
      }

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Disconnected from $deviceName'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to disconnect: $e');
    }
  }
}
