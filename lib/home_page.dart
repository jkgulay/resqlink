import 'dart:async';
import 'package:flutter/material.dart';
import 'message_page.dart';
import 'gps_page.dart';
import 'settings_page.dart';
import '../services/p2p_services.dart';
import '../services/database_service.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int selectedIndex = 0;
  final P2PConnectionService _p2pService = P2PConnectionService();
  LocationModel? _currentLocation;
  String? _userId = "user_${DateTime.now().millisecondsSinceEpoch}";
  bool _isP2PInitialized = false;

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCurrentLocation();
    _initializeP2P();

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
        onLocationShare: (location) {
          setState(() {
            _currentLocation = location;
          });
          // Share location via P2P
          _shareLocationViaP2P(location);
        },
      ),
      MessagePage(p2pService: _p2pService, currentLocation: _currentLocation),
      SettingsPage(),
    ];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check permissions when app resumes
      _p2pService.checkAndRequestPermissions();
    }
  }

  Future<void> _initializeP2P() async {
    final userName =
        "User_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
    final success = await _p2pService.initialize(userName);

    if (success) {
      setState(() {
        _isP2PInitialized = true;
      });

      // Setup callbacks
      _p2pService.onMessageReceived = (message) {
        _showNotification(message);
      };

      _p2pService.onDeviceConnected = (deviceId, userName) {
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

      // Listen for changes
      _p2pService.addListener(_updateUI);

      // Enable emergency mode by default
      _p2pService.emergencyMode = true;
    }
  }

  void _updateUI() {
    if (mounted) setState(() {});
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
                  // Navigate to messages to see full conversation
                  setState(() {
                    selectedIndex = 2;
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
    _p2pService.removeListener(_updateUI);
    _p2pService.dispose();
    super.dispose();
  }

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
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/1.png',
              height: 30,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.emergency),
            ),
            const SizedBox(width: 8),
            const Text(
              "ResQLink",
              style: TextStyle(
                fontFamily: 'Ubuntu',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          // Emergency Mode Indicator
          if (_p2pService.emergencyMode)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emergency, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'EMERGENCY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          // P2P Connection Status
          Container(
            margin: EdgeInsets.only(right: 8),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _p2pService.currentRole != P2PRole.none
                  ? Colors.green
                  : Colors.grey,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  _p2pService.currentRole == P2PRole.host
                      ? 'HOST'
                      : _p2pService.currentRole == P2PRole.client
                      ? 'CLIENT'
                      : 'OFF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_p2pService.connectedDevices.isNotEmpty) ...[
                  SizedBox(width: 4),
                  Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_p2pService.connectedDevices.length}',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Online/Offline Status
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(
              _p2pService.isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _p2pService.isOnline ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
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
  List<BleDiscoveredDevice> _discoveredDevices = [];
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
    widget.p2pService.addListener(_updateUI);
    widget.p2pService.onDevicesDiscovered = _onDevicesDiscovered;

    // Enable emergency mode by default for quick connections
    if (widget.p2pService.connectedDevices.isEmpty) {
      widget.p2pService.emergencyMode = true;
    }
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
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
    widget.p2pService.onDevicesDiscovered = null;
    super.dispose();
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  void _onDevicesDiscovered(List<BleDiscoveredDevice> devices) {
    if (mounted) {
      setState(() {
        _discoveredDevices = devices;
        _isScanning = false;
      });
    }
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

  Future<void> _startManualScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    try {
      await widget.p2pService.checkAndRequestPermissions();
      await widget.p2pService.enableServices();

      // Start discovery scan
      final subscription = await widget.p2pService.startScan((devices) {
        setState(() {
          _discoveredDevices = devices;
        });
      });

      // Stop scan after 10 seconds
      Future.delayed(Duration(seconds: 10), () {
        subscription.cancel();
        if (mounted) {
          setState(() {
            _isScanning = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

            // Connection Status Card
            _buildConnectionStatusCard(connectionInfo, isConnected),

            const SizedBox(height: 16),

            // Quick Emergency Actions
            if (isConnected) _buildEmergencyActionsCard(),

            const SizedBox(height: 16),

            // Device Discovery Card
            _buildDeviceDiscoveryCard(),

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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                                : Colors.red,
                            size: 30,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Emergency Mode',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.p2pService.emergencyMode
                            ? Colors.white
                            : null,
                      ),
                    ),
                  ],
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
              const SizedBox(height: 12),
              Text(
                'Auto-connect enabled • Broadcasting location • High priority mode',
                style: TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(
    Map<String, dynamic> connectionInfo,
    bool isConnected,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Network Status',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                if (widget.p2pService.isDiscovering)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              Icons.person,
              'Device ID',
              connectionInfo['deviceId']?.toString().substring(0, 8) ??
                  'Not initialized',
            ),
            _buildStatusRow(
              Icons.router,
              'Role',
              connectionInfo['role']?.toString().toUpperCase() ?? 'NONE',
              valueColor: widget.p2pService.currentRole != P2PRole.none
                  ? Colors.green
                  : Colors.grey,
            ),
            _buildStatusRow(
              Icons.devices,
              'Connected',
              '${connectionInfo['connectedDevices'] ?? 0} devices',
            ),
            if (isConnected) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat),
                  label: const Text('Open Chat'),
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
          ],
        ),
      ),
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

  Widget _buildDeviceDiscoveryCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Nearby Devices',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                if (!_isScanning)
                  TextButton(onPressed: _startManualScan, child: Text('Scan')),
              ],
            ),
            const SizedBox(height: 12),
            if (_isScanning)
              Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Scanning for devices...'),
                  ],
                ),
              )
            else if (_discoveredDevices.isEmpty)
              Center(
                child: Text(
                  'No devices found nearby',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _discoveredDevices.length,
                itemBuilder: (context, index) {
                  final device = _discoveredDevices[index];
                  final deviceInfo = widget.p2pService.getDeviceInfo(
                    device.deviceAddress,
                  );

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: deviceInfo['isConnected']
                          ? Colors.green
                          : Colors.blue,
                      child: Icon(
                        deviceInfo['isKnown'] ? Icons.star : Icons.devices,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(device.deviceName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.deviceAddress),
                        if (deviceInfo['isKnown'])
                          Text(
                            'Known device',
                            style: TextStyle(color: Colors.green, fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: deviceInfo['isConnected']
                        ? Chip(
                            label: Text('Connected'),
                            backgroundColor: Colors.green,
                            labelStyle: TextStyle(color: Colors.white),
                          )
                        : ElevatedButton(
                            onPressed: () => _connectToDevice(device),
                            child: Text('Connect'),
                          ),
                  );
                },
              ),
            const SizedBox(height: 12),
            if (!widget.p2pService.emergencyMode && _discoveredDevices.isEmpty)
              Text(
                'Tip: Enable Emergency Mode for automatic discovery and connection',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectToDevice(BleDiscoveredDevice device) async {
    try {
      await widget.p2pService.connectToDevice(device);

      // Check if widget is still mounted before using context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.deviceName}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Check if widget is still mounted before using context
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _latestLocation!.type == LocationType.emergency ||
                          _latestLocation!.type == LocationType.sos
                      ? Icons.emergency_share
                      : Icons.location_on,
                  color:
                      _latestLocation!.type == LocationType.emergency ||
                          _latestLocation!.type == LocationType.sos
                      ? Colors.red
                      : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  "Last Known Location",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (_unsyncedCount > 0) ...[
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_unsyncedCount unsynced',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _buildLocationRow(
              Icons.map,
              "Latitude",
              _latestLocation!.latitude.toStringAsFixed(6),
            ),
            _buildLocationRow(
              Icons.map,
              "Longitude",
              _latestLocation!.longitude.toStringAsFixed(6),
            ),
            _buildLocationRow(
              Icons.access_time,
              "Time",
              _formatDateTime(_latestLocation!.timestamp),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  onPressed: () async {
                    await _loadLatestLocation();
                    await _checkUnsyncedLocations();
                    // Check if the widget is still mounted before using context
                    if (mounted) {
                      setState(() {}); // Update the UI if needed
                    }
                  },
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Share Location'),
                  onPressed: () async {
                    if (_latestLocation != null) {
                      await widget.p2pService.sendMessage(
                        message: 'My current location',
                        type: MessageType.location,
                        latitude: _latestLocation!.latitude,
                        longitude: _latestLocation!.longitude,
                      );
                      // Check if the widget is still mounted before using context
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Location shared'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'How It Works',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInstructionItem(
              '1.',
              'Emergency Mode automatically discovers and connects to nearby devices',
            ),
            _buildInstructionItem(
              '2.',
              'Messages relay through multiple devices to reach everyone (up to ${P2PConnectionService.maxTtl} hops)',
            ),
            _buildInstructionItem(
              '3.',
              'All devices use the same emergency password: ${P2PConnectionService.emergencyPassword}',
            ),
            _buildInstructionItem(
              '4.',
              'Messages are saved locally and sync to cloud when internet is available',
            ),
            _buildInstructionItem(
              '5.',
              'Location sharing helps rescuers find you in emergencies',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
