import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/controllers/gps_controller.dart';
import 'package:resqlink/services/settings_service.dart';
import '../utils/responsive_utils.dart';
import '../utils/resqlink_theme.dart';
import 'message_page.dart';
import 'gps_page.dart';
import 'settings_page.dart';
import '../services/p2p/p2p_main_service.dart';
import '../services/p2p/p2p_base_service.dart';
import '../services/map_service.dart';
import '../services/location_state_service.dart';
import '../services/temporary_identity_service.dart';
import '../features/database/repositories/chat_repository.dart';
import '../controllers/home_controller.dart';
import '../helpers/chat_navigation_helper.dart';
import '../widgets/home/emergency_actions_card.dart';
import '../widgets/home/location_status_card.dart';
import '../widgets/home/connection_discovery_card.dart';
import '../widgets/home/instructions_card.dart';

class HomePage extends StatefulWidget {
  final int? initialTab;
  final double? initialGpsLatitude;
  final double? initialGpsLongitude;
  final String? senderName;

  const HomePage({
    super.key,
    this.initialTab,
    this.initialGpsLatitude,
    this.initialGpsLongitude,
    this.senderName,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late int selectedIndex;
  final P2PMainService _p2pService = P2PMainService();
  String? _userId = "user_${DateTime.now().millisecondsSinceEpoch}";
  bool _isP2PInitialized = false;
  bool _isInBackground = false;

  late HomeController _homeController;
  SettingsService? _settingsService;
  Timer? _updateTimer;

  // Shared GPS controller instance
  late GpsController _gpsController;

  late final List<Widget> pages;
  GlobalKey? _messagePageKey;

  // Track recently connected devices to prevent duplicate processing
  final Map<String, DateTime> _recentlyConnectedDevices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set initial tab if provided
    selectedIndex = widget.initialTab ?? 0;

    _homeController = HomeController(_p2pService);

    _gpsController = GpsController(
      _p2pService,
      userId: _userId,
      onLocationShare: _onLocationShare,
    );
    LocationStateService().setP2PService(_p2pService);

    _initializeP2P();
    _initializeMapService();

    // Clean up any existing duplicate chat sessions
    _cleanupDuplicateSessions();

    // Create MessagePage with key for external control
    _messagePageKey = GlobalKey();

    pages = [
      _buildHomePage(),
      ChangeNotifierProvider<GpsController>.value(
        value: _gpsController,
        child: GpsPage(
          userId: _userId,
          p2pService: _p2pService,
          onLocationShare: _onLocationShare,
          initialLatitude: widget.initialGpsLatitude,
          initialLongitude: widget.initialGpsLongitude,
          senderName: widget.senderName,
        ),
      ),
      MessagePage(
        key: _messagePageKey,
        p2pService: _p2pService,
        currentLocation: _homeController.currentLocation,
      ),
      SettingsPage(p2pService: _p2pService),
    ];

    // Set up lifecycle handler
    SystemChannels.lifecycle.setMessageHandler(_handleLifecycleMessage);

    // CRITICAL FIX: Check permissions immediately on first launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestPermissions();
    });
  }

  Widget _buildHomePage() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _homeController),
        ChangeNotifierProvider.value(value: LocationStateService()),
        ChangeNotifierProvider.value(
          value: _gpsController,
        ), // Add GPS controller
      ],
      child: Consumer3<HomeController, LocationStateService, GpsController>(
        builder: (context, controller, locationState, gpsController, child) {
          return RefreshIndicator(
            onRefresh: () async {
              // CRITICAL FIX: Add device scan to pull-to-refresh
              debugPrint('🔄 Pull to refresh triggered');
              await Future.wait([
                controller.refreshLocation(),
                locationState.refreshLocation(),
                gpsController.getCurrentLocation(),
                _homeController.startScan(), // Trigger device scan
              ]);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: ResponsiveSpacing.padding(
                    context,
                    horizontal: ResponsiveUtils.isMobile(context) ? 16 : 24,
                    vertical: ResponsiveUtils.isMobile(context) ? 16 : 20,
                  ),
                  child: ConstrainedBox(
                    constraints: ResponsiveUtils.isDesktop(context)
                        ? BoxConstraints(maxWidth: 1200)
                        : BoxConstraints(),
                    child: Column(
                      children: [
                        // Use responsive layout for tablet/desktop
                        if (ResponsiveUtils.isDesktop(context))
                          _buildDesktopLayout(
                            controller,
                            locationState,
                            gpsController,
                          )
                        else if (ResponsiveUtils.isTablet(context))
                          _buildTabletLayout(
                            controller,
                            locationState,
                            gpsController,
                          )
                        else
                          _buildMobileLayout(
                            controller,
                            locationState,
                            gpsController,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // Responsive layout builders
  Widget _buildMobileLayout(
    HomeController controller,
    LocationStateService locationState,
    GpsController gpsController,
  ) {
    return Column(
      children: [
        // Connection & Discovery Card
        ConnectionDiscoveryCard(
          controller: controller,
          onDeviceChatTap: _onDeviceChatTap,
        ),
        SizedBox(height: ResponsiveSpacing.lg(context)),

        // Emergency Actions (only when connected)
        if (controller.isConnected) ...[
          EmergencyActionsCard(
            p2pService: _p2pService,
            onEmergencyMessage: _sendEmergencyMessage,
          ),
          SizedBox(height: ResponsiveSpacing.lg(context)),
        ],

        // Location Status Card
        LocationStatusCard(
          location: locationState.currentLocation,
          isLoading: locationState.isLoadingLocation,
          unsyncedCount: locationState.unsyncedCount,
          onRefresh: () async {
            await locationState.refreshLocation();
            await gpsController.getCurrentLocation();
          },
          onShare: locationState.shareLocation,
        ),
        SizedBox(height: ResponsiveSpacing.lg(context)),

        // Instructions Card
        InstructionsCard(),
      ],
    );
  }

  Widget _buildTabletLayout(
    HomeController controller,
    LocationStateService locationState,
    GpsController gpsController,
  ) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ConnectionDiscoveryCard(
                controller: controller,
                onDeviceChatTap: _onDeviceChatTap,
              ),
            ),
            SizedBox(width: ResponsiveSpacing.lg(context)),
            Expanded(
              child: LocationStatusCard(
                location: locationState.currentLocation,
                isLoading: locationState.isLoadingLocation,
                unsyncedCount: locationState.unsyncedCount,
                onRefresh: () async {
                  await locationState.refreshLocation();
                  await gpsController.getCurrentLocation();
                },
                onShare: locationState.shareLocation,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveSpacing.lg(context)),

        // Emergency Actions (only when connected)
        if (controller.isConnected) ...[
          EmergencyActionsCard(
            p2pService: _p2pService,
            onEmergencyMessage: _sendEmergencyMessage,
          ),
          SizedBox(height: ResponsiveSpacing.lg(context)),
        ],

        // Instructions Card
        InstructionsCard(),
      ],
    );
  }

  Widget _buildDesktopLayout(
    HomeController controller,
    LocationStateService locationState,
    GpsController gpsController,
  ) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  ConnectionDiscoveryCard(
                    controller: controller,
                    onDeviceChatTap: _onDeviceChatTap,
                  ),
                  if (controller.isConnected) ...[
                    SizedBox(height: ResponsiveSpacing.lg(context)),
                    EmergencyActionsCard(
                      p2pService: _p2pService,
                      onEmergencyMessage: _sendEmergencyMessage,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 24)),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  LocationStatusCard(
                    location: locationState.currentLocation,
                    isLoading: locationState.isLoadingLocation,
                    unsyncedCount: locationState.unsyncedCount,
                    onRefresh: () async {
                      await locationState.refreshLocation();
                      await gpsController.getCurrentLocation();
                    },
                    onShare: locationState.shareLocation,
                  ),
                  SizedBox(height: ResponsiveSpacing.lg(context)),
                  InstructionsCard(),
                ],
              ),
            ),
          ],
        ),
      ],
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

    if (_isP2PInitialized) {
      try {
        debugPrint('🔍 Checking for existing connections...');

        await _p2pService.checkForExistingConnections();
        await _p2pService.checkForSystemConnections();

        debugPrint('✅ Connection check completed');
      } catch (e) {
        debugPrint('❌ Error checking connections on app resume: $e');
      }
    } else {
      debugPrint('⚠️ P2P service not initialized, skipping connection check');
    }
  }

  /// CRITICAL FIX: Check and request permissions with user feedback
  Future<void> _checkAndRequestPermissions() async {
    if (!mounted) return;

    try {
      debugPrint('🔐 Checking WiFi Direct permissions...');

      final granted = await _p2pService.checkAndRequestPermissions();

      if (!granted && mounted) {
        debugPrint('⚠️ Permissions not granted, showing user prompt');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Location & Nearby Devices permissions required for WiFi Direct',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
            action: SnackBarAction(
              label: 'GRANT',
              textColor: Colors.white,
              onPressed: () async {
                await _p2pService.checkAndRequestPermissions();
                // Retry after permission grant
                if (mounted) {
                  await Future.delayed(Duration(milliseconds: 500));
                  _checkAndRequestPermissions();
                }
              },
            ),
          ),
        );
      } else if (granted) {
        debugPrint('✅ All permissions granted');
      }
    } catch (e) {
      debugPrint('❌ Error checking permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to check permissions: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
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
    String? displayName =
        await TemporaryIdentityService.getTemporaryDisplayName();
    final userName =
        displayName ??
        "User_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";

    debugPrint('🆔 Initializing P2P with username: $userName');

    final preferredRole = DateTime.now().millisecondsSinceEpoch % 2 == 0
        ? 'host'
        : 'client';

    final success = await _p2pService.initialize(
      userName,
      preferredRole: preferredRole,
    );

    if (success) {
      setState(() => _isP2PInitialized = true);

      // Note: Message handling is centralized in P2PMainService and MessageRouter
      // Individual pages should use event listeners instead of overriding onMessageReceived
      _p2pService.onDeviceConnected = _onDeviceConnected;
      _p2pService.onDeviceDisconnected = _onDeviceDisconnected;
      _p2pService.addListener(_updateUI);
      _p2pService.emergencyMode = true;

      // Message queue service initialization removed
      debugPrint('✅ P2P Service initialized without message queue');

      // Clean up and merge any duplicate chat sessions based on deviceAddress
      // This runs on every startup to consolidate sessions from display name changes
      try {
        final duplicatesRemoved =
            await ChatRepository.cleanupDuplicateSessions();
        if (duplicatesRemoved > 0) {
          debugPrint(
            '🧹 Merged and cleaned $duplicatesRemoved duplicate chat sessions on startup',
          );
        }
      } catch (e) {
        debugPrint('❌ Error cleaning up duplicate sessions: $e');
      }
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

  void _onDeviceConnected(String deviceId, String userName) async {
    debugPrint("✅ Device connected: $userName ($deviceId)");

    // CRITICAL FIX: Register device with identifier resolver
    // This maps display name to MAC address for message routing
    _p2pService.registerDevice(deviceId, userName);
    debugPrint(
      "📝 Registered device: Display Name='$userName', MAC='$deviceId'",
    );

    // Prevent duplicate connection processing for the same device
    if (_recentlyConnectedDevices.containsKey(deviceId)) {
      final lastConnection = _recentlyConnectedDevices[deviceId]!;
      final timeSinceLastConnection = DateTime.now().difference(lastConnection);
      if (timeSinceLastConnection.inSeconds < 30) {
        // Increased from 10s to 30s
        debugPrint(
          "⚠️ Ignoring duplicate connection for $userName ($deviceId) - connected ${timeSinceLastConnection.inSeconds}s ago",
        );
        return;
      }
    }

    // Mark device as recently connected
    _recentlyConnectedDevices[deviceId] = DateTime.now();

    if (mounted) {
      // Create device map for navigation
      final device = {
        'deviceId': deviceId, // MAC address as identifier
        'deviceAddress': deviceId, // MAC address
        'deviceName': userName, // Display name for UI
        'isConnected': true,
      };

      // Create persistent conversation for the device (uses MAC as identifier)
      try {
        await _createPersistentConversationForDevice(deviceId, userName);
      } catch (e) {
        debugPrint('❌ Error creating persistent conversation: $e');
      }

      // Show enhanced connection notification with display name
      _showDisplayNameConnectedSnackBar(userName, device);

      // Auto-navigate to chat after a brief delay
      Timer(Duration(seconds: 2), () {
        if (mounted) {
          _onDeviceChatTap(device);
        }
      });
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
      // WiFi Direct only mode - no fallback configuration needed

      if (settings.offlineMode) {
        _p2pService.emergencyMode = true;
      }
    }
    setState(() {});
  }

  void _onLocationShare(LocationModel location) {}

  void _onDeviceChatTap(Map<String, dynamic> device) {
    debugPrint('🎯 HomePage: Device chat tap for ${device['deviceName']}');

    // Use the new ChatNavigationHelper to navigate to messages tab
    ChatNavigationHelper.navigateToMessagesTab(
      context: context,
      device: device,
      setSelectedIndex: (index) => setState(() => selectedIndex = index),
      messagePageKey: _messagePageKey,
    );
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

  /// Clean up duplicate chat sessions on app startup
  Future<void> _cleanupDuplicateSessions() async {
    try {
      await ChatRepository.cleanupDuplicateSessions();
      debugPrint('✅ Chat session cleanup completed');
    } catch (e) {
      debugPrint('❌ Chat session cleanup failed: $e');
    }
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

    // Message page is created once in initState and reused

    final mainArea = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: 200),
        child: pages[selectedIndex],
      ),
    );

    return Scaffold(
      appBar: _buildResponsiveAppBar(context),
      resizeToAvoidBottomInset:
          false, // Prevent bottom navigation from moving up with keyboard
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

  /// Show connection snackbar with display name
  void _showDisplayNameConnectedSnackBar(
    String userName,
    Map<String, dynamic> device,
  ) {
    ChatNavigationHelper.showConnectionSuccess(
      context: context,
      deviceName: userName,
      onChatTap: () => _onDeviceChatTap(device),
    );
  }

  /// Create persistent conversation for connected device with deduplication
  /// CRITICAL: deviceId MUST be the MAC address from WiFi Direct
  Future<void> _createPersistentConversationForDevice(
    String deviceId,
    String deviceName,
  ) async {
    try {
      debugPrint(
        '📱 Creating/updating chat session for: $deviceName (MAC: $deviceId)',
      );

      final currentUserName =
          await TemporaryIdentityService.getTemporaryDisplayName();

      // CRITICAL: Pass deviceAddress as the stable MAC address identifier
      // This ensures ONE session per device regardless of display name changes
      final sessionId = await ChatRepository.createOrUpdate(
        deviceId: deviceId, // MAC address
        deviceName: deviceName, // Current display name (can change)
        deviceAddress:
            deviceId, // CRITICAL: MAC address for stable identification
        currentUserId: 'local',
        currentUserName: currentUserName,
        peerUserName: deviceName,
      );

      if (sessionId.isNotEmpty) {
        debugPrint('✅ Chat session ready: $sessionId for $deviceName');
      } else {
        debugPrint('❌ Failed to create/update chat session');
      }
    } catch (e) {
      debugPrint('❌ Error creating persistent conversation: $e');
    }
  }
}
