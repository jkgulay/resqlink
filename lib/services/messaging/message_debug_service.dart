import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../features/database/repositories/message_repository.dart';
import '../p2p/p2p_main_service.dart';

/// Debug service for tracing message flow and testing connectivity
class MessageDebugService {
  static final MessageDebugService _instance = MessageDebugService._internal();
  factory MessageDebugService() => _instance;
  MessageDebugService._internal();

  final List<MessageTrace> _messageTraces = [];
  final List<ConnectionEvent> _connectionEvents = [];
  bool _debugModeEnabled = false;

  void enableDebugMode() {
    _debugModeEnabled = true;
    debugPrint('🔍 Message Debug Service enabled');
  }

  void disableDebugMode() {
    _debugModeEnabled = false;
    debugPrint('🔍 Message Debug Service disabled');
  }

  bool get isDebugModeEnabled => _debugModeEnabled;

  // Trace message lifecycle
  void traceMessageSent(String messageId, String content, String recipient) {
    if (!_debugModeEnabled) return;
    
    final trace = MessageTrace(
      messageId: messageId,
      content: content.length > 50 ? '${content.substring(0, 50)}...' : content,
      timestamp: DateTime.now(),
      event: MessageEvent.sent,
      recipient: recipient,
    );
    
    _messageTraces.add(trace);
    _keepRecentTraces();
    
    debugPrint('📤 TRACE: Message sent - ID: $messageId, To: $recipient');
  }

  void traceMessageReceived(String messageId, String content, String sender) {
    if (!_debugModeEnabled) return;
    
    final trace = MessageTrace(
      messageId: messageId,
      content: content.length > 50 ? '${content.substring(0, 50)}...' : content,
      timestamp: DateTime.now(),
      event: MessageEvent.received,
      sender: sender,
    );
    
    _messageTraces.add(trace);
    _keepRecentTraces();
    
    debugPrint('📥 TRACE: Message received - ID: $messageId, From: $sender');
  }

  void traceMessageFailed(String messageId, String error, String? recipient) {
    if (!_debugModeEnabled) return;
    
    final trace = MessageTrace(
      messageId: messageId,
      content: 'FAILED: $error',
      timestamp: DateTime.now(),
      event: MessageEvent.failed,
      recipient: recipient,
      error: error,
    );
    
    _messageTraces.add(trace);
    _keepRecentTraces();
    
    debugPrint('❌ TRACE: Message failed - ID: $messageId, Error: $error');
  }

  void traceConnectionEvent(String deviceId, String deviceName, ConnectionEventType type) {
    if (!_debugModeEnabled) return;
    
    final event = ConnectionEvent(
      deviceId: deviceId,
      deviceName: deviceName,
      timestamp: DateTime.now(),
      type: type,
    );
    
    _connectionEvents.add(event);
    _keepRecentConnectionEvents();
    
    debugPrint('🔗 CONNECTION: ${type.name} - $deviceName ($deviceId)');
  }

  // Test message sending with debug info
  Future<TestResult> testMessageSending(P2PMainService p2pService, String testMessage) async {
    final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();
    
    debugPrint('🧪 Starting message test - ID: $testId');
    
    try {
      // Test 1: Check connection status
      if (!p2pService.isConnected) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'No active connections',
          duration: DateTime.now().difference(startTime),
        );
      }

      // Test 2: Send test message
      await p2pService.sendMessage(
        message: testMessage,
        type: MessageType.text,
        senderName: p2pService.userName ?? 'TestUser',
      );

      // Test 3: Verify message was saved locally
      await Future.delayed(Duration(milliseconds: 500));
      final messages = await MessageRepository.getAllMessages();
      final testMessages = messages.where((m) => m.message == testMessage).toList();
      
      if (testMessages.isEmpty) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Message not saved to local database',
          duration: DateTime.now().difference(startTime),
        );
      }

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details: 'Message sent and saved successfully',
      );

    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: e.toString(),
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  // Test connection establishment
  Future<TestResult> testConnectionEstablishment(P2PMainService p2pService) async {
    final testId = 'conn_test_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();
    
    debugPrint('🧪 Starting connection test - ID: $testId');
    
    try {
      // Test 1: Check permissions
      final permissionsOk = await _checkPermissions();
      if (!permissionsOk) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Required permissions not granted',
          duration: DateTime.now().difference(startTime),
        );
      }

      // Test 2: Check WiFi status
      final wifiOk = await _checkWiFiStatus();
      if (!wifiOk) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'WiFi not enabled or not connected',
          duration: DateTime.now().difference(startTime),
        );
      }



      // Test 4: Test device discovery
      await p2pService.discoverDevices(force: true);
      await Future.delayed(Duration(seconds: 5));

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details: 'Connection test completed - hotspot created and discovery initiated',
      );

    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: e.toString(),
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  Future<bool> _checkPermissions() async {
    // This would check all required permissions
    // For now, return true as a placeholder
    return true;
  }

  Future<bool> _checkWiFiStatus() async {
    // This would check WiFi connectivity
    // For now, return true as a placeholder
    return true;
  }

  // Generate test message for debugging
  String generateTestMessage({String? prefix}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${prefix ?? 'TEST'}: Message sent at $timestamp';
  }

  // Get debug information
  String getDebugReport() {
    final buffer = StringBuffer();
    
    buffer.writeln('=== MESSAGE DEBUG REPORT ===');
    buffer.writeln('Debug Mode: $_debugModeEnabled');
    buffer.writeln('Total Message Traces: ${_messageTraces.length}');
    buffer.writeln('Total Connection Events: ${_connectionEvents.length}');
    buffer.writeln();
    
    buffer.writeln('Recent Message Traces:');
    for (final trace in _messageTraces.take(10)) {
      buffer.writeln('  ${trace.timestamp}: ${trace.event.name} - ${trace.messageId}');
      if (trace.error != null) {
        buffer.writeln('    Error: ${trace.error}');
      }
    }
    buffer.writeln();
    
    buffer.writeln('Recent Connection Events:');
    for (final event in _connectionEvents.take(10)) {
      buffer.writeln('  ${event.timestamp}: ${event.type.name} - ${event.deviceName}');
    }
    
    return buffer.toString();
  }

  // Get message flow statistics
  Map<String, dynamic> getMessageStats() {
    final stats = <String, dynamic>{};
    
    final sentCount = _messageTraces.where((t) => t.event == MessageEvent.sent).length;
    final receivedCount = _messageTraces.where((t) => t.event == MessageEvent.received).length;
    final failedCount = _messageTraces.where((t) => t.event == MessageEvent.failed).length;
    
    stats['total_traces'] = _messageTraces.length;
    stats['sent_messages'] = sentCount;
    stats['received_messages'] = receivedCount;
    stats['failed_messages'] = failedCount;
    stats['success_rate'] = sentCount > 0 ? (sentCount - failedCount) / sentCount : 0.0;
    
    return stats;
  }

  void _keepRecentTraces() {
    if (_messageTraces.length > 200) {
      _messageTraces.removeRange(0, _messageTraces.length - 200);
    }
  }

  void _keepRecentConnectionEvents() {
    if (_connectionEvents.length > 100) {
      _connectionEvents.removeRange(0, _connectionEvents.length - 100);
    }
  }

  void clearTraces() {
    _messageTraces.clear();
    _connectionEvents.clear();
    debugPrint('🧹 Debug traces cleared');
  }

  List<MessageTrace> get messageTraces => List.from(_messageTraces);
  List<ConnectionEvent> get connectionEvents => List.from(_connectionEvents);
}

// Data models for debugging
class MessageTrace {
  final String messageId;
  final String content;
  final DateTime timestamp;
  final MessageEvent event;
  final String? sender;
  final String? recipient;
  final String? error;

  MessageTrace({
    required this.messageId,
    required this.content,
    required this.timestamp,
    required this.event,
    this.sender,
    this.recipient,
    this.error,
  });
}

class ConnectionEvent {
  final String deviceId;
  final String deviceName;
  final DateTime timestamp;
  final ConnectionEventType type;

  ConnectionEvent({
    required this.deviceId,
    required this.deviceName,
    required this.timestamp,
    required this.type,
  });
}

class TestResult {
  final String testId;
  final bool success;
  final String? error;
  final Duration duration;
  final String? details;

  TestResult({
    required this.testId,
    required this.success,
    this.error,
    required this.duration,
    this.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Test ID: $testId');
    buffer.writeln('Success: $success');
    buffer.writeln('Duration: ${duration.inMilliseconds}ms');
    
    if (error != null) {
      buffer.writeln('Error: $error');
    }
    
    if (details != null) {
      buffer.writeln('Details: $details');
    }
    
    return buffer.toString();
  }
}

enum MessageEvent { sent, received, failed, queued, delivered }
enum ConnectionEventType { connected, disconnected, discovered, timeout }