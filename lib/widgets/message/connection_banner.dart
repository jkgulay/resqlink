import 'package:flutter/material.dart';
import '../../utils/resqlink_theme.dart';

class ConnectionBanner extends StatelessWidget {
  final VoidCallback onScanPressed;

  const ConnectionBanner({
    super.key,
    required this.onScanPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      color: ResQLinkTheme.warningYellow.withValues(alpha: 0.9),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Not connected to any devices. Messages will be saved locally.',
              style: TextStyle(color: Colors.white),
              maxLines: 2,
            ),
          ),
          TextButton(
            onPressed: onScanPressed,
            child: Text(
              'SCAN',
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
}