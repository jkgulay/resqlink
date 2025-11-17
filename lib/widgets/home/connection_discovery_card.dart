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
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: _buildCardDecoration(),
        child: Padding(
          padding: ResponsiveSpacing.padding(context, all: isCompact ? 20 : 24),
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
                ConnectedDevices(
                  controller: controller,
                  onDeviceChatTap: onDeviceChatTap,
                ),
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
