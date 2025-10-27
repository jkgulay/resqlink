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
              Expanded(child: _buildWiFiDirectStat(context)),
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
          styleBuilder: (context) => ResponsiveText.heading3(
            context,
          ).copyWith(color: color, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: ResponsiveSpacing.xs(context) / 2),
        ResponsiveTextWidget(
          label,
          styleBuilder: (context) => ResponsiveText.caption(
            context,
          ).copyWith(color: color.withValues(alpha: 0.8)),
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
      margin: EdgeInsets.symmetric(horizontal: ResponsiveSpacing.sm(context)),
    );
  }

  Widget _buildWiFiDirectStat(BuildContext context) {
    final isScanning = controller.isScanning;
    final isWiFiDirectActive =
        controller.p2pService.wifiDirectService?.connectionState ==
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

    return _buildNetworkStat(context, 'WiFi Direct', status, icon, color);
  }

  Widget _buildScanButton(BuildContext context) {
    final isHost =
        controller.p2pService.wifiDirectService?.isGroupOwner ?? false;
    final groupFormed =
        controller.p2pService.wifiDirectService?.groupFormed ?? false;
    final isWiFiDirectActive =
        controller.p2pService.wifiDirectService?.connectionState ==
        WiFiDirectConnectionState.connected;

    return Column(
      children: [
        // Host Group Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (controller.isScanning || groupFormed)
                ? null
                : () async {
                    try {
                      await controller.createGroup();
                    } catch (e) {
                      debugPrint('❌ Error creating group: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(
                                  Icons.error,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Failed to create group: ${e.toString().contains('Permission') ? 'Check permissions' : 'Try again'}',
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                            action: SnackBarAction(
                              label: 'RETRY',
                              textColor: Colors.white,
                              onPressed: () async {
                                await controller.p2pService
                                    .checkAndRequestPermissions();
                              },
                            ),
                          ),
                        );
                      }
                    }
                  },
            icon: isHost && groupFormed
                ? Icon(
                    Icons.check_circle,
                    size: ResponsiveUtils.isMobile(context) ? 18 : 20,
                  )
                : Icon(
                    Icons.group_add,
                    size: ResponsiveUtils.isMobile(context) ? 18 : 20,
                  ),
            label: Text(
              isHost && groupFormed
                  ? (isWiFiDirectActive
                        ? 'Group Active (${controller.p2pService.connectedDevices.length} connected)'
                        : 'Waiting for peers...')
                  : 'Create WiFi Direct Group',
              style: TextStyle(
                fontSize: ResponsiveUtils.isMobile(context) ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isHost && groupFormed
                  ? ResQLinkTheme.safeGreen
                  : ResQLinkTheme.emergencyOrange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveUtils.isMobile(context) ? 20 : 24,
                vertical: ResponsiveUtils.isMobile(context) ? 12 : 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: (controller.isScanning || groupFormed) ? 0 : 2,
            ),
          ),
        ),
        SizedBox(height: ResponsiveSpacing.sm(context)),
        // Join Group Button (Scan & Connect) OR Cancel Scan Button
        if (controller.isScanning) ...[
          // Cancel Scan Button (while scanning)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                controller.stopScan();
              },
              icon: Icon(
                Icons.close,
                size: ResponsiveUtils.isMobile(context) ? 18 : 20,
              ),
              label: Text(
                'Cancel Scan',
                style: TextStyle(
                  fontSize: ResponsiveUtils.isMobile(context) ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveUtils.isMobile(context) ? 20 : 24,
                  vertical: ResponsiveUtils.isMobile(context) ? 12 : 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ] else ...[
          // Join Group Button (when not scanning)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: groupFormed
                  ? null
                  : () async {
                      try {
                        await controller.startScan();
                      } catch (e) {
                        debugPrint('❌ Error starting scan: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(
                                    Icons.error,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Failed to start scan: Check permissions',
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 3),
                              action: SnackBarAction(
                                label: 'RETRY',
                                textColor: Colors.white,
                                onPressed: () async {
                                  await controller.p2pService
                                      .checkAndRequestPermissions();
                                },
                              ),
                            ),
                          );
                        }
                      }
                    },
              icon: Icon(
                Icons.radar,
                size: ResponsiveUtils.isMobile(context) ? 18 : 20,
              ),
              label: Text(
                'Join WiFi Direct Group',
                style: TextStyle(
                  fontSize: ResponsiveUtils.isMobile(context) ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ResQLinkTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveUtils.isMobile(context) ? 20 : 24,
                  vertical: ResponsiveUtils.isMobile(context) ? 12 : 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: groupFormed ? 0 : 2,
              ),
            ),
          ),
        ],
        // Disconnect button (only show when group is formed)
        if (groupFormed) ...[
          SizedBox(height: ResponsiveSpacing.md(context)),
          Container(
            padding: EdgeInsets.all(
              ResponsiveUtils.isMobile(context) ? 12 : 16,
            ),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red.shade300,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isHost
                            ? 'Hosting a group. Leave to join another group instead.'
                            : 'Connected to a group. Leave to create or join a different one.',
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: ResponsiveUtils.isMobile(context) ? 12 : 13,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveSpacing.sm(context)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await controller.p2pService.wifiDirectService
                            ?.removeGroup();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    isHost
                                        ? 'Group disbanded'
                                        : 'Left group successfully',
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('❌ Error leaving group: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(
                                    Icons.error,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Failed to leave group'),
                                ],
                              ),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                    icon: Icon(
                      Icons.exit_to_app,
                      size: ResponsiveUtils.isMobile(context) ? 18 : 20,
                    ),
                    label: Text(
                      isHost ? 'Disband Group' : 'Leave Group',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.isMobile(context) ? 14 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.isMobile(context) ? 20 : 24,
                        vertical: ResponsiveUtils.isMobile(context) ? 12 : 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
