import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:english_words/english_words.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:resqlink/pages/landing_page.dart';
import 'package:resqlink/pages/message_page.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'services/database_service.dart';
import 'services/firebase_debug.dart';
import 'services/map_service.dart';
import 'services/settings_service.dart';
import 'utils/app_theme.dart';
import 'widgets/auth/auth_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (kDebugMode) {
      await FirebaseDebugService.checkFirebaseSetup();
    }
  } catch (e) {
    debugPrint('Firebase init failed (offline?): $e');
  }

  await _initializeServices();

  runApp(const MyApp());
}

Future<void> _initializeServices() async {
  // Initialize map service early
  try {
    await PhilippinesMapService.instance.initialize();
    debugPrint('✅ Map service initialized in main');
  } catch (e) {
    debugPrint('❌ Map service init failed in main: $e');
  }

  // Initialize other services
  await NotificationService.initialize();
  await SettingsService.instance.loadSettings();

  // FORCE database recreation to fix schema issues
  try {
    debugPrint('🗑️ Deleting old database to fix schema...');
    await DatabaseService.deleteDatabaseFile();
    debugPrint('✅ Old database deleted');
  } catch (e) {
    debugPrint('⚠️ Could not delete old database: $e');
  }

  // Initialize database with new schema
  try {
    await DatabaseService.database;
    debugPrint('✅ New database initialized successfully');
  } catch (e) {
    debugPrint('❌ Database initialization failed: $e');
  }
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
