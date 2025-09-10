import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/controllers/gps_controller.dart';
import 'package:resqlink/services/settings_service.dart';
import 'message_page.dart';
import 'gps_page.dart';
import 'settings_page.dart';
import 'services/p2p_service.dart';
import 'services/map_service.dart';
import 'services/location_state_service.dart';
import 'controllers/home_controller.dart';
import 'widgets/home/emergency_mode_card.dart';
import 'widgets/home/emergency_actions_card.dart';
import 'widgets/home/location_status_card.dart';
import 'widgets/home/connection_discovery_card.dart';
import 'widgets/home/instructions_card.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int selectedIndex = 0;
  final P2PConnectionService _p2pService = P2PConnectionService();
  String? _userId = "user_${DateTime.now().millisecondsSinceEpoch}";
  bool _isP2PInitialized = false;
  bool _isInBackground = false;

  late HomeController _homeController;
  SettingsService? _settingsService;
  Timer? _updateTimer;

  // Shared GPS controller instance
  late GpsController _gpsController;

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _homeController = HomeController(_p2pService);

    _gpsController = GpsController(
      _p2pService,
      userId: _userId,
      onLocationShare: _onLocationShare,
    );
    LocationStateService().setP2PService(_p2pService);

    _initializeP2P();
    _initializeMapService();

    pages = [
      _buildHomePage(),
      ChangeNotifierProvider<GpsController>.value(
        value: _gpsController,
        child: GpsPage(
          userId: _userId,
          p2pService: _p2pService,
          onLocationShare: _onLocationShare,
        ),
      ),
      MessagePage(
        p2pService: _p2pService,
        currentLocation: _homeController.currentLocation,
      ),
      SettingsPage(p2pService: _p2pService),
    ];

    // Set up lifecycle handler
    SystemChannels.lifecycle.setMessageHandler(_handleLifecycleMessage);
  }

  Widget _buildHomePage() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _homeController),
        ChangeNotifierProvider.value(value: LocationStateService()),
      ],
      child: Consumer2<HomeController, LocationStateService>(
        builder: (context, controller, locationState, child) {
          return RefreshIndicator(
            onRefresh: () async {
              await controller.refreshLocation();
              await locationState.refreshLocation();
            },
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Emergency Mode Card
                  EmergencyModeCard(
                    p2pService: _p2pService,
                    onToggle: controller.toggleEmergencyMode,
                  ),
                  SizedBox(height: 16),

                  // Connection & Discovery Card
                  ConnectionDiscoveryCard(controller: controller),
                  SizedBox(height: 16),

                  // Emergency Actions (only when connected)
                  if (controller.isConnected) ...[
                    EmergencyActionsCard(
                      p2pService: _p2pService,
                      onEmergencyMessage: _sendEmergencyMessage,
                    ),
                    SizedBox(height: 16),
                  ],

                  // Location Status Card - Now using shared state
                  LocationStatusCard(
                    location: locationState.currentLocation,
                    isLoading: locationState.isLoadingLocation,
                    unsyncedCount: locationState.unsyncedCount,
                    onRefresh: locationState.refreshLocation,
                    onShare: locationState.shareLocation,
                  ),
                  SizedBox(height: 16),

                  // Instructions Card
                  InstructionsCard(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsService == null) {
      _settingsService = context.read<SettingsService>();
      _settingsService!.loadSettings().then((_) async {
        if (mounted) {
          _onSettingsChanged();
          if (!_isP2PInitialized) {
            await _initializeP2P();
          }
        }
      });
      _settingsService!.addListener(_onSettingsChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _isInBackground = false;
        _onAppResumed();
        _p2pService.checkAndRequestPermissions();
      case AppLifecycleState.paused:
        _isInBackground = true;
        _onAppPaused();
      case AppLifecycleState.inactive:
        _onAppInactive();
      case AppLifecycleState.detached:
        _onAppDetached();
      case AppLifecycleState.hidden:
        _onAppHidden();
    }
  }

  // Lifecycle handler methods
  Future<String?> _handleLifecycleMessage(String? message) async {
    debugPrint('Lifecycle message: $message');
    switch (message) {
      case 'AppLifecycleState.paused':
        await _onAppPaused();
      case 'AppLifecycleState.resumed':
        await _onAppResumed();
      case 'AppLifecycleState.inactive':
        await _onAppInactive();
      case 'AppLifecycleState.detached':
        await _onAppDetached();
    }
    return null;
  }

  Future<void> _onAppResumed() async {
    debugPrint('App resumed - restoring state');
  }

  Future<void> _onAppPaused() async {
    debugPrint('App paused - saving state');
  }

  Future<void> _onAppInactive() async {}
  Future<void> _onAppDetached() async {}
  Future<void> _onAppHidden() async {}

  Future<void> _initializeMapService() async {
    try {
      await PhilippinesMapService.instance.initialize();
      debugPrint('✅ Map service initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize map service: $e');
    }
  }

  Future<void> _initializeP2P() async {
    final userName =
        "User_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
    final preferredRole = DateTime.now().millisecondsSinceEpoch % 2 == 0
        ? 'host'
        : 'client';

    final success = await _p2pService.initialize(
      userName,
      preferredRole: preferredRole,
    );

    if (success) {
      setState(() => _isP2PInitialized = true);

      _p2pService.onMessageReceived = _showNotification;
      _p2pService.onDeviceConnected = _onDeviceConnected;
      _p2pService.onDeviceDisconnected = _onDeviceDisconnected;
      _p2pService.addListener(_updateUI);
      _p2pService.emergencyMode = true;
    } else {
      setState(() => _isP2PInitialized = false);
      debugPrint("❌ Failed to initialize P2P service");
    }
  }

  void _updateUI() {
    if (!mounted) return;
    if (_updateTimer?.isActive == true) return;

    _updateTimer = Timer(Duration(milliseconds: 100), () {
      if (mounted) setState(() {});
    });
  }

  void _onDeviceConnected(String deviceId, String userName) {
    debugPrint("✅ Device connected: $userName ($deviceId)");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $userName'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _onDeviceDisconnected(String deviceId) {
    debugPrint("❌ Device disconnected: $deviceId");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device disconnected'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _onSettingsChanged() {
    if (_settingsService == null || !mounted) return;

    final settings = _settingsService!;
    if (_isP2PInitialized) {
      final connectionMode = settings.connectionMode;
      switch (connectionMode) {
        case 'wifi_direct':
          _p2pService.setHotspotFallbackEnabled(false);
        case 'hotspot_fallback':
          _p2pService.setHotspotFallbackEnabled(true);
        case 'hybrid':
        default:
          _p2pService.setHotspotFallbackEnabled(true);
      }

      if (settings.offlineMode) {
        _p2pService.emergencyMode = true;
      }
    }
    setState(() {});
  }

  void _showNotification(P2PMessage message) {
    if (!mounted) return;

    if (message.type == MessageType.emergency ||
        message.type == MessageType.sos) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.red.shade900,
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Text('EMERGENCY ALERT', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From: ${message.senderName}',
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                message.message,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (message.latitude != null && message.longitude != null) ...[
                SizedBox(height: 8),
                Text(
                  'Location: ${message.latitude!.toStringAsFixed(4)}, ${message.longitude!.toStringAsFixed(4)}',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK', style: TextStyle(color: Colors.white)),
            ),
            if (message.latitude != null && message.longitude != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() => selectedIndex = 2);
                },
                child: Text(
                  'View in Chat',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      );
    }
  }

  void _onLocationShare(LocationModel location) {
    // Handle location sharing
  }

  Future<void> _sendEmergencyMessage(EmergencyTemplate template) async {
    await _homeController.sendEmergencyMessage(template);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Emergency message sent!'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VIEW CHAT',
          onPressed: () => setState(() => selectedIndex = 2),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChannels.lifecycle.setMessageHandler(null);
    _settingsService?.removeListener(_onSettingsChanged);
    _p2pService.removeListener(_updateUI);
    _homeController.dispose();
    _p2pService.dispose();
    super.dispose();
  }

  PreferredSizeWidget _buildResponsiveAppBar(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;

    return AppBar(
      elevation: 2,
      shadowColor: Colors.black26,
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      toolbarHeight: isNarrowScreen ? 56 : 64,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B192C), Color(0xFF1E3A5F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: _buildAppBarTitle(isNarrowScreen),
      actions: _buildAppBarActions(isNarrowScreen),
    );
  }

  Widget _buildAppBarTitle(bool isNarrowScreen) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/1.png',
          height: isNarrowScreen ? 24 : 30,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.emergency,
            size: isNarrowScreen ? 24 : 30,
            color: Colors.white,
          ),
        ),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            "ResQLink",
            style: GoogleFonts.rajdhani(
              fontSize: isNarrowScreen ? 16 : 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(bool isNarrowScreen) {
    final actions = <Widget>[];

    // Emergency Mode Indicator
    if (_p2pService.emergencyMode) {
      actions.add(
        Container(
          margin: EdgeInsets.only(right: isNarrowScreen ? 4 : 8),
          padding: EdgeInsets.symmetric(
            horizontal: isNarrowScreen ? 8 : 12,
            vertical: isNarrowScreen ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emergency,
                size: isNarrowScreen ? 10 : 12,
                color: Colors.white,
              ),
              if (!isNarrowScreen ||
                  MediaQuery.of(context).size.width > 400) ...[
                SizedBox(width: 3),
                Text(
                  isNarrowScreen ? 'SOS' : 'EMERGENCY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isNarrowScreen ? 10 : 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // P2P Connection Status
    actions.add(
      Container(
        margin: EdgeInsets.only(right: isNarrowScreen ? 4 : 8),
        padding: EdgeInsets.symmetric(
          horizontal: isNarrowScreen ? 8 : 12,
          vertical: isNarrowScreen ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: _p2pService.currentRole != P2PRole.none
              ? Colors.green
              : Colors.grey,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:
                  (_p2pService.currentRole != P2PRole.none
                          ? Colors.green
                          : Colors.grey)
                      .withValues(alpha: 0.3),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_tethering,
              size: isNarrowScreen ? 12 : 16,
              color: Colors.white,
            ),
            if (!isNarrowScreen || MediaQuery.of(context).size.width > 360) ...[
              SizedBox(width: 3),
              Text(
                _p2pService.currentRole == P2PRole.host
                    ? (isNarrowScreen ? 'H' : 'HOST')
                    : _p2pService.currentRole == P2PRole.client
                    ? (isNarrowScreen ? 'C' : 'CLIENT')
                    : 'OFF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isNarrowScreen ? 10 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (_p2pService.connectedDevices.isNotEmpty) ...[
              SizedBox(width: 4),
              Container(
                padding: EdgeInsets.all(isNarrowScreen ? 2 : 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${_p2pService.connectedDevices.length}',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: isNarrowScreen ? 8 : 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Online/Offline Status
    actions.add(
      Padding(
        padding: EdgeInsets.only(right: isNarrowScreen ? 8 : 12),
        child: Container(
          padding: EdgeInsets.all(isNarrowScreen ? 6 : 8),
          decoration: BoxDecoration(
            color: _p2pService.isOnline
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _p2pService.isOnline ? Icons.cloud_done : Icons.cloud_off,
            color: _p2pService.isOnline ? Colors.green : Colors.grey.shade300,
            size: isNarrowScreen ? 16 : 20,
          ),
        ),
      ),
    );

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Update message page with current location
    if (selectedIndex == 2 && pages.length > 2) {
      pages[2] = MessagePage(
        p2pService: _p2pService,
        currentLocation: _homeController.currentLocation,
      );
    }

    final mainArea = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: 200),
        child: pages[selectedIndex],
      ),
    );

    return Scaffold(
      appBar: _buildResponsiveAppBar(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 450) {
            return Column(
              children: [
                Expanded(child: mainArea),
                SafeArea(
                  child: BottomNavigationBar(
                    currentIndex: selectedIndex,
                    onTap: (index) => setState(() => selectedIndex = index),
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: Color(0xFF0B192C),
                    selectedItemColor: Color(0xFFFF6500),
                    unselectedItemColor: Colors.grey,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.gps_fixed),
                        label: 'Location',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.message),
                        label: 'Chat',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    extended: constraints.maxWidth >= 600,
                    onDestinationSelected: (index) =>
                        setState(() => selectedIndex = index),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.gps_fixed),
                        label: Text('Location'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.message),
                        label: Text('Chat'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: mainArea),
              ],
            );
          }
        },
      ),
    );
  }

  // Required WidgetsBindingObserver methods that we don't need to implement
  @override
  void didChangeAccessibilityFeatures() {}

  @override
  void didChangeLocales(List<Locale>? locales) {}

  @override
  void didChangeMetrics() {}

  @override
  void didChangePlatformBrightness() {}

  @override
  void didChangeTextScaleFactor() {}

  @override
  void didHaveMemoryPressure() {}

  @override
  Future<bool> didPopRoute() async => false;

  @override
  Future<bool> didPushRoute(String route) async => false;

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async => false;

  bool get isInBackground => _isInBackground;
}
