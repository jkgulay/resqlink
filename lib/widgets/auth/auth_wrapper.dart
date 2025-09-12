import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../firebase_auth_helper.dart';
import '../../services/auth_service.dart';
import '../../services/map_service.dart';
import '../../services/temporary_identity_service.dart';
import '../../models/user_model.dart';
import '../../pages/home_page.dart';
import '../../pages/landing_page.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  UserModel? _currentUser;
  bool _loading = true;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToAuthChanges();
    _bootstrap();
    _initializeMapService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('App resumed, checking auth state...');
      _bootstrap();
    }
  }

  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuthHelper.authStateChanges.listen((
      User? user,
    ) {
      print('Firebase auth state changed: ${user?.email}');
      if (user == null && _currentUser != null) {
        print('Firebase user logged out, clearing local state');
        setState(() {
          _currentUser = null;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeMapService() async {
    try {
      await PhilippinesMapService.instance.initialize();
      debugPrint('✅ Map service initialized successfully');
    } catch (e) {
      debugPrint('❌ Map service initialization failed: $e');
    }
  }

  Future<void> _bootstrap() async {
    print('Bootstrapping emergency authentication...');

    // Check connectivity
    final connected = await AuthService.isConnected;
    print('Connected: $connected');

    // Priority 1: Check for active temporary session (emergency mode)
    final hasTemporarySession = await TemporaryIdentityService.hasActiveTemporarySession();
    if (hasTemporarySession) {
      _currentUser = await TemporaryIdentityService.getCurrentTemporaryUser();
      if (_currentUser != null) {
        final sessionDesc = await TemporaryIdentityService.getSessionDescription();
        print('Active temporary session found: $sessionDesc');
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
    }

    // Priority 2: Try online authentication if connected
    if (connected) {
      try {
        _currentUser = await AuthService.trySilentFirebaseLogin();
        print('Silent Firebase login result: ${_currentUser?.email}');
        if (_currentUser != null) {
          if (mounted) {
            setState(() => _loading = false);
          }
          return;
        }
      } catch (e) {
        print('Silent Firebase login failed: $e');
      }
    }

    // Priority 3: Try offline login with saved credentials
    _currentUser = await AuthService.tryOfflineLogin();
    print('Offline login result: ${_currentUser?.email}');

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emergency, size: 80, color: Colors.red),
              SizedBox(height: 16),
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Checking authentication...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return _currentUser != null ? HomePage() : const LandingPage();
  }
}