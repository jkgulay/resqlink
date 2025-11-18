import 'package:flutter/material.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'package:resqlink/widgets/home/connection/device_badges.dart';


class DeviceInfo extends StatelessWidget {
  final Map<String, dynamic> device;
  final bool isConnected;
  final VoidCallback? onChatTap;

  const DeviceInfo({
    super.key,
    required this.device,
    required this.isConnected,
    this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatarRadius = ResponsiveHelper.isDesktop(context) ? 28.0 : 
                        ResponsiveHelper.isTablet(context) ? 26.0 : 24.0;
    final spacing = ResponsiveHelper.getContentSpacing(context) * 0.75;

    return Row(
      children: [
        _buildDeviceAvatar(context, avatarRadius),
        SizedBox(width: spacing),
        Expanded(child: _buildDeviceDetails(context)),
      ],
    );
  }

  Widget _buildDeviceAvatar(BuildContext context, double avatarRadius) {
    final signalStrength = DeviceBadges.parseSignalStrength(device);
    final signalLevel = DeviceBadges.getSignalLevel(signalStrength);
    final signalColor = DeviceBadges.getSignalColor(signalLevel);
    final connectionType = device['connectionType'] as String? ?? 'unknown';

    return CircleAvatar(
      backgroundColor: signalColor.withValues(alpha: 0.2),
      radius: avatarRadius,
      child: Icon(
        DeviceBadges.getConnectionTypeIcon(connectionType),
        color: signalColor,
        size: ResponsiveHelper.getIconSize(context, narrow: 22.0),
      ),
    );
  }

  Widget _buildDeviceDetails(BuildContext context) {
    final nameSize = ResponsiveHelper.getTitleSize(context, narrow: 15.0);
    final addressSize = ResponsiveHelper.getSubtitleSize(context, narrow: 11.0);
    final deviceStatus = device['status'] as String? ?? 'unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: isConnected ? onChatTap : null,
                child: FutureBuilder<String>(
                  future: _getDisplayName(),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data ?? device['deviceName'] ?? 'Unknown Device',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: nameSize,
                        color: isConnected ? Colors.green : Colors.white,
                        decoration: isConnected ? TextDecoration.underline : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            ),
            DeviceBadges.buildConnectionStatusBadge(isConnected, deviceStatus),
          ],
        ),
        SizedBox(height: 4),
        Text(
          device['deviceAddress'] ?? '',
          style: TextStyle(
            fontSize: addressSize,
            color: Colors.grey.shade600,
            fontFamily: 'monospace',
          ),
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 6),
        Row(
          children: [
            DeviceBadges.buildConnectionTypeBadge(
              device['connectionType'] as String? ?? 'unknown',
            ),
            SizedBox(width: 8),
            DeviceBadges.buildSignalBadge(device),
          ],
        ),
      ],
    );
  }

  Future<String> _getDisplayName() async {
   return device['deviceName'] ?? 'Unknown Device';
  }
}