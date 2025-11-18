import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/message_model.dart';
import '../../utils/resqlink_theme.dart';
import '../../services/p2p/p2p_main_service.dart';

class MessageSummary {
  final String endpointId;
  final String deviceName;
  final MessageModel? lastMessage;
  final int messageCount;
  final int unreadCount;
  final bool isConnected;
  final bool isMeshReachable;
  final int meshHopCount;

  MessageSummary({
    required this.endpointId,
    required this.deviceName,
    this.lastMessage,
    required this.messageCount,
    required this.unreadCount,
    required this.isConnected,
    this.isMeshReachable = false,
    this.meshHopCount = 0,
  });

  bool get isReachable => isConnected || isMeshReachable;
  bool get hasMeshRelay => !isConnected && isMeshReachable;
}

class ConversationList extends StatelessWidget {
  final List<MessageSummary> conversations;
  final P2PMainService p2pService;
  final Function(String, String) onConversationTap;
  final Future<void> Function() onRefresh;

  const ConversationList({
    super.key,
    required this.conversations,
    required this.p2pService,
    required this.onConversationTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
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
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              p2pService.connectedDevices.isEmpty
                  ? 'Connect to a device to start messaging'
                  : 'Select a device to start messaging',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: ResQLinkTheme.primaryRed,
      backgroundColor: ResQLinkTheme.surfaceDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: conversations.length,
        itemBuilder: (context, index) => ConversationCard(
          conversation: conversations[index],
          onTap: () => onConversationTap(
            conversations[index].endpointId,
            conversations[index].deviceName,
          ),
        ),
      ),
    );
  }
}

class ConversationCard extends StatelessWidget {
  final MessageSummary conversation;
  final VoidCallback onTap;

  const ConversationCard({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final message = conversation.lastMessage;
    final isEmergency = message?.isEmergency ?? false;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ResQLinkTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergency ? ResQLinkTheme.primaryRed : Colors.transparent,
          width: isEmergency ? 2 : 0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: conversation.isConnected
                          ? ResQLinkTheme.safeGreen
                          : conversation.hasMeshRelay
                          ? Colors.orange
                          : ResQLinkTheme.offlineGray,
                      radius: 24,
                      child: Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                    if (conversation.isReachable)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: conversation.isConnected
                                ? ResQLinkTheme.safeGreen
                                : Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.deviceName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (message != null)
                            Text(
                              _formatRelativeTime(message.dateTime),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white54,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                      if (message != null) ...[
                        SizedBox(height: 4),
                        Text(
                          message.message,
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                if (conversation.unreadCount > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: ResQLinkTheme.primaryRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${conversation.unreadCount}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m';
    if (difference.inHours < 24) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';

    return '${dateTime.day}/${dateTime.month}';
  }
}
