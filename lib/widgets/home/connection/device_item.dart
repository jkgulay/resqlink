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

  @override
  Widget build(BuildContext context) {
    final deviceStatus = widget.device['status'] as String? ?? 'unknown';
    // FIXED: Only "connected" status (0) means truly connected
    // "invited" status (1) means connection pending, not yet established
    final isWiFiDirectConnected = deviceStatus == 'connected';
    final isGenerallyConnected = widget.device['isConnected'] as bool? ?? false;
    final isConnected = isWiFiDirectConnected || isGenerallyConnected;

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
          DeviceInfo(
            device: widget.device,
            isConnected: isConnected,
            onChatTap: () => _connectionManager.navigateToChat(
              context,
              widget.device,
              widget.onDeviceChatTap,
            ),
          ),
          SizedBox(height: ResponsiveSpacing.sm(context)),
          DeviceActions(
            device: widget.device,
            controller: widget.controller,
            isConnected: isConnected,
            onDeviceChatTap: widget.onDeviceChatTap,
          ),
        ],
      ),
    );
  }
}
