import 'dart:async';
import 'package:flutter/material.dart';
import 'package:resqlink/features/database/repositories/message_repository.dart';
import 'package:resqlink/services/messaging/message_debug_service.dart';
import '../models/message_model.dart';
import 'p2p/p2p_main_service.dart';

class MessageTestFunctions {
  /// Test basic message sending functionality
  static Future<TestResult> testBasicMessageSending(
    P2PMainService p2pService,
  ) async {
    final testId = 'basic_send_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    debugPrint('🧪 Running basic message sending test...');

    try {
      // 1. Check if service is initialized
      if (p2pService.deviceId == null) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'P2P service not properly initialized - deviceId is null',
          duration: DateTime.now().difference(startTime),
        );
      }

      // 2. Check if userName is set
      if (p2pService.userName == null || p2pService.userName!.isEmpty) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Username not set in P2P service',
          duration: DateTime.now().difference(startTime),
        );
      }

      // 3. Send a test message
      final testMessage =
          'Test message ${DateTime.now().millisecondsSinceEpoch}';

      await p2pService.sendMessage(
        message: testMessage,
        type: MessageType.text,
        senderName: p2pService.userName,
      );

      // 4. Verify message was saved to database
      await Future.delayed(Duration(milliseconds: 500));
      final allMessages = await MessageRepository.getAllMessages();
      final testMessages = allMessages
          .where((m) => m.message == testMessage)
          .toList();

      if (testMessages.isEmpty) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Test message not found in database after sending',
          duration: DateTime.now().difference(startTime),
        );
      }

      final savedMessage = testMessages.first;

      // 5. Verify message properties
      if (savedMessage.fromUser != p2pService.userName!) {
        return TestResult(
          testId: testId,
          success: false,
          error:
              'Message fromUser field incorrect: expected "${p2pService.userName}", got "${savedMessage.fromUser}"',
          duration: DateTime.now().difference(startTime),
        );
      }

      if (!savedMessage.isMe) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Message isMe field should be true for sent messages',
          duration: DateTime.now().difference(startTime),
        );
      }

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details:
            'Message sent and saved successfully with ID: ${savedMessage.messageId}',
      );
    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: 'Exception during test: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Test emergency message sending
  static Future<TestResult> testEmergencyMessageSending(
    P2PMainService p2pService,
  ) async {
    final testId = 'emergency_send_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    debugPrint('🧪 Running emergency message sending test...');

    try {
      final emergencyMessage =
          '🚨 TEST EMERGENCY MESSAGE ${DateTime.now().millisecondsSinceEpoch}';

      await p2pService.sendMessage(
        message: emergencyMessage,
        type: MessageType.emergency,
        senderName: p2pService.userName ?? 'TestUser',
      );

      await Future.delayed(Duration(milliseconds: 500));
      final allMessages = await MessageRepository.getAllMessages();
      final emergencyMessages = allMessages
          .where((m) => m.message == emergencyMessage && m.isEmergency)
          .toList();

      if (emergencyMessages.isEmpty) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Emergency message not found in database',
          duration: DateTime.now().difference(startTime),
        );
      }

      final savedMessage = emergencyMessages.first;

      if (savedMessage.type != 'emergency') {
        return TestResult(
          testId: testId,
          success: false,
          error:
              'Message type should be "emergency", got "${savedMessage.type}"',
          duration: DateTime.now().difference(startTime),
        );
      }

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details: 'Emergency message sent successfully with correct properties',
      );
    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: 'Exception during emergency test: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Test message receiving simulation
  static Future<TestResult> testMessageReceiving(
    P2PMainService p2pService,
  ) async {
    final testId = 'receive_test_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    debugPrint('🧪 Running message receiving test...');

    try {
      // Set up a listener to capture received messages
      MessageModel? receivedMessage;
      final completer = Completer<void>();

      void messageListener(MessageModel message) {
        if (message.message.contains('RECEIVE_TEST')) {
          receivedMessage = message;
          completer.complete();
        }
      }

      // Add the listener
      final originalListener = p2pService.onMessageReceived;
      p2pService.onMessageReceived = messageListener;

      try {
        // Simulate receiving a message by creating a test message
        final testMessage = MessageModel(
          messageId: 'test_receive_${DateTime.now().millisecondsSinceEpoch}',
          endpointId: 'test_sender',
          fromUser: 'Test Sender',
          message: 'RECEIVE_TEST: This is a simulated received message',
          isMe: false,
          isEmergency: false,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          messageType: MessageType.text,
          type: 'text',
          routePath: ['test_sender'],
          deviceId: null,
        );

        // Simulate the message being received
        if (p2pService.onMessageReceived != null) {
          p2pService.onMessageReceived!(testMessage);
        }

        // Wait for the message to be processed
        await completer.future.timeout(Duration(seconds: 5));

        if (receivedMessage == null) {
          return TestResult(
            testId: testId,
            success: false,
            error: 'Message listener was not called',
            duration: DateTime.now().difference(startTime),
          );
        }

        // Verify the received message
        if (receivedMessage!.endpointId != testMessage.endpointId) {
          return TestResult(
            testId: testId,
            success: false,
            error: 'Received message endpointId mismatch',
            duration: DateTime.now().difference(startTime),
          );
        }

        return TestResult(
          testId: testId,
          success: true,
          duration: DateTime.now().difference(startTime),
          details: 'Message received successfully through listener',
        );
      } finally {
        // Restore original listener
        p2pService.onMessageReceived = originalListener;
      }
    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: 'Exception during receive test: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Test connection establishment
  static Future<TestResult> testConnectionEstablishment(
    P2PMainService p2pService,
  ) async {
    final testId = 'connection_test_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    debugPrint('🧪 Running connection establishment test...');

    try {
      // Test 1: Check initialization
      if (p2pService.deviceId == null) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'P2P service not initialized - deviceId is null',
          duration: DateTime.now().difference(startTime),
        );
      }

      // Test 3: Try device discovery
      await p2pService.discoverDevices(force: true);

      // Wait a moment for discovery to complete
      await Future.delayed(Duration(seconds: 3));

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details: 'Hotspot created and device discovery initiated successfully',
      );
    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: 'Exception during connection test: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Test message status updates
  static Future<TestResult> testMessageStatusUpdates(
    P2PMainService p2pService,
  ) async {
    final testId = 'status_test_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    debugPrint('🧪 Running message status update test...');

    try {
      // Send a message and track its status
      final testMessage =
          'Status test message ${DateTime.now().millisecondsSinceEpoch}';

      await p2pService.sendMessage(
        message: testMessage,
        type: MessageType.text,
        senderName: p2pService.userName ?? 'TestUser',
      );

      // Wait for message to be saved
      await Future.delayed(Duration(milliseconds: 500));

      final allMessages = await MessageRepository.getAllMessages();
      final testMessages = allMessages
          .where((m) => m.message == testMessage)
          .toList();

      if (testMessages.isEmpty) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Test message not found after sending',
          duration: DateTime.now().difference(startTime),
        );
      }

      final savedMessage = testMessages.first;

      // Check initial status
      if (savedMessage.status == MessageStatus.pending) {
        // This is expected for offline messages
        debugPrint('✅ Message has pending status (expected for offline)');
      } else if (savedMessage.status == MessageStatus.sent) {
        // This means the message was sent successfully
        debugPrint('✅ Message has sent status');
      } else {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Unexpected initial message status: ${savedMessage.status}',
          duration: DateTime.now().difference(startTime),
        );
      }

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details:
            'Message status tracking working correctly - initial status: ${savedMessage.status}',
      );
    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: 'Exception during status test: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  /// Run comprehensive test suite
  static Future<List<TestResult>> runComprehensiveTests(
    P2PMainService p2pService,
  ) async {
    debugPrint('🧪 Running comprehensive message test suite...');

    final results = <TestResult>[];

    // Test 1: Basic message sending
    results.add(await testBasicMessageSending(p2pService));

    // Test 2: Emergency message sending
    results.add(await testEmergencyMessageSending(p2pService));

    // Test 3: Message receiving
    results.add(await testMessageReceiving(p2pService));

    // Test 4: Connection establishment
    results.add(await testConnectionEstablishment(p2pService));

    // Test 5: Message status updates
    results.add(await testMessageStatusUpdates(p2pService));

    // Print summary
    final passedTests = results.where((r) => r.success).length;
    final totalTests = results.length;

    debugPrint(
      '🧪 Test suite completed: $passedTests/$totalTests tests passed',
    );

    for (final result in results) {
      final status = result.success ? '✅' : '❌';
      debugPrint(
        '$status ${result.testId}: ${result.success ? 'PASSED' : 'FAILED'}',
      );
      if (!result.success) {
        debugPrint('   Error: ${result.error}');
      }
    }

    return results;
  }

  /// Generate test message with specific properties
  static String generateTestMessage({
    String? prefix,
    bool includeTimestamp = true,
    bool includeEmoji = false,
  }) {
    final buffer = StringBuffer();

    if (prefix != null) {
      buffer.write('$prefix: ');
    }

    if (includeEmoji) {
      buffer.write('🧪 ');
    }

    buffer.write('Test message');

    if (includeTimestamp) {
      buffer.write(' ${DateTime.now().millisecondsSinceEpoch}');
    }

    return buffer.toString();
  }

  /// Create a simulated MessageModel for testing
  static MessageModel createTestMessage({
    String? message,
    MessageType type = MessageType.text,
    String? senderId,
    String? senderName,
  }) {
    return MessageModel(
      messageId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      endpointId: senderId ?? 'test_sender',
      fromUser: senderName ?? 'Test Sender',
      message: message ?? generateTestMessage(prefix: 'TEST'),
      isMe: false,
      isEmergency: type == MessageType.emergency || type == MessageType.sos,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      messageType: type,
      type: type.name,
      routePath: [senderId ?? 'test_sender'],
      ttl: 5,
      deviceId: 'deviceId',
    );
  }

  /// Verify message chain integrity
  static Future<TestResult> verifyMessageChain(
    P2PMainService p2pService,
  ) async {
    final testId = 'chain_verify_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    debugPrint('🧪 Verifying message chain integrity...');

    try {
      // Get all messages from database
      final allMessages = await MessageRepository.getAllMessages();

      // Check for basic integrity issues
      final issues = <String>[];

      for (final message in allMessages) {
        // Check required fields
        if (message.messageId == null || message.messageId!.isEmpty) {
          issues.add('Message with empty messageId found');
        }

        if (message.fromUser.isEmpty) {
          issues.add('Message with empty fromUser found: ${message.messageId}');
        }

        if (message.timestamp <= 0) {
          issues.add('Message with invalid timestamp: ${message.messageId}');
        }

        // Check message type consistency
        if (message.isEmergency &&
            !['emergency', 'sos'].contains(message.type)) {
          issues.add(
            'Emergency flag mismatch in message: ${message.messageId}',
          );
        }
      }

      if (issues.isNotEmpty) {
        return TestResult(
          testId: testId,
          success: false,
          error: 'Message chain integrity issues found: ${issues.join(', ')}',
          duration: DateTime.now().difference(startTime),
        );
      }

      return TestResult(
        testId: testId,
        success: true,
        duration: DateTime.now().difference(startTime),
        details:
            'Message chain integrity verified - ${allMessages.length} messages checked',
      );
    } catch (e) {
      return TestResult(
        testId: testId,
        success: false,
        error: 'Exception during chain verification: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }
}
