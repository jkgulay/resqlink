import 'package:flutter/material.dart';
import 'home_page.dart'; // Import where WiFiDirectService is defined
import 'chat_screen.dart'; // Import the new unified chat screen

class MessagePage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;
  
  const MessagePage({super.key, required this.wifiDirectService});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  @override
  void initState() {
    super.initState();
    widget.wifiDirectService.addListener(_update);
  }

  @override
  void dispose() {
    widget.wifiDirectService.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final connectedDevices = widget.wifiDirectService.connectedDevices;
    final messageHistory = widget.wifiDirectService.messageHistory;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Chats')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: connectedDevices.length,
        itemBuilder: (context, index) {
          final endpointId = connectedDevices.keys.elementAt(index);
          final userName = connectedDevices[endpointId]!;
          final history = messageHistory[endpointId] ?? [];
          final lastMessage = history.isNotEmpty ? history.last['message'] : 'No messages yet';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                userName[0],
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(userName),
            subtitle: Text(
              lastMessage,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UnifiedChatScreen(
                  endpointId: endpointId,
                  userName: userName,
                  wifiDirectService: widget.wifiDirectService,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}