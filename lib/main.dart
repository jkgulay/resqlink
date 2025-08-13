import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:english_words/english_words.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:resqlink/message_page.dart';
import 'package:resqlink/services/map_service.dart';
import 'package:resqlink/services/message_sync_service.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'widgets/connection_status_widget.dart';
import 'models/user_model.dart';

final _secureStorage = FlutterSecureStorage();

// Responsive utility class
class ResponsiveUtils {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  static bool isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.height < 600;

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSize * 0.85;
    if (width > tabletBreakpoint) return baseSize * 1.15;
    if (width > mobileBreakpoint) return baseSize * 1.05;
    return baseSize;
  }

  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return baseSpacing * 0.8;
    if (width > tabletBreakpoint) return baseSpacing * 1.5;
    if (width > mobileBreakpoint) return baseSpacing * 1.2;
    return baseSpacing;
  }

  static EdgeInsets getResponsivePadding(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (isDesktop(context)) {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.15,
        vertical: size.height * 0.05,
      );
    } else if (isTablet(context)) {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.1,
        vertical: size.height * 0.04,
      );
    } else {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.04,
      );
    }
  }

  static double getImageHeight(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (isLandscape(context)) {
      return size.height * 0.4;
    } else if (isSmallScreen(context)) {
      return 180;
    } else if (isDesktop(context)) {
      return size.height * 0.35;
    } else if (isTablet(context)) {
      return size.height * 0.32;
    } else {
      return size.height * 0.28;
    }
  }

  static double getMaxDialogWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return 400;
    if (isTablet(context)) return 350;
    return width * 0.9;
  }
}

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

Future<String?> loadIdToken() async {
  try {
    return await _secureStorage.read(key: 'idToken');
  } catch (e) {
    debugPrint('Error reading idToken: $e');
    return null;
  }
}

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
  final List<ConnectivityResult> connectivityResult = (await Connectivity()
      .checkConnectivity());
  return connectivityResult.contains(ConnectivityResult.mobile) ||
      connectivityResult.contains(ConnectivityResult.wifi);
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
  try {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser != null && firebaseUser.email != null) {
      final idToken = await firebaseUser.getIdToken();
      final expiresAt = DateTime.now().add(const Duration(hours: 1));
      await saveToken(idToken!, '', expiresAt);

      // Store the Firebase UID as a way to verify offline login
      await _secureStorage.write(key: 'firebase_uid', value: firebaseUser.uid);
      await _secureStorage.write(
        key: 'cached_email',
        value: firebaseUser.email!,
      );

      // Try to find local user by email
      final localUser = await DatabaseService.getUserByEmail(
        firebaseUser.email!,
      );

      if (localUser != null) {
        return localUser;
      }

      // Create user with Firebase UID as identifier for offline verification
      final newUser = await DatabaseService.createUser(
        firebaseUser.email!,
        firebaseUser.uid, // Use Firebase UID instead of empty password
        isOnlineUser: true,
      );

      return newUser;
    }
  } catch (e) {
    debugPrint('Silent Firebase login failed: $e');
  }
  return null;
}

Future<UserModel?> tryOfflineLogin() async {
  // First try the current AuthService method
  final user = await AuthService.getCurrentUser();
  if (user != null) return user;

  // Then try cached Firebase credentials
  final cachedEmail = await _secureStorage.read(key: 'cached_email');
  final firebaseUid = await _secureStorage.read(key: 'firebase_uid');

  if (cachedEmail != null && firebaseUid != null) {
    // Verify cached user exists in local database
    final localUser = await DatabaseService.loginUser(cachedEmail, firebaseUid);
    return localUser;
  }

  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed (offline?): $e');
  }

  // Initialize services
  await PhilippinesMapService.instance.initialize();
  await NotificationService.initialize();
  MessageSyncService().initialize(); // Add this line
  
  if (kDebugMode) {
    await DatabaseService.deleteDatabaseFile();
  }
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

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  UserModel? _currentUser;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add this
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    ); // Remove 'as WidgetsBindingObserver'
    super.dispose();
  }

  // Add this required method
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
  }

  Future<void> _bootstrap() async {
    if (await isOnline()) {
      try {
        _currentUser = await trySilentFirebaseLogin();
      } catch (e) {
        debugPrint('Silent Firebase login failed: $e');
      }
    }

    _currentUser ??= await tryOfflineLogin();

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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = ResponsiveUtils.isLandscape(context);
            final isDesktop = ResponsiveUtils.isDesktop(context);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Container(
                    width: double.infinity,
                    padding: ResponsiveUtils.getResponsivePadding(context),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0B192C), Color(0xFF1E3E62)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: isLandscape && !isDesktop
                        ? _buildLandscapeLayout(context)
                        : _buildPortraitLayout(context),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const ConnectionStatusWidget(),
        _buildImageSection(context),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),
        _buildTitleSection(context),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),
        _buildFeatureHighlight(context),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 30)),
        _buildEnterButton(context),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ConnectionStatusWidget(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 20),
              ),
              _buildImageSection(context),
            ],
          ),
        ),
        SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 40)),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleSection(context),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 20),
              ),
              _buildFeatureHighlight(context),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 30),
              ),
              _buildEnterButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageSection(BuildContext context) {
    return SizedBox(
      height: ResponsiveUtils.getImageHeight(context),
      child: Image.asset('assets/1.png', fit: BoxFit.contain),
    );
  }

  Widget _buildTitleSection(BuildContext context) {
    return Column(
      crossAxisAlignment:
          ResponsiveUtils.isLandscape(context) &&
              !ResponsiveUtils.isDesktop(context)
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'Welcome to ResQLink',
          textAlign:
              ResponsiveUtils.isLandscape(context) &&
                  !ResponsiveUtils.isDesktop(context)
              ? TextAlign.left
              : TextAlign.center,
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 28),
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 10)),
        Text(
          'Offline Emergency Communication Using Wi-Fi Direct & Geolocation Services',
          textAlign:
              ResponsiveUtils.isLandscape(context) &&
                  !ResponsiveUtils.isDesktop(context)
              ? TextAlign.left
              : TextAlign.center,
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureHighlight(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(
        ResponsiveUtils.getResponsiveSpacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: Row(
        mainAxisAlignment:
            ResponsiveUtils.isLandscape(context) &&
                !ResponsiveUtils.isDesktop(context)
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Icon(
            Icons.offline_bolt,
            color: Colors.green,
            size: ResponsiveUtils.getResponsiveFontSize(context, 20),
          ),
          SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 8)),
          Flexible(
            child: Text(
              'Works Offline for Emergency Use',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterButton(BuildContext context) {
    final buttonWidth = ResponsiveUtils.isDesktop(context)
        ? 300.0
        : ResponsiveUtils.isTablet(context)
        ? 250.0
        : MediaQuery.of(context).size.width * 0.8;

    return SizedBox(
      width: buttonWidth,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6500),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.getResponsiveSpacing(context, 24),
            vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(
          Icons.power_settings_new,
          size: ResponsiveUtils.getResponsiveFontSize(context, 20),
        ),
        label: Text(
          'Enter App',
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () => _showLoginDialog(context),
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

    setState(() => isLoading = true);

    try {
      AuthResult result;
      if (isLogin) {
        result = await AuthService.login(email, password);

        // If online login successful, cache the credentials
        if (result.isSuccess && result.method == AuthMethod.online) {
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            await _secureStorage.write(key: 'cached_email', value: email);
            await _secureStorage.write(
              key: 'firebase_uid',
              value: firebaseUser.uid,
            );
          }
        }
      } else {
        result = await AuthService.register(email, password);

        // Cache registration credentials too
        if (result.isSuccess && result.method == AuthMethod.online) {
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            await _secureStorage.write(key: 'cached_email', value: email);
            await _secureStorage.write(
              key: 'firebase_uid',
              value: firebaseUser.uid,
            );
          }
        }
      }
    } catch (e) {
      _showSnackBar('An error occurred: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveUtils.getMaxDialogWidth(context);

    return Dialog(
      insetPadding: EdgeInsets.all(
        ResponsiveUtils.getResponsiveSpacing(context, 20),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFF1E3E62),
      child: SizedBox(
        width: maxWidth,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(
                ResponsiveUtils.getResponsiveSpacing(context, 20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogHeader(context),
                  SizedBox(
                    height: ResponsiveUtils.getResponsiveSpacing(context, 20),
                  ),
                  _buildTextField(
                    controller: emailController,
                    label: "Email",
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(
                    height: ResponsiveUtils.getResponsiveSpacing(context, 12),
                  ),
                  _buildTextField(
                    controller: passwordController,
                    label: "Password",
                    obscureText: true,
                  ),
                  if (!isLogin) ...[
                    SizedBox(
                      height: ResponsiveUtils.getResponsiveSpacing(context, 12),
                    ),
                    _buildTextField(
                      controller: confirmPasswordController,
                      label: "Confirm Password",
                      obscureText: true,
                    ),
                  ],
                  SizedBox(
                    height: ResponsiveUtils.getResponsiveSpacing(context, 16),
                  ),
                  _buildInfoBox(context),
                  SizedBox(
                    height: ResponsiveUtils.getResponsiveSpacing(context, 20),
                  ),
                  _buildSubmitButton(context),
                  SizedBox(
                    height: ResponsiveUtils.getResponsiveSpacing(context, 12),
                  ),
                  _buildToggleButton(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isLogin ? "Login" : "Register",
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 24),
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const ConnectionStatusWidget(),
      ],
    );
  }

  Widget _buildInfoBox(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(
        ResponsiveUtils.getResponsiveSpacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'This app works offline for emergency use. Your credentials are stored securely on your device.',
        style: TextStyle(
          color: Colors.blue,
          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6500),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveUtils.getResponsiveSpacing(context, 32),
            vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: isLoading ? null : _handleSubmit,
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                isLogin ? "Login" : "Register",
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildToggleButton(BuildContext context) {
    return TextButton(
      onPressed: isLoading ? null : _toggleMode,
      child: Text(
        isLogin
            ? "Need an Account? Register"
            : "Already have an Account? Login",
        style: TextStyle(
          color: Colors.white,
          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(
        color: Colors.white,
        fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
      ),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF0B192C),
        labelStyle: TextStyle(
          color: Colors.white70,
          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveUtils.getResponsiveSpacing(context, 16),
          vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
        ),
      ),
    );
  }
}
