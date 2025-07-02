import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthHelper {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user
  static User? get currentUser => _auth.currentUser;

  // Check if user is logged in
  static bool get isLoggedIn => _auth.currentUser != null;

  // Register user with Firebase
  static Future<User?> registerUser(String email, String password) async {
    try {
      print("Attempting to register user with email: $email");
      print("Password length: ${password.length}");

      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      print("User registered successfully!");
      print("User ID: ${userCredential.user?.uid}");
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Error during registration:");
      print("Error Code: ${e.code}");
      print("Error Message: ${e.message}");
      print("Error Details: $e");

      // Handle specific Firebase Auth errors
      switch (e.code) {
        case 'weak-password':
          throw Exception(
            'The password provided is too weak. Use at least 6 characters.',
          );
        case 'email-already-in-use':
          throw Exception('An account already exists for this email.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        case 'operation-not-allowed':
          throw Exception(
            'Email/password accounts are not enabled in Firebase Console.',
          );
        case 'network-request-failed':
          throw Exception(
            'Network error. Please check your internet connection.',
          );
        default:
          throw Exception('Registration failed: ${e.message ?? e.code}');
      }
    } catch (e) {
      print("General error during registration: $e");
      print("Error type: ${e.runtimeType}");
      throw Exception("Failed to register user: $e");
    }
  }

  // Login user with Firebase
  static Future<User?> loginUser(String email, String password) async {
    try {
      print("Attempting to login user with email: $email");

      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(email: email.trim(), password: password);
      print("User logged in successfully!");
      print("User ID: ${userCredential.user?.uid}");
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Error during login:");
      print("Error Code: ${e.code}");
      print("Error Message: ${e.message}");
      print("Error Details: $e");

      // Handle specific Firebase Auth errors
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No user found for this email.');
        case 'wrong-password':
          throw Exception('Wrong password provided.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        case 'user-disabled':
          throw Exception('This user account has been disabled.');
        case 'too-many-requests':
          throw Exception(
            'Too many failed login attempts. Please try again later.',
          );
        case 'invalid-credential':
          throw Exception('Invalid email or password.');
        case 'network-request-failed':
          throw Exception(
            'Network error. Please check your internet connection.',
          );
        default:
          throw Exception('Login failed: ${e.message ?? e.code}');
      }
    } catch (e) {
      print("General error during login: $e");
      print("Error type: ${e.runtimeType}");
      throw Exception("Failed to login: $e");
    }
  }

  // Logout user
  static Future<void> logoutUser() async {
    try {
      await _auth.signOut();
      print("User logged out successfully!");
    } catch (e) {
      print("Error during logout: $e");
      throw Exception("Failed to logout: $e");
    }
  }

  // Reset password
  static Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      print("Password reset email sent!");
    } on FirebaseAuthException catch (e) {
      print(
        "Firebase Auth Error during password reset: ${e.code} - ${e.message}",
      );

      switch (e.code) {
        case 'user-not-found':
          throw Exception('No user found for this email.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        default:
          throw Exception('Password reset failed: ${e.message}');
      }
    } catch (e) {
      print("General error during password reset: $e");
      throw Exception("Failed to send password reset email: $e");
    }
  }

  // Delete user account
  static Future<void> deleteUser() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        await user.delete();
        print("User account deleted successfully!");
      } else {
        throw Exception("No user is currently logged in.");
      }
    } on FirebaseAuthException catch (e) {
      print(
        "Firebase Auth Error during account deletion: ${e.code} - ${e.message}",
      );

      switch (e.code) {
        case 'requires-recent-login':
          throw Exception('Please log in again before deleting your account.');
        default:
          throw Exception('Account deletion failed: ${e.message}');
      }
    } catch (e) {
      print("General error during account deletion: $e");
      throw Exception("Failed to delete account: $e");
    }
  }

  // Update user email
  static Future<void> updateEmail(String newEmail) async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        // Send verification email to new address
        await user.verifyBeforeUpdateEmail(newEmail);
        print(
          "Verification email sent to $newEmail! Please check your inbox and verify before the email is updated.",
        );
      } else {
        throw Exception("No user is currently logged in.");
      }
    } on FirebaseAuthException catch (e) {
      print(
        "Firebase Auth Error during email update: ${e.code} - ${e.message}",
      );

      switch (e.code) {
        case 'requires-recent-login':
          throw Exception('Please log in again before updating your email.');
        case 'email-already-in-use':
          throw Exception('This email is already in use by another account.');
        case 'invalid-email':
          throw Exception('The email address is not valid.');
        case 'too-many-requests':
          throw Exception('Too many requests. Please try again later.');
        default:
          throw Exception('Email update failed: ${e.message}');
      }
    } catch (e) {
      print("General error during email update: $e");
      throw Exception("Failed to update email: $e");
    }
  }

  // Update user password
  static Future<void> updatePassword(String newPassword) async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        await user.updatePassword(newPassword);
        print("Password updated successfully!");
      } else {
        throw Exception("No user is currently logged in.");
      }
    } on FirebaseAuthException catch (e) {
      print(
        "Firebase Auth Error during password update: ${e.code} - ${e.message}",
      );

      switch (e.code) {
        case 'requires-recent-login':
          throw Exception('Please log in again before updating your password.');
        case 'weak-password':
          throw Exception('The new password is too weak.');
        default:
          throw Exception('Password update failed: ${e.message}');
      }
    } catch (e) {
      print("General error during password update: $e");
      throw Exception("Failed to update password: $e");
    }
  }

  // Send email verification
  static Future<void> sendEmailVerification() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        print("Email verification sent!");
      } else if (user?.emailVerified == true) {
        throw Exception("Email is already verified.");
      } else {
        throw Exception("No user is currently logged in.");
      }
    } catch (e) {
      print("Error sending email verification: $e");
      throw Exception("Failed to send email verification: $e");
    }
  }

  // Check if email is verified
  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  // Reload user to get updated information
  static Future<void> reloadUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      print("Error reloading user: $e");
    }
  }

  // Listen to auth state changes
  static Stream<User?> get authStateChanges => _auth.authStateChanges();
}
