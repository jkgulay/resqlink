import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';

class ConnectedDevices extends StatelessWidget {
  final HomeController controller;

  const ConnectedDevices({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final containerPadding = ResponsiveHelper.getItemPadding(context, narrow: 16.0);
    final iconPadding = ResponsiveHelper.isDesktop(context) ? 12.0 : 
                      ResponsiveHelper.isTablet(context) ? 11.0 : 10.0;

    return Container(
      padding: EdgeInsets.all(containerPadding),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, iconPadding),
          SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
          _buildDevicesList(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double iconPadding) {
    final iconSize = ResponsiveHelper.getIconSize(context, narrow: 18.0);
    final titleSize = ResponsiveHelper.getTitleSize(context, narrow: 15.0);
    final spacing = ResponsiveHelper.getContentSpacing(context);

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(iconPadding),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.check_circle, color: Colors.green, size: iconSize),
        ),
        SizedBox(width: spacing),
        Expanded(
          child: Text(
            'Connected Devices',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w600,
              fontSize: titleSize,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesList(BuildContext context) {
    final deviceIconSize = ResponsiveHelper.getIconSize(context, narrow: 16.0);
    final deviceNameSize = ResponsiveHelper.getTitleSize(context, narrow: 14.0);
    final badgeSize = ResponsiveHelper.getSubtitleSize(context, narrow: 10.0);
    final spacing = ResponsiveHelper.getContentSpacing(context);

    return Column(
      children: controller.p2pService.connectedDevices.values.map(
        (device) => Padding(
          padding: EdgeInsets.symmetric(vertical: spacing * 0.25),
          child: Row(
            children: [
              Icon(
                Icons.wifi_tethering,
                size: deviceIconSize,
                color: Colors.green,
              ),
              SizedBox(width: spacing),
              Expanded(
                child: FutureBuilder<String>(
                  future: _getDisplayName(device),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data ?? device.userName,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: deviceNameSize,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.isDesktop(context) ? 12 : 10,
                  vertical: ResponsiveHelper.isDesktop(context) ? 8 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Text(
                  device.isHost ? 'HOST' : 'CLIENT',
                  style: TextStyle(
                    fontSize: badgeSize,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ).toList(),
    );
  }

  Future<String> _getDisplayName(dynamic device, [String? fallbackDeviceName]) async {
    // Return the device's name directly - this is for displaying OTHER connected devices
    return fallbackDeviceName ?? device.userName;
  }
}