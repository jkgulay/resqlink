import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../utils/resqlink_theme.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final hasLocation = message.hasLocation;
    final isEmergency =
        message.isEmergency ||
        message.type == 'emergency' ||
        message.type == 'sos';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        margin: EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (isEmergency) _buildEmergencyHeader(message.type),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: _getMessageGradient(isMe, isEmergency, message.type),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.message,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  if (hasLocation) ...[
                    SizedBox(height: 8),
                    _buildLocationPreview(context, message),
                  ],
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.dateTime),
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (isMe) ...[
                        SizedBox(width: 4),
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

  Widget _buildEmergencyHeader(String type) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 16),
          SizedBox(width: 4),
          Text(
            type.toUpperCase(),
            style: TextStyle(
              color: ResQLinkTheme.primaryRed,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPreview(BuildContext context, MessageModel message) {
    return InkWell(
      onTap: () => _showLocationDetails(context, message),
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              'Location shared',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _getMessageGradient(bool isMe, bool isEmergency, String type) {
    if (isEmergency) {
      return LinearGradient(
        colors: [ResQLinkTheme.primaryRed, Colors.red.shade700],
      );
    }

    if (type == 'location') {
      return LinearGradient(colors: [Colors.blue, Colors.blue.shade700]);
    }

    if (isMe) {
      return LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF0B192C)]);
    }

    return LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade800]);
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    IconData icon;
    Color color;

    switch (status) {
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.white70;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = ResQLinkTheme.safeGreen;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = ResQLinkTheme.primaryRed;
      case MessageStatus.pending:
      default:
        icon = Icons.schedule;
        color = Colors.white54;
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text('Location Details', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Latitude: ${message.latitude!.toStringAsFixed(6)}',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              'Longitude: ${message.longitude!.toStringAsFixed(6)}',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}