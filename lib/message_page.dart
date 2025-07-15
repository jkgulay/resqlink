import 'package:flutter/material.dart';
import 'package:resqlink/services/database_service.dart';
import 'package:resqlink/models/message_model.dart';
import 'home_page.dart';

// Responsive utility class (same as before)
class ResponsiveUtils {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  static bool isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.height < 600;

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSize * 0.85;
    if (width > tabletBreakpoint) return baseSize * 1.15;
    if (width > mobileBreakpoint) return baseSize * 1.05;
    return baseSize;
  }

  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSpacing * 0.8;
    if (width > tabletBreakpoint) return baseSpacing * 1.5;
    if (width > mobileBreakpoint) return baseSpacing * 1.2;
    return baseSpacing;
  }

  static EdgeInsets getResponsivePadding(
    BuildContext context, {
    double? horizontal,
    double? vertical,
  }) {
    final size = MediaQuery.of(context).size;
    final baseHorizontal = horizontal ?? (size.width * 0.04);
    final baseVertical = vertical ?? (size.height * 0.02);

    if (isDesktop(context)) {
      return EdgeInsets.symmetric(
        horizontal: baseHorizontal * 1.5,
        vertical: baseVertical * 1.5,
      );
    } else if (isTablet(context)) {
      return EdgeInsets.symmetric(
        horizontal: baseHorizontal * 1.2,
        vertical: baseVertical * 1.2,
      );
    } else {
      return EdgeInsets.symmetric(
        horizontal: baseHorizontal,
        vertical: baseVertical,
      );
    }
  }

  static double getMaxChatWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return width * 0.7;
    if (isTablet(context)) return width * 0.85;
    return width;
  }

  static double getMessageBubbleMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return width * 0.5;
    if (isTablet(context)) return width * 0.65;
    return width * 0.75;
  }

  static double getAvatarSize(BuildContext context) {
    if (isDesktop(context)) return 50;
    if (isTablet(context)) return 45;
    return 40;
  }

  static double getListTileHeight(BuildContext context) {
    if (isDesktop(context)) return 80;
    if (isTablet(context)) return 75;
    return 70;
  }
}

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
      body: Center(
        child: SizedBox(
          width: ResponsiveUtils.getMaxChatWidth(context),
          child: FutureBuilder<List<MessageModel>>(
            future: _loadAllMessages(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        16,
                      ),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState(context);
              }

              final grouped = <String, List<MessageModel>>{};
              for (var m in snapshot.data!) {
                grouped.putIfAbsent(m.endpointId, () => []).add(m);
              }

              return _buildMessageList(context, grouped, connectedDevices);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: ResponsiveUtils.getResponsiveFontSize(context, 64),
            color: Colors.grey,
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 16)),
          Text(
            'No messages yet.',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 18),
              color: Colors.grey,
            ),
          ),
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 8)),
          Text(
            'Connect to nearby devices to start messaging',
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    Map<String, List<MessageModel>> grouped,
    Map<String, String> connectedDevices,
  ) {
    return ListView.separated(
      padding: ResponsiveUtils.getResponsivePadding(
        context,
        horizontal: 12,
        vertical: 8,
      ),
      itemCount: grouped.keys.length,
      separatorBuilder: (context, index) =>
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 4)),
      itemBuilder: (context, index) {
        final endpointId = grouped.keys.elementAt(index);
        final history = grouped[endpointId]!;
        final last = history.last;
        final userName = connectedDevices[endpointId] ?? last.fromUser;

        return _buildMessageTile(context, endpointId, userName, last);
      },
    );
  }

  Widget _buildMessageTile(
    BuildContext context,
    String endpointId,
    String userName,
    MessageModel lastMessage,
  ) {
    final avatarSize = ResponsiveUtils.getAvatarSize(context);
    final tileHeight = ResponsiveUtils.getListTileHeight(context);

    return Container(
      height: tileHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: ResponsiveUtils.getResponsivePadding(
          context,
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          radius: avatarSize / 2,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            userName[0].toUpperCase(),
            style: TextStyle(
              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          userName,
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 4)),
            Row(
              children: [
                if (lastMessage.isEmergency) ...[
                  Icon(
                    Icons.warning,
                    color: Colors.red,
                    size: ResponsiveUtils.getResponsiveFontSize(context, 16),
                  ),
                  SizedBox(
                    width: ResponsiveUtils.getResponsiveSpacing(context, 4),
                  ),
                ],
                Expanded(
                  child: Text(
                    lastMessage.message,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        14,
                      ),
                      color: lastMessage.isEmergency ? Colors.red : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: ResponsiveUtils.getResponsiveFontSize(context, 20),
            ),
            if (ResponsiveUtils.isTablet(context) ||
                ResponsiveUtils.isDesktop(context))
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 4),
              ),
            if (ResponsiveUtils.isTablet(context) ||
                ResponsiveUtils.isDesktop(context))
              Text(
                'Chat',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
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
  final ScrollController _scrollController = ScrollController();
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
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                widget.userName[0].toUpperCase(),
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 12)),
            Expanded(
              child: Text(
                widget.userName,
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 18),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (ResponsiveUtils.isTablet(context) ||
              ResponsiveUtils.isDesktop(context))
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                // Show user info or connection details
              },
            ),
        ],
      ),
      body: Center(
        child: SizedBox(
          width: ResponsiveUtils.getMaxChatWidth(context),
          child: Column(
            children: [
              Expanded(child: _buildMessagesList()),
              _buildMessageInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: ResponsiveUtils.getResponsiveFontSize(context, 48),
              color: Colors.grey,
            ),
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 16)),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                color: Colors.grey,
              ),
            ),
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 8)),
            Text(
              'Start a conversation with ${widget.userName}',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: ResponsiveUtils.getResponsivePadding(
        context,
        horizontal: 16,
        vertical: 8,
      ),
      itemCount: _messages.length,
      itemBuilder: (_, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(MessageModel msg) {
    final isMe = msg.isMe;
    final maxWidth = ResponsiveUtils.getMessageBubbleMaxWidth(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: EdgeInsets.symmetric(
          vertical: ResponsiveUtils.getResponsiveSpacing(context, 4),
          horizontal: ResponsiveUtils.getResponsiveSpacing(context, 8),
        ),
        padding: ResponsiveUtils.getResponsivePadding(
          context,
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: msg.isEmergency
              ? Colors.red.shade600
              : isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(
            ResponsiveUtils.getResponsiveSpacing(context, 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isEmergency) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning, color: Colors.white, size: 16),
                  SizedBox(
                    width: ResponsiveUtils.getResponsiveSpacing(context, 4),
                  ),
                  Text(
                    'EMERGENCY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        12,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 4),
              ),
            ],
            Text(
              msg.message,
              style: TextStyle(
                color: isMe || msg.isEmergency
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
            if (ResponsiveUtils.isTablet(context) ||
                ResponsiveUtils.isDesktop(context)) ...[
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 4),
              ),
              Text(
                _formatTimestamp(msg.timestamp as String),
                style: TextStyle(
                  color:
                      (isMe || msg.isEmergency
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant)
                          .withOpacity(0.7),
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: ResponsiveUtils.getResponsivePadding(
        context,
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                ),
                decoration: InputDecoration(
                  hintText: 'Type message...',
                  hintStyle: TextStyle(
                    fontSize: ResponsiveUtils.getResponsiveFontSize(
                      context,
                      16,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: ResponsiveUtils.getResponsivePadding(
                    context,
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                maxLines: ResponsiveUtils.isDesktop(context) ? 3 : 1,
              ),
            ),
            SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 8)),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _sendMessage,
                icon: Icon(
                  Icons.send,
                  color: Colors.white,
                  size: ResponsiveUtils.getResponsiveFontSize(context, 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }
}
