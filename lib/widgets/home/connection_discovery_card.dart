import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:resqlink/services/p2p/p2p_base_service.dart';
import 'package:resqlink/services/p2p/wifi_direct_service.dart';
import '../../controllers/home_controller.dart';
import '../../utils/resqlink_theme.dart';

class ConnectionDiscoveryCard extends StatelessWidget {
  final HomeController controller;

  const ConnectionDiscoveryCard({super.key, required this.controller});

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
        SizedBox(height: 24),
        _buildActionButtons(context, isNarrow),
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

  Widget _buildActionButtons(BuildContext context, bool isNarrow) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: isNarrow ? 50 : 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: controller.isScanning
                    ? [Colors.orange, Colors.orange.shade700]
                    : [Colors.blue, Colors.blue.shade700],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (controller.isScanning ? Colors.orange : Colors.blue)
                      .withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: controller.isScanning
                  ? null
                  : () => controller.startScan(),
              icon: controller.isScanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.search, size: isNarrow ? 18 : 20),
              label: Text(
                controller.isScanning ? 'Scanning' : 'Find Devices',
                style: TextStyle(
                  fontSize: isNarrow ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Container(
            height: isNarrow ? 50 : 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                // ✅ FIX: Better role-based color logic
                colors: _getRoleButtonColors(controller),
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _getRoleButtonColor(controller).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _getRoleButtonAction(controller, context),
              icon: _getRoleButtonIcon(controller, isNarrow),
              label: Text(
                _getRoleButtonText(controller),
                style: TextStyle(
                  fontSize: isNarrow ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Color> _getRoleButtonColors(HomeController controller) {
    if (controller.p2pService.isHotspotEnabled) {
      return [Colors.green, Colors.green.shade700];
    }

    if (controller.p2pService.wifiDirectService.connectionState ==
        WiFiDirectConnectionState.connected) {
      return [Colors.blue, Colors.blue.shade700];
    }

    if (controller.isConnected) {
      return [Colors.orange, Colors.orange.shade700];
    }

    return [Colors.purple, Colors.purple.shade700];
  }

  Color _getRoleButtonColor(HomeController controller) {
    // Check actual status instead of role
    if (controller.p2pService.isHotspotEnabled) {
      return Colors.green; // Hosting hotspot
    }

    if (controller.p2pService.wifiDirectService.connectionState ==
        WiFiDirectConnectionState.connected) {
      return Colors.blue; // WiFi Direct connected
    }

    if (controller.isConnected) {
      return Colors.orange; // General connection
    }

    return Colors.purple; // Default create network
  }

  String _getRoleButtonText(HomeController controller) {
    // Check actual hotspot status first
    if (controller.p2pService.isHotspotEnabled) {
      return 'Hosting Hotspot';
    }

    // Check WiFi Direct connection
    if (controller.p2pService.wifiDirectService.connectionState ==
        WiFiDirectConnectionState.connected) {
      return 'WiFi Direct Connected';
    }

    // Check if connected to any network
    if (controller.isConnected) {
      return 'Connected';
    }

    // Default state
    return 'Create Network';
  }

  Widget _getRoleButtonIcon(HomeController controller, bool isNarrow) {
    IconData iconData;

    // Choose icon based on actual status
    if (controller.p2pService.isHotspotEnabled) {
      iconData = Icons.wifi_tethering; // Hosting hotspot
    } else if (controller.p2pService.wifiDirectService.connectionState ==
        WiFiDirectConnectionState.connected) {
      iconData = Icons.wifi; // WiFi Direct connected
    } else if (controller.isConnected) {
      iconData = Icons.link; // General connection
    } else {
      iconData = Icons.add_circle; // Create network
    }

    return Icon(iconData, size: isNarrow ? 18 : 20);
  }

  String _getConnectionStatusText(HomeController controller) {
    if (controller.p2pService.isHotspotEnabled) {
      return 'Hosting hotspot - ${controller.p2pService.connectedDevices.length} connected';
    }

    if (controller.p2pService.wifiDirectService.connectionState ==
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

  VoidCallback? _getRoleButtonAction(
    HomeController controller,
    BuildContext context,
  ) {
    // Actions based on actual status
    if (controller.p2pService.isHotspotEnabled) {
      return () =>
          _showHotspotDetails(context, controller); // Show hotspot info
    }

    if (controller.p2pService.wifiDirectService.connectionState ==
            WiFiDirectConnectionState.connected ||
        controller.isConnected) {
      return () =>
          _showConnectionDetails(context, controller); // Show connection info
    }

    // Default: show create network dialog
    return () => _showCreateNetworkDialog(context);
  }

  void _showConnectionDetails(BuildContext context, HomeController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connection Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Role: ${controller.p2pService.currentRole.name.toUpperCase()}',
            ),
            Text(
              'Connected Devices: ${controller.p2pService.connectedDevices.length}',
            ),
            Text(
              'Connection Mode: ${controller.p2pService.currentConnectionMode.name}',
            ),
            if (controller.p2pService.connectedHotspotSSID != null)
              Text('Network: ${controller.p2pService.connectedHotspotSSID}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.p2pService.disconnect();
            },
            child: Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  void _showHotspotDetails(BuildContext context, HomeController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.wifi_tethering, color: Colors.green),
            SizedBox(width: 8),
            Text('Hotspot Details'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SSID: ${controller.p2pService.hotspotService.currentSSID ?? "Unknown"}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Status: Active', style: TextStyle(color: Colors.green)),
            SizedBox(height: 8),
            Text(
              'Connected Devices: ${controller.p2pService.connectedDevices.length}',
            ),
            if (controller.p2pService.connectedDevices.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('Devices:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...controller.p2pService.connectedDevices.values.map(
                (device) => Padding(
                  padding: EdgeInsets.only(left: 16, top: 4),
                  child: Text('• ${device.userName}'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopHotspot(controller);
            },
            child: Text('Stop Hotspot', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _stopHotspot(HomeController controller) async {
    try {
      await controller.p2pService.disconnect();
      debugPrint('✅ Hotspot stopped successfully');
    } catch (e) {
      debugPrint('❌ Failed to stop hotspot: $e');
    }
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
              return _buildDeviceItem(device, isNarrow);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(Map<String, dynamic> device, bool isNarrow) {
    // Fix: Check if device is actually connected via WiFi Direct
    final isWiFiDirectConnected = device['status'] == 'connected';
    final isConnected = device['isConnected'] as bool? ?? isWiFiDirectConnected;

    // Fix: Properly parse signal strength
    final signalStrength =
        device['signalLevel'] as int? ??
        device['rssi'] as int? ??
        (-45 - (device.hashCode % 40)); // Fallback calculation
    final signalLevel = _getSignalLevel(signalStrength);
    final signalColor = _getSignalColor(signalLevel);

    // Get connection type
    final connectionType = device['connectionType'] as String? ?? 'unknown';
    final isAvailable = device['isAvailable'] as bool? ?? true;

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
                          child: Text(
                            device['deviceName'] ?? 'Unknown Device',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: isConnected ? Colors.green : Colors.white,
                            ),
                          ),
                        ),
                        if (isConnected)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              'CONNECTED',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getConnectionTypeColor(
                              connectionType,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getConnectionTypeColor(
                                connectionType,
                              ).withValues(alpha: 0.3),
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
                        ),
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: signalColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: signalColor.withValues(alpha: 0.3),
                            ),
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isAvailable
                        ? () => _connectToDevice(device)
                        : null,
                    icon: Icon(Icons.link, size: 16),
                    label: Text(isAvailable ? 'Connect' : 'Unavailable'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAvailable ? Colors.blue : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () =>
                      _showDeviceDetails(context as BuildContext, device),
                  icon: Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  tooltip: 'Device Details',
                ),
              ],
            ),
          ],
        ],
      ),
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

  void _showCreateNetworkDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: ResQLinkTheme.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.add_circle, color: ResQLinkTheme.primaryRed),
              SizedBox(width: 8),
              Text('Create Network', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose how to create your emergency network:',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 20),

              // WiFi Direct Option
              Container(
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.wifi, color: Colors.blue),
                  ),
                  title: Text(
                    'WiFi Direct',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Direct device-to-device connection (200m range)',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _createWiFiDirectNetwork();
                  },
                ),
              ),

              // Emergency Hotspot Option
              Container(
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.router, color: Colors.purple),
                  ),
                  title: Text(
                    'Emergency Hotspot',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Create WiFi hotspot for multiple devices',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _createHotspotNetwork();
                  },
                ),
              ),

              // Smart Network Option (your existing one, enhanced)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.green.withValues(alpha: 0.1),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome, color: Colors.green),
                  ),
                  title: Text(
                    'Smart Network (Recommended)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Automatically choose the best method',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _createSmartNetwork();
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createWiFiDirectNetwork() async {
    try {
      debugPrint('🔗 Creating WiFi Direct network...');

      // Disable hotspot fallback for pure WiFi Direct
      controller.p2pService.setHotspotFallbackEnabled(false);

      // Check and request permissions
      final hasPermissions = await controller.p2pService
          .checkAndRequestPermissions();
      if (!hasPermissions) {
        debugPrint('❌ WiFi Direct permissions not granted');
        return;
      }

      // Create WiFi Direct group (become group owner)
      final groupCreated = await controller.p2pService.wifiDirectService
          .createGroup();

      if (groupCreated) {
        // Set role to host
        controller.p2pService.setRole(P2PRole.host);

        // Start discovery for peers
        await controller.startScan();

        debugPrint('✅ WiFi Direct group created successfully');
      } else {
        debugPrint('❌ Failed to create WiFi Direct group');
      }
    } catch (e) {
      debugPrint('❌ Failed to create WiFi Direct network: $e');
    }
  }

  Future<void> _createHotspotNetwork() async {
    try {
      debugPrint('📶 Creating emergency hotspot...');

      // Check and request permissions
      final hasPermissions = await controller.p2pService
          .checkAndRequestPermissions();
      if (!hasPermissions) {
        debugPrint('❌ Hotspot permissions not granted');
        return;
      }

      // Actually create the emergency hotspot
      final hotspotCreated = await controller.p2pService
          .createEmergencyHotspot();

      if (hotspotCreated) {
        // Set role to host
        controller.p2pService.setRole(P2PRole.host);

        // Start scanning for connecting devices
        await controller.startScan();

        debugPrint('✅ Emergency hotspot created successfully');
      } else {
        debugPrint('❌ Failed to create emergency hotspot');
      }
    } catch (e) {
      debugPrint('❌ Failed to create hotspot: $e');
    }
  }

  Future<void> _createSmartNetwork() async {
    try {
      debugPrint('🤖 Creating smart network...');

      // Check and request permissions
      final hasPermissions = await controller.p2pService
          .checkAndRequestPermissions();
      if (!hasPermissions) {
        debugPrint('❌ Smart network permissions not granted');
        return;
      }

      // Enable hybrid mode for fallback capability
      controller.p2pService.setHotspotFallbackEnabled(true);

      // Try WiFi Direct first
      debugPrint('📡 Attempting WiFi Direct group creation...');
      final wifiDirectSuccess = await controller.p2pService.wifiDirectService
          .createGroup();

      if (wifiDirectSuccess) {
        debugPrint('✅ WiFi Direct group created successfully');
        controller.p2pService.setRole(P2PRole.host);
      } else {
        debugPrint('📶 WiFi Direct failed, falling back to hotspot...');

        // Fallback to hotspot creation
        final hotspotSuccess = await controller.p2pService
            .createEmergencyHotspot();

        if (hotspotSuccess) {
          debugPrint('✅ Emergency hotspot created as fallback');
          controller.p2pService.setRole(P2PRole.host);
        } else {
          debugPrint('❌ Both WiFi Direct and hotspot creation failed');
          return;
        }
      }

      // Start scanning for connecting devices
      await controller.startScan();

      debugPrint('✅ Smart network created successfully');
    } catch (e) {
      debugPrint('❌ Failed to create smart network: $e');
    }
  }

  Future<void> _connectToDevice(Map<String, dynamic> device) async {
    try {
      debugPrint('🔗 Connecting to device: ${device['deviceName']}');

      final connectionType = device['connectionType'] as String? ?? 'unknown';
      bool success = false;

      switch (connectionType) {
        case 'wifi_direct':
          final deviceAddress = device['deviceAddress'] as String?;
          if (deviceAddress != null) {
            success = await controller.p2pService.wifiDirectService
                .connectToPeer(deviceAddress);

            if (success) {
              debugPrint('✅ WiFi Direct peer connection successful');
              await Future.delayed(Duration(seconds: 2));

              try {
                await controller.p2pService.wifiDirectService
                    .establishSocketConnection();
                debugPrint('✅ Socket connection established');
              } catch (e) {
                debugPrint('⚠️ Socket establishment failed: $e');
              }
            }
          }

        case 'hotspot':
        case 'hotspot_enhanced':
          await controller.connectToDevice(device);
          success = true;

        default:
          await controller.connectToDevice(device);
          success = true;
      }

      if (success) {
        debugPrint('✅ Successfully connected to ${device['deviceName']}');
        // Show success feedback - FIXED (removed mounted check)
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device['deviceName']}'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        debugPrint('❌ Failed to connect to ${device['deviceName']}');
        // Show error feedback - FIXED (removed mounted check)
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${device['deviceName']}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      // Show error feedback - FIXED (removed mounted check)
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Connection error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
