import 'package:flutter/material.dart';
import 'package:resqlink/utils/offline_fonts.dart';
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
          Text(
            'Send Emergency SOS?',
            style: OfflineFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: Text(
        'This will send an emergency SOS message to the selected device, including your location if available.',
        style: OfflineFonts.poppins(
          color: Colors.white70,
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: OfflineFonts.poppins(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ResQLinkTheme.primaryRed,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Send SOS',
            style: OfflineFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
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
        style: OfflineFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      content: Text(
        'This will permanently delete all messages in this conversation.',
        style: OfflineFonts.poppins(
          color: Colors.white70,
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: OfflineFonts.poppins(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ResQLinkTheme.primaryRed,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Clear',
            style: OfflineFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
