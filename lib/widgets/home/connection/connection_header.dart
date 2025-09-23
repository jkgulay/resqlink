import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'package:resqlink/services/p2p/wifi_direct_service.dart';

class ConnectionHeader extends StatelessWidget {
  final HomeController controller;

  const ConnectionHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.getItemPadding(context)),
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
          _buildStatusIcon(context),
          SizedBox(width: ResponsiveHelper.getContentSpacing(context)),
          Expanded(child: _buildStatusText(context)),
          if (controller.p2pService.hotspotService.isEnabled)
            _buildHotspotIndicator(context),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final iconPadding = ResponsiveHelper.isDesktop(context) ? 16.0 : 
                      ResponsiveHelper.isTablet(context) ? 14.0 : 12.0;
    final iconSize = ResponsiveHelper.getIconSize(context, narrow: 24.0);

    return Container(
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
    );
  }

  Widget _buildStatusText(BuildContext context) {
    final titleSize = ResponsiveHelper.getTitleSize(context, narrow: 18.0);
    final subtitleSize = ResponsiveHelper.getSubtitleSize(context, narrow: 13.0);

    return Column(
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
          _getConnectionStatusText(),
          style: TextStyle(
            fontSize: subtitleSize,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  String _getConnectionStatusText() {
    final hotspotService = controller.p2pService.hotspotService;

    if (hotspotService.isEnabled) {
      final clientCount = hotspotService.connectedClients.length;
      final ssid = hotspotService.currentSSID ?? 'ResQLink';
      return 'Hosting "$ssid" - $clientCount client${clientCount == 1 ? '' : 's'}';
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

  Widget _buildHotspotIndicator(BuildContext context) {
    final hotspotService = controller.p2pService.hotspotService;
    final clientCount = hotspotService.connectedClients.length;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_tethering,
            color: Colors.orange,
            size: 16,
          ),
          SizedBox(width: 4),
          Text(
            '$clientCount',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}