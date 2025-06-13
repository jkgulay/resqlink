import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:english_words/english_words.dart';
import 'home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'ResQLink',
        theme: ThemeData(
          fontFamily: 'Ubuntu',
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: const Color(0xFFFF6500),
                brightness: Brightness.dark,
                surface: const Color(0xFF0B192C),
                surfaceContainerHighest: const Color(0xFF1E3E62),
              ).copyWith(
                primary: const Color(0xFFFF6500),
                onPrimary: Colors.white,
                onSurface: Colors.white,
                onSecondary: Colors.white,
              ),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0B192C),
            foregroundColor: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6500),
              foregroundColor: Colors.white,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white),
          ),
        ),
        home: const LandingPage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var current = WordPair.random();

  void getNext() {
    current = WordPair.random();
    notifyListeners();
  }

  var favorites = <WordPair>[];

  void toggleFavorite() {
    if (favorites.contains(current)) {
      favorites.remove(current);
    } else {
      favorites.add(current);
    }
    notifyListeners();
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sos, size: 80, color: Color(0xFFFF6500)),
            const SizedBox(height: 20),
            const Text(
              'Welcome to ResQLink',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('Tap below to enter the app'),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => HomePage()),
                );
              },
              child: const Text('Enter App'),
            ),
          ],
        ),
      ),
    );
  }
}
