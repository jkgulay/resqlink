import 'package:flutter/material.dart';
import '../../utils/resqlink_theme.dart';

class EmergencyDialog extends StatelessWidget {
  const EmergencyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ResQLinkTheme.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 24),
          SizedBox(width: 8),
          Text('Send Emergency SOS?', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Text(
        'This will send an emergency SOS message to the selected device, including your location if available.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ResQLinkTheme.primaryRed,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Send SOS', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class ClearChatDialog extends StatelessWidget {
  const ClearChatDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ResQLinkTheme.cardDark,
      title: Text(
        'Clear Chat History?',
        style: TextStyle(color: Colors.white),
      ),
      content: Text(
        'This will permanently delete all messages in this conversation.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ResQLinkTheme.primaryRed,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Clear', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}