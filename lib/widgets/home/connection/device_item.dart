import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'device_actions.dart';
import 'device_info.dart';
import 'connection_manager.dart';

class DeviceItem extends StatefulWidget {
  final Map<String, dynamic> device;
  final HomeController controller;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const DeviceItem({
    super.key,
    required this.device,
    required this.controller,
    this.onDeviceChatTap,
  });

  @override
  State<DeviceItem> createState() => _DeviceItemState();
}

class _DeviceItemState extends State<DeviceItem> {
  final ConnectionManager _connectionManager = ConnectionManager();
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final deviceStatus = widget.device['status'] as String? ?? 'unknown';
    // FIXED: Only "connected" status (0) means truly connected
    // "invited" status (1) means connection pending, not yet established
    final isWiFiDirectConnected = deviceStatus == 'connected';
    final isGenerallyConnected = widget.device['isConnected'] as bool? ?? false;
    final isConnected = isWiFiDirectConnected || isGenerallyConnected;

    // Get mesh devices (other devices in the same WiFi Direct group)
    final meshDevices = _getMeshDevices();
    final hasMeshDevices = meshDevices.isNotEmpty;

    return Container(
      padding: ResponsiveSpacing.padding(context, all: 16),
      decoration: BoxDecoration(
        color: isConnected
            ? ResQLinkTheme.safeGreen.withValues(alpha: 0.1)
            : ResQLinkTheme.offlineGray.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? ResQLinkTheme.safeGreen.withValues(alpha: 0.4)
              : ResQLinkTheme.offlineGray.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color:
                (isConnected
                        ? ResQLinkTheme.safeGreen
                        : ResQLinkTheme.offlineGray)
                    .withValues(alpha: 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DeviceInfo(
                  device: widget.device,
                  isConnected: isConnected,
                  onChatTap: () => _connectionManager.navigateToChat(
                    context,
                    widget.device,
                    widget.onDeviceChatTap,
                  ),
                ),
              ),
              if (hasMeshDevices)
                IconButton(
                  icon: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: ResQLinkTheme.primaryBlue,
                  ),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  tooltip:
                      '${_isExpanded ? "Hide" : "Show"} ${meshDevices.length} device${meshDevices.length == 1 ? "" : "s"} in group',
                ),
            ],
          ),
          SizedBox(height: ResponsiveSpacing.sm(context)),
          DeviceActions(
            device: widget.device,
            controller: widget.controller,
            isConnected: isConnected,
            onDeviceChatTap: widget.onDeviceChatTap,
          ),
          if (_isExpanded && hasMeshDevices) ...[
            SizedBox(height: ResponsiveSpacing.md(context)),
            _buildMeshDevicesList(context, meshDevices, isConnected),
          ],
        ],
      ),
    );
  }

  /// Get mesh devices (devices in the same WiFi Direct group)
  List<Map<String, dynamic>> _getMeshDevices() {
    // Only show mesh devices if this device is connected and is a group owner
    final isConnected = widget.device['isConnected'] as bool? ?? false;
    final deviceStatus = widget.device['status'] as String? ?? 'unknown';
    final isWiFiDirectConnected = deviceStatus == 'connected';

    if (!isConnected && !isWiFiDirectConnected) {
      return [];
    }

    // Get all connected devices from P2P service
    final myDeviceId = widget.controller.p2pService.deviceId;
    final targetDeviceId =
        widget.device['deviceId'] ?? widget.device['deviceAddress'];

    // If I'm connected TO this device (it's the group owner), show its connected clients
    if (targetDeviceId != myDeviceId) {
      // Get mesh devices that are NOT me and NOT the group owner itself
      final meshDevices = widget.controller.p2pService.meshDevices;
      final result = <Map<String, dynamic>>[];

      for (final entry in meshDevices.entries) {
        final deviceId = entry.key;
        final device = entry.value;

        // Exclude myself and the group owner from the list
        if (deviceId != myDeviceId && deviceId != targetDeviceId) {
          result.add({
            'deviceId': deviceId,
            'deviceName': device.userName,
            'deviceAddress': deviceId,
            'isHost': device.isHost,
            'isConnected': true,
            'isMeshDevice': true,
          });
        }
      }

      return result;
    }

    // If this IS me (I'm the group owner), this case is handled by ConnectedDevices widget
    return [];
  }

  /// Build the list of mesh devices
  Widget _buildMeshDevicesList(
    BuildContext context,
    List<Map<String, dynamic>> meshDevices,
    bool isGroupConnected,
  ) {
    return Container(
      margin: EdgeInsets.only(left: ResponsiveSpacing.lg(context)),
      padding: ResponsiveSpacing.padding(context, all: 12),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.group_outlined,
                size: 16,
                color: ResQLinkTheme.primaryBlue,
              ),
              SizedBox(width: ResponsiveSpacing.xs(context)),
              Text(
                'Devices in Group (${meshDevices.length})',
                style: TextStyle(
                  color: ResQLinkTheme.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveSpacing.sm(context)),
          ...meshDevices.map((device) => _buildMeshDeviceItem(context, device)),
        ],
      ),
    );
  }

  /// Build a single mesh device item
  Widget _buildMeshDeviceItem(
    BuildContext context,
    Map<String, dynamic> device,
  ) {
    final deviceName = device['deviceName'] ?? 'Unknown Device';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveSpacing.xs(context)),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering, size: 14, color: ResQLinkTheme.safeGreen),
          SizedBox(width: ResponsiveSpacing.sm(context)),
          Expanded(
            child: Text(
              deviceName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chat_bubble_outline,
              color: Color(0xFFFF6500),
              size: 16,
            ),
            onPressed: () {
              if (widget.onDeviceChatTap != null) {
                widget.onDeviceChatTap!(device);
              }
            },
            padding: EdgeInsets.all(8),
            constraints: BoxConstraints(),
            tooltip: 'Chat with $deviceName',
          ),
        ],
      ),
    );
  }
}
