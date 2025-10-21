import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../p2p_base_service.dart';
import '../../../models/message_model.dart';
import '../../../features/database/repositories/message_repository.dart';
import '../../messaging/message_router.dart';
import '../../settings_service.dart';
import 'p2p_wifi_direct_handler.dart';
import '../protocols/socket_protocol.dart';

/// Handles message processing, deduplication, routing, and multi-hop forwarding
class P2PMessageHandler {
  final P2PBaseService _baseService;
  final MessageRouter _messageRouter;
  final SocketProtocol _socketProtocol;
  final P2PWiFiDirectHandler _wifiDirectHandler;

  // Message tracing for debugging
  final List<String> _messageTrace = [];

  // Message deduplication
  final Set<String> _processedMessages = {};
  final Map<String, DateTime> _messageTimestamps = {};
  static const Duration _messageDedupWindow = Duration(seconds: 5);

  // Callbacks
  void Function(MessageModel)? onMessageProcessed;
  String? Function(String ipAddress)? onResolveIpToMac;

  P2PMessageHandler(
    this._baseService,
    this._messageRouter,
    this._socketProtocol,
    this._wifiDirectHandler,
  ) {
    _messageRouter.setGlobalListener(_handleGlobalMessage);
  }

  /// Handle incoming WiFi Direct message with deduplication
  Future<void> handleIncomingMessage(String message, String? from) async {
    try {
      debugPrint('📨 Processing WiFi Direct message: $message from: $from');

      // Check for duplicates
      final messageHash = '${from}_${message.hashCode}';
      _cleanupMessageDeduplication();

      final now = DateTime.now();
      final existingTimestamp = _messageTimestamps[messageHash];
      if (existingTimestamp != null) {
        final timeDiff = now.difference(existingTimestamp).inSeconds;
        if (timeDiff < 5) {
          debugPrint(
            '⚠️ Duplicate WiFi Direct message blocked: $messageHash',
          );
          return;
        }
      }

      // Mark as processed
      _processedMessages.add(messageHash);
      _messageTimestamps[messageHash] = now;

      // CRITICAL: Resolve IP to MAC address before routing
      String? resolvedMac;
      if (onResolveIpToMac != null && from != null) {
        // Extract IP from "/192.168.49.1:8889" format
        final ipMatch = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(from);
        if (ipMatch != null) {
          final ipAddress = ipMatch.group(1)!;
          resolvedMac = onResolveIpToMac!(ipAddress);
          if (resolvedMac != null) {
            debugPrint('🔍 Resolved message sender IP $ipAddress to MAC: $resolvedMac');
          }
        }
      }

      // Use resolved MAC if available, otherwise use raw from address
      final deviceIdentifier = resolvedMac ?? from ?? 'unknown';

      // Parse message to check if it's a handshake
      try {
        final messageData = jsonDecode(message);
        final messageType = messageData['type'] as String?;

        if (messageType == 'handshake') {
          await _handleHandshake(messageData, from);
          return;
        }

        if (messageType == 'handshake_response') {
          await _handleHandshakeResponse(messageData, from);
          return;
        }
      } catch (parseError) {
        // If not JSON or not a handshake, continue with normal processing
      }

      // Route through MessageRouter for non-handshake messages
      // CRITICAL: Pass resolved MAC address, not raw IP/port
      await _messageRouter.routeRawMessage(message, deviceIdentifier);

      _addMessageTrace('WiFi Direct message routed successfully');
      debugPrint('✅ WiFi Direct message routed successfully via MessageRouter');
    } catch (e) {
      debugPrint('❌ Error routing message: $e');
      _addMessageTrace('Failed to route message: $e');

      // Fallback to direct processing if routing fails
      try {
        await _fallbackMessageProcessing(message, from);
      } catch (fallbackError) {
        debugPrint('❌ Fallback message processing also failed: $fallbackError');
      }
    }
  }

  /// Handle handshake message
  Future<void> _handleHandshake(
    Map<String, dynamic> messageData,
    String? from,
  ) async {
    final deviceId = messageData['deviceId'] as String?;
    final macAddress = messageData['macAddress'] as String?;
    final userName = messageData['userName'] as String?;
    final deviceName = messageData['deviceName'] as String?;

    // CRITICAL: Try to resolve the real MAC address from the IP
    String? resolvedMac;
    if (onResolveIpToMac != null && from != null) {
      // Extract IP from "/192.168.49.1:8889" format
      final ipMatch = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(from);
      if (ipMatch != null) {
        final ipAddress = ipMatch.group(1)!;
        resolvedMac = onResolveIpToMac!(ipAddress);
        if (resolvedMac != null) {
          debugPrint('🔍 Resolved WiFi Direct IP $ipAddress to MAC: $resolvedMac');
        }
      }
    }

    // Priority for device identifier:
    // 1. Resolved MAC from WiFi Direct peer list (most reliable)
    // 2. MAC address from handshake
    // 3. Device ID from handshake
    final finalDeviceId = resolvedMac ?? macAddress ?? deviceId;

    if (finalDeviceId != null) {
      debugPrint(
        '🤝 Processing WiFi Direct handshake from $userName',
      );
      debugPrint('📱 Device ID (from handshake): $deviceId');
      debugPrint('📍 MAC Address (from handshake): $macAddress');
      debugPrint('🔍 Resolved MAC (from WiFi Direct): $resolvedMac');
      debugPrint('✅ Using final identifier: $finalDeviceId');

      // Register device (async)
      await _wifiDirectHandler.registerWiFiDirectDevice(
        finalDeviceId,
        userName ?? 'Unknown',
        deviceName ?? 'Unknown Device',
        from,
      );

      // Send handshake response (async)
      await _wifiDirectHandler.sendHandshakeResponse(finalDeviceId, from);
    }
  }

  /// Handle handshake response message
  Future<void> _handleHandshakeResponse(
    Map<String, dynamic> messageData,
    String? from,
  ) async {
    final deviceId = messageData['deviceId'] as String?;
    final macAddress = messageData['macAddress'] as String?;
    final userName = messageData['userName'] as String?;
    final deviceName = messageData['deviceName'] as String?;

    // CRITICAL: Try to resolve the real MAC address from the IP
    String? resolvedMac;
    if (onResolveIpToMac != null && from != null) {
      // Extract IP from "/192.168.49.1:8889" format
      final ipMatch = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(from);
      if (ipMatch != null) {
        final ipAddress = ipMatch.group(1)!;
        resolvedMac = onResolveIpToMac!(ipAddress);
        if (resolvedMac != null) {
          debugPrint('🔍 Resolved WiFi Direct response IP $ipAddress to MAC: $resolvedMac');
        }
      }
    }

    // Priority for device identifier:
    // 1. Resolved MAC from WiFi Direct peer list (most reliable)
    // 2. MAC address from handshake
    // 3. Device ID from handshake
    final finalDeviceId = resolvedMac ?? macAddress ?? deviceId;

    if (finalDeviceId != null) {
      debugPrint(
        '🤝 Processing WiFi Direct handshake response from $userName',
      );
      debugPrint('📱 Device ID (from handshake): $deviceId');
      debugPrint('📍 MAC Address (from handshake): $macAddress');
      debugPrint('🔍 Resolved MAC (from WiFi Direct): $resolvedMac');
      debugPrint('✅ Using final identifier: $finalDeviceId');

      // Register device (async)
      await _wifiDirectHandler.registerWiFiDirectDevice(
        finalDeviceId,
        userName ?? 'Unknown',
        deviceName ?? 'Unknown Device',
        from,
      );
    }
  }

  /// Fallback message processing if router fails
  Future<void> _fallbackMessageProcessing(String message, String? from) async {
    final messageData = Map<String, dynamic>.from(json.decode(message));

    final messageText = messageData['message'] as String? ?? message;
    final senderName =
        messageData['senderName'] as String? ?? 'WiFi Direct User';
    final messageType = MessageType.values.firstWhere(
      (type) => type.name == messageData['messageType'],
      orElse: () => MessageType.text,
    );

    final messageModel = MessageModel.createDirectMessage(
      fromUser: senderName,
      message: messageText,
      deviceId: messageData['deviceId'] ?? 'unknown',
      targetDeviceId: _baseService.deviceId ?? 'unknown',
      type: messageType,
      isEmergency:
          messageType == MessageType.emergency ||
          messageType == MessageType.sos,
    );

    await MessageRepository.insertMessage(messageModel);
    _baseService.saveMessageToHistory(messageModel);

    debugPrint('✅ Fallback message processing completed');
  }

  /// Send message via appropriate protocol
  Future<bool> sendMessage({
    required String message,
    required MessageType type,
    String? targetDeviceId,
    double? latitude,
    double? longitude,
    String? senderName,
    String? id,
    int? ttl,
    List<String>? routePath,
  }) async {
    try {
      _addMessageTrace('Sending message: $message (type: ${type.name})');

      final actualSenderName = _baseService.userName ?? senderName ?? 'Unknown User';
      debugPrint('📤 Sending message: "$message" from: $actualSenderName');

      // Create message model
      final messageModel = targetDeviceId != null
          ? MessageModel.createDirectMessage(
              fromUser: actualSenderName,
              message: message,
              deviceId: _baseService.deviceId!,
              targetDeviceId: targetDeviceId,
              type: type,
              isEmergency:
                  type == MessageType.emergency || type == MessageType.sos,
              latitude: latitude,
              longitude: longitude,
            )
          : MessageModel.createBroadcastMessage(
              fromUser: actualSenderName,
              message: message,
              deviceId: _baseService.deviceId!,
              type: type,
              isEmergency:
                  type == MessageType.emergency || type == MessageType.sos,
              latitude: latitude,
              longitude: longitude,
            );

      // Save to database first
      await MessageRepository.insertMessage(messageModel);
      _baseService.saveMessageToHistory(messageModel);

      // Create message JSON for network transmission
      final messageJson = jsonEncode({
        'type': 'message',
        'messageId': messageModel.messageId,
        'message': message,
        'senderName': actualSenderName,
        'deviceId': _baseService.deviceId,
        'targetDeviceId': targetDeviceId,
        'messageType': type.name,
        'timestamp': messageModel.timestamp,
        'isEmergency': type == MessageType.emergency || type == MessageType.sos,
        'latitude': latitude,
        'longitude': longitude,
        'ttl': ttl ?? P2PBaseService.maxTtl,
        'routePath': routePath ?? [_baseService.deviceId!],
      });

      // Check if connected and has actual peer connections
      if (!_baseService.isConnected || _baseService.connectedDevices.isEmpty) {
        debugPrint('📥 Device not connected or no peers available, message will not be sent');
        debugPrint('  - Connection status: ${_baseService.isConnected}');
        debugPrint('  - Connected devices: ${_baseService.connectedDevices.length}');

        await MessageRepository.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.failed,
        );

        _addMessageTrace('Message failed - no active peer connections');
        throw Exception('No active peer connections available');
      }

      bool success = false;

      // Send via appropriate protocol with fallback strategy
      final hasConnectedDevices = _baseService.connectedDevices.isNotEmpty;

      if (hasConnectedDevices && _wifiDirectHandler.wifiDirectService != null) {
        // Try WiFi Direct first
        success = await _wifiDirectHandler.sendMessage(messageJson);
        debugPrint('📡 WiFi Direct send result: $success');

        // Fallback to socket protocol if WiFi Direct failed
        if (!success) {
          debugPrint('⚠️ WiFi Direct send failed, attempting socket protocol fallback...');
          if (targetDeviceId != null) {
            success = await _socketProtocol.sendMessage(
              messageJson,
              targetDeviceId,
            );
            debugPrint('📡 Socket protocol send result: $success');
          } else {
            success = await _socketProtocol.broadcastMessage(messageJson);
            debugPrint('📡 Socket protocol broadcast result: $success');
          }
        }
      } else {
        // Use socket protocol directly if WiFi Direct not available
        debugPrint('📡 Using socket protocol (WiFi Direct unavailable)');
        if (targetDeviceId != null) {
          success = await _socketProtocol.sendMessage(
            messageJson,
            targetDeviceId,
          );
        } else {
          success = await _socketProtocol.broadcastMessage(messageJson);
        }
      }

      if (success) {
        await MessageRepository.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.sent,
        );
        _addMessageTrace(
          'Message sent successfully: ${messageModel.messageId}',
        );
      } else {
        debugPrint('❌ Primary send failed');

        await MessageRepository.updateMessageStatus(
          messageModel.messageId!,
          MessageStatus.failed,
        );

        _addMessageTrace('Message send failed');
        throw Exception('Message send failed');
      }

      debugPrint('✅ Message processing completed');
      return true;
    } catch (e) {
      _addMessageTrace('Message send failed: $e');
      debugPrint('❌ Message send failed: $e');
      rethrow;
    }
  }

  /// Handle global messages from message router
  void _handleGlobalMessage(MessageModel message) {
    _baseService.onMessageReceived?.call(message);
    _baseService.saveMessageToHistory(message);

    // Multi-hop: Forward message to other connected devices if applicable
    _maybeForwardMessage(message);

    onMessageProcessed?.call(message);
  }

  /// Multi-hop message forwarding logic
  Future<void> _maybeForwardMessage(MessageModel message) async {
    try {
      // Check if multi-hop is enabled
      final settings = SettingsService.instance;
      if (!settings.multiHopEnabled) {
        debugPrint('🚫 Multi-hop disabled, not forwarding message');
        return;
      }

      // Don't forward messages from ourselves
      if (message.deviceId == _baseService.deviceId) {
        debugPrint('ℹ️ Message is from us, not forwarding');
        return;
      }

      // Only forward emergency and broadcast messages
      if (!message.isEmergency && message.targetDeviceId != null) {
        debugPrint('ℹ️ Message is not emergency/broadcast, not forwarding');
        return;
      }

      // Check TTL (time-to-live / hop count)
      final currentTtl = message.ttl ?? P2PBaseService.maxTtl;
      if (currentTtl <= 1) {
        debugPrint('⏱️ Message TTL expired ($currentTtl), not forwarding');
        return;
      }

      // Check if we've already forwarded this message (prevent loops)
      final routePath = message.routePath ?? [];
      if (routePath.contains(_baseService.deviceId)) {
        debugPrint('🔄 We already forwarded this message, skipping to prevent loop');
        return;
      }

      // Get other connected devices (exclude the sender)
      final otherDevices = _baseService.connectedDevices.keys
          .where((id) => id != message.deviceId && id != _baseService.deviceId)
          .toList();

      if (otherDevices.isEmpty) {
        debugPrint('📭 No other devices to forward to');
        return;
      }

      debugPrint('🔁 Forwarding message to ${otherDevices.length} device(s) (TTL: $currentTtl → ${currentTtl - 1})');

      // Create forwarded message with decremented TTL and updated route path
      final updatedRoutePath = [...routePath, _baseService.deviceId!];
      final forwardedMessageJson = jsonEncode({
        'type': 'message',
        'messageId': message.messageId,
        'message': message.message,
        'senderName': message.fromUser,
        'deviceId': message.deviceId,  // Original sender
        'targetDeviceId': message.targetDeviceId,
        'messageType': message.messageType.name,
        'timestamp': message.timestamp,
        'isEmergency': message.isEmergency,
        'latitude': message.latitude,
        'longitude': message.longitude,
        'ttl': currentTtl - 1,
        'routePath': updatedRoutePath,
      });

      // Forward to all other connected devices with fallback strategy
      bool forwardSuccess = false;

      // Try WiFi Direct first if available
      if (_wifiDirectHandler.wifiDirectService != null) {
        forwardSuccess = await _wifiDirectHandler.sendMessage(forwardedMessageJson);
        debugPrint('📡 WiFi Direct forward result: $forwardSuccess');

        // Fallback to socket protocol if WiFi Direct failed
        if (!forwardSuccess) {
          debugPrint('⚠️ WiFi Direct forward failed, attempting socket protocol fallback...');
          forwardSuccess = await _socketProtocol.broadcastMessage(forwardedMessageJson);
          debugPrint('📡 Socket protocol forward result: $forwardSuccess');
        }
      } else {
        // Use socket protocol directly if WiFi Direct not available
        debugPrint('📡 Using socket protocol for forwarding (WiFi Direct unavailable)');
        forwardSuccess = await _socketProtocol.broadcastMessage(forwardedMessageJson);
      }

      if (forwardSuccess) {
        debugPrint('✅ Message forwarded successfully (hops: ${updatedRoutePath.length})');
        _addMessageTrace('Forwarded message ${message.messageId} (TTL: ${currentTtl - 1})');
      } else {
        debugPrint('❌ Failed to forward message');
      }
    } catch (e) {
      debugPrint('❌ Error forwarding message: $e');
    }
  }

  /// Clean up old message deduplication entries
  void _cleanupMessageDeduplication() {
    final cutoff = DateTime.now().subtract(_messageDedupWindow);
    final toRemove = <String>[];

    _messageTimestamps.forEach((messageHash, timestamp) {
      if (timestamp.isBefore(cutoff)) {
        toRemove.add(messageHash);
      }
    });

    for (final messageHash in toRemove) {
      _processedMessages.remove(messageHash);
      _messageTimestamps.remove(messageHash);
    }

    if (toRemove.isNotEmpty) {
      debugPrint(
        '🧹 Cleaned up ${toRemove.length} old message entries from WiFi Direct deduplication',
      );
    }
  }

  /// Add message trace for debugging
  void _addMessageTrace(String trace) {
    final timestamp = DateTime.now().toIso8601String();
    _messageTrace.add('[$timestamp] $trace');

    // Keep only last 100 entries
    if (_messageTrace.length > 100) {
      _messageTrace.removeAt(0);
    }
  }

  /// Get message trace for debugging
  List<String> getMessageTrace() => List.from(_messageTrace);

  /// Get message router for external access
  MessageRouter get messageRouter => _messageRouter;

  /// Dispose and cleanup
  void dispose() {
    _messageTrace.clear();
    _processedMessages.clear();
    _messageTimestamps.clear();
    debugPrint('🗑️ Message handler disposed');
  }
}
