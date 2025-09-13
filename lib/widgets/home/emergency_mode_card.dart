import 'package:flutter/material.dart';
import '../../services/p2p/p2p_main_service.dart';
import '../../utils/resqlink_theme.dart';

class EmergencyModeCard extends StatefulWidget {
  final P2PMainService p2pService;
  final VoidCallback onToggle;

  const EmergencyModeCard({
    super.key,
    required this.p2pService,
    required this.onToggle,
  });

  @override
  State<EmergencyModeCard> createState() => _EmergencyModeCardState();
}

class _EmergencyModeCardState extends State<EmergencyModeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.p2pService.emergencyMode) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EmergencyModeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.p2pService.emergencyMode && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.p2pService.emergencyMode && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: widget.p2pService.emergencyMode ? Colors.red.shade900 : null,
      elevation: 4,
      child: ResponsiveWidget(
        mobile: _buildMobileLayout(),
        tablet: _buildTabletLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Padding(
      padding: ResponsiveSpacing.padding(context, all: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: widget.p2pService.emergencyMode
                              ? _pulseAnimation.value
                              : 1.0,
                          child: Icon(
                            Icons.emergency,
                            color: widget.p2pService.emergencyMode
                                ? Colors.white
                                : ResQLinkTheme.primaryRed,
                            size: ResponsiveSpacing.lg(context),
                          ),
                        );
                      },
                    ),
                    SizedBox(width: ResponsiveSpacing.sm(context)),
                    Expanded(
                      child: ResponsiveTextWidget(
                        'Emergency Mode',
                        styleBuilder: (context) =>
                            ResponsiveText.heading3(context).copyWith(
                              color: widget.p2pService.emergencyMode
                                  ? Colors.white
                                  : ResQLinkTheme.primaryRed,
                            ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: widget.p2pService.emergencyMode,
                onChanged: (value) => widget.onToggle(),
                activeColor: Colors.white,
                activeTrackColor: Colors.red.shade300,
              ),
            ],
          ),
          if (widget.p2pService.emergencyMode) ...[
            SizedBox(height: ResponsiveSpacing.sm(context)),
            ResponsiveTextWidget(
              'Auto-connect enabled • Broadcasting location • High priority mode',
              styleBuilder: (context) => ResponsiveText.caption(context)
                  .copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Padding(
      padding: ResponsiveSpacing.padding(context, all: 24),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: widget.p2pService.emergencyMode
                    ? _pulseAnimation.value
                    : 1.0,
                child: Icon(
                  Icons.emergency,
                  color: widget.p2pService.emergencyMode
                      ? Colors.white
                      : ResQLinkTheme.primaryRed,
                  size: ResponsiveSpacing.xl(context),
                ),
              );
            },
          ),
          SizedBox(width: ResponsiveSpacing.md(context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResponsiveTextWidget(
                  'Emergency Mode',
                  styleBuilder: (context) =>
                      ResponsiveText.heading2(context).copyWith(
                        color: widget.p2pService.emergencyMode
                            ? Colors.white
                            : ResQLinkTheme.primaryRed,
                      ),
                ),
                if (widget.p2pService.emergencyMode) ...[
                  SizedBox(height: ResponsiveSpacing.xs(context)),
                  ResponsiveTextWidget(
                    'Auto-connect enabled • Broadcasting location • High priority mode',
                    styleBuilder: (context) => ResponsiveText.bodySmall(context)
                        .copyWith(color: Colors.white70),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: widget.p2pService.emergencyMode,
            onChanged: (value) => widget.onToggle(),
            activeColor: Colors.white,
            activeTrackColor: Colors.red.shade300,
          ),
        ],
      ),
    );
  }
}