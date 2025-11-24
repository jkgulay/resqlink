import 'package:flutter/material.dart';
import 'package:resqlink/utils/offline_fonts.dart';
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
        final isNarrow = screenWidth < 400;
        final emergencyColor = _getEmergencyColor(
          controller.currentEmergencyLevel,
        );

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
                padding: EdgeInsets.all(isNarrow ? 14 : 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ResQLinkTheme.cardDark.withValues(alpha: 0.95),
                      ResQLinkTheme.cardDark.withValues(alpha: 0.90),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: emergencyColor.withValues(alpha: 0.6),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: emergencyColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Always visible header
                    _buildCompactHeader(controller, isNarrow, emergencyColor),

                    // Expandable content
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      child: Column(
                        children: [
                          SizedBox(height: isNarrow ? 14 : 18),
                          _buildStatsGrid(controller, isNarrow),
                          if (controller.sosMode) ...[
                            SizedBox(height: isNarrow ? 14 : 18),
                            _buildSOSPanel(controller, isNarrow),
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

  Widget _buildCompactHeader(
    GpsController controller,
    bool isNarrow,
    Color emergencyColor,
  ) {
    return Row(
      children: [
        // Status indicator with gradient
        Container(
          padding: EdgeInsets.all(isNarrow ? 8 : 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                emergencyColor.withValues(alpha: 0.3),
                emergencyColor.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: emergencyColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: emergencyColor.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            _getEmergencyIcon(controller.currentEmergencyLevel),
            color: emergencyColor,
            size: isNarrow ? 18 : 20,
          ),
        ),
        const SizedBox(width: 12),

        // Compact info
        Expanded(
          child: Row(
            children: [
              // GPS Status
              _buildQuickStat(
                controller.isLocationServiceEnabled
                    ? Icons.gps_fixed_rounded
                    : Icons.gps_off_rounded,
                '${controller.savedLocations.length}',
                controller.isLocationServiceEnabled
                    ? ResQLinkTheme.safeGreen
                    : ResQLinkTheme.primaryRed,
                isNarrow,
              ),
              SizedBox(width: isNarrow ? 10 : 12),

              // Battery
              _buildQuickStat(
                _getBatteryIcon(controller.batteryLevel),
                '${controller.batteryLevel}%',
                _getBatteryColor(controller.batteryLevel),
                isNarrow,
              ),
              SizedBox(width: isNarrow ? 10 : 12),

              // Network
              _buildQuickStat(
                controller.isConnected
                    ? Icons.wifi_rounded
                    : Icons.wifi_off_rounded,
                '',
                controller.isConnected
                    ? ResQLinkTheme.safeGreen
                    : ResQLinkTheme.orange,
                isNarrow,
              ),
            ],
          ),
        ),

        // SOS indicator
        if (controller.sosMode)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 10 : 12,
              vertical: isNarrow ? 5 : 6,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ResQLinkTheme.primaryRed,
                  ResQLinkTheme.primaryRed.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: ResQLinkTheme.primaryRed.withValues(alpha: 0.5),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'SOS',
              style: OfflineFonts.poppins(
                color: Colors.white,
                fontSize: isNarrow ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),

        SizedBox(width: isNarrow ? 10 : 12),

        // Expand/collapse icon
        AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withValues(alpha: 0.8),
              size: isNarrow ? 20 : 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStat(
    IconData icon,
    String text,
    Color color,
    bool isNarrow,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: isNarrow ? 16 : 18),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            text,
            style: OfflineFonts.poppins(
              color: color,
              fontSize: isNarrow ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsGrid(GpsController controller, bool isNarrow) {
    // Determine accuracy quality and color
    final accuracy = controller.lastKnownLocation?.accuracy;
    Color accuracyColor;
    String accuracyLabel;

    if (accuracy == null) {
      accuracyColor = Colors.grey;
      accuracyLabel = 'Unknown';
    } else if (accuracy < 5) {
      accuracyColor = Colors.green; // Excellent
      accuracyLabel = '±${accuracy.toStringAsFixed(1)}m';
    } else if (accuracy < 15) {
      accuracyColor = Colors.lightGreen; // Good
      accuracyLabel = '±${accuracy.toStringAsFixed(1)}m';
    } else if (accuracy < 30) {
      accuracyColor = Colors.orange; // Fair
      accuracyLabel = '±${accuracy.toStringAsFixed(1)}m';
    } else {
      accuracyColor = Colors.red; // Poor
      accuracyLabel = '±${accuracy.toStringAsFixed(0)}m';
    }

    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            'Accuracy',
            accuracyLabel,
            Icons.gps_fixed_rounded,
            accuracyColor,
            isNarrow,
          ),
        ),
        SizedBox(width: isNarrow ? 10 : 12),
        Expanded(
          child: _buildStatItem(
            'Emergency',
            _getEmergencyLevelText(controller.currentEmergencyLevel),
            _getEmergencyIcon(controller.currentEmergencyLevel),
            _getEmergencyColor(controller.currentEmergencyLevel),
            isNarrow,
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
    bool isNarrow,
  ) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: isNarrow ? 20 : 22),
          SizedBox(height: isNarrow ? 6 : 8),
          Text(
            value,
            style: OfflineFonts.poppins(
              color: color,
              fontSize: isNarrow ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: OfflineFonts.poppins(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: isNarrow ? 10 : 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSOSPanel(GpsController controller, bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
            ResQLinkTheme.primaryRed.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ResQLinkTheme.primaryRed.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ResQLinkTheme.primaryRed.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ResQLinkTheme.primaryRed.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.warning_rounded,
              color: ResQLinkTheme.primaryRed,
              size: isNarrow ? 18 : 20,
            ),
          ),
          SizedBox(width: isNarrow ? 10 : 12),
          Expanded(
            child: Text(
              'EMERGENCY MODE ACTIVE',
              style: OfflineFonts.poppins(
                color: Colors.white,
                fontSize: isNarrow ? 12 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: isNarrow ? 8 : 10),
          ElevatedButton(
            onPressed: () => controller.deactivateSOS(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
              minimumSize: Size(isNarrow ? 50 : 60, isNarrow ? 32 : 36),
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Text(
              'STOP',
              style: OfflineFonts.poppins(
                color: Colors.white,
                fontSize: isNarrow ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
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
        return ResQLinkTheme.warningYellow;
      case EmergencyLevel.warning:
        return ResQLinkTheme.orange;
      case EmergencyLevel.danger:
        return ResQLinkTheme.emergencyOrange;
      case EmergencyLevel.critical:
        return ResQLinkTheme.primaryRed;
    }
  }

  IconData _getEmergencyIcon(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe:
        return Icons.check_circle_rounded;
      case EmergencyLevel.caution:
        return Icons.info_rounded;
      case EmergencyLevel.warning:
        return Icons.warning_amber_rounded;
      case EmergencyLevel.danger:
        return Icons.warning_rounded;
      case EmergencyLevel.critical:
        return Icons.emergency_rounded;
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
    if (level > 50) return ResQLinkTheme.safeGreen;
    if (level > 20) return ResQLinkTheme.orange;
    return ResQLinkTheme.primaryRed;
  }

  IconData _getBatteryIcon(int level) {
    if (level > 90) return Icons.battery_full_rounded;
    if (level > 70) return Icons.battery_6_bar_rounded;
    if (level > 50) return Icons.battery_5_bar_rounded;
    if (level > 30) return Icons.battery_3_bar_rounded;
    if (level > 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }
}
