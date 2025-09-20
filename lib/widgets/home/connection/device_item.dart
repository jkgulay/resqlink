import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';
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
    final isWiFiDirectConnected = deviceStatus == 'connected';
    final isGenerallyConnected = widget.device['isConnected'] as bool? ?? false;
    final isConnected = isWiFiDirectConnected || isGenerallyConnected;

    final itemPadding = ResponsiveHelper.getItemPadding(context, narrow: 16.0);

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
          DeviceInfo(
            device: widget.device,
            isConnected: isConnected,
            onChatTap: () => _connectionManager.navigateToChat(
              context,
              widget.device,
              widget.onDeviceChatTap,
            ),
          ),
          SizedBox(height: ResponsiveHelper.getContentSpacing(context) * 0.75),
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