import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/gps_controller.dart';
import '../../pages/gps_page.dart';
import '../../utils/resqlink_theme.dart';

class GpsStatsPanel extends StatefulWidget {
  const GpsStatsPanel({super.key});

  @override
  State<GpsStatsPanel> createState() => _GpsStatsPanelState();
}

class _GpsStatsPanelState extends State<GpsStatsPanel>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

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
            child: GestureDetector(
              onTap: _toggleExpansion,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
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
                    // Always visible header
                    _buildCompactHeader(controller, isSmallScreen),

                    // Expandable content
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      child: Column(
                        children: [
                          SizedBox(height: isSmallScreen ? 12 : 16),
                          _buildStatsGrid(controller, isSmallScreen),
                          if (controller.sosMode) ...[
                            SizedBox(height: isSmallScreen ? 12 : 16),
                            _buildSOSPanel(controller, isSmallScreen),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactHeader(GpsController controller, bool isSmallScreen) {
    final emergencyColor = _getEmergencyColor(controller.currentEmergencyLevel);

    return Row(
      children: [
        // Status indicator
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: emergencyColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: emergencyColor, width: 1.5),
          ),
          child: Icon(
            _getEmergencyIcon(controller.currentEmergencyLevel),
            color: emergencyColor,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),

        // Compact info
        Expanded(
          child: Row(
            children: [
              // GPS Status
              Icon(
                controller.isLocationServiceEnabled
                    ? Icons.gps_fixed
                    : Icons.gps_off,
                color: controller.isLocationServiceEnabled
                    ? Colors.green
                    : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${controller.savedLocations.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),

              // Battery
              Icon(
                Icons.battery_std,
                color: _getBatteryColor(controller.batteryLevel),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${controller.batteryLevel}%',
                style: TextStyle(
                  color: _getBatteryColor(controller.batteryLevel),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),

              // Network
              Icon(
                controller.isConnected ? Icons.wifi : Icons.wifi_off,
                color: controller.isConnected ? Colors.green : Colors.orange,
                size: 16,
              ),
            ],
          ),
        ),

        // SOS indicator
        if (controller.sosMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ResQLinkTheme.primaryRed,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        const SizedBox(width: 8),

        // Expand/collapse icon
        AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white.withValues(alpha: 0.7),
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(GpsController controller, bool isSmallScreen) {
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
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatItem(
            'Emergency',
            _getEmergencyLevelText(controller.currentEmergencyLevel),
            _getEmergencyIcon(controller.currentEmergencyLevel),
            _getEmergencyColor(controller.currentEmergencyLevel),
            isSmallScreen,
          ),
        ),
      ],
    );
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSOSPanel(GpsController controller, bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ResQLinkTheme.primaryRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ResQLinkTheme.primaryRed, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'EMERGENCY MODE ACTIVE',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => controller.deactivateSOS(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              minimumSize: const Size(40, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              'STOP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
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
