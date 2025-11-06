import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/gps_controller.dart';
import '../../utils/resqlink_theme.dart';

class GpsEmergencyButton extends StatefulWidget {
  const GpsEmergencyButton({super.key});

  @override
  State<GpsEmergencyButton> createState() => _GpsEmergencyButtonState();
}

class _GpsEmergencyButtonState extends State<GpsEmergencyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Offset _position = const Offset(16, 120); // Draggable position

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isNarrow = screenWidth < 400;

    return Consumer<GpsController>(
      builder: (context, controller, child) {
        if (controller.sosMode && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (!controller.sosMode && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }

        return Positioned(
          left: _position.dx,
          top: _position.dy,
          child: SafeArea(
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  final buttonSize = isNarrow ? 60.0 : 64.0;
                  final safeAreaPadding = MediaQuery.of(context).padding;

                  // Update position with accurate placement
                  final newX = (_position.dx + details.delta.dx).clamp(
                    safeAreaPadding.left,
                    screenWidth - buttonSize - safeAreaPadding.right,
                  );
                  final newY = (_position.dy + details.delta.dy).clamp(
                    safeAreaPadding.top,
                    screenHeight - buttonSize - safeAreaPadding.bottom,
                  );

                  _position = Offset(newX, newY);
                });
              },
              child: _buildButton(controller, isNarrow),
            ),
          ),
        );
      },
    );
  }

  Widget _buildButton(GpsController controller, bool isNarrow) {
    final buttonSize = isNarrow ? 60.0 : 64.0;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: controller.sosMode ? _pulseAnimation.value : 1.0,
          child: Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: controller.sosMode
                    ? [
                        ResQLinkTheme.primaryRed,
                        ResQLinkTheme.primaryRed.withValues(alpha: 0.7),
                      ]
                    : [
                        ResQLinkTheme.primaryRed.withValues(alpha: 0.9),
                        ResQLinkTheme.primaryRed.withValues(alpha: 0.7),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: ResQLinkTheme.primaryRed.withValues(alpha: 0.4),
                  blurRadius: controller.sosMode ? 16 : 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _handleEmergencyPress(controller),
                borderRadius: BorderRadius.circular(buttonSize / 2),
                child: Center(
                  child: Icon(
                    controller.sosMode
                        ? Icons.stop_rounded
                        : Icons.warning_rounded,
                    color: Colors.white,
                    size: isNarrow ? 28 : 32,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleEmergencyPress(GpsController controller) {
    if (controller.sosMode) {
      _showStopSOSDialog(controller);
    } else {
      _showStartSOSDialog(controller);
    }
  }

  void _showStartSOSDialog(GpsController controller) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ResQLinkTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ResQLinkTheme.primaryRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.warning_rounded,
                color: ResQLinkTheme.primaryRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Activate SOS',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          'This will continuously broadcast your location every 30 seconds to nearby devices and emergency services. Use only in actual emergencies.',
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.activateSOS();
              Navigator.pop(dialogContext);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.primaryRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'ACTIVATE SOS',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStopSOSDialog(GpsController controller) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ResQLinkTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ResQLinkTheme.safeGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: ResQLinkTheme.safeGreen,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Stop SOS',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you safe? This will stop emergency broadcasting.',
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Keep SOS Active',
              style: GoogleFonts.poppins(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.deactivateSOS();
              Navigator.pop(dialogContext);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.safeGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'I\'M SAFE',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
