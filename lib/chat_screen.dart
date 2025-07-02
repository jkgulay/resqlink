import 'package:flutter/material.dart';
import 'home_page.dart'; // Import where WiFiDirectService is defined

class UnifiedChatScreen extends StatefulWidget {
  final String endpointId;
  final String userName;
  final WiFiDirectService wifiDirectService;

  const UnifiedChatScreen({
    super.key,
    required this.endpointId,
    required this.userName,
    required this.wifiDirectService,
  });

  @override
  State<UnifiedChatScreen> createState() => _UnifiedChatScreenState();
}

class _UnifiedChatScreenState extends State<UnifiedChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.wifiDirectService.addListener(_update);
  }

  @override
  void dispose() {
    widget.wifiDirectService.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  void _update() => setState(() {});

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    widget.wifiDirectService.sendMessage(widget.endpointId, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.wifiDirectService.messageHistory[widget.endpointId] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            onPressed: () => widget.wifiDirectService.broadcastEmergency(
              "EMERGENCY ASSISTANCE NEEDED!",
              null,
              null,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status
          Container(
            padding: const EdgeInsets.all(8),
            color: widget.wifiDirectService.connectedDevices.containsKey(widget.endpointId)
                ? Colors.green
                : Colors.red,
            child: Text(
              widget.wifiDirectService.connectedDevices.containsKey(widget.endpointId)
                  ? 'Connected to ${widget.userName}'
                  : 'Disconnected from ${widget.userName}',
              textAlign: TextAlign.center,
            ),
          ),
          
          // Messages list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (_, index) {
                final msg = messages[index];
                final isMe = msg['isMe'] as bool;
                final isEmergency = msg['type'] == 'emergency';
                
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: isEmergency
                          ? Colors.red
                          : isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isEmergency)
                          const Text('🚨 EMERGENCY', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          msg['message'],
                          style: TextStyle(
                            color: isEmergency || isMe ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(msg['timestamp']),
                          style: TextStyle(
                            color: (isEmergency || isMe) ? Colors.white70 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Input area
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}