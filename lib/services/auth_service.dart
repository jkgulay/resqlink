import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'database_service.dart';
import '../firebase_auth_helper.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _currentUserKey = 'current_user_id';
  static const String _isLoggedInKey = 'is_logged_in';
  static const _secureStorage = FlutterSecureStorage();

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

  // Add this to your AuthService class for debugging
  static Future<void> debugAuthState() async {
    print('=== AUTH DEBUG INFO ===');
    print('Firebase user: ${FirebaseAuth.instance.currentUser?.email}');
    print('Current user: ${(await getCurrentUser())?.email}');
    print('Cached email: ${await _secureStorage.read(key: 'cached_email')}');
    print('Firebase UID: ${await _secureStorage.read(key: 'firebase_uid')}');
    print('Connected: ${await isConnected}');
    print('======================');
  }

  static Future<void> logout({bool clearOfflineCredentials = false}) async {
    try {
      // Handle online logout if connected
      if (await isConnected) {
        try {
          await FirebaseAuth.instance.signOut();
          print('Firebase logout successful');
        } catch (e) {
          print('Firebase logout error: $e');
          // Continue with local logout even if Firebase logout fails
        }
      }

      // Clear current session
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentUserKey);
      await prefs.setBool(_isLoggedInKey, false);

      // Only clear offline credentials if explicitly requested (e.g., account deletion)
      if (clearOfflineCredentials) {
        await _secureStorage.delete(key: 'cached_email');
        await _secureStorage.delete(key: 'firebase_uid');
        print('Offline credentials cleared');
      } else {
        print('Offline credentials preserved for future offline login');
      }

      // Always clear session tokens
      await _secureStorage.delete(key: 'idToken');
      await _secureStorage.delete(key: 'refreshToken');
      await _secureStorage.delete(key: 'expiresAt');

      print('User logged out successfully');
    } catch (e) {
      print('Error during logout: $e');
      throw Exception('Failed to logout: $e');
    }
  }

  static Future<void> clearAllUserData() async {
    try {
      // Clear all local data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Clear all secure storage
      await _secureStorage.deleteAll();

      // Clear database
      await DatabaseService.clearAllData();

      print('All user data cleared');
    } catch (e) {
      print('Error clearing user data: $e');
      throw Exception('Failed to clear user data: $e');
    }
  }

  static Future<UserModel?> trySilentFirebaseLogin() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null && firebaseUser.email != null) {
        // User is already authenticated with Firebase
        print('Firebase user found: ${firebaseUser.email}');

        // Cache credentials
        await _secureStorage.write(
          key: 'cached_email',
          value: firebaseUser.email!,
        );
        await _secureStorage.write(
          key: 'firebase_uid',
          value: firebaseUser.uid,
        );

        // Try to find or create local user
        UserModel? localUser = await DatabaseService.getUserByEmail(
          firebaseUser.email!,
        );

        localUser ??= await DatabaseService.createUser(
          firebaseUser.email!,
          firebaseUser.uid, // Use Firebase UID as password hash
          isOnlineUser: true,
        );

        if (localUser != null) {
          await _setCurrentUser(localUser);
          return localUser;
        }
      }
    } catch (e) {
      print('Silent Firebase login failed: $e');
    }
    return null;
  }

  static Future<UserModel?> tryOfflineLogin() async {
    // First try the current user (if they're still logged in locally)
    final user = await getCurrentUser();
    if (user != null) {
      print('Found existing logged-in user: ${user.email}');
      return user;
    }

    // Then try cached Firebase credentials
    final cachedEmail = await _secureStorage.read(key: 'cached_email');
    final firebaseUid = await _secureStorage.read(key: 'firebase_uid');

    if (cachedEmail != null && firebaseUid != null) {
      print('Attempting offline login with cached credentials: $cachedEmail');

      // Try to login with cached Firebase UID
      final localUser = await DatabaseService.loginUser(
        cachedEmail,
        firebaseUid,
      );

      if (localUser != null) {
        await _setCurrentUser(localUser);
        print('Offline login successful with cached Firebase UID');
        return localUser;
      }

      // If Firebase UID doesn't work, the user might have been created with a regular password
      // This can happen if they registered offline first, then went online
      print('Firebase UID login failed, user may have offline-only account');
    }

    return null;
  }

  static Future<bool> isOfflineLoginAvailable() async {
    final cachedEmail = await _secureStorage.read(key: 'cached_email');
    final firebaseUid = await _secureStorage.read(key: 'firebase_uid');

    if (cachedEmail != null && firebaseUid != null) {
      // Check if user exists in local database
      final userExists = await DatabaseService.userExists(cachedEmail);
      return userExists;
    }

    return false;
  }

  static Future<AuthResult> login(String email, String password) async {
    try {
      print('Attempting login for: $email');
      final connected = await isConnected;

      if (connected) {
        // Try online authentication first
        try {
          print('Attempting Firebase login...');
          await FirebaseAuthHelper.loginUser(email, password);
          print('Firebase login successful');

          // Cache credentials for offline use
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            await _secureStorage.write(key: 'cached_email', value: email);
            await _secureStorage.write(
              key: 'firebase_uid',
              value: firebaseUser.uid,
            );
          }

          // Try to find or create local user
          UserModel? localUser = await DatabaseService.loginUser(
            email,
            firebaseUser?.uid ?? password,
          );

          localUser ??= await DatabaseService.createUser(
            email,
            firebaseUser?.uid ?? password,
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
      print('Attempting offline login...');

      // First try with original password
      UserModel? localUser = await DatabaseService.loginUser(email, password);

      // If that fails, try with cached Firebase UID
      if (localUser == null) {
        final cachedUid = await _secureStorage.read(key: 'firebase_uid');
        if (cachedUid != null) {
          localUser = await DatabaseService.loginUser(email, cachedUid);
        }
      }

      if (localUser != null) {
        await _setCurrentUser(localUser);
        print('Offline login successful');
        return AuthResult.success(localUser, AuthMethod.offline);
      }

      return AuthResult.failure('Invalid credentials');
    } catch (e) {
      print('Login error: $e');
      return AuthResult.failure('Authentication error: ${e.toString()}');
    }
  }

  static Future<AuthResult> register(String email, String password) async {
    try {
      print('Attempting registration for: $email');
      final connected = await isConnected;

      // Check if user already exists locally
      if (await DatabaseService.userExists(email)) {
        return AuthResult.failure('User already exists');
      }

      if (connected) {
        // Try online registration first
        try {
          print('Attempting Firebase registration...');
          await FirebaseAuthHelper.registerUser(email, password);
          print('Firebase registration successful');

          // Cache credentials for offline use
          final firebaseUser = FirebaseAuth.instance.currentUser;
          if (firebaseUser != null) {
            await _secureStorage.write(key: 'cached_email', value: email);
            await _secureStorage.write(
              key: 'firebase_uid',
              value: firebaseUser.uid,
            );
          }

          // Create user in local database
          final localUser = await DatabaseService.createUser(
            email,
            firebaseUser?.uid ?? password,
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
      print('Creating offline user...');
      final localUser = await DatabaseService.createUser(
        email,
        password,
        isOnlineUser: false,
      );

      if (localUser != null) {
        await _setCurrentUser(localUser);
        print('Offline registration successful');
        return AuthResult.success(localUser, AuthMethod.offline);
      }

      return AuthResult.failure('Failed to create user');
    } catch (e) {
      print('Registration error: $e');
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
