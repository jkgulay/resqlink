import 'package:flutter/material.dart';
import '../../utils/responsive_utils.dart';
import '../../services/auth_service.dart';
import '../../services/message_sync_service.dart';
import '../../pages/home_page.dart';

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

    // Validation
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter all fields');
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

    if (!isLogin && password != confirmPassword) {
      _showSnackBar('Passwords do not match');
      return;
    }

    setState(() => isLoading = true);

    try {
      AuthResult result;
      if (isLogin) {
        result = await AuthService.login(email, password);
      } else {
        result = await AuthService.register(email, password);
      }

      if (result.isSuccess && result.user != null) {
        // Initialize MessageSyncService only after successful authentication
        if (result.method == AuthMethod.online) {
          try {
            MessageSyncService().initialize();
            debugPrint('✅ MessageSyncService initialized after login');
          } catch (e) {
            debugPrint('⚠️ MessageSyncService initialization failed: $e');
          }
        }

        final methodText = result.method == AuthMethod.online
            ? 'Online'
            : 'Offline';
        _showSnackBar(
          '${isLogin ? 'Login' : 'Registration'} successful ($methodText)',
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
      print('Auth exception: $e');
      _showSnackBar('An error occurred: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isLoading = false);
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
        FutureBuilder<bool>(
          future: AuthService.isOnline(),
          builder: (context, snapshot) {
            final online = snapshot.data ?? false;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: online
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: online ? Colors.green : Colors.orange,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    online ? Icons.cloud_done : Icons.cloud_off,
                    color: online ? Colors.green : Colors.orange,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    online ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: online ? Colors.green : Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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
