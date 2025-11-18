import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:resqlink/utils/responsive_utils.dart';
import 'device_item.dart';

class DeviceList extends StatelessWidget {
  final HomeController controller;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const DeviceList({super.key, required this.controller, this.onDeviceChatTap});

  @override
  Widget build(BuildContext context) {
    // Get connected device IDs to filter them out from discovered devices
    final connectedDeviceIds = <String>{};
    final p2pService = controller.p2pService;

    // Add directly connected devices
    for (var id in p2pService.connectedDevices.keys) {
      connectedDeviceIds.add(id);
    }

    // Add mesh devices
    for (var id in p2pService.meshDevices.keys) {
      connectedDeviceIds.add(id);
    }

    // Filter devices with valid UUIDs AND exclude already connected devices
    final validDevices = controller.discoveredDevices.where((device) {
      final deviceId = device['deviceId'] ?? device['deviceAddress'];
      if (deviceId == null || deviceId.toString().isEmpty) {
        return false;
      }

      // Exclude if device is already connected/in mesh registry
      if (connectedDeviceIds.contains(deviceId.toString())) {
        return false;
      }

      return true;
    }).toList();

    return Container(
      padding: ResponsiveSpacing.padding(context, all: 16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: validDevices.isEmpty
          ? _buildEmptyStateContent(context)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, validDevices.length),
                SizedBox(height: ResponsiveSpacing.md(context)),
                _buildDevicesList(context, validDevices),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context, int deviceCount) {
    final iconSize = ResponsiveUtils.isMobile(context) ? 18.0 : 22.0;
    final iconPadding = ResponsiveSpacing.sm(context);

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(iconPadding),
          decoration: BoxDecoration(
            color: ResQLinkTheme.safeGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ResQLinkTheme.safeGreen.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.devices_outlined,
            color: ResQLinkTheme.safeGreen,
            size: iconSize,
          ),
        ),
        SizedBox(width: ResponsiveSpacing.sm(context)),
        Expanded(
          child: ResponsiveTextWidget(
            'Found $deviceCount device${deviceCount == 1 ? '' : 's'}',
            styleBuilder: (context) =>
                ResponsiveText.bodyLarge(context).copyWith(
                  color: ResQLinkTheme.safeGreen,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesList(
    BuildContext context,
    List<Map<String, dynamic>> validDevices,
  ) {
    if (ResponsiveUtils.isDesktop(context) && validDevices.length > 2) {
      return _buildDevicesGrid(context, validDevices);
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: validDevices.length,
      separatorBuilder: (context, index) =>
          SizedBox(height: ResponsiveSpacing.sm(context)),
      itemBuilder: (context, index) {
        final device = validDevices[index];
        return DeviceItem(
          device: device,
          controller: controller,
          onDeviceChatTap: onDeviceChatTap,
        );
      },
    );
  }

  Widget _buildDevicesGrid(
    BuildContext context,
    List<Map<String, dynamic>> validDevices,
  ) {
    final crossAxisCount = ResponsiveUtils.isDesktop(context) ? 2 : 1;
    final spacing = ResponsiveSpacing.md(context);

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: ResponsiveHelper.isDesktop(context) ? 2.5 : 3.0,
      ),
      itemCount: validDevices.length,
      itemBuilder: (context, index) {
        final device = validDevices[index];
        return DeviceItem(
          device: device,
          controller: controller,
          onDeviceChatTap: onDeviceChatTap,
        );
      },
    );
  }

  Widget _buildEmptyStateContent(BuildContext context) {
    return Center(
      child: Container(
        padding: ResponsiveSpacing.padding(
          context,
          horizontal: 32,
          vertical: 48,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_outlined,
              size: ResponsiveUtils.isMobile(context) ? 64 : 80,
              color: ResQLinkTheme.offlineGray,
            ),
            SizedBox(height: ResponsiveSpacing.lg(context)),
            ResponsiveTextWidget(
              'No Devices Found',
              styleBuilder: (context) =>
                  ResponsiveText.heading3(context).copyWith(
                    color: ResQLinkTheme.offlineGray,
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveSpacing.sm(context)),
            ResponsiveTextWidget(
              controller.isScanning
                  ? 'Searching for WiFi Direct groups...'
                  : 'Tap "Join WiFi Direct Group" to discover nearby groups',
              styleBuilder: (context) =>
                  ResponsiveText.bodyMedium(context).copyWith(
                    color: ResQLinkTheme.offlineGray.withValues(alpha: 0.8),
                  ),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
            if (controller.isScanning) ...[
              SizedBox(height: ResponsiveSpacing.lg(context)),
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: ResQLinkTheme.primaryBlue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
