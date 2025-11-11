import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: Text(
        'This will send an emergency SOS message to the selected device, including your location if available.',
        style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(
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
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      content: Text(
        'This will permanently delete all messages in this conversation.',
        style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
