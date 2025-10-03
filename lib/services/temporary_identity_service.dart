import 'package:resqlink/features/database/core/database_manager.dart';
import 'package:resqlink/features/database/repositories/user_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import '../models/user_model.dart';

class TemporaryIdentityService {
  static const String _tempUserKey = 'temp_user_id';
  static const String _tempDisplayNameKey = 'temp_display_name';
  static const String _tempIdentifierKey = 'temp_identifier';
  static const String _tempSessionKey = 'temp_session_active';
  
  // Generate a unique temporary identifier for this session
  static String _generateTempIdentifier() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomBytes = List.generate(8, (i) => random.nextInt(256));
    final combined = '$timestamp${randomBytes.join()}';
    
    // Create a short, readable identifier
    final hash = sha256.convert(utf8.encode(combined));
    return hash.toString().substring(0, 8).toUpperCase();
  }

  // Create a temporary identity for emergency use
  static Future<UserModel?> createTemporaryIdentity(String displayName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Generate unique temp identifier
      final tempId = _generateTempIdentifier();
      final tempEmail = 'temp_$tempId@emergency.local';
      
      debugPrint('🆔 Creating temporary identity: $displayName ($tempId)');
      
      // Create or update user in local database
      final tempUser = await UserRepository.createUser(
        email: tempEmail,
        password: tempId, 
        name: displayName,
        phoneNumber: null,
        isOnlineUser: false,
      );
      
      if (tempUser != null) {
        // Store temporary session info
        await prefs.setInt(_tempUserKey, tempUser.id!);
        await prefs.setString(_tempDisplayNameKey, displayName);
        await prefs.setString(_tempIdentifierKey, tempId);
        await prefs.setBool(_tempSessionKey, true);
        
        debugPrint('✅ Temporary identity created successfully');
        return tempUser;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Failed to create temporary identity: $e');
      return null;
    }
  }

  static Future<UserModel?> getCurrentTemporaryUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool(_tempSessionKey) ?? false;
      
      if (!isActive) return null;
      
      final userId = prefs.getInt(_tempUserKey);
      if (userId == null) return null;
      
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
      debugPrint('Error getting temporary user: $e');
      return null;
    }
  }

  // Get temporary display name
  static Future<String?> getTemporaryDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tempDisplayNameKey);
    } catch (e) {
      debugPrint('Error getting temporary display name: $e');
      return null;
    }
  }

  // Get temporary identifier
  static Future<String?> getTemporaryIdentifier() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tempIdentifierKey);
    } catch (e) {
      debugPrint('Error getting temporary identifier: $e');
      return null;
    }
  }

  // Check if there's an active temporary session
  static Future<bool> hasActiveTemporarySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_tempSessionKey) ?? false;
    } catch (e) {
      debugPrint('Error checking temporary session: $e');
      return false;
    }
  }

  // Clear temporary session (when user logs in with real account or exits)
  static Future<void> clearTemporarySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_tempUserKey);
      await prefs.remove(_tempDisplayNameKey);
      await prefs.remove(_tempIdentifierKey);
      await prefs.setBool(_tempSessionKey, false);
      
      debugPrint('🧹 Temporary session cleared');
    } catch (e) {
      debugPrint('Error clearing temporary session: $e');
    }
  }

  // Upgrade temporary user to permanent account
  static Future<bool> upgradeToPermananentAccount(
    String email, 
    String password
  ) async {
    try {
      final tempUser = await getCurrentTemporaryUser();
      if (tempUser == null) return false;
      
      final prefs = await SharedPreferences.getInstance();
      final displayName = prefs.getString(_tempDisplayNameKey);
      
      // Create permanent user
      final permanentUser = await UserRepository.createUser(
        email: email,
        password: password,
        name: displayName ?? 'User',
        phoneNumber: null,
        isOnlineUser: true,
      );
      
      if (permanentUser != null && displayName != null) {
        
        // Clear temporary session
        await clearTemporarySession();
        
        debugPrint('⬆️ Successfully upgraded temporary account to permanent');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Failed to upgrade temporary account: $e');
      return false;
    }
  }

  // Get a user-friendly description of the current session
  static Future<String> getSessionDescription() async {
    try {
      final hasTemp = await hasActiveTemporarySession();
      if (!hasTemp) return 'No active session';
      
      final displayName = await getTemporaryDisplayName();
      final identifier = await getTemporaryIdentifier();
      
      if (displayName != null && identifier != null) {
        return 'Emergency mode: $displayName (#$identifier)';
      } else {
        return 'Emergency mode active';
      }
    } catch (e) {
      return 'Session status unknown';
    }
  }

  // Generate a shareable emergency contact code
  static Future<String?> generateEmergencyContactCode() async {
    try {
      final identifier = await getTemporaryIdentifier();
      final displayName = await getTemporaryDisplayName();
      
      if (identifier != null && displayName != null) {
        // Create a shareable code format: DISPLAYNAME-IDENTIFIER
        final code = '${displayName.replaceAll(' ', '').toUpperCase()}-$identifier';
        return code;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error generating emergency contact code: $e');
      return null;
    }
  }
}