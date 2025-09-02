import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/services/settings_service.dart';
import 'package:resqlink/utils/resqlink_theme.dart';
import 'message_page.dart';
import 'gps_page.dart';
import 'settings_page.dart';
import 'services/p2p_service.dart';
import '../services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/map_service.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, AppLifecycleMixin {
  int selectedIndex = 0;
  final P2PConnectionService _p2pService = P2PConnectionService();
  LocationModel? _currentLocation;
  String? _userId = "user_${DateTime.now().millisecondsSinceEpoch}";
  bool _isP2PInitialized = false;

  // Store the settings service reference
  SettingsService? _settingsService;

  @override
  Future<void> onAppResumed() async {
    // Refresh P2P status
    await _p2pService.checkAndRequestPermissions();
    setState(() {});
  }

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Don't access context.read here - do it in didChangeDependencies
    _loadCurrentLocation();
    _initializeP2P();
    _initializeMapService();

    pages = [
      EmergencyHomePage(
        p2pService: _p2pService,
        onLocationUpdate: (location) {
          setState(() {
            _currentLocation = location;
          });
        },
      ),
      GpsPage(
        userId: _userId,
        p2pService: _p2pService,

        onLocationShare: (location) {
          setState(() {
            _currentLocation = location;
          });
          // Share location via P2P
          _shareLocationViaP2P(location);
        },
      ),
      MessagePage(p2pService: _p2pService, currentLocation: _currentLocation),
      SettingsPage(p2pService: _p2pService),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Safely get the settings service reference here
    if (_settingsService == null) {
      _settingsService = context.read<SettingsService>();
      // Load settings and apply them
      _settingsService!.loadSettings().then((_) {
        if (mounted) {
          _onSettingsChanged(); // Apply settings to P2P service
        }
      });
      _settingsService!.addListener(_onSettingsChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check permissions when app resumes
      _p2pService.checkAndRequestPermissions();
    }
  }

  Future<void> _initializeMapService() async {
    try {
      await PhilippinesMapService.instance.initialize();
      debugPrint('Map service initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize map service: $e');
    }
  }

  Future<void> _initializeP2P() async {
    final userName =
        "User_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";

    // Determine preferred role based on some criteria (e.g., battery level, device type)
    final preferredRole = DateTime.now().millisecondsSinceEpoch % 2 == 0
        ? 'host'
        : 'client';

    final success = await _p2pService.initialize(
      userName,
      preferredRole: preferredRole,
    );

    final prefs = await SharedPreferences.getInstance();
    final connectionMode = prefs.getString('connection_mode') ?? 'hybrid';
    switch (connectionMode) {
      case 'wifi_direct':
        _p2pService.setHotspotFallbackEnabled(false);
      case 'hotspot_fallback':
        _p2pService.setHotspotFallbackEnabled(true);
      case 'hybrid':
      default:
        _p2pService.setHotspotFallbackEnabled(true);
    }

    if (success) {
      setState(() {
        _isP2PInitialized = true;
      });

      _p2pService.onMessageReceived = (message) {
        _showNotification(message);
      };

      _p2pService.onDeviceConnected = (deviceId, userName) {
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
      };

      _p2pService.onDeviceDisconnected = (deviceId) {
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
      };

      _p2pService.addListener(_updateUI);

      // Enable emergency mode by default
      _p2pService.emergencyMode = true;
    } else {
      debugPrint("❌ Failed to initialize P2P service");
    }
  }

  void _updateUI() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _shareLocationViaP2P(LocationModel location) async {
    if (!_isP2PInitialized) return;

    await _p2pService.sendMessage(
      message: 'Shared location: ${location.type.name}',
      type: MessageType.location,
      latitude: location.latitude,
      longitude: location.longitude,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location shared via P2P network'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _onSettingsChanged() {
    // Use the stored reference instead of context.read
    if (_settingsService == null || !mounted) return;

    final settings = _settingsService!;

    // Apply settings to P2P service
    if (_isP2PInitialized) {
      // Update connection mode
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

      // Update multi-hop setting
      if (!settings.multiHopEnabled) {
        // Disable multi-hop features if needed
      }

      // Update offline mode
      if (settings.offlineMode) {
        // Force offline mode
        _p2pService.emergencyMode = true;
      }
    }
    setState(() {}); // Refresh UI to show connection mode changes
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
              SizedBox(height: 8),
              Text(
                'Hops: ${message.routePath.length}',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
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
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        selectedIndex = 2;
                      });
                    }
                  });
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

  Future<void> _loadCurrentLocation() async {
    try {
      final location = await LocationService.getLastKnownLocation();
      if (mounted && location != null) {
        setState(() {
          _currentLocation = location;
        });
      }
    } catch (e) {
      print('Error loading location: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Use the stored reference instead of context.read
    if (_settingsService != null) {
      _settingsService!.removeListener(_onSettingsChanged);
    }

    _p2pService.removeListener(_updateUI);
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
        // Logo with responsive sizing
        Image.asset(
          'assets/1.png',
          height: isNarrowScreen ? 24 : 30,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.emergency,
            size: isNarrowScreen ? 24 : 30,
            color: Colors.white,
          ),
        ),
        SizedBox(width: ResponsiveSpacing.xs(context)),
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

    // Emergency Mode Indicator - Responsive
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
                color: Colors.red.withValues(alpha: 0.3), // Fixed
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
                Text(
                  _p2pService.hotspotFallbackEnabled ? 'HYBRID' : 'DIRECT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isNarrowScreen ? 8 : 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // P2P Connection Status - Responsive
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
            // Show connection mode indicator
            if (_settingsService != null) ...[
              SizedBox(width: 4),
              Text(
                _getConnectionModeAbbreviation(
                  _settingsService!.connectionMode,
                ),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isNarrowScreen ? 8 : 10,
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

    // Online/Offline Status - Always visible but responsive
    actions.add(
      Padding(
        padding: EdgeInsets.only(right: isNarrowScreen ? 8 : 12),
        child: Container(
          padding: EdgeInsets.all(isNarrowScreen ? 6 : 8),
          decoration: BoxDecoration(
            color: _p2pService.isOnline
                ? Colors.green.withValues(alpha: 0.2) // Fixed
                : Colors.grey.withValues(alpha: 0.2), // Fixed
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

  String _getConnectionModeAbbreviation(String mode) {
    switch (mode) {
      case 'wifi_direct':
        return 'DIRECT';
      case 'hotspot_fallback':
        return 'HOTSPOT';
      case 'hybrid':
      default:
        return 'HYBRID';
    }
  }

  // UPDATED: Build method with responsive AppBar
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Update message page with current location
    if (selectedIndex == 2 && pages.length > 2) {
      pages[2] = MessagePage(
        p2pService: _p2pService,
        currentLocation: _currentLocation,
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
}

// Emergency Home Page
class EmergencyHomePage extends StatefulWidget {
  final P2PConnectionService p2pService;
  final Function(LocationModel)? onLocationUpdate;

  const EmergencyHomePage({
    super.key,
    required this.p2pService,
    this.onLocationUpdate,
  });

  @override
  State<EmergencyHomePage> createState() => _EmergencyHomePageState();
}

class _EmergencyHomePageState extends State<EmergencyHomePage>
    with SingleTickerProviderStateMixin {
  LocationModel? _latestLocation;
  bool _isLoadingLocation = true;
  int _unsyncedCount = 0;
  List<Map<String, dynamic>> _discoveredDevices = [];
  bool _isScanning = false;

  // Animation controller for emergency pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadLatestLocation();
    _checkUnsyncedLocations();

    // Setup listeners
    widget.p2pService.onDevicesDiscovered = _onDevicesDiscovered;
    widget.p2pService.addListener(_updateUI);
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.p2pService.emergencyMode) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    widget.p2pService.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  void _onDevicesDiscovered(List<Map<String, dynamic>> devices) {
    setState(() {
      _discoveredDevices = devices;
      if (_isScanning && devices.isNotEmpty) {
        // Stop scanning animation once devices are found
        _isScanning = false;
      }
    });
  }

  Future<void> _loadLatestLocation() async {
    try {
      setState(() {
        _isLoadingLocation = true;
      });

      final lastLocation = await LocationService.getLastKnownLocation();

      if (mounted) {
        setState(() {
          _latestLocation = lastLocation;
          _isLoadingLocation = false;
        });

        if (lastLocation != null && widget.onLocationUpdate != null) {
          widget.onLocationUpdate!(lastLocation);
        }
      }
    } catch (e) {
      print('Error loading last location: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _checkUnsyncedLocations() async {
    try {
      final messages = await DatabaseService.getUnsyncedMessages();
      if (mounted) {
        setState(() {
          _unsyncedCount = messages.length;
        });
      }
    } catch (e) {
      print('Error checking unsynced: $e');
    }
  }

  void _toggleEmergencyMode() {
    setState(() {
      widget.p2pService.emergencyMode = !widget.p2pService.emergencyMode;
      if (widget.p2pService.emergencyMode) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  void _sendEmergencyMessage(EmergencyTemplate template) async {
    await widget.p2pService.sendEmergencyTemplate(template);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Emergency message sent!'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _performConnectionTest() async {
    try {
      await widget.p2pService.sendMessage(
        message: 'Test message from ${widget.p2pService.userName}',
        type: MessageType.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Test message sent!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionInfo = widget.p2pService.getConnectionInfo();
    final isConnected = widget.p2pService.connectedDevices.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadLatestLocation();
        await _checkUnsyncedLocations();
      },
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Emergency Mode Toggle Card
            _buildEmergencyModeCard(),

            const SizedBox(height: 16),

            // Unified Device Discovery Card (merged!)
            _buildConnectionAndDiscoveryCard(connectionInfo, isConnected),

            const SizedBox(height: 16),

            // Quick Emergency Actions
            if (isConnected) _buildEmergencyActionsCard(),

            const SizedBox(height: 16),

            // Location Card
            if (!_isLoadingLocation && _latestLocation != null)
              _buildLocationCard(),

            const SizedBox(height: 16),

            // Instructions Card
            _buildInstructionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyModeCard() {
    return Card(
      color: widget.p2pService.emergencyMode ? Colors.red.shade900 : null,
      elevation: 4,
      child: ResponsiveWidget(
        mobile: _buildMobileEmergencyCard(),
        tablet: _buildTabletEmergencyCard(),
      ),
    );
  }

  Widget _buildMobileEmergencyCard() {
    return Padding(
      padding: ResponsiveSpacing.padding(context, all: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: widget.p2pService.emergencyMode
                              ? _pulseAnimation.value
                              : 1.0,
                          child: Icon(
                            Icons.emergency,
                            color: widget.p2pService.emergencyMode
                                ? Colors.white
                                : ResQLinkTheme.primaryRed,
                            size: ResponsiveSpacing.lg(context),
                          ),
                        );
                      },
                    ),
                    SizedBox(width: ResponsiveSpacing.sm(context)),
                    Expanded(
                      child: ResponsiveTextWidget(
                        'Emergency Mode',
                        styleBuilder: (context) =>
                            ResponsiveText.heading3(context).copyWith(
                              color: widget.p2pService.emergencyMode
                                  ? Colors.white
                                  : ResQLinkTheme.primaryRed,
                            ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: widget.p2pService.emergencyMode,
                onChanged: (value) => _toggleEmergencyMode(),
                activeColor: Colors.white,
                activeTrackColor: Colors.red.shade300,
              ),
            ],
          ),
          if (widget.p2pService.emergencyMode) ...[
            SizedBox(height: ResponsiveSpacing.sm(context)),
            ResponsiveTextWidget(
              'Auto-connect enabled • Broadcasting location • High priority mode',
              styleBuilder: (context) => ResponsiveText.caption(
                context,
              ).copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabletEmergencyCard() {
    return Padding(
      padding: ResponsiveSpacing.padding(context, all: 24),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: widget.p2pService.emergencyMode
                    ? _pulseAnimation.value
                    : 1.0,
                child: Icon(
                  Icons.emergency,
                  color: widget.p2pService.emergencyMode
                      ? Colors.white
                      : ResQLinkTheme.primaryRed,
                  size: ResponsiveSpacing.xl(context),
                ),
              );
            },
          ),
          SizedBox(width: ResponsiveSpacing.md(context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResponsiveTextWidget(
                  'Emergency Mode',
                  styleBuilder: (context) =>
                      ResponsiveText.heading2(context).copyWith(
                        color: widget.p2pService.emergencyMode
                            ? Colors.white
                            : ResQLinkTheme.primaryRed,
                      ),
                ),
                if (widget.p2pService.emergencyMode) ...[
                  SizedBox(height: ResponsiveSpacing.xs(context)),
                  ResponsiveTextWidget(
                    'Auto-connect enabled • Broadcasting location • High priority mode',
                    styleBuilder: (context) => ResponsiveText.bodySmall(
                      context,
                    ).copyWith(color: Colors.white70),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: widget.p2pService.emergencyMode,
            onChanged: (value) => _toggleEmergencyMode(),
            activeColor: Colors.white,
            activeTrackColor: Colors.red.shade300,
          ),
        ],
      ),
    );
  }

  // NEW: Enhanced status row method
  Widget _buildEnhancedStatusRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final connectionInfo = widget.p2pService.getConnectionInfo();
    final connectionType = connectionInfo['connectionType'] ?? 'wifi_direct';

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Color(0xFF1E3A5F)),
              if (connectionType == 'hotspot') ...[
                SizedBox(width: 4),
                Icon(Icons.wifi_tethering, size: 12, color: Colors.orange),
              ],
            ],
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: valueColor ?? Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (connectionType == 'hotspot') ...[
                    SizedBox(width: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'HOTSPOT',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyActionsCard() {
    return Card(
      elevation: 2,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.quick_contacts_mail, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Quick Emergency Messages',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildEmergencyButton(
                  'SOS',
                  Colors.red,
                  Icons.sos,
                  () => _sendEmergencyMessage(EmergencyTemplate.sos),
                ),
                _buildEmergencyButton(
                  'Trapped',
                  Colors.orange,
                  Icons.warning,
                  () => _sendEmergencyMessage(EmergencyTemplate.trapped),
                ),
                _buildEmergencyButton(
                  'Medical',
                  Colors.blue,
                  Icons.medical_services,
                  () => _sendEmergencyMessage(EmergencyTemplate.medical),
                ),
                _buildEmergencyButton(
                  'Safe',
                  Colors.green,
                  Icons.check_circle,
                  () => _sendEmergencyMessage(EmergencyTemplate.safe),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyButton(
    String label,
    Color color,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildConnectionAndDiscoveryCard(
    Map<String, dynamic> connectionInfo,
    bool isConnected,
  ) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.08),
              Color(0xFF1E3A5F).withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status indicator and scan control - Responsive
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 400;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top header row with enhanced design
                      Container(
                        padding: EdgeInsets.all(isNarrow ? 18 : 22),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Color(0xFF1E3A5F).withValues(alpha: 0.12),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Status icon with enhanced styling
                            Container(
                              padding: EdgeInsets.all(isNarrow ? 14 : 16),
                              decoration: BoxDecoration(
                                color: isConnected
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isConnected
                                      ? Colors.green
                                      : Colors.grey,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isConnected
                                                ? Colors.green
                                                : Colors.grey)
                                            .withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.wifi_tethering,
                                color: isConnected ? Colors.green : Colors.grey,
                                size: isNarrow ? 26 : 30,
                              ),
                            ),
                            SizedBox(width: isNarrow ? 14 : 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Network & Devices',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: isNarrow ? 18 : 20,
                                      color: Color.fromARGB(255, 252, 254, 255),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: isConnected
                                              ? Colors.green
                                              : Colors.orange,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  (isConnected
                                                          ? Colors.green
                                                          : Colors.orange)
                                                      .withValues(alpha: 0.4),
                                              blurRadius: 6,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          isConnected
                                              ? 'Connected & Ready'
                                              : 'Searching for devices...',
                                          style: TextStyle(
                                            color: isConnected
                                                ? Colors.green
                                                : Colors.orange,
                                            fontSize: isNarrow ? 13 : 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isNarrow ? 18 : 22),

                      // Unified scan button with enhanced styling
                      Container(
                        width: double.infinity,
                        height: isNarrow ? 50 : 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: _isScanning
                              ? LinearGradient(
                                  colors: [Colors.grey, Colors.grey.shade600],
                                )
                              : LinearGradient(
                                  colors: [
                                    Color(0xFFFF6500),
                                    Color(0xFFFF8533),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          boxShadow: _isScanning
                              ? []
                              : [
                                  BoxShadow(
                                    color: Color(
                                      0xFFFF6500,
                                    ).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                    spreadRadius: 1,
                                  ),
                                ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isScanning ? null : _startUnifiedScan,
                          icon: _isScanning
                              ? SizedBox(
                                  width: isNarrow ? 18 : 20,
                                  height: isNarrow ? 18 : 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  widget.p2pService.isDiscovering
                                      ? Icons.refresh
                                      : Icons.radar,
                                  size: isNarrow ? 18 : 20,
                                ),
                          label: Text(
                            _isScanning
                                ? 'Scanning...'
                                : widget.p2pService.isDiscovering
                                ? 'Refresh Network'
                                : 'Scan for Devices',
                            style: TextStyle(
                              fontSize: isNarrow ? 14 : 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      // Show scan stats with improved design
                      if (_discoveredDevices.isNotEmpty ||
                          widget.p2pService.connectedDevices.isNotEmpty) ...[
                        SizedBox(height: 14),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.analytics,
                                size: isNarrow ? 16 : 18,
                                color: Colors.blue,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Found: ${_discoveredDevices.length} nearby • Connected: ${widget.p2pService.connectedDevices.length}',
                                style: TextStyle(
                                  fontSize: isNarrow ? 12 : 13,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),

              SizedBox(height: 24),

              // Connection details section with enhanced glass design
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    105,
                    107,
                    109,
                  ).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Color(0xFF1E3A5F).withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF0B192C).withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildEnhancedStatusRow(
                      Icons.person_outline,
                      'Device ID',
                      connectionInfo['deviceId']?.toString().substring(0, 8) ??
                          'Not initialized',
                      valueColor: Color.fromARGB(255, 116, 117, 119),
                    ),
                    SizedBox(height: 16),
                    _buildEnhancedStatusRow(
                      Icons.router_outlined,
                      'Network Role',
                      connectionInfo['role']?.toString().toUpperCase() ??
                          'NONE',
                      valueColor: widget.p2pService.currentRole != P2PRole.none
                          ? Colors.green
                          : Color(0xFF666666),
                    ),
                    SizedBox(height: 16),
                    _buildEnhancedStatusRow(
                      Icons.devices_outlined,
                      'Connected Devices',
                      '${connectionInfo['connectedDevices'] ?? 0}',
                      valueColor: Color.fromARGB(255, 116, 117, 119),
                    ),
                    if (isConnected) ...[
                      SizedBox(height: 16),
                      _buildEnhancedStatusRow(
                        Icons.network_check,
                        'Network Quality',
                        'Excellent',
                        valueColor: Colors.green,
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Device discovery results section
              if (_isScanning)
                _buildScanningState()
              // Discovered devices list
              else if (_discoveredDevices.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    return Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Color(0xFF1E3A5F).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Icon(
                                  Icons.devices,
                                  color: Colors.green,
                                  size: isNarrow ? 18 : 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Found ${_discoveredDevices.length} device${_discoveredDevices.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: isNarrow ? 15 : 16,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isNarrow ? 16 : 20),

                          // Device list
                          ListView.separated(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: _discoveredDevices.length,
                            separatorBuilder: (context, index) =>
                                SizedBox(height: isNarrow ? 8 : 12),
                            itemBuilder: (context, index) {
                              final device = _discoveredDevices[index];
                              final deviceInfo = widget.p2pService
                                  .getDeviceInfo(device['deviceAddress']);

                              final signalStrength =
                                  -45 -
                                  (index * 8) -
                                  (DateTime.now().millisecondsSinceEpoch % 20);

                              return _buildResponsiveDeviceItem(
                                device,
                                deviceInfo,
                                signalStrength,
                                isNarrow,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                )
              // No devices found state
              else if (_discoveredDevices.isEmpty &&
                  !widget.p2pService.isDiscovering &&
                  !_isScanning)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    return Container(
                      padding: EdgeInsets.all(isNarrow ? 20 : 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Color(0xFF1E3A5F).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              Icons.devices_other,
                              size: isNarrow ? 40 : 48,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          SizedBox(height: isNarrow ? 12 : 16),
                          Text(
                            'No devices found nearby',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: isNarrow ? 16 : 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Make sure other devices have ResQLink open and WiFi enabled',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: isNarrow ? 12 : 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // Connected devices section with enhanced design
              if (widget.p2pService.connectedDevices.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    return Container(
                      margin: EdgeInsets.only(top: 20),
                      padding: EdgeInsets.all(isNarrow ? 16 : 20),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: isNarrow ? 18 : 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Connected Devices',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: isNarrow ? 15 : 16,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isNarrow ? 12 : 16),
                          ...widget.p2pService.connectedDevices.values.map(
                            (device) => Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.wifi_tethering,
                                    size: isNarrow ? 16 : 18,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      device.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: isNarrow ? 14 : 15,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.green.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      device.isHost ? 'HOST' : 'CLIENT',
                                      style: TextStyle(
                                        fontSize: isNarrow ? 10 : 11,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              SizedBox(height: 24),

              // Action buttons section - Responsive with enhanced design
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 400;

                  return Column(
                    children: [
                      // Test connection button
                      if (isConnected) ...[
                        Container(
                          width: double.infinity,
                          height: isNarrow ? 52 : 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [Color(0xFF0B192C), Color(0xFF1E3A5F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF0B192C).withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.science, size: 20),
                            label: Text(
                              'Test Connection',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => _performConnectionTest(),
                          ),
                        ),
                        SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          height: isNarrow ? 52 : 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [Colors.green, Colors.green.shade600],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.chat_bubble_outline, size: 20),
                            label: Text(
                              'Open Chat',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MessagePage(
                                    p2pService: widget.p2pService,
                                    currentLocation: _latestLocation,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                      // Emergency mode tip
                      if (!widget.p2pService.emergencyMode &&
                          _discoveredDevices.isEmpty &&
                          !_isScanning) ...[
                        if (isConnected) SizedBox(height: 20),
                        Container(
                          padding: EdgeInsets.all(isNarrow ? 16 : 18),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Icon(
                                  Icons.lightbulb_outline,
                                  color: Colors.orange,
                                  size: isNarrow ? 18 : 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Tip: Enable Emergency Mode for automatic discovery and connection',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: isNarrow ? 12 : 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reusable scanning state widget
  Widget _buildScanningState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 400;
        return Container(
          padding: EdgeInsets.all(isNarrow ? 20 : 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(0xFF1E3A5F).withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: isNarrow ? 12 : 16),
                Text(
                  'Scanning for devices...',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: isNarrow ? 16 : 18,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'This may take up to 10 seconds',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isNarrow ? 12 : 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // In your home_page.dart, update the connection button method:
  Future<void> _startUnifiedScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    try {
      await widget.p2pService.checkAndRequestPermissions();

      // Use the connection fallback manager
      await widget.p2pService.connectionFallbackManager.initiateConnection();

      // Auto-stop scanning after 15 seconds
      Timer(Duration(seconds: 15), () {
        if (mounted && _isScanning) {
          setState(() {
            _isScanning = false;
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.network_check, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Smart connection initiated (WiFi Direct + Hotspot)'),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildResponsiveDeviceItem(
    Map<String, dynamic> device,
    Map<String, dynamic> deviceInfo,
    int signalStrength,
    bool isNarrow,
  ) {
    final signalLevel = _getSignalLevel(signalStrength);
    final signalColor = _getSignalColor(signalLevel);
    final isConnected = deviceInfo['isConnected'] ?? false;
    final isKnown = deviceInfo['isKnown'] ?? false;

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? Colors.green.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isConnected ? Colors.green : Colors.grey).withValues(
              alpha: 0.15,
            ),
            blurRadius: 8,
            offset: Offset(0, 2),
            spreadRadius: 1,
          ),
        ],
      ),
      child: isNarrow
          ? _buildNarrowDeviceLayout(
              device,
              deviceInfo,
              signalStrength,
              signalLevel,
              signalColor,
              isConnected,
              isKnown,
            )
          : _buildWideDeviceLayout(
              device,
              deviceInfo,
              signalStrength,
              signalLevel,
              signalColor,
              isConnected,
              isKnown,
            ),
    );
  }

  // Narrow screen layout (stacked) with enhanced design
  Widget _buildNarrowDeviceLayout(
    Map<String, dynamic> device,
    Map<String, dynamic> deviceInfo,
    int signalStrength,
    int signalLevel,
    Color signalColor,
    bool isConnected,
    bool isKnown,
  ) {
    return Padding(
      padding: ResponsiveSpacing.padding(context, all: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + name + status
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: isConnected
                        ? Colors.green
                        : signalColor.withValues(alpha: 0.2),
                    radius: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isConnected
                              ? Colors.green.shade700
                              : signalColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isConnected ? Colors.green : signalColor)
                                .withValues(alpha: 0.3),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        isKnown ? Icons.star : Icons.devices,
                        color: isConnected ? Colors.white : signalColor,
                        size: 22,
                      ),
                    ),
                  ),
                  if (isKnown)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.bookmark,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device['deviceName'] ?? 'Unknown Device',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isConnected ? Colors.green : null,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      device['deviceAddress'] ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 14),

          // Bottom row: signal + button
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: signalColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSignalBars(signalLevel, signalColor, size: 12),
                    SizedBox(width: 6),
                    Text(
                      '$signalStrength dBm',
                      style: TextStyle(
                        fontSize: 10,
                        color: signalColor,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Text(
                _getSignalQualityText(signalLevel),
                style: TextStyle(
                  fontSize: 11,
                  color: signalColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Spacer(),
              _buildActionButton(device, isConnected, signalLevel, true),
            ],
          ),
        ],
      ),
    );
  }

  // Wide screen layout (horizontal) with enhanced design
  Widget _buildWideDeviceLayout(
    Map<String, dynamic> device,
    Map<String, dynamic> deviceInfo,
    int signalStrength,
    int signalLevel,
    Color signalColor,
    bool isConnected,
    bool isKnown,
  ) {
    return Padding(
      padding: EdgeInsets.all(18),
      child: Row(
        children: [
          // Device icon with signal indicator
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                backgroundColor: isConnected
                    ? Colors.green
                    : signalColor.withValues(alpha: 0.2),
                radius: 28,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isConnected ? Colors.green.shade700 : signalColor,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected ? Colors.green : signalColor)
                            .withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isKnown ? Icons.star : Icons.devices,
                    color: isConnected ? Colors.white : signalColor,
                    size: 26,
                  ),
                ),
              ),
              if (isKnown)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(Icons.bookmark, size: 14, color: Colors.white),
                  ),
                ),
              if (!isConnected)
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: _buildSignalBars(signalLevel, signalColor, size: 12),
                  ),
                ),
            ],
          ),

          SizedBox(width: 18),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        device['deviceName'] ?? 'Unknown Device',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isConnected ? Colors.green : null,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 6),

                Text(
                  device['deviceAddress'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),

                SizedBox(height: 10),

                // Signal strength and status
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: signalColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSignalBars(signalLevel, signalColor),
                      SizedBox(width: 8),
                      Text(
                        '$signalStrength dBm',
                        style: TextStyle(
                          fontSize: 11,
                          color: signalColor,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        _getSignalQualityText(signalLevel),
                        style: TextStyle(
                          fontSize: 11,
                          color: signalColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(width: 16),

          // Action button
          _buildActionButton(device, isConnected, signalLevel, false),
        ],
      ),
    );
  }

  // Responsive action button with enhanced design
  Widget _buildActionButton(
    Map<String, dynamic> device,
    bool isConnected,
    int signalLevel,
    bool isNarrow,
  ) {
    if (isConnected) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 12 : 16,
          vertical: isNarrow ? 8 : 10,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green, Colors.green.shade600],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: Offset(0, 3),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              size: isNarrow ? 14 : 16,
              color: Colors.white,
            ),
            SizedBox(width: 6),
            Text(
              'Connected',
              style: TextStyle(
                color: Colors.white,
                fontSize: isNarrow ? 11 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    } else {
      final buttonColor = signalLevel >= 3 ? Colors.blue : Colors.orange;

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: signalLevel >= 3
                ? [Colors.blue, Colors.blue.shade600]
                : [Colors.orange, Colors.orange.shade600],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: buttonColor.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: Offset(0, 3),
              spreadRadius: 1,
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: () => _connectToDevice(device),
          icon: Icon(Icons.link, size: isNarrow ? 14 : 16),
          label: Text(
            'Connect',
            style: TextStyle(
              fontSize: isNarrow ? 11 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 12 : 16,
              vertical: isNarrow ? 8 : 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
  }

  int _getSignalLevel(int dbm) {
    if (dbm >= -50) return 5;
    if (dbm >= -60) return 4;
    if (dbm >= -70) return 3;
    if (dbm >= -80) return 2;
    if (dbm >= -90) return 1;
    return 0;
  }

  Color _getSignalColor(int level) {
    switch (level) {
      case 5:
      case 4:
        return Colors.green;
      case 3:
        return Colors.amber;
      case 2:
      case 1:
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _getSignalQualityText(int level) {
    switch (level) {
      case 5:
      case 4:
        return 'Excellent';
      case 3:
        return 'Good';
      case 2:
        return 'Fair';
      case 1:
        return 'Poor';
      default:
        return 'Very Poor';
    }
  }

  Widget _buildSignalBars(int level, Color color, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isActive = index < level;
        final barHeight = (size / 4) + (index * (size / 8));
        return Container(
          width: size / 6,
          height: barHeight,
          margin: EdgeInsets.only(right: 1.5),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 2,
                      spreadRadius: 0.5,
                    ),
                  ]
                : [],
          ),
        );
      }),
    );
  }

  Future<void> _connectToDevice(Map<String, dynamic> device) async {
    try {
      await widget.p2pService.connectToDevice(device);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device['deviceName']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 8,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.08),
              Color(0xFF1E3A5F).withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 400;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enhanced header with glass morphism design
                  Container(
                    padding: EdgeInsets.all(isNarrow ? 18 : 22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Color(0xFF1E3A5F).withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Enhanced location icon with glow effect
                        Container(
                          padding: EdgeInsets.all(isNarrow ? 14 : 16),
                          decoration: BoxDecoration(
                            color:
                                (_latestLocation!.type ==
                                        LocationType.emergency ||
                                    _latestLocation!.type == LocationType.sos)
                                ? Colors.red.withValues(alpha: 0.15)
                                : Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color:
                                  (_latestLocation!.type ==
                                          LocationType.emergency ||
                                      _latestLocation!.type == LocationType.sos)
                                  ? Colors.red
                                  : Colors.blue,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    ((_latestLocation!.type ==
                                                    LocationType.emergency ||
                                                _latestLocation!.type ==
                                                    LocationType.sos)
                                            ? Colors.red
                                            : Colors.blue)
                                        .withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            _latestLocation!.type == LocationType.emergency ||
                                    _latestLocation!.type == LocationType.sos
                                ? Icons.emergency_share
                                : Icons.location_on,
                            color:
                                _latestLocation!.type ==
                                        LocationType.emergency ||
                                    _latestLocation!.type == LocationType.sos
                                ? Colors.red
                                : Colors.blue,
                            size: isNarrow ? 26 : 30,
                          ),
                        ),
                        SizedBox(width: isNarrow ? 14 : 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Known Location',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: isNarrow ? 18 : 20,
                                  color: Color.fromARGB(255, 252, 254, 255),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color:
                                          (_latestLocation!.type ==
                                                  LocationType.emergency ||
                                              _latestLocation!.type ==
                                                  LocationType.sos)
                                          ? Colors.red
                                          : Colors.green,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              ((_latestLocation!.type ==
                                                              LocationType
                                                                  .emergency ||
                                                          _latestLocation!
                                                                  .type ==
                                                              LocationType.sos)
                                                      ? Colors.red
                                                      : Colors.green)
                                                  .withValues(alpha: 0.4),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      (_latestLocation!.type ==
                                                  LocationType.emergency ||
                                              _latestLocation!.type ==
                                                  LocationType.sos)
                                          ? 'Emergency Location Active'
                                          : 'Location Available',
                                      style: TextStyle(
                                        color:
                                            (_latestLocation!.type ==
                                                    LocationType.emergency ||
                                                _latestLocation!.type ==
                                                    LocationType.sos)
                                            ? Colors.red
                                            : Colors.green,
                                        fontSize: isNarrow ? 13 : 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Unsynced badge with modern design
                        if (_unsyncedCount > 0)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 10 : 12,
                              vertical: isNarrow ? 6 : 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '$_unsyncedCount unsynced',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: isNarrow ? 11 : 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Location details section with enhanced glass design
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Color.fromARGB(
                        255,
                        105,
                        107,
                        109,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Color(0xFF1E3A5F).withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF0B192C).withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildEnhancedLocationRow(
                          Icons.my_location,
                          "Latitude",
                          _latestLocation!.latitude.toStringAsFixed(6),
                          valueColor: Color.fromARGB(255, 116, 117, 119),
                          isNarrow: isNarrow,
                        ),
                        SizedBox(height: 16),
                        _buildEnhancedLocationRow(
                          Icons.my_location,
                          "Longitude",
                          _latestLocation!.longitude.toStringAsFixed(6),
                          valueColor: Color.fromARGB(255, 116, 117, 119),
                          isNarrow: isNarrow,
                        ),
                        SizedBox(height: 16),
                        _buildEnhancedLocationRow(
                          Icons.schedule,
                          "Timestamp",
                          _formatDateTime(_latestLocation!.timestamp),
                          valueColor: Color.fromARGB(255, 116, 117, 119),
                          isNarrow: isNarrow,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Enhanced action buttons
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: isNarrow ? 50 : 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [Color(0xFF0B192C), Color(0xFF1E3A5F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF0B192C).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.refresh, size: isNarrow ? 16 : 18),
                            label: Text(
                              'Refresh',
                              style: TextStyle(
                                fontSize: isNarrow ? 14 : 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () async {
                              await _loadLatestLocation();
                              await _checkUnsyncedLocations();
                              if (mounted) {
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: isNarrow ? 50 : 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF6500), Color(0xFFFF8533)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFFF6500).withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.share, size: isNarrow ? 16 : 18),
                            label: Text(
                              'Share',
                              style: TextStyle(
                                fontSize: isNarrow ? 14 : 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () async {
                              if (_latestLocation != null) {
                                await widget.p2pService.sendMessage(
                                  message: 'My current location',
                                  type: MessageType.location,
                                  latitude: _latestLocation!.latitude,
                                  longitude: _latestLocation!.longitude,
                                );
                                if (!mounted) return;

                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Location shared successfully'),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      elevation: 8,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color(0xFF0B192C).withValues(alpha: 0.08),
              Color(0xFF1E3A5F).withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Color(0xFF1E3A5F).withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 400;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enhanced header
                  Container(
                    padding: EdgeInsets.all(isNarrow ? 18 : 22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Color(0xFF1E3A5F).withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(isNarrow ? 14 : 16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.orange,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.lightbulb,
                            color: Colors.orange,
                            size: isNarrow ? 26 : 30,
                          ),
                        ),
                        SizedBox(width: isNarrow ? 14 : 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'How It Works',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: isNarrow ? 18 : 20,
                                  color: Color.fromARGB(255, 252, 254, 255),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'ResQLink Emergency Network',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: isNarrow ? 13 : 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Instructions list with enhanced design
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Color.fromARGB(
                        255,
                        105,
                        107,
                        109,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Color(0xFF1E3A5F).withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF0B192C).withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildEnhancedInstructionItem(
                          '1',
                          'Emergency Mode automatically discovers and connects to nearby devices using WiFi Direct (up to 200m range)',
                          Icons.wifi_tethering,
                          Colors.blue,
                          isNarrow,
                        ),
                        SizedBox(height: 20),
                        _buildEnhancedInstructionItem(
                          '2',
                          'Messages relay through multiple devices to reach everyone (up to ${P2PConnectionService.maxTtl} hops)',
                          Icons.hub,
                          Colors.green,
                          isNarrow,
                        ),
                        SizedBox(height: 20),
                        _buildEnhancedInstructionItem(
                          '3',
                          'No internet required - pure peer-to-peer communication',
                          Icons.cloud_off,
                          Colors.purple,
                          isNarrow,
                        ),
                        SizedBox(height: 20),
                        _buildEnhancedInstructionItem(
                          '4',
                          'Messages are saved locally and sync to cloud when internet is available',
                          Icons.sync,
                          Colors.teal,
                          isNarrow,
                        ),
                        SizedBox(height: 20),
                        _buildEnhancedInstructionItem(
                          '5',
                          'Location sharing helps rescuers find you in emergencies',
                          Icons.my_location,
                          Colors.red,
                          isNarrow,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedLocationRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    required bool isNarrow,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: isNarrow ? 16 : 18, color: Colors.blue),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isNarrow ? 12 : 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? Color.fromARGB(255, 252, 254, 255),
                  fontSize: isNarrow ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedInstructionItem(
    String number,
    String text,
    IconData icon,
    Color color,
    bool isNarrow,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: isNarrow ? 40 : 44,
          height: isNarrow ? 40 : 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: isNarrow ? 18 : 20, color: color),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: isNarrow ? 16 : 18,
                  height: isNarrow ? 16 : 18,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isNarrow ? 10 : 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: TextStyle(
                fontSize: isNarrow ? 13 : 14,
                color: Color.fromARGB(255, 200, 200, 200),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return dateTime.toString().substring(0, 19);
    }
  }
}

class BatteryWarningManager {
  static const String _lastWarningKey = 'last_battery_warning';
  static const String _dismissedWarningKey = 'battery_warning_dismissed';
  static const Duration _warningCooldown = Duration(hours: 1);

  static Future<bool> shouldShowWarning(int batteryLevel) async {
    final prefs = await SharedPreferences.getInstance();

    final dismissed = prefs.getBool(_dismissedWarningKey) ?? false;
    if (dismissed && batteryLevel > 15) {
      await prefs.setBool(_dismissedWarningKey, false);
    } else if (dismissed) {
      return false;
    }

    final lastWarningTimestamp = prefs.getInt(_lastWarningKey) ?? 0;
    final lastWarning = DateTime.fromMillisecondsSinceEpoch(
      lastWarningTimestamp,
    );
    final now = DateTime.now();

    if (now.difference(lastWarning) < _warningCooldown) {
      return false;
    }

    if (batteryLevel <= 10) {
      await prefs.setInt(_lastWarningKey, now.millisecondsSinceEpoch);
      return true;
    }

    return false;
  }

  static Future<void> dismissWarning() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedWarningKey, true);
  }

  static void showDismissibleWarning(BuildContext context, int batteryLevel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.battery_alert, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Low battery ($batteryLevel%)! Consider activating SOS mode.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 10),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () async {
            await BatteryWarningManager.dismissWarning();
          },
        ),
      ),
    );
  }
}

class DeviceSignalWidget extends StatelessWidget {
  final String deviceName;
  final String deviceAddress;
  final int signalStrength;
  final bool isConnected;
  final bool isKnown;
  final VoidCallback onConnect;

  const DeviceSignalWidget({
    required this.deviceName,
    required this.deviceAddress,
    required this.signalStrength,
    required this.isConnected,
    required this.isKnown,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final signalLevel = _getSignalLevel(signalStrength);
    final signalColor = _getSignalColor(signalLevel);

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              backgroundColor: isConnected
                  ? Colors.green
                  : signalColor.withValues(
                      alpha: 0.2,
                    ), // Fixed from withAlpha(51)
              radius: 24,
              child: Icon(
                isKnown ? Icons.star : Icons.devices,
                color: isConnected ? Colors.white : signalColor,
                size: 24,
              ),
            ),
            if (!isConnected)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: _buildSignalIndicator(signalLevel, signalColor),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                deviceName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isConnected ? Colors.green : null,
                ),
              ),
            ),
            if (isKnown) Icon(Icons.bookmark, size: 16, color: Colors.amber),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(deviceAddress, style: TextStyle(fontSize: 12)),
            SizedBox(height: 2),
            Row(
              children: [
                _buildSignalBars(signalLevel, signalColor),
                SizedBox(width: 8),
                Text(
                  '$signalStrength dBm',
                  style: TextStyle(fontSize: 11, color: signalColor),
                ),
                if (isKnown) ...[
                  SizedBox(width: 8),
                  Text(
                    '• Known device',
                    style: TextStyle(fontSize: 11, color: Colors.green),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: isConnected
            ? Chip(
                label: Text('Connected'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white, fontSize: 12),
              )
            : ElevatedButton(
                onPressed: onConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: signalLevel >= 3
                      ? Colors.blue
                      : Colors.orange,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text('Connect'),
              ),
      ),
    );
  }

  int _getSignalLevel(int dbm) {
    if (dbm >= -50) return 5;
    if (dbm >= -60) return 4;
    if (dbm >= -70) return 3;
    if (dbm >= -80) return 2;
    if (dbm >= -90) return 1;
    return 0;
  }

  Color _getSignalColor(int level) {
    switch (level) {
      case 5:
      case 4:
        return Colors.green;
      case 3:
        return Colors.amber;
      case 2:
      case 1:
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Widget _buildSignalIndicator(int level, Color color) {
    return Icon(Icons.signal_cellular_alt, size: 16, color: color);
  }

  Widget _buildSignalBars(int level, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isActive = index < level;
        return Container(
          width: 3,
          height: 4.0 + (index * 2),
          margin: EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

mixin AppLifecycleMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  bool _isInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (mounted) {
      SystemChannels.lifecycle.setMessageHandler(_handleLifecycleMessage);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChannels.lifecycle.setMessageHandler(null);
    super.dispose();
  }

  Future<String?> _handleLifecycleMessage(String? message) async {
    debugPrint('Lifecycle message: $message');

    switch (message) {
      case 'AppLifecycleState.paused':
        await onAppPaused();
      case 'AppLifecycleState.resumed':
        await onAppResumed();
      case 'AppLifecycleState.inactive':
        await onAppInactive();
      case 'AppLifecycleState.detached':
        await onAppDetached();
    }

    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _isInBackground = false;
        onAppResumed();
      case AppLifecycleState.paused:
        _isInBackground = true;
        onAppPaused();
      case AppLifecycleState.inactive:
        onAppInactive();
      case AppLifecycleState.detached:
        onAppDetached();
      case AppLifecycleState.hidden:
        onAppHidden();
    }
  }

  // Override these in your widgets
  Future<void> onAppResumed() async {
    debugPrint('App resumed - restoring state');
    // Restore P2P connections, refresh UI, etc.
  }

  Future<void> onAppPaused() async {
    debugPrint('App paused - saving state');
    // Save current state, maintain P2P connections
  }

  Future<void> onAppInactive() async {}
  Future<void> onAppDetached() async {}
  Future<void> onAppHidden() async {}

  bool get isInBackground => _isInBackground;
}
