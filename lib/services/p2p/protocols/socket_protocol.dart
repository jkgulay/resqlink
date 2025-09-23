import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/models/message_model.dart';
import '../../messaging/message_router.dart';

class SocketProtocol {
  static const int defaultPort= 8888;
  static const int bufferSize = 4096;

  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _connectedClients = [];
  final Map<String, Socket> _deviceSockets = {};

  final MessageRouter _messageRouter = MessageRouter();
  StreamSubscription? _serverSubscription;
  final Map<Socket, StreamSubscription> _clientSubscriptions = {};

  bool _isRunning = false;
  String? _deviceId;
  String? _userName;

  // CRITICAL: Callback for device connections
  Function(String deviceId, String userName)? onDeviceConnected;

  /// Initialize socket protocol
  void initialize(String deviceId, String userName) {
    _deviceId = deviceId;
    _userName = userName;
  }

  /// Start socket server
  Future<bool> startServer({int port = defaultPort}) async {
    try {
      if (_isRunning) {
        debugPrint('⚠️ Socket server already running');
        return true;
      }

      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      _isRunning = true;
      debugPrint('✅ Socket server started on port $port');

      _serverSubscription = _serverSocket!.listen(
        _handleClientConnection,
        onError: (error) {
          debugPrint('❌ Server error: $error');
        },
        onDone: () {
          debugPrint('🔚 Server stopped');
          _isRunning = false;
        },
      );

      return true;
    } catch (e) {
      debugPrint('❌ Failed to start server: $e');
      return false;
    }
  }

  /// Handle new client connection
  void _handleClientConnection(Socket client) {
    final clientAddress = client.remoteAddress.address;
    final clientPort = client.remotePort;

    debugPrint('👤 New client connected: $clientAddress:$clientPort');

    _connectedClients.add(client);

    // Send handshake
    _sendHandshake(client);

    // Listen for messages
    final subscription = client.listen(
      (Uint8List data) => _handleSocketData(data, client),
      onError: (error) {
        debugPrint('❌ Client error: $error');
        _removeClient(client);
      },
      onDone: () {
        debugPrint('👋 Client disconnected: $clientAddress:$clientPort');
        _removeClient(client);
      },
      cancelOnError: false,
    );

    _clientSubscriptions[client] = subscription;
  }

  /// Connect to server as client
  Future<bool> connectToServer(
    String address, {
    int port = defaultPort,
  }) async {
    try {
      if (_clientSocket != null) {
        debugPrint('⚠️ Already connected as client');
        return true;
      }

      _clientSocket = await Socket.connect(
        address,
        port,
        timeout: Duration(seconds: 10),
      );

      debugPrint('✅ Connected to server: $address:$port');

      // Send handshake
      _sendHandshake(_clientSocket!);

      // Listen for messages
      _clientSocket!.listen(
        (Uint8List data) => _handleSocketData(data, _clientSocket!),
        onError: (error) {
          debugPrint('❌ Connection error: $error');
          _disconnectClient();
        },
        onDone: () {
          debugPrint('🔚 Disconnected from server');
          _disconnectClient();
        },
        cancelOnError: false,
      );

      return true;
    } catch (e) {
      debugPrint('❌ Failed to connect: $e');
      return false;
    }
  }

  /// Send handshake message
  void _sendHandshake(Socket socket) {
    final handshake = jsonEncode({
      'type': 'handshake',
      'deviceId': _deviceId,
      'userName': _userName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    _sendToSocket(socket, handshake);
  }

  /// Handle incoming socket data
  void _handleSocketData(Uint8List data, Socket socket) {
    try {
      final message = utf8.decode(data);
      final lines = message.split('\n').where((line) => line.isNotEmpty);

      for (final line in lines) {
        _processMessage(line, socket);
      }
    } catch (e) {
      debugPrint('❌ Error processing socket data: $e');
    }
  }

  /// Process individual message
  void _processMessage(String message, Socket socket) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;

      switch (type) {
        case 'handshake':
          _handleHandshake(data, socket);
        case 'message':
          _handleMessage(data, socket);
        case 'heartbeat':
          _handleHeartbeat(data, socket);
        case 'ack':
          _handleAcknowledgment(data);
        default:
          debugPrint('⚠️ Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('❌ Error processing message: $e');
    }
  }

  /// Handle handshake message
  void _handleHandshake(Map<String, dynamic> data, Socket socket) {
    final deviceId = data['deviceId'] as String?;
    final userName = data['userName'] as String?;

    if (deviceId != null) {
      _deviceSockets[deviceId] = socket;

      // CRITICAL: Notify P2P service about the connected device
      onDeviceConnected?.call(deviceId, userName ?? 'Unknown');

      debugPrint('🤝 Handshake completed with $userName ($deviceId)');

      // Send acknowledgment
      final ack = jsonEncode({
        'type': 'ack',
        'ackType': 'handshake',
        'deviceId': _deviceId,
        'userName': _userName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _sendToSocket(socket, ack);
    }
  }

  /// Handle regular message
  void _handleMessage(Map<String, dynamic> data, Socket socket) {
    // Find device ID from socket
    String? fromDevice;
    _deviceSockets.forEach((deviceId, deviceSocket) {
      if (deviceSocket == socket) {
        fromDevice = deviceId;
      }
    });

    // Route message
    _messageRouter.routeRawMessage(jsonEncode(data), fromDevice);

    // Send acknowledgment
    final messageId = data['messageId'] as String?;
    if (messageId != null) {
      final ack = jsonEncode({
        'type': 'ack',
        'ackType': 'message',
        'messageId': messageId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _sendToSocket(socket, ack);
    }
  }

  /// Handle heartbeat
  void _handleHeartbeat(Map<String, dynamic> data, Socket socket) {
    final pong = jsonEncode({
      'type': 'heartbeat',
      'subtype': 'pong',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    _sendToSocket(socket, pong);
  }

  /// Handle acknowledgment
  void _handleAcknowledgment(Map<String, dynamic> data) {
    final ackType = data['ackType'] as String?;
    final messageId = data['messageId'] as String?;

    if (ackType == 'message' && messageId != null) {
      debugPrint('✅ Message acknowledged: $messageId');
      // Update message status in database
      MessageRepository.updateMessageStatus(messageId, MessageStatus.delivered);
    }
  }

  /// Send message to specific device
  Future<bool> sendMessage(String message, String? targetDeviceId) async {
    try {
      // If target specified, send to specific device
      if (targetDeviceId != null &&
          _deviceSockets.containsKey(targetDeviceId)) {
        final socket = _deviceSockets[targetDeviceId]!;
        return _sendToSocket(socket, message);
      }

      // Otherwise broadcast to all
      return broadcastMessage(message);
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }

  /// Broadcast message to all connected clients
  Future<bool> broadcastMessage(String message) async {
    try {
      bool success = false;

      // Send to all connected clients (if server)
      for (final client in _connectedClients) {
        if (_sendToSocket(client, message)) {
          success = true;
        }
      }

      // Send to server (if client)
      if (_clientSocket != null) {
        if (_sendToSocket(_clientSocket!, message)) {
          success = true;
        }
      }

      return success;
    } catch (e) {
      debugPrint('❌ Error broadcasting message: $e');
      return false;
    }
  }

  /// Send data to socket
  bool _sendToSocket(Socket socket, String data) {
    try {
      socket.writeln(data);
      socket.flush();
      return true;
    } catch (e) {
      debugPrint('❌ Error sending to socket: $e');
      return false;
    }
  }

  /// Remove client from connections
  void _removeClient(Socket client) {
    _connectedClients.remove(client);
    _clientSubscriptions[client]?.cancel();
    _clientSubscriptions.remove(client);

    // Remove from device sockets
    _deviceSockets.removeWhere((_, socket) => socket == client);

    try {
      client.close();
    } catch (_) {}
  }

  /// Disconnect client connection
  void _disconnectClient() {
    _clientSocket?.close();
    _clientSocket = null;
  }

  /// Stop socket server/client
  Future<void> stop() async {
    _isRunning = false;

    // Close all client connections
    for (final client in _connectedClients) {
      _removeClient(client);
    }
    _connectedClients.clear();

    // Cancel server subscription
    await _serverSubscription?.cancel();

    // Close server socket
    await _serverSocket?.close();
    _serverSocket = null;

    // Disconnect as client
    _disconnectClient();

    // Clear device sockets
    _deviceSockets.clear();

    debugPrint('🛑 Socket protocol stopped');
  }

  /// Get connection status
  bool get isConnected => _isRunning || _clientSocket != null;

  /// Get connected device count
  int get connectedDeviceCount => _deviceSockets.length;
}
