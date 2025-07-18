// lib/pages/message_page.dart
import 'package:flutter/material.dart';
import '../services/p2p_services.dart';
import '../services/database_service.dart';
import '../models/message_model.dart';
import '../home_page.dart'; // For P2PChatScreen
import 'gps_page.dart';

class MessagePage extends StatefulWidget {
  final P2PConnectionService p2pService;
  final LocationModel? currentLocation;

  const MessagePage({
    super.key,
    required this.p2pService,
    this.currentLocation,
  });

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  Map<String, List<MessageModel>> _groupedMessages = {};
  Map<String, MessageSummary> _messageSummaries = {};

  @override
  void initState() {
    super.initState();
    _loadMessages();
    widget.p2pService.addListener(_onP2PUpdate);
  }

  @override
  void dispose() {
    widget.p2pService.removeListener(_onP2PUpdate);
    super.dispose();
  }

  void _onP2PUpdate() {
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final allMessages = await DatabaseService.getAllMessages();

      // Group messages by endpoint/device
      final grouped = <String, List<MessageModel>>{};
      for (var msg in allMessages) {
        grouped.putIfAbsent(msg.endpointId, () => []).add(msg);
      }

      // Create summaries
      final summaries = <String, MessageSummary>{};
      for (var entry in grouped.entries) {
        final messages = entry.value;
        if (messages.isNotEmpty) {
          messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          final lastMessage = messages.first;
          final unreadCount = messages.where((m) => !m.isMe).length;

          summaries[entry.key] = MessageSummary(
            deviceId: entry.key,
            deviceName: lastMessage.fromUser,
            lastMessage: lastMessage,
            messageCount: messages.length,
            unreadCount: unreadCount,
            isConnected: widget.p2pService.connectedDevices.containsKey(
              entry.key,
            ),
          );
        }
      }

      // Add connected devices without messages
      for (var device in widget.p2pService.connectedDevices.entries) {
        if (!summaries.containsKey(device.key)) {
          summaries[device.key] = MessageSummary(
            deviceId: device.key,
            deviceName: device.value.name,
            lastMessage: null,
            messageCount: 0,
            unreadCount: 0,
            isConnected: true,
          );
        }
      }

      if (mounted) {
        setState(() {
          _groupedMessages = grouped;
          _messageSummaries = summaries;
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedSummaries = _messageSummaries.values.toList()
      ..sort((a, b) {
        // Connected devices first
        if (a.isConnected != b.isConnected) {
          return a.isConnected ? -1 : 1;
        }
        // Then by last message time
        if (a.lastMessage != null && b.lastMessage != null) {
          return b.lastMessage!.timestamp.compareTo(a.lastMessage!.timestamp);
        }
        return 0;
      });

    return Scaffold(
      body: Column(
        children: [
          // P2P Status Header
          Container(
            padding: EdgeInsets.all(16),
            color: Theme.of(
              context,
            ).primaryColor.withAlpha((0.1 * 255).round()),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: widget.p2pService.currentRole != P2PRole.none
                      ? Colors.green
                      : Colors.orange,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'P2P Network: ${widget.p2pService.currentRole != P2PRole.none ? "Active" : "Inactive"}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Connected: ${widget.p2pService.connectedDevices.length} | '
                        'Messages: ${_groupedMessages.values.expand((m) => m).length}',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (widget.p2pService.currentRole == P2PRole.none)
                  TextButton(
                    onPressed: () {
                      // Navigate to home to start P2P
                      DefaultTabController.of(context).animateTo(0);
                    },
                    child: Text('Start P2P'),
                  ),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: sortedSummaries.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadMessages,
                    child: ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: sortedSummaries.length,
                      itemBuilder: (context, index) {
                        final summary = sortedSummaries[index];
                        return _buildMessageTile(summary);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            widget.p2pService.currentRole == P2PRole.none
                ? 'Start P2P network to begin messaging'
                : 'Connect to devices to start chatting',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          if (widget.p2pService.currentRole != P2PRole.none) ...[
            SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(Icons.people),
              label: Text('View Connected Devices'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => P2PDevicesPage(
                      p2pService: widget.p2pService,
                      currentLocation: widget.currentLocation,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageTile(MessageSummary summary) {
    final hasMessages = summary.lastMessage != null;
    final isEmergency = summary.lastMessage?.isEmergency ?? false;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: summary.isConnected ? 2 : 1,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => P2PChatScreen(
                p2pService: widget.p2pService,
                targetDeviceId: summary.deviceId,
                targetDeviceName: summary.deviceName,
                currentLocation: widget.currentLocation,
              ),
            ),
          ).then((_) => _loadMessages());
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: summary.isConnected
                  ? Colors.green.withAlpha((0.3 * 255).round())
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isEmergency
                      ? Colors.red
                      : summary.isConnected
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                  child: Text(
                    summary.deviceName[0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (summary.isConnected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    summary.deviceName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (hasMessages)
                  Text(
                    _formatTimestamp(summary.lastMessage!.timestamp),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                if (hasMessages) ...[
                  Row(
                    children: [
                      if (isEmergency) ...[
                        Icon(Icons.warning, size: 16, color: Colors.red),
                        SizedBox(width: 4),
                      ],
                      if (summary.lastMessage!.type == 'location') ...[
                        Icon(Icons.location_on, size: 16, color: Colors.blue),
                        SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          summary.lastMessage!.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isEmergency ? Colors.red : Colors.grey[700],
                            fontWeight: isEmergency
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    summary.isConnected
                        ? 'Connected - Tap to chat'
                        : 'No messages yet',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      summary.isConnected
                          ? Icons.signal_cellular_4_bar
                          : Icons.signal_cellular_off,
                      size: 14,
                      color: summary.isConnected ? Colors.green : Colors.grey,
                    ),
                    SizedBox(width: 4),
                    Text(
                      summary.isConnected ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: summary.isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                    Spacer(),
                    if (summary.messageCount > 0)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${summary.messageCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'now';
    }
  }
}

// Message Summary Model
class MessageSummary {
  final String deviceId;
  final String deviceName;
  final MessageModel? lastMessage;
  final int messageCount;
  final int unreadCount;
  final bool isConnected;

  MessageSummary({
    required this.deviceId,
    required this.deviceName,
    this.lastMessage,
    required this.messageCount,
    required this.unreadCount,
    required this.isConnected,
  });
}
