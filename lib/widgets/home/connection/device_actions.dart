import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'connection_manager.dart';

class DeviceActions extends StatefulWidget {
  final Map<String, dynamic> device;
  final HomeController controller;
  final bool isConnected;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const DeviceActions({
    super.key,
    required this.device,
    required this.controller,
    required this.isConnected,
    this.onDeviceChatTap,
  });

  @override
  State<DeviceActions> createState() => _DeviceActionsState();
}

class _DeviceActionsState extends State<DeviceActions> {
  final ConnectionManager _connectionManager = ConnectionManager();

  @override
  Widget build(BuildContext context) {
    return widget.isConnected 
        ? _buildConnectedActions()
        : _buildDisconnectedActions();
  }

  Widget _buildDisconnectedActions() {
    final isAvailable = widget.device['isAvailable'] as bool? ?? true;
    final iconSize = ResponsiveHelper.getSubtitleSize(context, narrow: 16.0);
    final fontSize = ResponsiveHelper.getSubtitleSize(context, narrow: 13.0);
    final padding = _getButtonPadding();
    final spacing = ResponsiveHelper.getContentSpacing(context) * 0.5;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isAvailable ? _connect : null,
            icon: Icon(Icons.link, size: iconSize),
            label: Text(
              isAvailable ? 'Connect' : 'Unavailable',
              style: TextStyle(fontSize: fontSize),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAvailable ? Colors.blue : Colors.grey,
              foregroundColor: Colors.white,
              padding: padding,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(width: spacing),
        IconButton(
          onPressed: _showDetails,
          icon: Icon(Icons.info_outline, color: Colors.blue, size: iconSize + 2),
          tooltip: 'Device Details',
        ),
      ],
    );
  }

  Widget _buildConnectedActions() {
    final iconSize = ResponsiveHelper.getSubtitleSize(context, narrow: 16.0);
    final fontSize = ResponsiveHelper.getSubtitleSize(context, narrow: 13.0);
    final padding = _getButtonPadding();
    final spacing = ResponsiveHelper.getContentSpacing(context) * 0.5;

    if (ResponsiveHelper.isDesktop(context) || ResponsiveHelper.isTablet(context)) {
      return _buildDesktopConnectedActions(iconSize, fontSize, padding, spacing);
    }
    return _buildMobileConnectedActions(iconSize, fontSize, padding, spacing);
  }

  Widget _buildDesktopConnectedActions(double iconSize, double fontSize, EdgeInsets padding, double spacing) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing / 2,
      children: [
        SizedBox(
          width: ResponsiveHelper.isDesktop(context) ? 140 : 120,
          child: ElevatedButton.icon(
            onPressed: _openChat,
            icon: Icon(Icons.chat, size: iconSize),
            label: Text('Chat', style: TextStyle(fontSize: fontSize)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: padding,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        IconButton(
          onPressed: _sendTest,
          icon: Icon(Icons.send, color: Colors.blue, size: iconSize + 2),
          tooltip: 'Send Test Message',
        ),
        IconButton(
          onPressed: _disconnect,
          icon: Icon(Icons.link_off, color: Colors.red, size: iconSize + 2),
          tooltip: 'Disconnect',
        ),
        IconButton(
          onPressed: _showDetails,
          icon: Icon(Icons.info_outline, color: Colors.grey, size: iconSize + 2),
          tooltip: 'Device Details',
        ),
      ],
    );
  }

  Widget _buildMobileConnectedActions(double iconSize, double fontSize, EdgeInsets padding, double spacing) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openChat,
            icon: Icon(Icons.chat, size: iconSize),
            label: Text('Chat', style: TextStyle(fontSize: fontSize)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: padding,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(height: spacing),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: _sendTest,
              icon: Icon(Icons.send, color: Colors.blue, size: iconSize + 2),
              tooltip: 'Send Test Message',
            ),
            IconButton(
              onPressed: _disconnect,
              icon: Icon(Icons.link_off, color: Colors.red, size: iconSize + 2),
              tooltip: 'Disconnect',
            ),
            IconButton(
              onPressed: _showDetails,
              icon: Icon(Icons.info_outline, color: Colors.grey, size: iconSize + 2),
              tooltip: 'Device Details',
            ),
          ],
        ),
      ],
    );
  }

  EdgeInsets _getButtonPadding() {
    if (ResponsiveHelper.isDesktop(context)) {
      return EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    } else if (ResponsiveHelper.isTablet(context)) {
      return EdgeInsets.symmetric(horizontal: 18, vertical: 10);
    }
    return EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  }

  Future<void> _connect() async {
    if (!mounted) return;
    await _connectionManager.connectToDevice(widget.device, context, widget.controller);
  }

  Future<void> _disconnect() async {
    if (!mounted) return;
    await _connectionManager.disconnectDevice(widget.device, context, widget.controller);
  }

  Future<void> _sendTest() async {
    if (!mounted) return;
    await _connectionManager.sendTestMessage(widget.device, context, widget.controller);
  }

  void _openChat() {
    _connectionManager.navigateToChat(context, widget.device, widget.onDeviceChatTap);
  }

  void _showDetails() {
    _connectionManager.showDeviceDetails(context, widget.device);
  }
}