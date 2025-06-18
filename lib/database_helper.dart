import 'dart:async';

class DatabaseHelper {
  // Simulate a simple user database with a map
  static final Map<String, String> _userDatabase = {};

  // Singleton instance
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // Mock function to register a user
  Future<void> registerUser(String username, String password) async {
    // Simulate a delay
    await Future.delayed(const Duration(seconds: 1));
    _userDatabase[username] = password;
    print("User registered: $username");
  }

  // Mock function to log in a user
  Future<String?> loginUser(String username, String password) async {
    // Simulate a delay
    await Future.delayed(const Duration(seconds: 1));

    // Check if user exists and the password matches
    if (_userDatabase.containsKey(username) &&
        _userDatabase[username] == password) {
      print("User logged in: $username");
      return username; // Return username as a sign of successful login
    } else {
      print("Login failed for: $username");
      return null;
    }
  }
}


