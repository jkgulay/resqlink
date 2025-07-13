import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:english_words/english_words.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'widgets/connection_status_widget.dart';
import 'models/user_model.dart';

final _secureStorage = FlutterSecureStorage();

Future<void> saveToken(
  String idToken,
  String refreshToken,
  DateTime expiresAt,
) async {
  await _secureStorage.write(key: 'idToken', value: idToken);
  await _secureStorage.write(key: 'refreshToken', value: refreshToken);
  await _secureStorage.write(
    key: 'expiresAt',
    value: expiresAt.toIso8601String(),
  );
}

Future<String?> loadIdToken() async =>
    await _secureStorage.read(key: 'idToken');
Future<String?> loadRefreshToken() async =>
    await _secureStorage.read(key: 'refreshToken');
Future<DateTime?> loadExpiresAt() async {
  final val = await _secureStorage.read(key: 'expiresAt');
  return val != null ? DateTime.tryParse(val) : null;
}

Future<void> clearTokens() async {
  await _secureStorage.deleteAll();
}

Future<bool> isOnline() async {
  final conn = await Connectivity().checkConnectivity();
  return conn == ConnectivityResult.mobile || conn == ConnectivityResult.wifi;
}

Future<String?> refreshIdToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await user.reload();
    final newToken = await user.getIdToken();
    final expiration = DateTime.now().add(const Duration(hours: 1));
    await saveToken(newToken!, '', expiration);
    return newToken;
  }
  return null;
}

Future<UserModel?> trySilentFirebaseLogin() async {
  final idToken = await loadIdToken();
  final expiresAt = await loadExpiresAt();
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (idToken != null &&
      expiresAt != null &&
      DateTime.now().isBefore(expiresAt)) {
    if (firebaseUser != null && firebaseUser.email != null) {
      final email = firebaseUser.email!;
      final localUser = await DatabaseService.loginUser(
        email,
        '',
      ); // dummy login to lookup
      if (localUser != null) {
        return localUser;
      }
    }
  }
  return null;
}

Future<UserModel?> tryOfflineLogin() async {
  return await AuthService.getCurrentUser();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed (offline?): \$e');
  }
  await DatabaseService.deleteDatabaseFile(); // ⚠️ dev only
  await DatabaseService.database;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MyAppState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ResQLink',
        theme: _darkTheme,
        home: const AuthWrapper(),
      ),
    );
  }
}

final _darkTheme = ThemeData(
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
);

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  UserModel? _currentUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (await isOnline()) {
      try {
        _currentUser = await trySilentFirebaseLogin();
      } catch (e) {
        debugPrint('Silent Firebase login failed: \$e');
      }
    }

    if (_currentUser == null) {
      _currentUser = await tryOfflineLogin();
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _currentUser != null ? HomePage() : const LandingPage();
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

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const LoginRegisterDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B192C), Color(0xFF1E3E62)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Connection status indicator
            const Positioned(
              top: 50,
              right: 24,
              child: ConnectionStatusWidget(),
            ),
            Image.asset('assets/1.png', height: 300, fit: BoxFit.contain),
            const SizedBox(height: 30),
            const Text(
              'Welcome to ResQLink',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Offline Emergency Communication Using Wi-Fi Direct & Geolocation Services',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            // Offline capability indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green, width: 1),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.offline_bolt, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Works Offline for Emergency Use',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6500),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.power_settings_new),
              label: const Text(
                'Enter App',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                _showLoginDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class LoginRegisterDialog extends StatefulWidget {
  const LoginRegisterDialog({super.key});

  @override
  State<LoginRegisterDialog> createState() => _LoginRegisterDialogState();
}

class _LoginRegisterDialogState extends State<LoginRegisterDialog> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool isLogin = true;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      isLogin = !isLogin;
      emailController.clear();
      passwordController.clear();
      confirmPasswordController.clear();
    });
  }

  Future<void> _handleSubmit() async {
    String email = emailController.text.trim();
    String password = passwordController.text;
    String confirmPassword = confirmPasswordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter all fields');
      return;
    }

    if (!isLogin && password != confirmPassword) {
      _showSnackBar('Passwords do not match');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      AuthResult result;
      if (isLogin) {
        result = await AuthService.login(email, password);
      } else {
        result = await AuthService.register(email, password);
      }

      if (result.isSuccess) {
        if (mounted) {
          Navigator.of(context).pop();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomePage()),
          );

          // Show success message with connection status
          String methodText = result.method == AuthMethod.online
              ? 'Online'
              : 'Offline';
          String actionText = isLogin ? 'Login' : 'Registration';
          _showSnackBar('$actionText successful ($methodText mode)');
        }
      } else {
        _showSnackBar(result.errorMessage ?? 'Authentication failed');
      }
    } catch (e) {
      _showSnackBar('An error occurred: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFF1E3E62),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isLogin ? "Login" : "Register",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const ConnectionStatusWidget(),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: "Email",
                filled: true,
                fillColor: const Color(0xFF0B192C),
                labelStyle: const TextStyle(color: Colors.white70),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: "Password",
                filled: true,
                fillColor: const Color(0xFF0B192C),
                labelStyle: const TextStyle(color: Colors.white70),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            if (!isLogin)
              TextField(
                controller: confirmPasswordController,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  filled: true,
                  fillColor: const Color(0xFF0B192C),
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                obscureText: true,
              ),
            const SizedBox(height: 15),
            // Info text about offline capability
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'This app works offline for emergency use. Your credentials are stored securely on your device.',
                style: TextStyle(color: Colors.blue, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6500),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: isLoading ? null : _handleSubmit,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(isLogin ? "Login" : "Register"),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: isLoading ? null : _toggleMode,
              child: Text(
                isLogin
                    ? "Need an Account? Register"
                    : "Already have an Account? Login",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
