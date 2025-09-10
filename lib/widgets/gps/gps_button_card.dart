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
  late AnimationController _sosAnimationController;
  late Animation<double> _sosAnimation;

  @override
  void initState() {
    super.initState();
    _sosAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _sosAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _sosAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _sosAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GpsController>(
      builder: (context, controller, child) {
        // Control animation based on SOS mode
        if (controller.sosMode && !_sosAnimationController.isAnimating) {
          _sosAnimationController.repeat(reverse: true);
        } else if (!controller.sosMode && _sosAnimationController.isAnimating) {
          _sosAnimationController.stop();
          _sosAnimationController.reset();
        }

        return Positioned(
          bottom: 100,
          right: 20,
          child: GestureDetector(
            onLongPress: () {
              if (!controller.sosMode) {
                controller.activateSOS();
                _showSOSActivatedMessage(context);
              } else {
                controller.deactivateSOS();
                _showSOSDeactivatedMessage(context);
              }
            },
            child: AnimatedBuilder(
              animation: controller.sosMode ? _sosAnimation : const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return Transform.scale(
                  scale: controller.sosMode ? _sosAnimation.value : 1.0,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: controller.sosMode
                          ? ResQLinkTheme.primaryRed
                          : ResQLinkTheme.darkRed,
                      boxShadow: [
                        BoxShadow(
                          color: (controller.sosMode
                                  ? ResQLinkTheme.primaryRed
                                  : ResQLinkTheme.darkRed)
                              .withValues(alpha: 0.6),
                          blurRadius: 20,
                          spreadRadius: controller.sosMode ? 5 : 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.emergency,
                          color: Colors.white,
                          size: controller.sosMode ? 40 : 35,
                        ),
                        Text(
                          controller.sosMode ? 'ACTIVE' : 'SOS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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

  void _showSOSActivatedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'SOS ACTIVATED! Broadcasting location...',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: ResQLinkTheme.primaryRed,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSOSDeactivatedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('SOS deactivated'),
        backgroundColor: ResQLinkTheme.safeGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}