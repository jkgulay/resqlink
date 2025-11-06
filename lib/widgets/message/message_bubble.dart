import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../utils/resqlink_theme.dart';
import 'location_map_widget.dart';
import 'location_preview_modal.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final hasLocation = message.hasLocation;
    final isEmergency =
        message.isEmergency ||
        message.type == 'emergency' ||
        message.type == 'sos';
    final isNarrow = MediaQuery.of(context).size.width < 400;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.symmetric(
          vertical: 4,
          horizontal: isNarrow ? 12 : 16,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Emergency badge
            if (isEmergency) _buildEmergencyBadge(message.type),

            // Message bubble
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 12 : 14,
                vertical: isNarrow ? 10 : 12,
              ),
              decoration: BoxDecoration(
                gradient: _getMessageGradient(isMe, isEmergency, message.type),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isMe ? 18 : 4),
                  topRight: Radius.circular(isMe ? 4 : 18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: _getBorderColor(isMe, isEmergency, message.type),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getShadowColor(
                      isMe,
                      isEmergency,
                    ).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name for received messages
                  if (!isMe) ...[
                    Text(
                      message.fromUser,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: isNarrow ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    SizedBox(height: 4),
                  ],

                  // Message text
                  Text(
                    message.message,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isNarrow ? 14 : 15,
                      height: 1.4,
                      fontFamily: 'Poppins',
                    ),
                  ),

                  // Location preview
                  if (hasLocation) ...[
                    SizedBox(height: 10),
                    _buildLocationPreview(context, message, isNarrow),
                  ],

                  SizedBox(height: 6),

                  // Time and status row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.dateTime),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: isNarrow ? 10 : 11,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      if (isMe) ...[
                        SizedBox(width: 6),
                        _buildMessageStatusIcon(message.status),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyBadge(String type) {
    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ResQLinkTheme.primaryRed, Colors.red.shade700],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: ResQLinkTheme.primaryRed.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_rounded, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            type.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              fontFamily: 'Poppins',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPreview(
    BuildContext context,
    MessageModel message,
    bool isNarrow,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LocationMapWidget(
              latitude: message.latitude!,
              longitude: message.longitude!,
              senderName: message.fromUser,
              isEmergency: message.isEmergency,
            ),
          ),
        ),
        SizedBox(height: 8),
        InkWell(
          onTap: () => _showLocationDetails(context, message),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_outlined,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 14,
                ),
                SizedBox(width: 6),
                Text(
                  'View on map',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: isNarrow ? 11 : 12,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LinearGradient _getMessageGradient(bool isMe, bool isEmergency, String type) {
    if (isEmergency) {
      return LinearGradient(
        colors: [ResQLinkTheme.primaryRed, Color(0xFFD32F2F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    if (type == 'location') {
      return LinearGradient(
        colors: [Color(0xFF4A9EFF), Color(0xFF2979FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    if (isMe) {
      return LinearGradient(
        colors: [
          Color(0xFF1E3E62).withValues(alpha: 0.9),
          Color(0xFF0B192C).withValues(alpha: 0.95),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return LinearGradient(
      colors: [Color(0xFF424242), Color(0xFF303030)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Color _getBorderColor(bool isMe, bool isEmergency, String type) {
    if (isEmergency) {
      return ResQLinkTheme.primaryRed.withValues(alpha: 0.3);
    }
    if (type == 'location') {
      return Color(0xFF4A9EFF).withValues(alpha: 0.3);
    }
    if (isMe) {
      return Color(0xFFFF6500).withValues(alpha: 0.2);
    }
    return Colors.white.withValues(alpha: 0.1);
  }

  Color _getShadowColor(bool isMe, bool isEmergency) {
    if (isEmergency) return ResQLinkTheme.primaryRed;
    if (isMe) return Color(0xFF1E3E62);
    return Colors.black;
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    IconData icon;
    Color color;

    switch (status) {
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.white.withValues(alpha: 0.6);
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = ResQLinkTheme.safeGreen;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = ResQLinkTheme.primaryRed;
      case MessageStatus.pending:
      default:
        icon = Icons.schedule;
        color = Colors.white.withValues(alpha: 0.5);
    }

    return Icon(icon, size: 14, color: color);
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    return '$displayHour:$minute $period';
  }

  void _showLocationDetails(BuildContext context, MessageModel message) {
    if (message.latitude == null || message.longitude == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LocationPreviewModal(
        latitude: message.latitude!,
        longitude: message.longitude!,
        senderName: message.fromUser,
        isEmergency: message.isEmergency,
      ),
    );
  }
}
