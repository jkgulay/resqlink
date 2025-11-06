import 'package:flutter/material.dart';
import '../../models/message_model.dart';

class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final Function(String, MessageType) onSendMessage;
  final VoidCallback onSendLocation;
  final Function(String) onTyping;
  final bool enabled;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    required this.onSendLocation,
    required this.onTyping,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 400;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 16,
        vertical: isNarrow ? 12 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B192C).withValues(alpha: 0.95),
            Color(0xFF1E3E62).withValues(alpha: 0.95),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: Color(0xFFFF6500).withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Location button
            Container(
              margin: EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: enabled
                    ? Color(0xFF4A9EFF).withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: enabled
                      ? Color(0xFF4A9EFF).withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.my_location,
                  color: enabled ? Color(0xFF4A9EFF) : Colors.grey,
                  size: isNarrow ? 20 : 22,
                ),
                onPressed: enabled ? onSendLocation : null,
                tooltip: 'Share GPS Location',
                constraints: BoxConstraints(
                  minWidth: isNarrow ? 40 : 44,
                  minHeight: isNarrow ? 40 : 44,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
            SizedBox(width: 8),
            // Text input
            Expanded(
              child: Container(
                constraints: BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Color(0xFF1E3E62).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: enabled
                        ? Color(0xFFFF6500).withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: controller,
                  onChanged: enabled ? onTyping : null,
                  enabled: enabled,
                  decoration: InputDecoration(
                    hintText: enabled ? 'Type a message...' : 'Device offline',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontFamily: 'Poppins',
                      fontSize: isNarrow ? 14 : 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontSize: isNarrow ? 14 : 15,
                  ),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            SizedBox(width: 8),
            // Send button
            Container(
              margin: EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                gradient: enabled
                    ? LinearGradient(
                        colors: [Color(0xFFFF6500), Color(0xFFFF8533)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: enabled ? null : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: Color(0xFFFF6500).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: isNarrow ? 20 : 22,
                ),
                onPressed: enabled
                    ? () {
                        final text = controller.text.trim();
                        if (text.isNotEmpty) {
                          onSendMessage(text, MessageType.text);
                          controller.clear();
                        }
                      }
                    : null,
                tooltip: 'Send message',
                constraints: BoxConstraints(
                  minWidth: isNarrow ? 40 : 44,
                  minHeight: isNarrow ? 40 : 44,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
