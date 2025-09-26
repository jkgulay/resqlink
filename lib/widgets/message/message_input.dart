import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../utils/resqlink_theme.dart';

class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final Function(String, MessageType) onSendMessage;
  final VoidCallback onSendLocation;
  final VoidCallback onSendLocationP2P;
  final VoidCallback onSendEmergency;
  final Function(String) onTyping;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    required this.onSendLocation,
    required this.onSendLocationP2P,
    required this.onSendEmergency,
    required this.onTyping,
    required bool enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ResQLinkTheme.surfaceDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.location_on, color: Colors.blue),
                  onPressed: onSendLocation,
                  tooltip: 'Share Location',
                ),
                IconButton(
                  icon: Icon(Icons.my_location, color: Colors.green),
                  onPressed: onSendLocationP2P,
                  tooltip: 'Share via P2P',
                ),
                IconButton(
                  icon: Icon(Icons.warning, color: ResQLinkTheme.primaryRed),
                  onPressed: onSendEmergency,
                  tooltip: 'Send Emergency',
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onTyping,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: ResQLinkTheme.cardDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: TextStyle(color: Colors.white),
                    maxLines: null,
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: ResQLinkTheme.primaryRed,
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isNotEmpty) {
                      onSendMessage(text, MessageType.text);
                      controller.clear();
                    }
                  },
                  child: Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
