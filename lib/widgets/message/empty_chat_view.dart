import 'package:flutter/material.dart';
import 'package:resqlink/utils/offline_fonts.dart';
import '../../services/p2p/p2p_main_service.dart';

class EmptyChatView extends StatelessWidget {
  final P2PMainService p2pService;

  const EmptyChatView({super.key, required this.p2pService});

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 400;
    final hasConnectedDevices = p2pService.connectedDevices.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B192C).withValues(alpha: 0.5),
            Color(0xFF1E3E62).withValues(alpha: 0.3),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(isNarrow ? 24 : 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon container with gradient background
              Container(
                padding: EdgeInsets.all(isNarrow ? 24 : 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1E3E62).withValues(alpha: 0.4),
                      Color(0xFF0B192C).withValues(alpha: 0.6),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF0B192C).withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: isNarrow ? 56 : 64,
                ),
              ),

              SizedBox(height: isNarrow ? 20 : 24),

              // Title
              Text(
                'No messages yet',
                style: OfflineFonts.poppins(
                  fontSize: isNarrow ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: isNarrow ? 10 : 12),

              // Subtitle
              Container(
                padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24),
                child: Text(
                  hasConnectedDevices
                      ? 'Start the conversation by sending\nyour first message'
                      : 'Connect to a device to start\nchatting offline',
                  style: OfflineFonts.poppins(
                    fontSize: isNarrow ? 14 : 15,
                    color: Colors.white.withValues(alpha: 0.6),
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Connection hint
              if (!hasConnectedDevices) ...[
                SizedBox(height: isNarrow ? 20 : 24),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 16 : 20,
                    vertical: isNarrow ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: Color(0xFFFF6500).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color(0xFFFF6500).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_tethering_rounded,
                        color: Color(0xFFFF6500),
                        size: isNarrow ? 18 : 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Enable WiFi to discover peers',
                        style: OfflineFonts.poppins(
                          color: Color(0xFFFF6500),
                          fontSize: isNarrow ? 12 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
