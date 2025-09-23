import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';

class ConnectionStats extends StatelessWidget {
  final HomeController controller;

  const ConnectionStats({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getItemPadding(context);
    final dividerHeight = ResponsiveHelper.isDesktop(context) ? 40.0 : 
                         ResponsiveHelper.isTablet(context) ? 35.0 : 30.0;

    return Container(
      padding: EdgeInsets.all(padding),
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
              context,
              'Discovered',
              '${controller.discoveredDevices.length}',
              Icons.radar,
              Colors.blue,
            ),
          ),
          _buildStatDivider(context, dividerHeight),
          Expanded(
            child: _buildNetworkStat(
              context,
              'Connected',
              '${controller.p2pService.connectedDevices.length}',
              Icons.link,
              Colors.green,
            ),
          ),
          _buildStatDivider(context, dividerHeight),
          Expanded(
            child: _buildHotspotStat(context),
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
    final iconSize = ResponsiveHelper.isDesktop(context) ? 28.0 : 
                    ResponsiveHelper.isTablet(context) ? 24.0 : 20.0;
    final valueSize = ResponsiveHelper.isDesktop(context) ? 20.0 : 
                     ResponsiveHelper.isTablet(context) ? 18.0 : 16.0;
    final labelSize = ResponsiveHelper.isDesktop(context) ? 14.0 : 
                     ResponsiveHelper.isTablet(context) ? 12.0 : 11.0;
    final spacing = ResponsiveHelper.isDesktop(context) ? 8.0 : 
                   ResponsiveHelper.isTablet(context) ? 6.0 : 4.0;

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

  Widget _buildStatDivider(BuildContext context, double height) {
    return Container(
      width: 1,
      height: height,
      color: Colors.blue.withValues(alpha: 0.3),
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.isDesktop(context) ? 20 :
                   ResponsiveHelper.isTablet(context) ? 16 : 12,
      ),
    );
  }

  Widget _buildHotspotStat(BuildContext context) {
    final hotspotService = controller.p2pService.hotspotService;
    final isHotspotEnabled = hotspotService.isEnabled;
    final clientCount = hotspotService.connectedClients.length;

    final color = isHotspotEnabled ? Colors.orange : Colors.grey;
    final status = isHotspotEnabled ? '$clientCount' : 'Off';

    return _buildNetworkStat(
      context,
      'Hotspot',
      status,
      isHotspotEnabled ? Icons.wifi_tethering : Icons.wifi_tethering_off,
      color,
    );
  }
}