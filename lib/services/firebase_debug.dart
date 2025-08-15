import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirebaseDebugService {
  static Future<void> checkFirebaseSetup() async {
    try {
      debugPrint('🔥 Firebase Setup Check Started');

      // Check if Firebase is initialized
      final apps = Firebase.apps;
      debugPrint('📱 Firebase apps: ${apps.length}');

      if (apps.isNotEmpty) {
        final app = apps.first;
        debugPrint('📱 App name: ${app.name}');
        debugPrint('📱 Project ID: ${app.options.projectId}');
        debugPrint('📱 API Key: ${app.options.apiKey.substring(0, 10)}...');
      }

      // Check Auth
      try {
        final auth = FirebaseAuth.instance;
        final currentUser = auth.currentUser;
        debugPrint(
          '🔐 Auth current user: ${currentUser?.email ?? 'Not logged in'}',
        );
        debugPrint('🔐 Auth initialized: ${auth.app.name}');
      } catch (e) {
        debugPrint('❌ Auth error: $e');
      }

      // Check Firestore
      try {
        final firestore = FirebaseFirestore.instance;
        debugPrint('🗄️ Firestore app: ${firestore.app.name}');

        // Try to write a test document
        await firestore.collection('test').doc('connection_test').set({
          'timestamp': FieldValue.serverTimestamp(),
          'message': 'Connection test',
        });

        debugPrint('✅ Firestore write test: SUCCESS');

        // Try to read it back
        final doc = await firestore
            .collection('test')
            .doc('connection_test')
            .get();
        if (doc.exists) {
          debugPrint('✅ Firestore read test: SUCCESS');
          debugPrint('📄 Test data: ${doc.data()}');
        }
      } catch (e) {
        debugPrint('❌ Firestore error: $e');
      }

      debugPrint('🔥 Firebase Setup Check Completed');
    } catch (e) {
      debugPrint('❌ Firebase setup check failed: $e');
    }
  }
}
