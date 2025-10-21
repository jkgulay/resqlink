import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/models/message_model.dart';
import '../../messaging/message_router.dart';
import '../../identity_service.dart';

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

  // Callbacks
  Function(String deviceId, String userName)? onDeviceConnected;
  Function(String deviceId, int sequence)? onPongReceived;

  /// Initialize socket protocol with UUID
  void initialize(String deviceId, String userName) {
    _deviceId = deviceId;
    _userName = userName;
    debugPrint('🔧 Socket protocol initialized with UUID: $deviceId');
  }

  /// Update device ID (called after MAC address is stored)
  void updateDeviceId(String newDeviceId) {
    final oldDeviceId = _deviceId;
    _deviceId = newDeviceId;
    debugPrint('🔄 Socket protocol device ID updated: $oldDeviceId → $newDeviceId');
  }

  /// Start socket server
  Future<bool> startServer({int port = defaultPort}) async {
    try {
      if (_isRunning && _serverSocket != null) {
        debugPrint('✅ Socket server already running on port ${_serverSocket!.port}');
        return true;
      }

      // Try the specified port first, then try alternative ports if it fails
      for (int attemptPort = port; attemptPort < port + 10; attemptPort++) {
        try {
          _serverSocket = await ServerSocket.bind(
            InternetAddress.anyIPv4,
            attemptPort,
            shared: true,
          );

          _isRunning = true;
          debugPrint('✅ Socket server started on port $attemptPort');
          break; // Success, exit the loop
        } on SocketException catch (e) {
          // Cross-platform port in use detection:
          // - Linux: error code 98 (EADDRINUSE)
          // - Windows: error code 10048 (WSAEADDRINUSE)
          // - Also check error message as fallback
          final isPortInUse = e.osError?.errorCode == 98 ||
              e.osError?.errorCode == 10048 ||
              e.message.toLowerCase().contains('address already in use') ||
              e.message.toLowerCase().contains('only one usage');

          if (isPortInUse) {
            debugPrint('⚠️ Port $attemptPort already in use, trying next port...');
            if (attemptPort == port + 9) {
              // Last attempt failed
              throw SocketException('All ports from $port to ${port + 9} are in use');
            }
            continue;
          } else {
            rethrow; // Other socket errors
          }
        }
      }

      if (_serverSocket == null) {
        debugPrint('❌ Failed to bind to any port');
        return false;
      }

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
        // Handle different types of connection errors gracefully
        if (error.toString().contains('Connection reset by peer')) {
          debugPrint('🔄 Client connection reset by peer: $clientAddress:$clientPort (normal disconnection)');
        } else if (error.toString().contains('Connection refused')) {
          debugPrint('❌ Client connection refused: $clientAddress:$clientPort');
        } else {
          debugPrint('❌ Client connection error: $error ($clientAddress:$clientPort)');
        }
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
  void _sendHandshake(Socket socket) async {
    debugPrint('🤝 Preparing to send handshake...');

    // Get UUID from IdentityService
    final identity = IdentityService();
    final deviceId = await identity.getDeviceId();

    debugPrint('✅ Sending handshake with UUID: $deviceId, DisplayName: $_userName');

    final handshake = jsonEncode({
      'type': 'handshake',
      'deviceId': deviceId,            // Persistent UUID (unique identifier)
      'displayName': _userName,        // User's chosen name (UI display)
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'protocol_version': '3.0',       // v3.0 = UUID-based identification

      // Legacy fields for backward compatibility with older versions
      'deviceMac': deviceId,
      'macAddress': deviceId,
      'userName': _userName,
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
        case 'ping':
          _handlePing(data, socket);
        case 'pong':
          _handlePong(data, socket);
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
  Future<void> _handleHandshake(Map<String, dynamic> data, Socket socket) async {
    final ipAddress = socket.remoteAddress.address;
    final protocolVersion = data['protocol_version'] ?? '1.0';

    // v3.0+ uses UUID as deviceId
    String? peerDeviceId = data['deviceId'] as String?;
    String? peerDisplayName = data['displayName'] as String?;

    // Legacy fallback for older versions
    if (peerDeviceId == null || peerDeviceId.isEmpty) {
      peerDeviceId = data['deviceMac'] as String? ??
                     data['macAddress'] as String?;
      peerDisplayName = peerDisplayName ?? data['userName'] as String?;
    }

    debugPrint('🤝 Received handshake from $ipAddress');
    debugPrint('   Protocol: $protocolVersion');
    debugPrint('   Peer Device ID: $peerDeviceId');
    debugPrint('   Display Name: $peerDisplayName');

    // Validate device ID exists
    if (peerDeviceId == null || peerDeviceId.isEmpty) {
      debugPrint('❌ REJECTING handshake: No device identifier provided');
      return;
    }

    // Register the socket with the device ID (UUID)
    _deviceSockets[peerDeviceId] = socket;

    debugPrint('🤝 Device connected: $peerDisplayName');
    debugPrint('📍 Device ID: $peerDeviceId');
    debugPrint('📱 Total connected devices: ${_deviceSockets.length}');

    // Notify P2P service about the connected device
    onDeviceConnected?.call(peerDeviceId, peerDisplayName ?? 'Unknown');

    debugPrint('✅ Handshake completed with $peerDisplayName ($peerDeviceId)');

    // Send acknowledgment with our UUID
    final identity = IdentityService();
    final ourDeviceId = await identity.getDeviceId();

    final ack = jsonEncode({
      'type': 'ack',
      'ackType': 'handshake',
      'deviceId': ourDeviceId,           // Our UUID
      'displayName': _userName,          // Our display name
      'peerId': peerDeviceId,            // Acknowledge their UUID
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'protocol_version': '3.0',

      // Legacy fields for backward compatibility
      'deviceMac': ourDeviceId,
      'macAddress': ourDeviceId,
      'userName': _userName,
    });

    _sendToSocket(socket, ack);
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

  /// Handle ping (for quality monitoring)
  void _handlePing(Map<String, dynamic> data, Socket socket) {
    final sequence = data['sequence'] as int?;
    final timestamp = data['timestamp'] as int?;

    if (sequence != null && timestamp != null) {
      final pong = jsonEncode({
        'type': 'pong',
        'sequence': sequence,
        'originalTimestamp': timestamp,
        'deviceId': _deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _sendToSocket(socket, pong);
    }
  }

  /// Handle pong (for quality monitoring)
  void _handlePong(Map<String, dynamic> data, Socket socket) {
    // Find device ID from socket
    String? fromDevice;
    _deviceSockets.forEach((deviceId, deviceSocket) {
      if (deviceSocket == socket) {
        fromDevice = deviceId;
      }
    });

    // Pong responses are handled by the quality monitor through callback
    // We don't process them here directly
    if (fromDevice != null) {
      final sequence = data['sequence'] as int?;
      if (sequence != null && onPongReceived != null) {
        onPongReceived?.call(fromDevice!, sequence);
      }
    }
  }

  /// Handle acknowledgment
  Future<void> _handleAcknowledgment(Map<String, dynamic> data) async {
    final ackType = data['ackType'] as String?;
    final messageId = data['messageId'] as String?;

    // UUID-based system - no need to learn MAC from peers
    if (ackType == 'handshake') {
      debugPrint('✅ Handshake acknowledged');
    }

    if (ackType == 'message' && messageId != null) {
      debugPrint('✅ Message acknowledged: $messageId');
      // Update message status in database
      MessageRepository.updateMessageStatus(messageId, MessageStatus.delivered);
    }
  }

  /// Send message to specific device
  Future<bool> sendMessage(String message, String? targetDeviceId) async {
    try {
      debugPrint('📤 Attempting to send message:');
      debugPrint('  Target: $targetDeviceId');
      debugPrint('  Connected devices: ${_deviceSockets.keys.toList()}');

      // If target specified, send to specific device
      if (targetDeviceId != null &&
          _deviceSockets.containsKey(targetDeviceId)) {
        debugPrint('✅ Sending to specific device: $targetDeviceId');
        final socket = _deviceSockets[targetDeviceId]!;
        return _sendToSocket(socket, message);
      }

      // Otherwise broadcast to all
      debugPrint('📡 Broadcasting message to all devices');
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

    // Clear device sockets and WiFi Direct devices
    _deviceSockets.clear();
    _wifiDirectDevices.clear();

    debugPrint('🛑 Socket protocol stopped');
  }

  /// Force cleanup of existing connections (useful after system changes)
  Future<void> forceCleanup() async {
    debugPrint('🧹 Force cleaning up socket protocol...');

    try {
      // Stop everything first
      await stop();

      // Small delay to ensure cleanup
      await Future.delayed(Duration(milliseconds: 500));

      debugPrint('✅ Socket protocol force cleanup completed');
    } catch (e) {
      debugPrint('⚠️ Error during force cleanup: $e');
    }
  }

  /// Get connection status
  bool get isConnected => _isRunning || _clientSocket != null;

  /// Get connected device count
  int get connectedDeviceCount => _deviceSockets.length;

  /// Register WiFi Direct device as connected (for message sending)
  void registerWiFiDirectDevice(String deviceId, String address) {
    try {
      debugPrint('📱 Registering WiFi Direct device: $deviceId at $address');

      // Store the device as connected without a socket
      // The sendMessage method will be updated to handle WiFi Direct devices
      _wifiDirectDevices[deviceId] = address;

      debugPrint('✅ WiFi Direct device registered for messaging: $deviceId');
    } catch (e) {
      debugPrint('❌ Error registering WiFi Direct device: $e');
    }
  }

  // Track WiFi Direct devices separately
  final Map<String, String> _wifiDirectDevices = {};

  /// Check if device is connected via WiFi Direct
  bool isWiFiDirectDevice(String deviceId) {
    return _wifiDirectDevices.containsKey(deviceId);
  }
}
