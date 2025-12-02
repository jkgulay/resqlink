import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:english_words/english_words.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:resqlink/features/database/core/database_manager.dart';
import 'package:resqlink/features/database/repositories/chat_repository.dart';
import 'package:resqlink/pages/landing_page.dart';
import 'package:resqlink/widgets/message/notification_service.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'services/firebase_debug.dart';
import 'services/map_service.dart';
import 'services/settings_service.dart';
import 'utils/app_theme.dart';
import 'widgets/auth/auth_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  try {
    debugPrint('🔥 Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 30));
    debugPrint('✅ Firebase initialized');

    if (kDebugMode) {
      debugPrint('🔍 Running Firebase debug checks...');
      await FirebaseDebugService.checkFirebaseSetup().timeout(
        const Duration(seconds: 10),
      );
      debugPrint('✅ Firebase debug checks completed');
    }
  } catch (e) {
    debugPrint('❌ Firebase init failed (offline?): $e');
  }

  await _initializeServices();

  runApp(const MyApp());
}

Future<void> _initializeServices() async {
  debugPrint('🚀 Starting service initialization...');

  // Initialize other services with timeout
  try {
    debugPrint('📱 Initializing notification service...');
    await NotificationService.initialize().timeout(const Duration(seconds: 10));
    debugPrint('✅ Notification service initialized');
  } catch (e) {
    debugPrint('❌ Notification service failed: $e');
  }

  try {
    debugPrint('⚙️ Loading settings...');
    await SettingsService.instance.loadSettings().timeout(
      const Duration(seconds: 10),
    );
    debugPrint('✅ Settings loaded');
  } catch (e) {
    debugPrint('❌ Settings loading failed: $e');
  }

  // Initialize map service with timeout
  try {
    debugPrint('🗺️ Initializing map service...');
    await PhilippinesMapService.instance.initialize().timeout(
      const Duration(seconds: 15),
    );
    debugPrint('✅ Map service initialized in main');
  } catch (e) {
    debugPrint('❌ Map service init failed in main: $e');
  }

  // Initialize database (preserve existing data) - DO THIS ONLY ONCE
  try {
    debugPrint('💾 Initializing database...');
    await DatabaseManager.database.timeout(const Duration(seconds: 10));
    debugPrint('✅ Database initialized successfully');
  } catch (e) {
    debugPrint('❌ Database initialization failed: $e');
    // If database fails, the app can still work in memory-only mode
  }

  // Clean up duplicate chat sessions on app startup
  try {
    debugPrint('🧹 Running session deduplication...');
    final mergedCount = await ChatRepository.cleanupDuplicateSessions().timeout(
      const Duration(seconds: 15),
    );
    if (mergedCount > 0) {
      debugPrint('✅ Merged $mergedCount duplicate sessions');
    } else {
      debugPrint('✅ No duplicate sessions found');
    }
  } catch (e) {
    debugPrint('❌ Session deduplication failed: $e');
    // Non-critical - app can still work with duplicates
  }

  debugPrint('🎯 Service initialization completed');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyAppState()),
        ChangeNotifierProvider.value(value: SettingsService.instance),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ResQLink',
        theme: AppTheme.darkTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthWrapper(),
          '/home': (context) => HomePage(),
          '/landing': (context) => const LandingPage(),
        },
        onGenerateRoute: (settings) {
          // Handle GPS page with arguments
          if (settings.name == '/gps') {
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (context) {
                // Get P2P service from context (it's in HomePage)
                // For now, we'll navigate back and let HomePage handle it
                // This is a workaround - ideally P2P service should be in Provider
                return HomePage(
                  initialTab: 1, // GPS tab index
                  initialGpsLatitude: args?['initialLatitude'] as double?,
                  initialGpsLongitude: args?['initialLongitude'] as double?,
                  senderName: args?['senderName'] as String?,
                );
              },
            );
          }
          return null;
        },
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var current = WordPair.random();
  final favorites = <WordPair>[];

  void getNext() {
    current = WordPair.random();
    notifyListeners();
  }

  void toggleFavorite() {
    favorites.contains(current)
        ? favorites.remove(current)
        : favorites.add(current);
    notifyListeners();
  }
}
