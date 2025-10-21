import 'package:flutter/services.dart';

/// Quick test script to verify MAC address retrieval
/// Run with: flutter run test_mac.dart
void main() async {
  print('🔍 Testing MAC address retrieval...');

  const platform = MethodChannel('com.example.resqlink/wifi_direct');

  try {
    final result = await platform.invokeMethod('testMacAddress');
    print('✅ Test completed!');
    print('Result: $result');
  } catch (e) {
    print('❌ Test failed: $e');
  }
}
