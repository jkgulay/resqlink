import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import '../features/database/repositories/user_repository.dart';
import '../features/database/core/database_manager.dart';
import '../firebase_auth_helper.dart';
import '../models/user_model.dart';
import 'identity_service.dart';
import 'temporary_identity_service.dart';

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

      final db = await DatabaseManager.database;
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

      // Clear the temporary identity as well
      await TemporaryIdentityService.clearTemporarySession();

      // Clear the user's display name
      await IdentityService().resetIdentity();

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
      await UserRepository.clearAllData();

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
        UserModel? localUser = await UserRepository.getByEmail(
          firebaseUser.email!,
        );

        localUser ??= await UserRepository.create(
          email: firebaseUser.email!,
          password: firebaseUser.uid, // Use Firebase UID as password hash
          name: firebaseUser.displayName ?? 'Firebase User',
        );

        if (localUser != null) {
          await _setCurrentUser(localUser);
          await IdentityService().setDisplayName(localUser.name);
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
      await IdentityService().setDisplayName(user.name);
      return user;
    }

    // Then try cached Firebase credentials
    final cachedEmail = await _secureStorage.read(key: 'cached_email');
    final firebaseUid = await _secureStorage.read(key: 'firebase_uid');

    if (cachedEmail != null && firebaseUid != null) {
      print('Attempting offline login with cached credentials: $cachedEmail');

      // Try to login with cached Firebase UID
      final localUser = await UserRepository.login(
        cachedEmail,
        firebaseUid,
      );

      if (localUser != null) {
        await _setCurrentUser(localUser);
        await IdentityService().setDisplayName(localUser.name);
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
      final userExists = await UserRepository.exists(cachedEmail);
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
          UserModel? localUser = await UserRepository.login(
            email,
            firebaseUser?.uid ?? password,
          );

          localUser ??= await UserRepository.create(
            email: email,
            password: firebaseUser?.uid ?? password,
            name: email.split('@').first,
          );

          if (localUser != null) {
            await _setCurrentUser(localUser);
            await IdentityService().setDisplayName(localUser.name);
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
      UserModel? localUser = await UserRepository.login(email, password);

      // If that fails, try with cached Firebase UID
      if (localUser == null) {
        final cachedUid = await _secureStorage.read(key: 'firebase_uid');
        if (cachedUid != null) {
          localUser = await UserRepository.login(email, cachedUid);
        }
      }

      if (localUser != null) {
        await _setCurrentUser(localUser);
        await IdentityService().setDisplayName(localUser.name);
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
      if (await UserRepository.exists(email)) {
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
          final localUser = await UserRepository.create(
            email: email,
            password: firebaseUser?.uid ?? password,
            name: email.split('@').first,
          );

          if (localUser != null) {
            await _setCurrentUser(localUser);
            await IdentityService().setDisplayName(localUser.name);
            return AuthResult.success(localUser, AuthMethod.online);
          }
        } catch (e) {
          print('Online registration failed: $e');
          // Continue with offline registration
        }
      }

      // Create user locally for offline use
      print('Creating offline user...');
      final localUser = await UserRepository.create(
        email: email,
        password: password,
        name: email.split('@').first,
      );

      if (localUser != null) {
        await _setCurrentUser(localUser);
        await IdentityService().setDisplayName(localUser.name);
        print('Offline registration successful');
        return AuthResult.success(localUser, AuthMethod.offline);
      }

      return AuthResult.failure('Failed to create user');
    } catch (e) {
      print('Registration error: $e');
      return AuthResult.failure('Registration error: ${e.toString()}');
    }
  }

  // Authentication utility functions
  static Future<void> saveToken(
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

  static Future<String?> loadIdToken() async {
    try {
      return await _secureStorage.read(key: 'idToken');
    } catch (e) {
      debugPrint('Error reading idToken: $e');
      return null;
    }
  }

  static Future<String?> loadRefreshToken() async =>
      await _secureStorage.read(key: 'refreshToken');
      
  static Future<DateTime?> loadExpiresAt() async {
    final val = await _secureStorage.read(key: 'expiresAt');
    return val != null ? DateTime.tryParse(val) : null;
  }

  static Future<void> clearTokens() async {
    await _secureStorage.deleteAll();
  }

  static Future<bool> isOnline() async {
    final List<ConnectivityResult> connectivityResult = (await Connectivity()
        .checkConnectivity());
    return connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);
  }

  static Future<String?> refreshIdToken() async {
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
