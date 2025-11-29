import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/models/device_model.dart';
import 'package:resqlink/services/p2p/p2p_base_service.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'package:resqlink/features/database/repositories/chat_repository.dart';

class ConnectedDevices extends StatelessWidget {
  final HomeController controller;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const ConnectedDevices({
    super.key,
    required this.controller,
    this.onDeviceChatTap,
  });

  @override
  Widget build(BuildContext context) {
    final containerPadding = ResponsiveHelper.getItemPadding(
      context,
      narrow: 16.0,
    );
    final iconPadding = ResponsiveHelper.isDesktop(context)
        ? 12.0
        : ResponsiveHelper.isTablet(context)
        ? 11.0
        : 10.0;

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

    final p2pService = controller.p2pService;
    final isGroupOwner =
        p2pService.currentRole == P2PRole.host ||
        (p2pService.wifiDirectService?.isGroupOwner ?? false);
    final myDeviceId = p2pService.deviceId;

    final Map<String, DeviceModel> devicesMap = {};

    void addDevice(DeviceModel device, {bool markAsHost = false}) {
      final deviceKey = device.deviceId;
      if (deviceKey.isEmpty || deviceKey == myDeviceId) {
        return;
      }

      final existing = devicesMap[deviceKey];
      final shouldOverrideExisting =
          existing == null ||
          (existing.discoveryMethod == 'mesh' &&
              device.discoveryMethod != 'mesh');

      if (shouldOverrideExisting) {
        devicesMap[deviceKey] = markAsHost
            ? device.copyWith(isHost: true)
            : device;
      } else if (markAsHost && !existing.isHost) {
        devicesMap[deviceKey] = existing.copyWith(isHost: true);
      }
    }

    final connectedDevices = p2pService.connectedDevices.values.toList();

    if (isGroupOwner) {
      for (final device in connectedDevices) {
        addDevice(device.copyWith(isHost: false));
      }
    } else {
      if (connectedDevices.isNotEmpty) {
        // First direct connection is the group owner when we're a client
        addDevice(
          connectedDevices.first.copyWith(isHost: true),
          markAsHost: true,
        );
        for (final device in connectedDevices.skip(1)) {
          addDevice(device.copyWith(isHost: false));
        }
      }
    }

    // Include mesh-discovered devices so clients can see the full group
    p2pService.meshDevices.values.forEach(addDevice);

    final devicesToShow = devicesMap.values.toList()
      ..sort(
        (a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()),
      );

    if (devicesToShow.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No connected devices yet',
          style: TextStyle(color: Colors.white70, fontSize: deviceNameSize),
        ),
      );
    }

    return Column(
      children: devicesToShow
          .map(
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
                      future: _getDeviceDisplayName(device),
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
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.4),
                      ),
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
                  SizedBox(width: spacing),
                  IconButton(
                    icon: Icon(
                      Icons.chat_bubble,
                      color: Color(0xFFFF6500),
                      size: deviceIconSize + 2,
                    ),
                    onPressed: () {
                      if (onDeviceChatTap != null) {
                        // CRITICAL: Get fresh device name before navigation
                        _getDeviceDisplayName(device).then((freshName) {
                          final deviceMap = {
                            'deviceId': device.deviceId,
                            'deviceName': freshName,
                            'isHost': device.isHost,
                          };
                          onDeviceChatTap!(deviceMap);
                        });
                      }
                    },
                    padding: EdgeInsets.all(8),
                    constraints: BoxConstraints(),
                    tooltip: 'Chat',
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  /// Get fresh device display name from various sources for consistency
  /// Priority: Connected Devices > Discovered Devices > Chat Session DB
  Future<String> _getDeviceDisplayName(DeviceModel device) async {
    // 1. Prioritize live connection name
    if (controller.p2pService.connectedDevices.containsKey(device.deviceId)) {
      final connectedDevice =
          controller.p2pService.connectedDevices[device.deviceId]!;
      if (connectedDevice.userName.isNotEmpty) {
        return connectedDevice.userName;
      }
    }

    // 2. Check discovered devices list
    try {
      final discovered =
          controller.p2pService.discoveredResQLinkDevices.firstWhere(
        (d) => d.deviceId == device.deviceId,
      );
      if (discovered.userName.isNotEmpty) {
        return discovered.userName;
      }
    } catch (e) {
      // Device not in discovered list, proceed to database
    }

    // 3. Fallback to database session
    try {
      final session = await ChatRepository.getSessionByDeviceId(
        device.deviceId,
      );
      if (session != null && session.deviceName.isNotEmpty) {
        return session.deviceName;
      }
    } catch (e) {
      // Fallback to the original device name if DB lookup fails
    }

    // 4. Last resort, the name from the initial device model
    return device.userName;
  }
}
