// lib/pages/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'message_page.dart';
import 'gps_page.dart';
import 'settings_page.dart';
import '../services/p2p_services.dart';
import '../services/database_service.dart';
import '../models/message_model.dart';
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => GpsPage(userId: _userId)),
                  );
                },
                child: Text(
                  'View Location',
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
          if (_currentLocation != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Icon(
                Icons.location_on,
                color: _currentLocation!.type == LocationType.emergency
                    ? Colors.red
                    : Colors.green,
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
                        label: 'Geolocation',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.message),
                        label: 'Messages',
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
                        label: Text('Geolocation'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.message),
                        label: Text('Messages'),
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

class _EmergencyHomePageState extends State<EmergencyHomePage> {
  LocationModel? _latestLocation;
  bool _isLoadingLocation = true;
  int _unsyncedCount = 0;
  StreamSubscription<List<BleDiscoveredDevice>>? _scanSubscription;
  List<BleDiscoveredDevice> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _loadLatestLocation();
    _checkUnsyncedLocations();
    widget.p2pService.addListener(_updateUI);
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    widget.p2pService.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() {
    if (mounted) setState(() {});
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

  void _showQuickEmergencyDialog(BuildContext context) {
    final TextEditingController messageController = TextEditingController();

    if (_latestLocation != null) {
      messageController.text =
          'EMERGENCY! My location: '
          'Lat: ${_latestLocation!.latitude.toStringAsFixed(6)}, '
          'Lon: ${_latestLocation!.longitude.toStringAsFixed(6)}';
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.emergency, color: Colors.red),
            SizedBox(width: 8),
            Text('Emergency Broadcast'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter emergency message...',
                border: OutlineInputBorder(),
              ),
            ),
            if (_latestLocation != null) ...[
              SizedBox(height: 8),
              Text(
                'Location will be included',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final message = messageController.text;

              // Close dialog first
              Navigator.of(dialogContext).pop();

              // Send emergency broadcast with location
              await widget.p2pService.sendMessage(
                message: message,
                type: MessageType.emergency,
                latitude: _latestLocation?.latitude,
                longitude: _latestLocation?.longitude,
              );

              // Check if widget is still mounted before showing snackbar
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Emergency broadcast sent!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Send Emergency'),
          ),
        ],
      ),
    );
  }

  void _showP2POptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('P2P Network Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.group_add, color: Colors.blue),
              title: Text('Create Emergency Group'),
              subtitle: Text('Become a host for others to connect'),
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await _createEmergencyGroup();
              },
            ),
            ListTile(
              leading: Icon(Icons.search, color: Colors.green),
              title: Text('Find Nearby Groups'),
              subtitle: Text('Scan for existing emergency networks'),
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await _startScanning();
              },
            ),
            if (widget.p2pService.knownDevices.isNotEmpty)
              ListTile(
                leading: Icon(Icons.history, color: Colors.orange),
                title: Text('Reconnect to Known Devices'),
                subtitle: Text(
                  '${widget.p2pService.knownDevices.length} devices saved',
                ),
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  _showKnownDevicesDialog();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _createEmergencyGroup() async {
    try {
      // Check permissions first
      if (!await widget.p2pService.checkAndRequestPermissions()) {
        throw Exception('Permissions not granted');
      }

      // Enable services
      if (!await widget.p2pService.enableServices()) {
        throw Exception('Required services not enabled');
      }

      // Check if still mounted before showing dialog
      if (!mounted) return;

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Creating emergency group...'),
                ],
              ),
            ),
          ),
        ),
      );

      await widget.p2pService.createEmergencyGroup();

      // Check if still mounted before using context
      if (!mounted) return;

      Navigator.of(context).pop(); // Close loading

      // Show success with group info
      final hostState = widget.p2pService.hostState;
      if (hostState != null && hostState.ssid != null) {
        if (!mounted) return;
        _showGroupCreatedDialog(hostState.ssid!, hostState.preSharedKey ?? '');
      }
    } catch (e) {
      // Check if still mounted before using context
      if (!mounted) return;

      // Close loading dialog if it's still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create group: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showGroupCreatedDialog(String ssid, String psk) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Group Created!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Others can now connect using:'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network: $ssid',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Password: $psk',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Share these credentials with nearby devices or let them scan via Bluetooth.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _startScanning() async {
    try {
      // Check permissions
      if (!await widget.p2pService.checkAndRequestPermissions()) {
        throw Exception('Permissions not granted');
      }

      if (!await widget.p2pService.enableServices()) {
        throw Exception('Required services not enabled');
      }

      // Check if still mounted before setState
      if (!mounted) return;

      setState(() {
        _discoveredDevices.clear();
      });

      // Start scanning
      _scanSubscription = await widget.p2pService.startScan((devices) {
        // Check if still mounted before setState in callback
        if (mounted) {
          setState(() {
            _discoveredDevices = devices;
          });
        }
      });

      // Check if still mounted before showing dialog
      if (!mounted) return;

      // Show scanning dialog
      _showScanningDialog();
    } catch (e) {
      // Check if still mounted before showing snackbar
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start scanning: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showScanningDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Scanning for Groups...'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_discoveredDevices.isEmpty)
              Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No devices found yet.\nMake sure other devices are hosting groups.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              )
            else
              ...List.generate(_discoveredDevices.length, (index) {
                final device = _discoveredDevices[index];
                return ListTile(
                  leading: Icon(Icons.wifi_tethering, color: Colors.blue),
                  title: Text(device.deviceName),
                  subtitle: Text(device.deviceAddress),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _connectToDevice(device);
                    },
                    child: Text('Connect'),
                  ),
                );
              }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _scanSubscription?.cancel();
              Navigator.of(context).pop();
            },
            child: Text('Cancel'),
          ),
        ],
      ),
    ).then((_) {
      _scanSubscription?.cancel();
    });
  }

  Future<void> _connectToDevice(BleDiscoveredDevice device) async {
    try {
      // Show connecting dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting to ${device.deviceName}...'),
                ],
              ),
            ),
          ),
        ),
      );

      await widget.p2pService.connectToDevice(device);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.deviceName}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showKnownDevicesDialog() {
    final knownDevices = widget.p2pService.knownDevices.values.toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Known Devices'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: knownDevices.map((device) {
            final lastSeenAgo = DateTime.now().difference(device.lastSeen);
            return ListTile(
              leading: Icon(
                device.isHost ? Icons.router : Icons.phone_android,
                color: device.isHost ? Colors.blue : Colors.green,
              ),
              title: Text(device.ssid),
              subtitle: Text('Last seen: ${_formatDuration(lastSeenAgo)} ago'),
              trailing: ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _reconnectToDevice(device);
                },
                child: Text('Reconnect'),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _reconnectToDevice(DeviceCredentials device) async {
    try {
      await widget.p2pService.connectWithCredentials(device.ssid, device.psk);

      // Check if still mounted before showing snackbar
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reconnected to ${device.ssid}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Check if still mounted before showing error snackbar
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reconnect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) return '${duration.inDays}d';
    if (duration.inHours > 0) return '${duration.inHours}h';
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return 'moments';
  }

  @override
  Widget build(BuildContext context) {
    final connectionInfo = widget.p2pService.getConnectionInfo();

    return RefreshIndicator(
      onRefresh: () async {
        await _loadLatestLocation();
        await _checkUnsyncedLocations();
      },
      child: Center(
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 100,
                color: Colors.orange,
              ),
              const SizedBox(height: 20),
              const Text(
                'Emergency P2P Network',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Connect with nearby devices without internet',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // P2P Connection Status Card
              Card(
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
                            color: widget.p2pService.currentRole != P2PRole.none
                                ? Colors.green
                                : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'P2P Network Status',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildStatusRow(
                        Icons.person,
                        'Device ID',
                        connectionInfo['deviceId']?.toString().substring(
                              0,
                              8,
                            ) ??
                            'Not initialized',
                      ),
                      _buildStatusRow(
                        Icons.router,
                        'Role',
                        connectionInfo['role']?.toString().toUpperCase() ??
                            'NONE',
                        valueColor:
                            widget.p2pService.currentRole != P2PRole.none
                            ? Colors.green
                            : Colors.grey,
                      ),
                      _buildStatusRow(
                        Icons.devices,
                        'Connected',
                        '${connectionInfo['connectedDevices'] ?? 0} devices',
                      ),
                      _buildStatusRow(
                        Icons.cloud,
                        'Sync Status',
                        connectionInfo['isOnline'] == true
                            ? 'Online'
                            : 'Offline',
                        valueColor: connectionInfo['isOnline'] == true
                            ? Colors.green
                            : Colors.orange,
                      ),
                      if (connectionInfo['pendingMessages'] != null &&
                          connectionInfo['pendingMessages'] > 0)
                        _buildStatusRow(
                          Icons.hourglass_empty,
                          'Pending',
                          '${connectionInfo['pendingMessages']} messages',
                          valueColor: Colors.orange,
                        ),
                      const SizedBox(height: 8),
                      if (widget.p2pService.currentRole == P2PRole.host &&
                          connectionInfo['hostInfo'] != null) ...[
                        Divider(),
                        Text(
                          'Group Info:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'SSID: ${connectionInfo['hostInfo']['ssid'] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Location Card
              if (_isLoadingLocation)
                const CircularProgressIndicator()
              else if (_latestLocation != null) ...[
                Card(
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
                                  _latestLocation!.type ==
                                          LocationType.emergency ||
                                      _latestLocation!.type == LocationType.sos
                                  ? Colors.red
                                  : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Last Known Location",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (_unsyncedCount > 0) ...[
                              const Spacer(),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                              },
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.gps_fixed, size: 16),
                              label: const Text('View on Map'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GpsPage(
                                      userId:
                                          'user_${DateTime.now().millisecondsSinceEpoch}',
                                      onLocationShare: (location) {
                                        if (widget.onLocationUpdate != null) {
                                          widget.onLocationUpdate!(location);
                                        }
                                      },
                                    ),
                                  ),
                                ).then((_) {
                                  _loadLatestLocation();
                                  _checkUnsyncedLocations();
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(
                    widget.p2pService.currentRole == P2PRole.none
                        ? 'Start P2P Network'
                        : widget.p2pService.currentRole == P2PRole.host
                        ? 'Managing Group (${widget.p2pService.connectedDevices.length} connected)'
                        : 'Connected to Group',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        widget.p2pService.currentRole != P2PRole.none
                        ? Colors.green
                        : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: widget.p2pService.currentRole == P2PRole.none
                      ? () => _showP2POptionsDialog(context)
                      : () async {
                          // Show connection details or stop P2P
                          final stop = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('P2P Network Active'),
                              content: Text(
                                'Role: ${widget.p2pService.currentRole.name}\n'
                                'Connected devices: ${widget.p2pService.connectedDevices.length}\n\n'
                                'Do you want to disconnect?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: Text(
                                    'Disconnect',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (stop == true) {
                            await widget.p2pService.stopP2P();
                          }
                        },
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.emergency),
                  label: const Text('Send Emergency Broadcast'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => _showQuickEmergencyDialog(context),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.people),
                  label: const Text('View Connected Devices'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: widget.p2pService.connectedDevices.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => P2PDevicesPage(
                                p2pService: widget.p2pService,
                                currentLocation: _latestLocation,
                              ),
                            ),
                          );
                        },
                ),
              ),

              const SizedBox(height: 24),

              // Info Cards
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'How Multi-hop Works',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Messages automatically relay through connected devices to reach everyone. '
                        'Each message can hop up to ${P2PConnectionService.maxTtl} times. '
                        'Duplicate messages are automatically filtered.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (widget.p2pService.isOnline)
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_done, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Online - Messages syncing to cloud',
                            style: TextStyle(color: Colors.green[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
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

// P2P Devices Page
class P2PDevicesPage extends StatefulWidget {
  final P2PConnectionService p2pService;
  final LocationModel? currentLocation;

  const P2PDevicesPage({
    super.key,
    required this.p2pService,
    this.currentLocation,
  });

  @override
  State<P2PDevicesPage> createState() => _P2PDevicesPageState();
}

class _P2PDevicesPageState extends State<P2PDevicesPage> {
  @override
  void initState() {
    super.initState();
    widget.p2pService.addListener(_updateUI);
  }

  @override
  void dispose() {
    widget.p2pService.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connectedDevices = widget.p2pService.connectedDevices;
    final connectionInfo = widget.p2pService.getConnectionInfo();

    return Scaffold(
      appBar: AppBar(
        title: Text('P2P Network Devices'),
        actions: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                'Role: ${widget.p2pService.currentRole.name.toUpperCase()}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Network Info
          Container(
            padding: EdgeInsets.all(16),
            color: Theme.of(
              context,
            ).primaryColor.withAlpha((0.1 * 255).round()),
            child: Column(
              children: [
                if (widget.p2pService.currentRole == P2PRole.host &&
                    connectionInfo['hostInfo'] != null) ...[
                  Text(
                    'Hosting Group: ${connectionInfo['hostInfo']['ssid']}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                ],
                Text(
                  'Connected: ${connectedDevices.length} devices | '
                  'Messages processed: ${connectionInfo['processedMessages'] ?? 0}',
                ),
              ],
            ),
          ),

          // Connected Devices List
          Expanded(
            child: connectedDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.devices_other, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No devices connected',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          widget.p2pService.currentRole == P2PRole.host
                              ? 'Waiting for devices to connect...'
                              : 'Connected to host only',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: connectedDevices.length,
                    itemBuilder: (context, index) {
                      final deviceId = connectedDevices.keys.elementAt(index);
                      final device = connectedDevices[deviceId]!;
                      final connectedDuration = DateTime.now().difference(
                        device.connectedAt,
                      );

                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: device.isHost
                                ? Colors.blue
                                : Colors.green,
                            child: Icon(
                              device.isHost
                                  ? Icons.router
                                  : Icons.phone_android,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            device.name,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${device.id.substring(0, 8)}...'),
                              Text(
                                'Connected: ${_formatDuration(connectedDuration)}',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.chat),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => P2PChatScreen(
                                    p2pService: widget.p2pService,
                                    targetDeviceId: device.id,
                                    targetDeviceName: device.name,
                                    currentLocation: widget.currentLocation,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Stats
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  Icons.message,
                  'Pending',
                  '${connectionInfo['pendingMessages'] ?? 0}',
                ),
                _buildStatItem(
                  Icons.history,
                  'Known',
                  '${connectionInfo['knownDevices'] ?? 0}',
                ),
                _buildStatItem(
                  Icons.cloud,
                  'Status',
                  connectionInfo['isOnline'] == true ? 'Online' : 'Offline',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[600]),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }
}

// P2P Chat Screen
class P2PChatScreen extends StatefulWidget {
  final P2PConnectionService p2pService;
  final String targetDeviceId;
  final String targetDeviceName;
  final LocationModel? currentLocation;

  const P2PChatScreen({
    super.key,
    required this.p2pService,
    required this.targetDeviceId,
    required this.targetDeviceName,
    this.currentLocation,
  });

  @override
  State<P2PChatScreen> createState() => _P2PChatScreenState();
}

class _P2PChatScreenState extends State<P2PChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<MessageModel> _messages = [];
  LocationModel? _currentLocation;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.currentLocation;
    _loadMessages();
    widget.p2pService.addListener(_onNewMessage);
  }

  @override
  void dispose() {
    widget.p2pService.removeListener(_onNewMessage);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewMessage() {
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final messages = await DatabaseService.getMessages(widget.targetDeviceId);
    if (mounted) {
      setState(() {
        _messages = messages;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    await widget.p2pService.sendMessage(
      message: text,
      type: MessageType.text,
      targetDeviceId: widget.targetDeviceId,
    );

    await _loadMessages();
  }

  Future<void> _sendLocation() async {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No location available to share'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await widget.p2pService.sendMessage(
      message: 'Shared location: ${_currentLocation!.type.name}',
      type: MessageType.location,
      targetDeviceId: widget.targetDeviceId,
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
    );

    await _loadMessages();
  }

  Future<void> _sendEmergencyMessage() async {
    await widget.p2pService.sendMessage(
      message: 'EMERGENCY ASSISTANCE NEEDED!',
      type: MessageType.sos,
      targetDeviceId: widget.targetDeviceId,
      latitude: _currentLocation?.latitude,
      longitude: _currentLocation?.longitude,
    );

    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.p2pService.connectedDevices.containsKey(
      widget.targetDeviceId,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.targetDeviceName),
            Text(
              isConnected ? 'Connected' : 'Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          if (isConnected) ...[
            IconButton(
              icon: Icon(Icons.location_on),
              onPressed: _currentLocation != null ? _sendLocation : null,
              tooltip: 'Share Location',
            ),
            IconButton(
              icon: Icon(Icons.emergency, color: Colors.red),
              onPressed: _sendEmergencyMessage,
              tooltip: 'Send Emergency',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Start a conversation',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      final msg = _messages[index];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),

          // Input Area
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (isConnected && _currentLocation != null)
                    IconButton(
                      icon: Icon(
                        Icons.location_on,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed: _sendLocation,
                      tooltip: 'Share Location',
                    ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: isConnected,
                      decoration: InputDecoration(
                        hintText: isConnected
                            ? 'Type a message...'
                            : 'Device disconnected',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: isConnected ? (_) => _sendMessage() : null,
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: isConnected
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: isConnected ? _sendMessage : null,
                      icon: Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg) {
    final isMe = msg.isMe;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: msg.isEmergency
              ? Colors.red.shade600
              : msg.type == 'location'
              ? Colors.blue.shade700
              : isMe
              ? Theme.of(context).primaryColor
              : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.1 * 255).round()),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isEmergency) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'EMERGENCY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
            ],
            if (msg.type == 'location' &&
                msg.latitude != null &&
                msg.longitude != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Location Shared',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GpsPage(userId: 'viewer'),
                    ),
                  );
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.2 * 255).round()),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Lat: ${msg.latitude!.toStringAsFixed(4)}, '
                          'Lon: ${msg.longitude!.toStringAsFixed(4)}',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              Text(
                msg.message,
                style: TextStyle(
                  color: (isMe || msg.isEmergency || msg.type == 'location')
                      ? Colors.white
                      : Colors.black87,
                  fontSize: 16,
                ),
              ),
            SizedBox(height: 4),
            Text(
              _formatTimestamp(msg.timestamp),
              style: TextStyle(
                color: (isMe || msg.isEmergency || msg.type == 'location')
                    ? Colors.white70
                    : Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
