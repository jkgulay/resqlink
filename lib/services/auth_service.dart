import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_service.dart';
import '../firebase_auth_helper.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _currentUserKey = 'current_user_id';
  static const String _isLoggedInKey = 'is_logged_in';

  static Future<bool> get isConnected async {
    final List<ConnectivityResult> connectivityResult = await Connectivity()
        .checkConnectivity();
    return connectivityResult.any(
      (result) => result != ConnectivityResult.none,
    );
  }

  static Future<UserModel?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt(_currentUserKey);
      final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;

      if (!isLoggedIn || userId == null) return null;

      final db = await DatabaseService.database;
      final result = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );

      if (result.isNotEmpty) {
        return UserModel.fromMap(result.first);
      }
      return null;
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }

  static Future<void> _setCurrentUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentUserKey, user.id!);
    await prefs.setBool(_isLoggedInKey, true);
  }

  static Future<void> logout() async {
    try {
      // Handle online logout if connected
      if (await isConnected) {
        try {
          await FirebaseAuthHelper.logoutUser();
        } catch (e) {
          print('Firebase logout error: $e');
          // Continue with local logout even if Firebase logout fails
        }
      }
      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentUserKey);
      await prefs.setBool(_isLoggedInKey, false);
      // Clear any cached user data or session information
      print('User logged out successfully');
    } catch (e) {
      print('Error during logout: $e');
      throw Exception('Failed to logout: $e');
    }
  }

  static Future<UserModel?> trySilentFirebaseLogin() async {
    final firebaseUser = FirebaseAuthHelper.currentUser;
    if (firebaseUser != null) {
      final email = firebaseUser.email!;
      final localUser = await DatabaseService.loginUser(
        email,
        '',
      ); // dummy for lookup
      if (localUser != null) {
        await _setCurrentUser(localUser);
        return localUser;
      }
    }
    return null;
  }

  static Future<UserModel?> tryOfflineLogin() async {
    return await getCurrentUser();
  }

  static Future<AuthResult> login(String email, String password) async {
    try {
      final connected = await isConnected;

      if (connected) {
        // Try online authentication first
        try {
          await FirebaseAuthHelper.loginUser(email, password);

          // If successful, try to store/update in local database
          UserModel? localUser = await DatabaseService.loginUser(
            email,
            password,
          );
          localUser ??= await DatabaseService.createUser(
            email,
            password,
            isOnlineUser: true,
          );

          if (localUser != null) {
            await _setCurrentUser(localUser);
            return AuthResult.success(localUser, AuthMethod.online);
          }
        } catch (e) {
          print('Online authentication failed: $e');
          // Fall back to offline authentication
        }
      }

      // Try offline authentication
      final localUser = await DatabaseService.loginUser(email, password);
      if (localUser != null) {
        await _setCurrentUser(localUser);
        return AuthResult.success(localUser, AuthMethod.offline);
      }

      return AuthResult.failure('Invalid credentials');
    } catch (e) {
      return AuthResult.failure('Authentication error: ${e.toString()}');
    }
  }

  static Future<AuthResult> register(String email, String password) async {
    try {
      final connected = await isConnected;

      // Check if user already exists locally
      if (await DatabaseService.userExists(email)) {
        return AuthResult.failure('User already exists');
      }

      if (connected) {
        // Try online registration first
        try {
          await FirebaseAuthHelper.registerUser(email, password);

          // If successful, store in local database
          final localUser = await DatabaseService.createUser(
            email,
            password,
            isOnlineUser: true,
          );
          if (localUser != null) {
            await _setCurrentUser(localUser);
            return AuthResult.success(localUser, AuthMethod.online);
          }
        } catch (e) {
          print('Online registration failed: $e');
          // Continue with offline registration
        }
      }

      // Create user locally for offline use
      final localUser = await DatabaseService.createUser(
        email,
        password,
        isOnlineUser: false,
      );
      if (localUser != null) {
        await _setCurrentUser(localUser);
        return AuthResult.success(localUser, AuthMethod.offline);
      }

      return AuthResult.failure('Failed to create user');
    } catch (e) {
      return AuthResult.failure('Registration error: ${e.toString()}');
    }
  }
}

enum AuthMethod { online, offline }

class AuthResult {
  final bool isSuccess;
  final UserModel? user;
  final String? errorMessage;
  final AuthMethod? method;

  AuthResult.success(this.user, this.method)
    : isSuccess = true,
      errorMessage = null;

  AuthResult.failure(this.errorMessage)
    : isSuccess = false,
      user = null,
      method = null;
}


