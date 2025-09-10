import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    return Consumer<GpsController>(
      builder: (context, controller, child) {
        if (controller.sosMode && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (!controller.sosMode && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }

        return Positioned(
          left: 16,
          top: 120, // Below stats panel, opposite side of action buttons
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: controller.sosMode ? _pulseAnimation.value : 1.0,
                  child: FloatingActionButton(
                    onPressed: () => _handleEmergencyPress(controller),
                    backgroundColor: controller.sosMode
                        ? ResQLinkTheme.primaryRed
                        : ResQLinkTheme.primaryRed.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                    elevation: 8,
                    child: Icon(
                      controller.sosMode ? Icons.stop : Icons.warning,
                      size: 28,
                    ),
                  ),
                );
              },
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
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Activate SOS',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'This will continuously broadcast your location every 30 seconds to nearby devices and emergency services. Use only in actual emergencies.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.activateSOS();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.primaryRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('ACTIVATE SOS'),
          ),
        ],
      ),
    );
  }

  void _showStopSOSDialog(GpsController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Stop SOS',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'Are you safe? This will stop emergency broadcasting.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep SOS Active'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.deactivateSOS();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('I\'M SAFE'),
          ),
        ],
      ),
    );
  }
}
