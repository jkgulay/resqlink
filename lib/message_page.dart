import 'package:flutter/material.dart';
import 'package:resqlink/services/database_service.dart';
import 'package:resqlink/models/message_model.dart';
import 'home_page.dart'; 

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

    return Scaffold(
      body: FutureBuilder<List<MessageModel>>(
        future: _loadAllMessages(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No messages yet.'));
          }

          final grouped = <String, List<MessageModel>>{};
          for (var m in snapshot.data!) {
            grouped.putIfAbsent(m.endpointId, () => []).add(m);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: grouped.keys.length,
            itemBuilder: (context, index) {
              final endpointId = grouped.keys.elementAt(index);
              final history = grouped[endpointId]!;
              final last = history.last;
              final userName =
                  connectedDevices[endpointId] ?? last.fromUser;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(userName[0]),
                ),
                title: Text(userName),
                subtitle: Text(
                  last.message,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                trailing: const Icon(Icons.chat_bubble_outline),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _ChatScreen(
                        endpointId: endpointId,
                        userName: userName,
                        wifiDirectService: widget.wifiDirectService,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<MessageModel>> _loadAllMessages() async {
    try {
      final db = await DatabaseService.database;
      final result = await db.query('messages', orderBy: 'timestamp ASC');
      return result.map((e) => MessageModel.fromMap(e)).toList();
    } catch (e) {
      print('Error loading messages: $e');
      rethrow;
    }
  }
}

class _ChatScreen extends StatefulWidget {
  final String endpointId;
  final String userName;
  final WiFiDirectService wifiDirectService;

  const _ChatScreen({
    required this.endpointId,
    required this.userName,
    required this.wifiDirectService,
  });

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List<MessageModel> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    widget.wifiDirectService.addListener(_onMessage);
  }

  void _onMessage() => _loadMessages();

  Future<void> _loadMessages() async {
    final msgs = await DatabaseService.getMessages(widget.endpointId);
    setState(() => _messages = msgs);
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    await widget.wifiDirectService.sendMessage(widget.endpointId, text);
    await _loadMessages();
  }

  @override
  void dispose() {
    widget.wifiDirectService.removeListener(_onMessage);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.userName)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isEmergency
                          ? Colors.red
                          : msg.isMe
                          ? Colors.blue
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.isEmergency)
                          const Text(
                            '🚨 EMERGENCY',
                            style: TextStyle(color: Colors.white),
                          ),
                        Text(
                          msg.message,
                          style: TextStyle(
                            color: msg.isMe || msg.isEmergency
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
