import 'package:flutter/material.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/p2p/p2p_main_service.dart';

class EmptyChatView extends StatelessWidget {
  final P2PMainService p2pService;

  const EmptyChatView({
    super.key,
    required this.p2pService,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: ResQLinkTheme.offlineGray,
          ),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
          SizedBox(height: 8),
          Text(
            p2pService.connectedDevices.isEmpty
                ? 'Connect to a device to start messaging'
                : 'Select a device to start messaging',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}