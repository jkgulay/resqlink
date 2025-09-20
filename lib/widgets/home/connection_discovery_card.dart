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
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 768;
        final isDesktop = screenWidth >= 1024;

        // Responsive margins and padding
        final horizontalMargin = isDesktop ? 24.0 : (isTablet ? 16.0 : 12.0);
        final cardPadding = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);

        return Card(
          elevation: 8,
          margin: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: isDesktop ? BoxConstraints(maxWidth: 1200) : null,
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
              padding: EdgeInsets.all(cardPadding),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _buildConnectionContent(context, constraints);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionContent(BuildContext context, BoxConstraints constraints) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = constraints.maxWidth < 400;
    final isTablet = screenWidth >= 768;
    final isDesktop = screenWidth >= 1024;

    final sectionSpacing = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);
    final contentSpacing = isDesktop ? 24.0 : (isTablet ? 22.0 : 20.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConnectionHeader(isNarrow, isTablet, isDesktop),
        SizedBox(height: contentSpacing),
        _buildConnectionStats(isNarrow, isTablet, isDesktop),
        if (controller.discoveredDevices.isNotEmpty) ...[
          SizedBox(height: sectionSpacing),
          _buildDevicesList(isNarrow, isTablet, isDesktop),
        ],
        if (controller.isConnected) ...[
          SizedBox(height: contentSpacing),
          _buildConnectedDevices(isNarrow, isTablet, isDesktop),
        ],
      ],
    );
  }

  Widget _buildConnectionHeader(bool isNarrow, bool isTablet, bool isDesktop) {
    final headerPadding = isDesktop ? 26.0 : (isTablet ? 24.0 : (isNarrow ? 18.0 : 22.0));
    final iconPadding = isDesktop ? 16.0 : (isTablet ? 14.0 : 12.0);
    final iconSize = isDesktop ? 32.0 : (isTablet ? 30.0 : (isNarrow ? 24.0 : 28.0));
    final titleSize = isDesktop ? 24.0 : (isTablet ? 22.0 : (isNarrow ? 18.0 : 20.0));
    final subtitleSize = isDesktop ? 16.0 : (isTablet ? 15.0 : (isNarrow ? 13.0 : 14.0));
    final spacing = isDesktop ? 22.0 : (isTablet ? 20.0 : (isNarrow ? 14.0 : 18.0));

    return Container(
      padding: EdgeInsets.all(headerPadding),
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
            padding: EdgeInsets.all(iconPadding),
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
              size: iconSize,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network Connection',
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _getConnectionStatusText(controller),
                  style: TextStyle(
                    fontSize: subtitleSize,
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



  Widget _buildConnectionStats(bool isNarrow, bool isTablet, bool isDesktop) {
    final statsPadding = isDesktop ? 20.0 : (isTablet ? 18.0 : 16.0);
    final dividerHeight = isDesktop ? 40.0 : (isTablet ? 35.0 : 30.0);

    return Container(
      padding: EdgeInsets.all(statsPadding),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _buildNetworkStat(
              'Discovered',
              '${controller.discoveredDevices.length}',
              Icons.radar,
              Colors.blue,
              isTablet,
              isDesktop,
            ),
          ),
          Container(
            width: 1,
            height: dividerHeight,
            color: Colors.blue.withValues(alpha: 0.3),
            margin: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : (isTablet ? 16 : 12)),
          ),
          Expanded(
            child: _buildNetworkStat(
              'Connected',
              '${controller.p2pService.connectedDevices.length}',
              Icons.link,
              Colors.green,
              isTablet,
              isDesktop,
            ),
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
    bool isTablet,
    bool isDesktop,
  ) {
    final iconSize = isDesktop ? 28.0 : (isTablet ? 24.0 : 20.0);
    final valueSize = isDesktop ? 20.0 : (isTablet ? 18.0 : 16.0);
    final labelSize = isDesktop ? 14.0 : (isTablet ? 12.0 : 11.0);
    final spacing = isDesktop ? 8.0 : (isTablet ? 6.0 : 4.0);

    return Column(
      children: [
        Icon(icon, color: color, size: iconSize),
        SizedBox(height: spacing),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: valueSize,
          ),
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: labelSize,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDevicesList(bool isNarrow, bool isTablet, bool isDesktop) {
    final listPadding = isDesktop ? 24.0 : (isTablet ? 22.0 : 20.0);
    final iconPadding = isDesktop ? 12.0 : (isTablet ? 11.0 : 10.0);
    final iconSize = isDesktop ? 22.0 : (isTablet ? 21.0 : (isNarrow ? 18.0 : 20.0));
    final titleSize = isDesktop ? 18.0 : (isTablet ? 17.0 : (isNarrow ? 15.0 : 16.0));
    final spacing = isDesktop ? 16.0 : (isTablet ? 14.0 : 12.0);
    final itemSpacing = isDesktop ? 16.0 : (isTablet ? 14.0 : (isNarrow ? 8.0 : 12.0));
    final contentSpacing = isDesktop ? 24.0 : (isTablet ? 22.0 : (isNarrow ? 16.0 : 20.0));

    return Container(
      padding: EdgeInsets.all(listPadding),
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
                padding: EdgeInsets.all(iconPadding),
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
                  size: iconSize,
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: Text(
                  'Found ${controller.discoveredDevices.length} device${controller.discoveredDevices.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: titleSize,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: contentSpacing),
          if (isDesktop && controller.discoveredDevices.length > 2)
            _buildDevicesGrid(isTablet, isDesktop)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: controller.discoveredDevices.length,
              separatorBuilder: (context, index) => SizedBox(height: itemSpacing),
              itemBuilder: (context, index) {
                final device = controller.discoveredDevices[index];
                return _buildDeviceItem(context, device, isNarrow, isTablet, isDesktop);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDevicesGrid(bool isTablet, bool isDesktop) {
    final crossAxisCount = isDesktop ? 2 : 1;
    final spacing = isDesktop ? 16.0 : 12.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: isDesktop ? 2.5 : 3.0,
      ),
      itemCount: controller.discoveredDevices.length,
      itemBuilder: (context, index) {
        final device = controller.discoveredDevices[index];
        return _buildDeviceItem(context, device, false, isTablet, isDesktop);
      },
    );
  }

  Widget _buildDeviceItem(BuildContext context, Map<String, dynamic> device, bool isNarrow, bool isTablet, bool isDesktop) {
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

    final itemPadding = isDesktop ? 20.0 : (isTablet ? 19.0 : (isNarrow ? 16.0 : 18.0));
    final avatarRadius = isDesktop ? 28.0 : (isTablet ? 26.0 : 24.0);
    final iconSize = isDesktop ? 26.0 : (isTablet ? 24.0 : 22.0);
    final nameSize = isDesktop ? 16.0 : (isTablet ? 15.5 : 15.0);
    final addressSize = isDesktop ? 12.0 : (isTablet ? 11.5 : 11.0);

    return Container(
      padding: EdgeInsets.all(itemPadding),
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
                radius: avatarRadius,
                child: Icon(
                  _getConnectionTypeIcon(connectionType),
                  color: signalColor,
                  size: iconSize,
                ),
              ),
              SizedBox(width: isDesktop ? 16 : (isTablet ? 15 : 14)),
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
                                fontSize: nameSize,
                                color: isConnected ? Colors.green : Colors.white,
                                decoration: isConnected ? TextDecoration.underline : null,
                              ),
                              overflow: TextOverflow.ellipsis,
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
                        fontSize: addressSize,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
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
            SizedBox(height: isDesktop ? 16 : (isTablet ? 14 : 12)),
            _buildActionButtons(context, device, isAvailable, isTablet, isDesktop),
          ] else ...[
            SizedBox(height: isDesktop ? 16 : (isTablet ? 14 : 12)),
            _buildConnectedActions(context, device, isTablet, isDesktop),
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

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> device, bool isAvailable, bool isTablet, bool isDesktop) {
    final iconSize = isDesktop ? 18.0 : (isTablet ? 17.0 : 16.0);
    final fontSize = isDesktop ? 15.0 : (isTablet ? 14.0 : 13.0);
    final padding = isDesktop ? EdgeInsets.symmetric(horizontal: 20, vertical: 12) :
                   (isTablet ? EdgeInsets.symmetric(horizontal: 18, vertical: 10) :
                   EdgeInsets.symmetric(horizontal: 16, vertical: 8));
    final spacing = isDesktop ? 12.0 : (isTablet ? 10.0 : 8.0);

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isAvailable ? () => _connectToDevice(device) : null,
            icon: Icon(Icons.link, size: iconSize),
            label: Text(
              isAvailable ? 'Connect' : 'Unavailable',
              style: TextStyle(fontSize: fontSize),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAvailable ? Colors.blue : Colors.grey,
              foregroundColor: Colors.white,
              padding: padding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        SizedBox(width: spacing),
        IconButton(
          onPressed: () => _showDeviceDetails(context, device),
          icon: Icon(Icons.info_outline, color: Colors.blue, size: iconSize + 2),
          tooltip: 'Device Details',
        ),
      ],
    );
  }

  /// NEW: Build actions for connected devices
  Widget _buildConnectedActions(BuildContext context, Map<String, dynamic> device, bool isTablet, bool isDesktop) {
    final iconSize = isDesktop ? 18.0 : (isTablet ? 17.0 : 16.0);
    final fontSize = isDesktop ? 15.0 : (isTablet ? 14.0 : 13.0);
    final padding = isDesktop ? EdgeInsets.symmetric(horizontal: 20, vertical: 12) :
                   (isTablet ? EdgeInsets.symmetric(horizontal: 18, vertical: 10) :
                   EdgeInsets.symmetric(horizontal: 16, vertical: 8));
    final spacing = isDesktop ? 12.0 : (isTablet ? 10.0 : 8.0);
    final actionIconSize = iconSize + 2;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing / 2,
      children: [
        SizedBox(
          width: isDesktop ? 140 : (isTablet ? 120 : double.infinity),
          child: ElevatedButton.icon(
            onPressed: () => _navigateToChat(context, device),
            icon: Icon(Icons.chat, size: iconSize),
            label: Text(
              'Chat',
              style: TextStyle(fontSize: fontSize),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: padding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (isDesktop || isTablet) ...[
          IconButton(
            onPressed: () => _sendTestMessage(device),
            icon: Icon(Icons.send, color: Colors.blue, size: actionIconSize),
            tooltip: 'Send Test Message',
          ),
          IconButton(
            onPressed: () => _disconnectDevice(device),
            icon: Icon(Icons.link_off, color: Colors.red, size: actionIconSize),
            tooltip: 'Disconnect',
          ),
          IconButton(
            onPressed: () => _showDeviceDetails(context, device),
            icon: Icon(Icons.info_outline, color: Colors.grey, size: actionIconSize),
            tooltip: 'Device Details',
          ),
        ] else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _sendTestMessage(device),
                icon: Icon(Icons.send, color: Colors.blue, size: actionIconSize),
                tooltip: 'Send Test Message',
              ),
              IconButton(
                onPressed: () => _disconnectDevice(device),
                icon: Icon(Icons.link_off, color: Colors.red, size: actionIconSize),
                tooltip: 'Disconnect',
              ),
              IconButton(
                onPressed: () => _showDeviceDetails(context, device),
                icon: Icon(Icons.info_outline, color: Colors.grey, size: actionIconSize),
                tooltip: 'Device Details',
              ),
            ],
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

  Widget _buildConnectedDevices(bool isNarrow, bool isTablet, bool isDesktop) {
    final containerPadding = isDesktop ? 24.0 : (isTablet ? 22.0 : (isNarrow ? 16.0 : 20.0));
    final iconPadding = isDesktop ? 12.0 : (isTablet ? 11.0 : 10.0);
    final iconSize = isDesktop ? 22.0 : (isTablet ? 21.0 : (isNarrow ? 18.0 : 20.0));
    final deviceIconSize = isDesktop ? 20.0 : (isTablet ? 19.0 : (isNarrow ? 16.0 : 18.0));
    final titleSize = isDesktop ? 18.0 : (isTablet ? 17.0 : (isNarrow ? 15.0 : 16.0));
    final deviceNameSize = isDesktop ? 16.0 : (isTablet ? 15.5 : (isNarrow ? 14.0 : 15.0));
    final badgeSize = isDesktop ? 12.0 : (isTablet ? 11.5 : (isNarrow ? 10.0 : 11.0));
    final spacing = isDesktop ? 16.0 : (isTablet ? 14.0 : 12.0);
    final contentSpacing = isDesktop ? 20.0 : (isTablet ? 18.0 : (isNarrow ? 12.0 : 16.0));

    return Container(
      padding: EdgeInsets.all(containerPadding),
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
                padding: EdgeInsets.all(iconPadding),
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
                  size: iconSize,
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: Text(
                  'Connected Devices',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: titleSize,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: contentSpacing),
          ...controller.p2pService.connectedDevices.values.map(
            (device) => Padding(
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 6 : (isTablet ? 5 : 4)),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_tethering,
                    size: deviceIconSize,
                    color: Colors.green,
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: Text(
                      device.userName,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: deviceNameSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 12 : (isTablet ? 11 : 10),
                      vertical: isDesktop ? 8 : (isTablet ? 7 : 6),
                    ),
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
                        fontSize: badgeSize,
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
