import 'package:flutter/material.dart';
import 'package:resqlink/controllers/home_controller.dart';
import 'package:resqlink/utils/responsive_helper.dart';
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
    final listPadding = ResponsiveHelper.getItemPadding(context);
    final iconPadding = ResponsiveHelper.isDesktop(context) ? 12.0 : 
                      ResponsiveHelper.isTablet(context) ? 11.0 : 10.0;

    return Container(
      padding: EdgeInsets.all(listPadding),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F).withValues(alpha: 0.2)),
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
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Icon(Icons.devices, color: Colors.green, size: iconSize),
        ),
        SizedBox(width: spacing),
        Expanded(
          child: Text(
            'Found ${controller.discoveredDevices.length} device${controller.discoveredDevices.length == 1 ? '' : 's'}',
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
    if (ResponsiveHelper.isDesktop(context) && controller.discoveredDevices.length > 2) {
      return _buildDevicesGrid(context);
    }

    final itemSpacing = ResponsiveHelper.getContentSpacing(context) * 0.5;

    return ListView.separated(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: controller.discoveredDevices.length,
      separatorBuilder: (context, index) => SizedBox(height: itemSpacing),
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
    final crossAxisCount = ResponsiveHelper.isDesktop(context) ? 2 : 1;
    final spacing = ResponsiveHelper.getContentSpacing(context) * 0.75;

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