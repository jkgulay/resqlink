import 'package:flutter/material.dart';
import 'dart:async';
import '../models/chat_session_model.dart';
import '../models/message_model.dart';
import '../features/database/repositories/chat_repository.dart';
import '../features/database/repositories/message_repository.dart';
import '../services/p2p/p2p_main_service.dart';
import '../utils/resqlink_theme.dart';
import '../widgets/message/chat_view.dart';
import '../widgets/message/message_input.dart';
import '../widgets/message/loading_view.dart';
import '../widgets/message/emergency_dialog.dart';

class ChatSessionPage extends StatefulWidget {
  final String sessionId;
  final String deviceName;
  final P2PMainService p2pService;

  const ChatSessionPage({
    super.key,
    required this.sessionId,
    required this.deviceName,
    required this.p2pService, required String deviceId,
  });

  @override
  State<ChatSessionPage> createState() => _ChatSessionPageState();
}

class _ChatSessionPageState extends State<ChatSessionPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  ChatSession? _chatSession;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isConnected = false;
  Timer? _refreshTimer;
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.p2pService.onMessageReceived = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChatData();
      _startPeriodicRefresh();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    }
  }

  Future<void> _initialize() async {
    await _loadChatData();
    _setupMessageListener();
    _markMessagesAsRead();
    _startPeriodicRefresh();
  }

  void _setupMessageListener() {
    widget.p2pService.onMessageReceived = _onMessageReceived;
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (_) {
      if (mounted) {
        _loadChatData();
      }
    });
  }

  Future<void> _loadChatData() async {
    if (!mounted) return;

    try {
      final session = await ChatRepository.getSession(widget.sessionId);
      final messages = await ChatRepository.getSessionMessages(widget.sessionId);

      if (mounted) {
        setState(() {
          _chatSession = session;
          _messages = messages;
          _isLoading = false;
          _isConnected = _chatSession?.isOnline ?? false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('❌ Error loading chat data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    await ChatRepository.markSessionMessagesAsRead(widget.sessionId);
  }

  void _onMessageReceived(MessageModel message) async {
    if (!mounted) return;

    // Check if this message belongs to the current chat session
    if (message.chatSessionId == widget.sessionId ||
        (_chatSession != null && message.endpointId == _chatSession!.deviceId)) {

      // Update message with chat session ID if not set
      if (message.chatSessionId == null) {
        final updatedMessage = message.copyWith(chatSessionId: widget.sessionId);
        await MessageRepository.insert(updatedMessage);
      }

      await _loadChatData();
      _markMessagesAsRead();
    }
  }

  Future<void> _sendMessage(String messageText, MessageType type) async {
    if (_chatSession == null || messageText.trim().isEmpty) return;

    try {
      final messageId = MessageModel.generateMessageId(
        widget.p2pService.deviceId ?? 'unknown',
      );
      final timestamp = DateTime.now();

      // Create message with chat session ID
      final message = MessageModel(
        messageId: messageId,
        endpointId: _chatSession!.deviceId,
        fromUser: widget.p2pService.userName ?? 'You',
        message: messageText.trim(),
        isMe: true,
        isEmergency: type == MessageType.emergency || type == MessageType.sos,
        timestamp: timestamp.millisecondsSinceEpoch,
        messageType: type,
        type: type.name,
        status: MessageStatus.pending,
        chatSessionId: widget.sessionId,
        connectionType: widget.p2pService.connectionType, deviceId: null,
      );

      // Save message to database
      await MessageRepository.insert(message);

      // Send via P2P if connected
      if (_isConnected) {
        try {
          await widget.p2pService.sendMessage(
            message: messageText.trim(),
            type: type,
            targetDeviceId: _chatSession!.deviceId,
            senderName: widget.p2pService.userName ?? 'You',
          );

          // Update message status to sent
          await MessageRepository.updateStatus(messageId, MessageStatus.sent);
        } catch (e) {
          debugPrint('❌ Error sending P2P message: $e');
          await MessageRepository.updateStatus(messageId, MessageStatus.failed);
        }
      } else {
        // Mark as failed if not connected
        await MessageRepository.updateStatus(messageId, MessageStatus.failed);
      }

      _messageController.clear();
      await _loadChatData();

    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      _showSnackBar('Failed to send message', isError: true);
    }
  }

  Future<void> _sendLocationMessage() async {
    if (_chatSession == null) return;

    try {
      // Get current location if available
      // This would integrate with your location service
      await _sendMessage('📍 Location shared', MessageType.location);
    } catch (e) {
      debugPrint('❌ Error sending location: $e');
      _showSnackBar('Failed to send location', isError: true);
    }
  }

  Future<void> _sendEmergencyMessage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmergencyDialog(),
    );

    if (confirmed == true) {
      await _sendMessage('🚨 Emergency SOS', MessageType.sos);
    }
  }

  Future<void> _reconnectToDevice() async {
    if (_chatSession == null) return;

    try {
      _showSnackBar('Attempting to reconnect...', isError: false);

      await widget.p2pService.discoverDevices(force: true);
      await Future.delayed(Duration(seconds: 2));

      final devices = widget.p2pService.discoveredDevices;
      Map<String, dynamic>? targetDevice;

      if (devices.containsKey(_chatSession!.deviceId)) {
        targetDevice = devices[_chatSession!.deviceId];
      } else {
        for (final deviceData in devices.values) {
          if (deviceData['deviceId'] == _chatSession!.deviceId ||
              deviceData['endpointId'] == _chatSession!.deviceId) {
            targetDevice = deviceData;
            break;
          }
        }
      }

      if (targetDevice != null && targetDevice.isNotEmpty) {
        final success = await widget.p2pService.connectToDevice(targetDevice);
        if (success) {
          await ChatRepository.updateSessionConnection(
            sessionId: widget.sessionId,
            connectionType: ConnectionType.wifiDirect,
            connectionTime: DateTime.now(),
          );
          await _loadChatData();
          _showSnackBar('Reconnected successfully!', isError: false);
        } else {
          _showSnackBar('Failed to reconnect. Try creating a new connection.');
        }
      } else {
        _showSnackBar('Device not found. Try scanning again.');
      }
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
      _showSnackBar('Reconnection failed. Try manual connection.');
    }
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleTyping(String text) {
    if (!_isTyping && mounted) {
      setState(() => _isTyping = true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isTyping = false);
      }
    });
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: isError ? ResQLinkTheme.primaryRed : ResQLinkTheme.safeGreen,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ResQLinkTheme.backgroundDark,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: ResQLinkTheme.cardDark,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.deviceName,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            _isConnected ? 'Connected' : _chatSession?.lastSeenText ?? 'Offline',
            style: TextStyle(
              color: _isConnected ? ResQLinkTheme.safeGreen : Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        if (!_isConnected)
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _reconnectToDevice,
            tooltip: 'Reconnect',
          ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.white),
          color: ResQLinkTheme.cardDark,
          onSelected: (value) async {
            switch (value) {
              case 'device_info':
                _showDeviceInfo();
              case 'clear_chat':
                _showClearChatDialog();
              case 'block_device':
                _showBlockDeviceDialog();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'device_info',
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text('Device Info', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text('Clear Chat', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'block_device',
              child: Row(
                children: [
                  Icon(Icons.block, color: ResQLinkTheme.primaryRed, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Block Device',
                    style: TextStyle(color: ResQLinkTheme.primaryRed),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return LoadingView();
    }

    return Column(
      children: [
        if (!_isConnected) _buildOfflineBanner(),
        Expanded(
          child: ChatView(
            messages: _messages,
            scrollController: _scrollController,
          ),
        ),
        MessageInput(
          controller: _messageController,
          onSendMessage: _sendMessage,
          onSendLocation: _sendLocationMessage,
          onSendLocationP2P: _sendLocationMessage,
          onSendEmergency: _sendEmergencyMessage,
          onTyping: _handleTyping,
          enabled: _isConnected,
        ),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ResQLinkTheme.primaryRed.withValues(alpha: 0.1),  
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: ResQLinkTheme.primaryRed, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Device offline - messages will be queued',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _reconnectToDevice,
            child: Text(
              'RECONNECT',
              style: TextStyle(color: ResQLinkTheme.primaryRed, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeviceInfo() {
    if (_chatSession == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Device Information',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name', _chatSession!.deviceName),
            _buildInfoRow('Device ID', _chatSession!.deviceId),
            _buildInfoRow('Status', _isConnected ? 'Connected' : 'Offline'),
            if (_chatSession!.lastConnectionType != null)
              _buildInfoRow('Last Connection', _chatSession!.lastConnectionType!.displayName),
            _buildInfoRow('Messages', _chatSession!.messageCount.toString()),
            _buildInfoRow('Created', _formatDate(_chatSession!.createdAt)),
            if (_chatSession!.lastConnectionAt != null)
              _buildInfoRow('Last Seen', _formatDate(_chatSession!.lastConnectionAt!)),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Clear Chat History',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to clear all messages in this chat? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop();
              await ChatRepository.deleteSession(widget.sessionId);
              if (mounted) {
                navigator.pop();
              }
            },
            child: Text(
              'Clear',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Text(
          'Block Device',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to block this device? You will no longer receive messages from this device.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop();
              // Implement device blocking logic here
              await ChatRepository.archiveSession(widget.sessionId);
              if (mounted) {
                navigator.pop();
              }
            },
            child: Text(
              'Block',
              style: TextStyle(color: ResQLinkTheme.primaryRed),
            ),
          ),
        ],
      ),
    );
  }
}