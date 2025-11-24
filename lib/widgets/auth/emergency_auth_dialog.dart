import 'package:flutter/material.dart';
import '../../utils/responsive_utils.dart';
import '../../services/auth_service.dart';
import '../../services/temporary_identity_service.dart';
import '../../services/messaging/message_sync_service.dart';
import '../../services/p2p/wifi_direct_service.dart';
import '../../services/identity_service.dart';
import '../../pages/home_page.dart';

class EmergencyAuthDialog extends StatefulWidget {
  const EmergencyAuthDialog({super.key});

  @override
  State<EmergencyAuthDialog> createState() => _EmergencyAuthDialogState();
}

class _EmergencyAuthDialogState extends State<EmergencyAuthDialog> {
  final displayNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isOnline = false;
  bool _showOnlineLogin = false;
  bool _isLoading = false;
  bool _isLogin = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  @override
  void dispose() {
    displayNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final online = await AuthService.isOnline();
    if (mounted) {
      setState(() {
        _isOnline = online;
      });
    }
  }

  //void _toggleOnlineLogin() {
  //  setState(() {
  //  _showOnlineLogin = !_showOnlineLogin;
  //  emailController.clear();
  //  passwordController.clear();
  // });
  // }

  void _toggleLoginMode() {
    setState(() {
      _isLogin = !_isLogin;
      emailController.clear();
      passwordController.clear();
    });
  }

  Future<void> _handleEmergencyStart() async {
    final displayName = displayNameController.text.trim();

    if (displayName.isEmpty) {
      _showSnackBar('Please enter your display name');
      return;
    }

    if (displayName.length < 2) {
      _showSnackBar('Display name must be at least 2 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // CRITICAL FIX: Clear old session data before creating new identity
      await TemporaryIdentityService.clearTemporarySession();
      debugPrint('🧹 Cleared old session data before new login');

      // Create temporary identity for emergency use
      final tempUser = await TemporaryIdentityService.createTemporaryIdentity(
        displayName,
      );

      if (tempUser != null) {
        // IMPORTANT: Set WiFi Direct device name to match display name
        // This ensures the device shows the user's chosen name instead of the system name
        try {
          final wifiDirectService = WiFiDirectService.instance;
          await wifiDirectService.setDeviceName(displayName);
          debugPrint('✅ WiFi Direct device name set to: $displayName');
        } catch (e) {
          debugPrint('⚠️ Failed to set WiFi Direct device name: $e');
          // Non-critical error - continue anyway
        }

        _showSnackBar('Emergency mode activated', Colors.green);
        await Future.delayed(Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
        }
      } else {
        _showSnackBar('Failed to create emergency identity');
      }
      // Persist new display name so IdentityService / P2P initialization picks it up
      final identityService = IdentityService();
      await identityService.setDisplayName(displayName);
      identityService.clearCache();
      debugPrint('💾 Stored new identity display name: $displayName');
    } catch (e) {
      _showSnackBar('Emergency setup failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOnlineAuth() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter email and password');
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showSnackBar('Please enter a valid email address');
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      AuthResult result;
      if (_isLogin) {
        result = await AuthService.login(email, password);
      } else {
        result = await AuthService.register(email, password);
      }

      if (result.isSuccess && result.user != null) {
        // Initialize sync service for online users
        if (result.method == AuthMethod.online) {
          try {
            MessageSyncService().initialize();
            debugPrint('✅ MessageSyncService initialized after login');
          } catch (e) {
            debugPrint('⚠️ MessageSyncService initialization failed: $e');
          }
        }

        _showSnackBar(
          '${_isLogin ? 'Login' : 'Registration'} successful',
          Colors.green,
        );

        await Future.delayed(Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
        }
      } else {
        _showSnackBar(result.errorMessage ?? 'Authentication failed');
      }
    } catch (e) {
      _showSnackBar('Authentication error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, [Color? color]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color ?? Colors.red,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
        child: SingleChildScrollView(
          padding: EdgeInsets.all(
            ResponsiveUtils.getResponsiveSpacing(context, 20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 20),
              ),

              if (!_showOnlineLogin) ...[
                _buildEmergencySection(),
              ] else ...[
                _buildOnlineSection(),
              ],

              SizedBox(
                height: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),
              _buildModeToggle(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _showOnlineLogin
              ? (_isLogin ? "Account Login" : "Create Account")
              : "Emergency Access",
          style: TextStyle(
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 24),
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isOnline
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _isOnline ? Colors.green : Colors.orange),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isOnline ? Icons.cloud_done : Icons.cloud_off,
                color: _isOnline ? Colors.green : Colors.orange,
                size: 14,
              ),
              SizedBox(width: 4),
              Text(
                _isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  color: _isOnline ? Colors.green : Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(
            ResponsiveUtils.getResponsiveSpacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.emergency, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isOnline
                      ? 'Quick emergency access - no account required'
                      : 'Offline emergency mode - ready to use',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: ResponsiveUtils.getResponsiveFontSize(
                      context,
                      12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),

        Text(
          'Enter your display name to start:',
          style: TextStyle(
            color: Colors.white,
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
            fontWeight: FontWeight.w500,
          ),
        ),

        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 12)),

        TextField(
          controller: displayNameController,
          style: TextStyle(
            color: Colors.white,
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
          ),
          decoration: InputDecoration(
            labelText: 'Display Name (e.g., "John", "Rescue Team 1")',
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
        ),

        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _isLoading ? null : _handleEmergencyStart,
            icon: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(Icons.emergency),
            label: Text(
              'Start Emergency Chat',
              style: TextStyle(
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineSection() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(
            ResponsiveUtils.getResponsiveSpacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.sync, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sync your profile and chat history across devices',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: ResponsiveUtils.getResponsiveFontSize(
                      context,
                      12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),

        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(
            color: Colors.white,
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
          ),
          decoration: InputDecoration(
            labelText: 'Email',
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
        ),

        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 12)),

        TextField(
          controller: passwordController,
          obscureText: true,
          style: TextStyle(
            color: Colors.white,
            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
          ),
          decoration: InputDecoration(
            labelText: 'Password',
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
        ),

        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 20)),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6500),
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _isLoading ? null : _handleOnlineAuth,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _isLogin ? "Login" : "Create Account",
                    style: TextStyle(
                      fontSize: ResponsiveUtils.getResponsiveFontSize(
                        context,
                        16,
                      ),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),

        if (_showOnlineLogin) ...[
          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 12)),
          TextButton(
            onPressed: _isLoading ? null : _toggleLoginMode,
            child: Text(
              _isLogin
                  ? "Need an account? Create one"
                  : "Already have an account? Login",
              style: TextStyle(
                color: Colors.white,
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeToggle() {
    // Disabled: User requested to hide this option
    return SizedBox.shrink();

    // Original code commented out:
    // if (!_isOnline) return SizedBox.shrink();
    //
    // return TextButton(
    //   onPressed: _isLoading ? null : _toggleOnlineLogin,
    //   child: Text(
    //     _showOnlineLogin
    //       ? "← Back to Emergency Mode"
    //       : "Have an account? Login instead",
    //     style: TextStyle(
    //       color: Colors.white70,
    //       fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
    //       decoration: TextDecoration.underline,
    //     ),
    //   ),
    // );
  }
}
