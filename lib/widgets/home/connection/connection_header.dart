import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:resqlink/utils/responsive_utils.dart';
import 'package:resqlink/services/p2p/wifi_direct_service.dart';

class ConnectionHeader extends StatelessWidget {
  final HomeController controller;

  const ConnectionHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ResponsiveSpacing.padding(context, all: 16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatusIcon(context),
          SizedBox(width: ResponsiveSpacing.md(context)),
          Expanded(child: _buildStatusText(context)),
          _buildWiFiDirectSettingsButton(context),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final iconSize = ResponsiveUtils.isMobile(context) ? 24.0 : 28.0;
    final iconPadding = ResponsiveSpacing.sm(context);

    final statusColor = controller.isConnected
        ? ResQLinkTheme.safeGreen
        : ResQLinkTheme.primaryBlue;

    return Container(
      padding: EdgeInsets.all(iconPadding),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.wifi,
        color: statusColor,
        size: iconSize,
      ),
    );
  }

  Widget _buildStatusText(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveTextWidget(
          'WiFi Direct Connection',
          styleBuilder: (context) => ResponsiveText.heading3(context).copyWith(
            color: Colors.white,
          ),
        ),
        SizedBox(height: ResponsiveSpacing.xs(context)),
        ResponsiveTextWidget(
          _getConnectionStatusText(),
          styleBuilder: (context) => ResponsiveText.bodyMedium(context).copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  String _getConnectionStatusText() {
    // Pure WiFi Direct implementation - no hotspot references
    if (controller.p2pService.wifiDirectService?.connectionState ==
        WiFiDirectConnectionState.connected) {
      final deviceCount = controller.p2pService.connectedDevices.length;
      return 'WiFi Direct active • $deviceCount device${deviceCount == 1 ? '' : 's'} connected';
    }

    if (controller.isConnected) {
      final deviceCount = controller.p2pService.connectedDevices.length;
      return 'Connected to $deviceCount device${deviceCount == 1 ? '' : 's'}';
    }

    if (controller.isScanning) {
      return 'Scanning for nearby devices...';
    }

    return 'Ready to discover and connect';
  }


  Widget _buildWiFiDirectSettingsButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: IconButton(
        onPressed: () => _openWiFiDirectSettings(context),
        icon: Icon(
          Icons.settings_outlined,
          color: ResQLinkTheme.primaryBlue,
          size: ResponsiveUtils.isMobile(context) ? 20.0 : 24.0,
        ),
        tooltip: 'WiFi Direct Settings',
        constraints: BoxConstraints(
          minWidth: ResponsiveUtils.isMobile(context) ? 40 : 48,
          minHeight: ResponsiveUtils.isMobile(context) ? 40 : 48,
        ),
      ),
    );
  }

  Future<void> _openWiFiDirectSettings(BuildContext context) async {
    try {
      await controller.p2pService.wifiDirectService?.openWiFiDirectSettings();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.settings, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('WiFi Direct settings opened'),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Failed to open WiFi Direct settings'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
