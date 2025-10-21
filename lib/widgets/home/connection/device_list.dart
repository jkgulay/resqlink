import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'package:resqlink/utils/responsive_utils.dart';
import 'device_item.dart';

class DeviceList extends StatelessWidget {
  final HomeController controller;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const DeviceList({
    super.key,
    required this.controller,
    this.onDeviceChatTap,
  });

  @override
  Widget build(BuildContext context) {
    // Filter devices with valid UUIDs
    final validDevices = controller.discoveredDevices.where((device) {
      final deviceId = device['deviceId'] ?? device['deviceAddress'];
      return deviceId != null && deviceId.toString().isNotEmpty;
    }).toList();

    // Show empty state if no valid devices
    if (validDevices.isEmpty) {
      return _buildEmptyState(context);
    }

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
      child: Column(
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
            styleBuilder: (context) => ResponsiveText.bodyLarge(context).copyWith(
              color: ResQLinkTheme.safeGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesList(BuildContext context, List<Map<String, dynamic>> validDevices) {
    if (ResponsiveUtils.isDesktop(context) && validDevices.length > 2) {
      return _buildDevicesGrid(context, validDevices);
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: validDevices.length,
      separatorBuilder: (context, index) => SizedBox(height: ResponsiveSpacing.sm(context)),
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

  Widget _buildDevicesGrid(BuildContext context, List<Map<String, dynamic>> validDevices) {
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

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: ResponsiveSpacing.padding(
        context,
        horizontal: 32,
        vertical: 48,
      ),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ResQLinkTheme.offlineGray.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.devices_outlined,
            size: ResponsiveUtils.isMobile(context) ? 64 : 80,
            color: ResQLinkTheme.offlineGray,
          ),
          SizedBox(height: ResponsiveSpacing.lg(context)),
          ResponsiveTextWidget(
            'No Devices Found',
            styleBuilder: (context) => ResponsiveText.heading3(context).copyWith(
              color: ResQLinkTheme.offlineGray,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveSpacing.sm(context)),
          ResponsiveTextWidget(
            controller.isScanning
                ? 'Searching for nearby WiFi Direct devices...'
                : 'Tap "Scan for Devices" to discover nearby WiFi Direct devices',
            styleBuilder: (context) => ResponsiveText.bodyMedium(context).copyWith(
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
    );
  }
}