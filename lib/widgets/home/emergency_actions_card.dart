import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/p2p/p2p_main_service.dart';
import '../../services/p2p/p2p_base_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/resqlink_theme.dart';
import '../../models/message_model.dart';

class EmergencyActionsCard extends StatefulWidget {
  final P2PMainService p2pService;
  final Function(EmergencyTemplate)? onEmergencyMessage;

  const EmergencyActionsCard({
    super.key,
    required this.p2pService,
    this.onEmergencyMessage,
  });

  @override
  State<EmergencyActionsCard> createState() => _EmergencyActionsCardState();
}

class _EmergencyActionsCardState extends State<EmergencyActionsCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
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
                  _buildHeader(context),
                  SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
                  _buildEmergencyGrid(context),
                  SizedBox(height: ResponsiveHelper.getContentSpacing(context)),
                  _buildConnectionStatus(context),
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
          ResQLinkTheme.emergencyOrange.withValues(alpha: 0.08),
          ResQLinkTheme.primaryRed.withValues(alpha: 0.05),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: ResQLinkTheme.emergencyOrange.withValues(alpha: 0.15),
        width: 1,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ResQLinkTheme.emergencyOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.emergency,
            color: ResQLinkTheme.emergencyOrange,
            size: ResponsiveHelper.getIconSize(context),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emergency Actions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: ResponsiveHelper.getTitleSize(context),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Rajdhani',
                ),
              ),
              Text(
                'Quick emergency message broadcast',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: ResponsiveHelper.getSubtitleSize(context),
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(ResQLinkTheme.emergencyOrange),
            ),
          ),
      ],
    );
  }

  Widget _buildEmergencyGrid(BuildContext context) {
    final isNarrow = ResponsiveHelper.isTablet(context) == false;

    return GridView.count(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      crossAxisCount: isNarrow ? 2 : 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isNarrow ? 1.2 : 1.0,
      children: [
        _buildEmergencyButton(
          context: context,
          label: 'SOS',
          icon: Icons.sos,
          color: ResQLinkTheme.primaryRed,
          template: EmergencyTemplate.sos,
          priority: true,
        ),
        _buildEmergencyButton(
          context: context,
          label: 'Trapped',
          icon: Icons.warning_amber_outlined,
          color: ResQLinkTheme.emergencyOrange,
          template: EmergencyTemplate.trapped,
        ),
        _buildEmergencyButton(
          context: context,
          label: 'Medical',
          icon: Icons.medical_services_outlined,
          color: ResQLinkTheme.locationBlue,
          template: EmergencyTemplate.medical,
        ),
        _buildEmergencyButton(
          context: context,
          label: 'Safe',
          icon: Icons.check_circle_outline,
          color: ResQLinkTheme.safeGreen,
          template: EmergencyTemplate.safe,
        ),
      ],
    );
  }

  Widget _buildEmergencyButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required EmergencyTemplate template,
    bool priority = false,
  }) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: priority && _pulseController.isAnimating ? _pulseAnimation.value : 1.0,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(16),
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isLoading ? null : () => _handleEmergencyAction(template),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.8),
                      color.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: Colors.white,
                      size: ResponsiveHelper.isTablet(context) ? 32 : 28,
                    ),
                    SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: ResponsiveHelper.isTablet(context) ? 14 : 12,
                        fontWeight: FontWeight.bold,
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

  Widget _buildConnectionStatus(BuildContext context) {
    final connectedDevices = widget.p2pService.connectedDevices.length;
    final isConnected = widget.p2pService.isConnected;

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConnected
            ? ResQLinkTheme.safeGreen.withValues(alpha: 0.1)
            : ResQLinkTheme.offlineGray.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? ResQLinkTheme.safeGreen.withValues(alpha: 0.2)
              : ResQLinkTheme.offlineGray.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.wifi : Icons.wifi_off,
            color: isConnected ? ResQLinkTheme.safeGreen : ResQLinkTheme.offlineGray,
            size: 16,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              isConnected
                  ? 'Ready to broadcast to $connectedDevices device${connectedDevices == 1 ? '' : 's'}'
                  : 'No connections - messages will be queued',
              style: TextStyle(
                color: isConnected ? ResQLinkTheme.safeGreen : ResQLinkTheme.offlineGray,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleEmergencyAction(EmergencyTemplate template) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Haptic feedback for emergency actions
      await HapticFeedback.mediumImpact();

      // Start pulse animation for SOS
      if (template == EmergencyTemplate.sos) {
        _pulseController.repeat(reverse: true);
      }

      // Send emergency message
      await _sendEmergencyMessage(template);

      // Call original callback if provided
      widget.onEmergencyMessage?.call(template);

      // Show success feedback
      _showSuccessSnackBar('Emergency message broadcasted');

      // Stop pulse animation after delay
      if (template == EmergencyTemplate.sos) {
        Future.delayed(Duration(seconds: 3), () {
          if (mounted) {
            _pulseController.stop();
            _pulseController.reset();
          }
        });
      }

    } catch (e) {
      debugPrint('❌ Emergency message failed: $e');
      _showErrorSnackBar('Failed to send emergency message');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendEmergencyMessage(EmergencyTemplate template) async {
    final messageText = _getEmergencyMessage(template);
    final messageType = template == EmergencyTemplate.sos
        ? MessageType.sos
        : MessageType.emergency;

    // Broadcast to all connected devices
    await widget.p2pService.sendMessage(
      message: messageText,
      type: messageType,
      targetDeviceId: 'broadcast',
      senderName: widget.p2pService.userName ?? 'Emergency Broadcast',
    );
  }

  String _getEmergencyMessage(EmergencyTemplate template) {
    switch (template) {
      case EmergencyTemplate.sos:
        return '🚨 SOS - I need immediate help!';
      case EmergencyTemplate.trapped:
        return '⚠️ I am trapped and need assistance!';
      case EmergencyTemplate.medical:
        return '🏥 Medical emergency - I need medical help!';
      case EmergencyTemplate.safe:
        return '✅ I am safe and secure';
      case EmergencyTemplate.evacuating:
        return '🚶 Evacuating area - proceeding to safety';
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: ResQLinkTheme.safeGreen,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: ResQLinkTheme.primaryRed,
        duration: Duration(seconds: 3),
      ),
    );
  }
}