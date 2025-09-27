import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:web_socket_channel/io.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../../models/message_model.dart';
import 'p2p_base_service.dart';

class P2PNetworkService {
  final P2PBaseService _baseService;

  final Map<String, Socket> _deviceSockets = {};
  final Map<String, IOWebSocketChannel> _webSocketConnections = {};
  ServerSocket? _hotspotServer;
  HttpServer? _localServer;
  MDnsClient? _mdnsClient;

  bool _isScanning = false;
  Timer? _hotspotScanTimer;
  List<WifiNetwork> _availableHotspots = [];

  P2PNetworkService(this._baseService);

  /// Start network services for hotspot
  Future<void> setupHotspotServices() async {
    try {
      debugPrint('🔧 Setting up hotspot services...');

      // Start TCP server for direct connections
      await _startTcpServer();

      // Start HTTP server for WebSocket connections
      await _startHttpServer();

      // Start mDNS advertising
      await _startMDNSAdvertising();

      debugPrint('✅ Hotspot services started successfully');
    } catch (e) {
      debugPrint('❌ Failed to setup hotspot services: $e');
    }
  }

  Future<bool> sendToDevice(String message, String? targetDeviceId) async {
    if (targetDeviceId == null) {
      debugPrint('⚠️ No target device specified');
      return false;
    }

    try {
      // Try WebSocket first
      for (final entry in _webSocketConnections.entries) {
        if (entry.key.contains(targetDeviceId)) {
          entry.value.sink.add(message);
          debugPrint('✅ Message sent via WebSocket to device: $targetDeviceId');
          return true;
        }
      }

      // Try TCP socket
      if (_deviceSockets.containsKey(targetDeviceId)) {
        _deviceSockets[targetDeviceId]!.write(message);
        _deviceSockets[targetDeviceId]!.flush();
        debugPrint('✅ Message sent via TCP to device: $targetDeviceId');
        return true;
      }

      // Try to find device by scanning connected devices
      for (final socketEntry in _deviceSockets.entries) {
        if (socketEntry.key == targetDeviceId) {
          socketEntry.value.write(message);
          socketEntry.value.flush();
          debugPrint('✅ Message sent to device: $targetDeviceId');
          return true;
        }
      }

      debugPrint('⚠️ No connection found for device: $targetDeviceId');

      // Fallback to broadcast
      await broadcastMessage(MessageModel.fromJson(jsonDecode(message)));
      return false;
    } catch (e) {
      debugPrint('❌ Error sending to device $targetDeviceId: $e');
      return false;
    }
  }

  /// Start TCP server for device connections
  Future<void> _startTcpServer() async {
    try {
      _hotspotServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        P2PBaseService.tcpPort,
      );

      _hotspotServer!.listen((socket) {
        final clientAddress = socket.remoteAddress.address;
        debugPrint('📡 New TCP connection from: $clientAddress');

        _handleTcpConnection(socket, clientAddress);
      });

      debugPrint('✅ TCP server started on port ${P2PBaseService.tcpPort}');
    } catch (e) {
      debugPrint('❌ Failed to start TCP server: $e');
    }
  }

  /// Handle incoming TCP connection
  void _handleTcpConnection(Socket socket, String clientAddress) {
    socket.listen(
      (data) {
        try {
          final message = String.fromCharCodes(data);
          _handleIncomingMessage(message, clientAddress);
        } catch (e) {
          debugPrint('❌ Error processing TCP data: $e');
        }
      },
      onDone: () {
        debugPrint('📡 TCP connection closed: $clientAddress');
        _deviceSockets.remove(clientAddress);
      },
      onError: (error) {
        debugPrint('❌ TCP connection error: $error');
        _deviceSockets.remove(clientAddress);
      },
    );

    _deviceSockets[clientAddress] = socket;
  }

  /// Start HTTP server for WebSocket connections
  Future<void> _startHttpServer() async {
    try {
      _localServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        P2PBaseService.defaultPort,
      );

      _localServer!.listen((request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketConnection(request);
        } else {
          _handleHttpRequest(request);
        }
      });

      debugPrint(
        '✅ HTTP/WebSocket server started on port ${P2PBaseService.defaultPort}',
      );
    } catch (e) {
      debugPrint('❌ Failed to start HTTP server: $e');
    }
  }

  /// Handle WebSocket connection
  void _handleWebSocketConnection(HttpRequest request) async {
    try {
      final webSocket = await WebSocketTransformer.upgrade(request);
      final clientAddress =
          request.connectionInfo?.remoteAddress.address ?? 'unknown';

      debugPrint('📡 New WebSocket connection from: $clientAddress');

      final channel = IOWebSocketChannel(webSocket);
      _webSocketConnections[clientAddress] = channel;

      channel.stream.listen(
        (data) {
          try {
            final message = data.toString();
            _handleIncomingMessage(message, clientAddress);
          } catch (e) {
            debugPrint('❌ Error processing WebSocket data: $e');
          }
        },
        onDone: () {
          debugPrint('📡 WebSocket connection closed: $clientAddress');
          _webSocketConnections.remove(clientAddress);
        },
        onError: (error) {
          debugPrint('❌ WebSocket connection error: $error');
          _webSocketConnections.remove(clientAddress);
        },
      );
    } catch (e) {
      debugPrint('❌ WebSocket upgrade failed: $e');
    }
  }

  /// Handle HTTP request
  void _handleHttpRequest(HttpRequest request) {
    try {
      final response = request.response;
      response.headers.contentType = ContentType.html;

      final deviceInfo = {
        'deviceId': _baseService.deviceId,
        'userName': _baseService.userName,
        'role': _baseService.currentRole.name,
        'emergencyMode': _baseService.emergencyMode,
        'connectedDevices': _baseService.connectedDevices.length,
      };

      response.write('''
        <!DOCTYPE html>
        <html>
        <head><title>ResQLink Device</title></head>
        <body>
          <h1>ResQLink Emergency Device</h1>
          <p>Device ID: ${deviceInfo['deviceId']}</p>
          <p>User: ${deviceInfo['userName']}</p>
          <p>Role: ${deviceInfo['role']}</p>
          <p>Emergency Mode: ${deviceInfo['emergencyMode']}</p>
          <p>Connected Devices: ${deviceInfo['connectedDevices']}</p>
        </body>
        </html>
      ''');

      response.close();
    } catch (e) {
      debugPrint('❌ HTTP request error: $e');
    }
  }

  /// Start mDNS advertising
  Future<void> _startMDNSAdvertising() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      // Advertise ResQLink service
      final serviceName = '${_baseService.userName}_${_baseService.deviceId}';
      debugPrint('📡 Starting mDNS advertising: $serviceName');

      // Note: mDNS advertising implementation would go here
      // This is a placeholder as the actual implementation depends on the mDNS library
    } catch (e) {
      debugPrint('❌ mDNS advertising failed: $e');
    }
  }

  /// Handle incoming message from network
  void _handleIncomingMessage(String rawMessage, String senderAddress) {
    try {
      final data = jsonDecode(rawMessage);

      if (data['type'] == 'handshake') {
        _handleHandshake(data, senderAddress);
      } else if (data['type'] == 'message') {
        _handleMessage(data, senderAddress);
      } else if (data['type'] == 'heartbeat') {
        _handleHeartbeat(data, senderAddress);
      }
    } catch (e) {
      debugPrint('❌ Error handling incoming message: $e');
    }
  }

  /// Handle handshake message
  void _handleHandshake(Map<String, dynamic> data, String senderAddress) {
    try {
      final deviceId = data['deviceId'] as String?;
      final userName = data['userName'] as String?;

      if (deviceId != null && userName != null) {
        _baseService.addConnectedDevice(deviceId, userName);

        // Send handshake response
        final response = jsonEncode({
          'type': 'handshake_response',
          'deviceId': _baseService.deviceId,
          'userName': _baseService.userName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        _sendToAddress(senderAddress, response);
      }
    } catch (e) {
      debugPrint('❌ Error handling handshake: $e');
    }
  }

  /// Handle message
  void _handleMessage(Map<String, dynamic> data, String senderAddress) {
    try {
      final messageData = data['messageData'] != null ?
        Map<String, dynamic>.from(data['messageData'] as Map? ?? {}) : null;
      if (messageData != null) {
        final message = MessageModel.fromNetworkJson(messageData);

        // Check for duplicates
        if (message.messageId != null &&
            _baseService.isMessageProcessed(message.messageId!)) {
          debugPrint('⚠️ Duplicate message ignored: ${message.messageId}');
          return;
        }

        // Save and notify
        _baseService.saveMessageToHistory(message);
        _baseService.onMessageReceived?.call(message);

        debugPrint(
          '📥 Message received: ${message.messageId} from ${message.fromUser}',
        );

        // Send acknowledgment
        final ack = jsonEncode({
          'type': 'acknowledgment',
          'messageId': message.messageId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        _sendToAddress(senderAddress, ack);
      }
    } catch (e) {
      debugPrint('❌ Error handling message: $e');
    }
  }

  /// Handle heartbeat
  void _handleHeartbeat(Map<String, dynamic> data, String senderAddress) {
    try {
      final deviceId = data['deviceId'] as String?;
      if (deviceId != null) {
        // Update device last seen time
        final device = _baseService.connectedDevices[deviceId];
        if (device != null) {
          final updatedDevice = device.copyWith(lastSeen: DateTime.now());
          _baseService.connectedDevices[deviceId] = updatedDevice;
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling heartbeat: $e');
    }
  }

  /// Send message to specific address
  void _sendToAddress(String address, String message) {
    try {
      // Try WebSocket first
      if (_webSocketConnections.containsKey(address)) {
        _webSocketConnections[address]!.sink.add(message);
        return;
      }

      // Try TCP socket
      if (_deviceSockets.containsKey(address)) {
        _deviceSockets[address]!.write(message);
        return;
      }

      debugPrint('⚠️ No connection found for address: $address');
    } catch (e) {
      debugPrint('❌ Error sending to address $address: $e');
    }
  }

  /// Broadcast message to all connected devices
  Future<void> broadcastMessage(MessageModel message) async {
    final messageJson = jsonEncode({
      'type': 'message',
      'messageData': message.toNetworkJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Send via WebSocket connections
    for (final entry in _webSocketConnections.entries) {
      try {
        entry.value.sink.add(messageJson);
        debugPrint('📤 Message sent via WebSocket to: ${entry.key}');
      } catch (e) {
        debugPrint('❌ WebSocket send failed to ${entry.key}: $e');
        _webSocketConnections.remove(entry.key);
      }
    }

    // Send via TCP connections
    for (final entry in _deviceSockets.entries) {
      try {
        entry.value.write(messageJson);
        debugPrint('📤 Message sent via TCP to: ${entry.key}');
      } catch (e) {
        debugPrint('❌ TCP send failed to ${entry.key}: $e');
        _deviceSockets.remove(entry.key);
      }
    }
  }

  /// Scan for ResQLink networks
  Future<List<WifiNetwork>> scanForResQLinkNetworks() async {
    if (_isScanning) {
      debugPrint('⏳ Network scan already in progress');
      return _availableHotspots;
    }

    _isScanning = true;

    try {
      debugPrint('🔍 Scanning for ResQLink networks...');

      // Get available WiFi networks
      final networks = await WiFiForIoTPlugin.loadWifiList();

      // Filter for ResQLink networks
      _availableHotspots = networks
          .where(
            (network) =>
                network.ssid?.startsWith(P2PBaseService.resqlinkPrefix) == true,
          )
          .toList();

      debugPrint('📡 Found ${_availableHotspots.length} ResQLink networks');

      return _availableHotspots;
    } catch (e) {
      debugPrint('❌ Network scan failed: $e');
      return [];
    } finally {
      _isScanning = false;
    }
  }

  


  /// Start periodic network scanning
  void startPeriodicScanning() {
    _hotspotScanTimer = Timer.periodic(Duration(seconds: 30), (_) {
      scanForResQLinkNetworks();
    });
  }

  /// Stop periodic network scanning
  void stopPeriodicScanning() {
    _hotspotScanTimer?.cancel();
    _hotspotScanTimer = null;
  }

  /// Get gateway IP address
  Future<String?> getGatewayIP() async {
    try {
      // Common gateway IPs for mobile hotspots
      final commonGateways = ['192.168.43.1', '192.168.4.1', '10.0.0.1'];

      for (final gateway in commonGateways) {
        try {
          // Try to ping the gateway
          final result = await InternetAddress.lookup(gateway);
          if (result.isNotEmpty) {
            debugPrint('🌐 Found gateway at: $gateway');
            return gateway;
          }
        } catch (e) {
          // Continue to next gateway
          continue;
        }
      }

      debugPrint('⚠️ No gateway IP found');
      return null;
    } catch (e) {
      debugPrint('❌ Error getting gateway IP: $e');
      return null;
    }
  }



  /// Get network status
  Map<String, dynamic> getNetworkStatus() {
    return {
      'tcpServerActive': _hotspotServer != null,
      'httpServerActive': _localServer != null,
      'mdnsActive': _mdnsClient != null,
      'connectedSockets': _deviceSockets.length,
      'webSocketConnections': _webSocketConnections.length,
      'availableHotspots': _availableHotspots.length,
      'isScanning': _isScanning,
    };
  }

  /// Dispose network resources
  void dispose() {
    debugPrint('🗑️ P2P Network Service disposing...');

    stopPeriodicScanning();

    _hotspotServer?.close();
    _localServer?.close();
    _mdnsClient?.stop();

    for (final socket in _deviceSockets.values) {
      socket.close();
    }
    _deviceSockets.clear();

    for (final channel in _webSocketConnections.values) {
      channel.sink.close();
    }
    _webSocketConnections.clear();

    _availableHotspots.clear();
  }

  List<WifiNetwork> get availableNetworks {
    return _availableHotspots
        .where(
          (network) =>
              network.ssid?.startsWith(P2PBaseService.resqlinkPrefix) ?? false,
        )
        .toList();
  }
}
