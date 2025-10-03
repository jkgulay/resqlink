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
          _buildHeader(context),
          SizedBox(height: ResponsiveSpacing.md(context)),
          _buildDevicesList(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            'Found ${controller.discoveredDevices.length} device${controller.discoveredDevices.length == 1 ? '' : 's'}',
            styleBuilder: (context) => ResponsiveText.bodyLarge(context).copyWith(
              color: ResQLinkTheme.safeGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesList(BuildContext context) {
    if (ResponsiveUtils.isDesktop(context) && controller.discoveredDevices.length > 2) {
      return _buildDevicesGrid(context);
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: controller.discoveredDevices.length,
      separatorBuilder: (context, index) => SizedBox(height: ResponsiveSpacing.sm(context)),
      itemBuilder: (context, index) {
        final device = controller.discoveredDevices[index];
        return DeviceItem(
          device: device,
          controller: controller,
          onDeviceChatTap: onDeviceChatTap,
        );
      },
    );
  }

  Widget _buildDevicesGrid(BuildContext context) {
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
      itemCount: controller.discoveredDevices.length,
      itemBuilder: (context, index) {
        final device = controller.discoveredDevices[index];
        return DeviceItem(
          device: device,
          controller: controller,
          onDeviceChatTap: onDeviceChatTap,
        );
      },
    );
  }
}