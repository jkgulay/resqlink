import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:resqlink/utils/responsive_utils.dart';
import 'package:resqlink/services/p2p/wifi_direct_service.dart';

class ConnectionStats extends StatelessWidget {
  final HomeController controller;

  const ConnectionStats({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ResponsiveSpacing.padding(context, all: 16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.4),
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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _buildNetworkStat(
              context,
              'Discovered',
              '${controller.discoveredDevices.length}',
              Icons.radar_outlined,
              ResQLinkTheme.primaryBlue,
            ),
          ),
          _buildStatDivider(context),
          Expanded(
            child: _buildNetworkStat(
              context,
              'Connected',
              '${controller.p2pService.connectedDevices.length}',
              Icons.link_outlined,
              ResQLinkTheme.safeGreen,
            ),
          ),
          _buildStatDivider(context),
          Expanded(
            child: _buildWiFiDirectStat(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final iconSize = ResponsiveUtils.isMobile(context) ? 20.0 : 24.0;

    return Column(
      children: [
        Icon(icon, color: color, size: iconSize),
        SizedBox(height: ResponsiveSpacing.xs(context)),
        ResponsiveTextWidget(
          value,
          styleBuilder: (context) => ResponsiveText.heading3(context).copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveSpacing.xs(context) / 2),
        ResponsiveTextWidget(
          label,
          styleBuilder: (context) => ResponsiveText.caption(context).copyWith(
            color: color.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatDivider(BuildContext context) {
    final height = ResponsiveUtils.isMobile(context) ? 30.0 : 40.0;

    return Container(
      width: 1.5,
      height: height,
      decoration: BoxDecoration(
        color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(1),
      ),
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveSpacing.sm(context),
      ),
    );
  }

  Widget _buildWiFiDirectStat(BuildContext context) {
    final isWiFiDirectActive = controller.p2pService.wifiDirectService?.connectionState ==
        WiFiDirectConnectionState.connected;

    final color = isWiFiDirectActive
        ? ResQLinkTheme.emergencyOrange
        : ResQLinkTheme.offlineGray;
    final status = isWiFiDirectActive ? 'Active' : 'Ready';

    return _buildNetworkStat(
      context,
      'WiFi Direct',
      status,
      isWiFiDirectActive ? Icons.wifi_outlined : Icons.wifi_off_outlined,
      color,
    );
  }
}