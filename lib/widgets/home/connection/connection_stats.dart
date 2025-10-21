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
    return Column(
      children: [
        Container(
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
        ),
        SizedBox(height: ResponsiveSpacing.md(context)),
        _buildScanButton(context),
      ],
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
    final isScanning = controller.isScanning;
    final isWiFiDirectActive = controller.p2pService.wifiDirectService?.connectionState ==
        WiFiDirectConnectionState.connected;

    Color color;
    String status;
    IconData icon;

    if (isScanning) {
      color = ResQLinkTheme.emergencyOrange;
      status = 'Scanning';
      icon = Icons.radar_outlined;
    } else if (isWiFiDirectActive) {
      color = ResQLinkTheme.safeGreen;
      status = 'Active';
      icon = Icons.wifi_outlined;
    } else {
      color = ResQLinkTheme.offlineGray;
      status = 'Ready';
      icon = Icons.wifi_off_outlined;
    }

    return _buildNetworkStat(
      context,
      'WiFi Direct',
      status,
      icon,
      color,
    );
  }

  Widget _buildScanButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: controller.isScanning ? null : () async {
          try {
            await controller.startScan();
          } catch (e) {
            debugPrint('❌ Error starting scan: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.error, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Failed to start scan: Check permissions'),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                  action: SnackBarAction(
                    label: 'RETRY',
                    textColor: Colors.white,
                    onPressed: () async {
                      await controller.p2pService.checkAndRequestPermissions();
                    },
                  ),
                ),
              );
            }
          }
        },
        icon: controller.isScanning
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.radar, size: ResponsiveUtils.isMobile(context) ? 18 : 20),
        label: Text(
          controller.isScanning ? 'Scanning for Devices...' : 'Scan for Devices',
          style: TextStyle(
            fontSize: ResponsiveUtils.isMobile(context) ? 14 : 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: controller.isScanning
              ? ResQLinkTheme.offlineGray
              : ResQLinkTheme.primaryBlue,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.isMobile(context) ? 20 : 24,
            vertical: ResponsiveUtils.isMobile(context) ? 12 : 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: controller.isScanning ? 0 : 2,
        ),
      ),
    );
  }
}