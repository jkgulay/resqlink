import 'package:flutter/material.dart';
import '../../controllers/home_controller.dart';
import 'connection/connection_header.dart';
import 'connection/connection_stats.dart';
import 'connection/device_list.dart';
import 'connection/connected_devices.dart';
import '../../utils/responsive_helper.dart';

class ConnectionDiscoveryCard extends StatelessWidget {
  final HomeController controller;
  final Function(Map<String, dynamic>)? onDeviceChatTap;

  const ConnectionDiscoveryCard({
    super.key,
    required this.controller,
    this.onDeviceChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Card(
          elevation: 8,
          margin: ResponsiveHelper.getCardMargins(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: ResponsiveHelper.getCardConstraints(context),
            decoration: _buildCardDecoration(),
            child: Padding(
              padding: ResponsiveHelper.getCardPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConnectionHeader(controller: controller),
                  SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
                  ConnectionStats(controller: controller),
                  if (controller.discoveredDevices.isNotEmpty) ...[
                    SizedBox(height: ResponsiveHelper.getSectionSpacing(context)),
                    DeviceList(
                      controller: controller,
                      onDeviceChatTap: onDeviceChatTap,
                    ),
                  ],
                  if (controller.isConnected) ...[
                    SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
                    ConnectedDevices(controller: controller),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        colors: [
          Color(0xFF0B192C).withValues(alpha: 0.08),
          Color(0xFF1E3A5F).withValues(alpha: 0.05),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
        width: 1,
      ),
    );
  }
}