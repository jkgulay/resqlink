import 'package:flutter/material.dart';
import '../../controllers/home_controller.dart';
import 'connection/connection_header.dart';
import 'connection/connection_stats.dart';
import 'connection/device_list.dart';
import 'connection/connected_devices.dart';
import '../../utils/resqlink_theme.dart';

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
    return ResponsiveWidget(
      mobile: _buildMobileLayout(context),
      tablet: _buildTabletLayout(context),
      desktop: _buildDesktopLayout(context),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return _buildCard(context, isCompact: true);
  }

  Widget _buildTabletLayout(BuildContext context) {
    return _buildCard(context, isCompact: false);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return _buildCard(context, isCompact: false);
  }

  Widget _buildCard(BuildContext context, {required bool isCompact}) {
    return Card(
      elevation: 12,
      margin: ResponsiveSpacing.padding(
        context,
        horizontal: isCompact ? 16 : 24,
        vertical: isCompact ? 8 : 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        decoration: _buildCardDecoration(),
        child: Padding(
          padding: ResponsiveSpacing.padding(
            context,
            all: isCompact ? 20 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionHeader(controller: controller),
              SizedBox(height: ResponsiveSpacing.lg(context)),
              ConnectionStats(controller: controller),
              SizedBox(height: ResponsiveSpacing.xl(context)),
              DeviceList(
                controller: controller,
                onDeviceChatTap: onDeviceChatTap,
              ),
              if (controller.isConnected) ...[
                SizedBox(height: ResponsiveSpacing.lg(context)),
                ConnectedDevices(controller: controller),
              ],
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        colors: [
          ResQLinkTheme.surfaceDark.withValues(alpha: 0.8),
          ResQLinkTheme.cardDark.withValues(alpha: 0.9),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.3),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: ResQLinkTheme.primaryBlue.withValues(alpha: 0.1),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
}