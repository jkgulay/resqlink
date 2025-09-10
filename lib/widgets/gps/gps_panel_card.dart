import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/gps_controller.dart';
import '../../gps_page.dart';
import '../../utils/resqlink_theme.dart';

class GpsStatsPanel extends StatelessWidget {
  const GpsStatsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GpsController>(
      builder: (context, controller, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isSmallScreen = screenWidth < 600;

        return Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth - 32),
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              decoration: BoxDecoration(
                color: ResQLinkTheme.cardDark.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _getEmergencyColor(
                    controller.currentEmergencyLevel,
                  ).withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow(controller, isSmallScreen),
                  SizedBox(height: isSmallScreen ? 12 : 16),
                  _buildStatsGrid(controller, isSmallScreen),
                  if (controller.sosMode) ...[
                    SizedBox(height: isSmallScreen ? 12 : 16),
                    _buildSOSPanel(controller, isSmallScreen),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(GpsController controller, bool isSmallScreen) {
    final emergencyColor = _getEmergencyColor(controller.currentEmergencyLevel);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: emergencyColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: emergencyColor, width: 2),
          ),
          child: Icon(
            _getEmergencyIcon(controller.currentEmergencyLevel),
            color: emergencyColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GPS Status',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getEmergencyLevelText(controller.currentEmergencyLevel),
                style: TextStyle(
                  color: emergencyColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (controller.sosMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ResQLinkTheme.primaryRed,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'SOS ACTIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsGrid(GpsController controller, bool isSmallScreen) {
    if (isSmallScreen) {
      // Stack stats vertically on small screens
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Accuracy',
                  controller.lastKnownLocation?.accuracy != null
                      ? '±${controller.lastKnownLocation!.accuracy!.toStringAsFixed(1)}m'
                      : 'Unknown',
                  Icons.gps_fixed,
                  controller.isLocationServiceEnabled
                      ? Colors.green
                      : Colors.red,
                  isSmallScreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  'Battery',
                  '${controller.batteryLevel}%',
                  Icons.battery_std,
                  _getBatteryColor(controller.batteryLevel),
                  isSmallScreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Saved',
                  '${controller.savedLocations.length}',
                  Icons.bookmark,
                  Colors.blue,
                  isSmallScreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  'Network',
                  controller.isConnected ? 'Online' : 'Offline',
                  controller.isConnected ? Icons.wifi : Icons.wifi_off,
                  controller.isConnected ? Colors.green : Colors.orange,
                  isSmallScreen,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // Horizontal layout for larger screens
      return Row(
        children: [
          Expanded(
            child: _buildStatItem(
              'Accuracy',
              controller.lastKnownLocation?.accuracy != null
                  ? '±${controller.lastKnownLocation!.accuracy!.toStringAsFixed(1)}m'
                  : 'Unknown',
              Icons.gps_fixed,
              controller.isLocationServiceEnabled ? Colors.green : Colors.red,
              isSmallScreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatItem(
              'Battery',
              '${controller.batteryLevel}%',
              Icons.battery_std,
              _getBatteryColor(controller.batteryLevel),
              isSmallScreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatItem(
              'Saved',
              '${controller.savedLocations.length}',
              Icons.bookmark,
              Colors.blue,
              isSmallScreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatItem(
              'Network',
              controller.isConnected ? 'Online' : 'Offline',
              controller.isConnected ? Icons.wifi : Icons.wifi_off,
              controller.isConnected ? Colors.green : Colors.orange,
              isSmallScreen,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isSmallScreen,
  ) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: isSmallScreen ? 16 : 20),
          SizedBox(height: isSmallScreen ? 4 : 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: isSmallScreen ? 12 : 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: isSmallScreen ? 8 : 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSOSPanel(GpsController controller, bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.primaryRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ResQLinkTheme.primaryRed, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ResQLinkTheme.primaryRed,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warning, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EMERGENCY MODE ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Broadcasting location every 30 seconds',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => controller.deactivateSOS(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'STOP',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEmergencyColor(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe:
        return ResQLinkTheme.safeGreen;
      case EmergencyLevel.caution:
        return Colors.yellow;
      case EmergencyLevel.warning:
        return Colors.orange;
      case EmergencyLevel.danger:
        return ResQLinkTheme.emergencyOrange;
      case EmergencyLevel.critical:
        return ResQLinkTheme.primaryRed;
    }
  }

  IconData _getEmergencyIcon(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe:
        return Icons.check_circle;
      case EmergencyLevel.caution:
        return Icons.info;
      case EmergencyLevel.warning:
        return Icons.warning_amber;
      case EmergencyLevel.danger:
        return Icons.warning;
      case EmergencyLevel.critical:
        return Icons.emergency;
    }
  }

  String _getEmergencyLevelText(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe:
        return 'All Clear';
      case EmergencyLevel.caution:
        return 'Stay Alert';
      case EmergencyLevel.warning:
        return 'Warning Level';
      case EmergencyLevel.danger:
        return 'Danger Zone';
      case EmergencyLevel.critical:
        return 'CRITICAL EMERGENCY';
    }
  }

  Color _getBatteryColor(int level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }
}
